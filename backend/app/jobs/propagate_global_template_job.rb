# frozen_string_literal: true

# S11 / OPS-121, DC-31 · S13 / OPS-466, D-80 — **propagar um padrão global para
# os projetos**.
#
# Dois modos:
#
#  - `insert` — o padrão global novo entra em todos os projetos. É o que o
#    `after_create` do legado fazia dentro de um `Project.all.each`, no corpo do
#    model (`global_availability_template.rb:26-38`);
#  - `sync_attributes` — `is_adjusted`/`is_cumulative` mudaram no catálogo e os
#    derivados acompanham (DC-31). **O legado não propagava nada disso**, e o
#    catálogo mentia sobre os padrões que gerou.
#
# ## Coordenador + filho (OPS-466 / D-80) — S13
#
# No modo `insert` esta classe **não faz trabalho de projeto**: ela conta os
# projetos, escreve o total no relatório e despacha **um
# `PropagateGlobalTemplateToProjectJob` por projeto**. A request enfileira só o
# coordenador, e o coordenador enfileira N filhos independentes.
#
# **Por que a mudança.** A versão anterior era um job só com o laço dentro. O
# `rescue` do bloco terminava em `raise` (a regra certa de `ApplicationJob`), só
# que dentro de um `find_each` o `raise` **aborta o laço**: o primeiro projeto que
# falhasse deixava os seguintes sem o padrão. O comentário dizia "o job segue" e
# o código não seguia. Agora a falha de um filho é retentada e morre no dead set
# **sozinha** — os irmãos já estão enfileirados.
#
# `sync_attributes` continua aqui: é **uma** consulta (`update_all`) para todos
# os projetos de uma vez, não um trabalho por projeto. Quebrá-lo em N jobs seria
# N vezes mais caro para fazer a mesma coisa.
#
# ## Progresso é POR PROJETO (OPS-121)
#
# No legado cada propagação escrevia `p.job_id`/`p.job_state` na linha do
# projeto e as propagações **se atropelavam**: duas rodando ao mesmo tempo
# sobrescreviam o estado uma da outra. Aqui cada projeto recebe o evento no
# **próprio** canal (`ProjectProgressChannel`, cujo nome de stream vive num
# lugar só) e o `job_id` carrega o id do global — dois padrões diferentes
# propagando ao mesmo tempo não se confundem na tela.
#
# ## Obrigatoriedade copiada, não forçada
#
# `Project#create_template_from_global` do legado escrevia `is_mandatory: 1`
# **literal** (`project.rb:359`), divergindo do caminho de semeadura, que
# copiava. O `Availability::GlobalSeeder` é um só e copia — há um spec que
# confere que um global com `is_mandatory = false` gera padrão de projeto com
# `is_mandatory = false`.
class PropagateGlobalTemplateJob < ApplicationJob
  queue_as :low_priority

  MODES = %w[insert sync_attributes].freeze

  # Chaves de contagem do relatório do coordenador. `skipped` cobre o projeto (ou
  # o global) removido entre o despacho e a execução do filho — não é sucesso nem
  # falha, mas **precisa** ser contado, senão o relatório nunca fecha.
  OUTCOMES = %w[completed failed skipped].freeze

  def self.job_identifier(template_id) = "availability_propagate_global:#{template_id}"

  # Contabiliza o desfecho de UM filho e fecha o relatório quando o último chega.
  #
  # **O desfecho é gravado POR PROJETO, não como contador.** A primeira versão
  # incrementava `completed`/`failed`, e rodando de verdade (26/08/2026, Sidekiq
  # no ar) o relatório fechou com `completed: 2, failed: 2` para **três**
  # projetos. A causa: `after_discard` do ActiveJob roda a **cada** tentativa
  # quando o job não declara `retry_on` — a retentativa do Sidekiq é opaca para o
  # ActiveJob, que trata toda exceção não tratada como descarte. O mesmo projeto
  # foi contado três vezes.
  #
  # Guardar o desfecho **por projeto** conserta isso de um jeito que não depende
  # da semântica de retentativa de nenhuma camada: registrar duas vezes o mesmo
  # projeto sobrescreve a chave, e uma retentativa que **dá certo** faz a chave
  # virar `completed` — o relatório se corrige sozinho em vez de somar mentira.
  # Os contadores continuam no relatório porque é o que se lê de relance, mas
  # são **derivados** do mapa, nunca incrementados.
  #
  # `lock` (SELECT … FOR UPDATE) porque N filhos escrevem na mesma linha em
  # paralelo: sem ele, duas escritas concorrentes leem o mesmo mapa e uma das
  # duas some.
  #
  # `update_all` de propósito: relatório de job não é edição do usuário e não
  # deve gerar versão de `paper_trail` (DEC-78 guarda o payload completo).
  def self.register_outcome!(global_template_id, project_id, outcome)
    raise ArgumentError, "desfecho desconhecido: #{outcome.inspect}" unless OUTCOMES.include?(outcome.to_s)

    AvailabilityTemplate.transaction do
      linha = AvailabilityTemplate.lock.find_by(id: global_template_id)
      next if linha.nil?

      relatorio = (linha.job_report || {}).dup
      resultados = (relatorio['results'] || {}).merge(project_id.to_s => outcome.to_s)
      relatorio['results'] = resultados
      OUTCOMES.each { |chave| relatorio[chave] = resultados.count { |_, valor| valor == chave } }

      total = relatorio['projects'].to_i
      concluidos = resultados.size

      atributos = { job_report: relatorio, updated_at: Time.current }
      if total.positive? && concluidos >= total
        relatorio['finished_at'] = Time.current.iso8601
        atributos[:job_report] = relatorio
        atributos[:job_state] = relatorio['failed'].to_i.positive? ? 'failed' : 'done'
        atributos[:job_progress] = 100
      elsif total.positive?
        atributos[:job_progress] = (concluidos * 100 / total)
      end

      AvailabilityTemplate.where(id: global_template_id).update_all(atributos)
    end
  end

  def perform(global_template_id, actor_id = nil, mode = 'insert')
    global = GlobalAvailabilityTemplate.find_by(id: global_template_id)
    return if global.nil?
    raise ArgumentError, "modo desconhecido: #{mode.inspect}" unless MODES.include?(mode.to_s)

    return sincronizar_atributos(global) if mode.to_s == 'sync_attributes'

    despachar_filhos(global, actor_id)
  end

  private

  # Tempo desta execução: uma contagem e N enfileiramentos. Nenhuma escrita de
  # domínio acontece aqui — ela toda mora no filho.
  def despachar_filhos(global, actor_id)
    ids = Project.order(:created_at).pluck(:id)

    AvailabilityTemplate.where(id: global.id).update_all(
      job_state: ids.empty? ? 'done' : 'running',
      job_progress: ids.empty? ? 100 : 0,
      job_report: { 'mode' => 'insert', 'projects' => ids.size, 'completed' => 0,
                    'failed' => 0, 'skipped' => 0, 'results' => {},
                    'dispatched_at' => Time.current.iso8601 },
      updated_at: Time.current
    )

    ids.each { |project_id| PropagateGlobalTemplateToProjectJob.perform_later(global.id, project_id, actor_id) }
    ids.size
  end

  def sincronizar_atributos(global)
    identificador = self.class.job_identifier(global.id)
    afetados = Availability::GlobalSeeder.sync_attributes!(global)

    ProjectAvailabilityTemplate.where(global_availability_template_id: global.id)
                               .distinct.pluck(:project_id).each do |project_id|
      Sfg::JobProgress.publish(project_id: project_id, job_id: identificador, status: 'done',
                               message: "\"#{global.title}\" atualizado neste projeto")
    end

    AvailabilityTemplate.where(id: global.id).update_all(
      job_state: 'done', job_progress: 100,
      job_report: { 'mode' => 'sync_attributes', 'updated' => afetados,
                    'finished_at' => Time.current.iso8601 },
      updated_at: Time.current
    )
    afetados
  end
end
