# frozen_string_literal: true

# S13 / tarefa 3.8 — **destravar o padrão cujo job nunca terminou** (melhoria de
# OPS-469 e OPS-470).
#
# ## O buraco que sobra depois do `ensure`
#
# `Availability::TemplateLock.around` põe o `unlock!` num `ensure`, e isso fecha o
# D-05 para **exceção**: com erro ou sem erro, o bloco termina e o padrão fica
# utilizável. O que o `ensure` **não** cobre é o processo morrer sem executar
# nada mais:
#
#   - `SIGKILL` no worker (OOM killer, `kill -9`, o container reciclado no meio
#     do deploy — e o legado literalmente chamava `Open3.capture3("kill -9 …")`,
#     ver OPS-464);
#   - a máquina cair;
#   - o job ser removido da fila enquanto o padrão já estava travado.
#
# Nesses casos o Ruby não roda `ensure` nenhum. O padrão fica `is_locked = true`
# com `job_state = 'running'` **para sempre**, e a interface não oferece caminho
# de recuperação — que é exatamente o estado terminal do legado, chegando por
# outra porta.
#
# ## O que este job faz
#
# De 10 em 10 minutos, procura padrão bloqueado há mais de
# `AVAILABILITY_LOCK_TIMEOUT_MINUTES` (padrão: 60) e:
#
#  1. **destrava** — o padrão volta a ser editável;
#  2. **escreve o motivo** em `job_report`, com o instante do bloqueio e há
#     quanto tempo ele durava. Destravar sem dizer por quê troca um travamento
#     misterioso por um destravamento misterioso;
#  3. marca `job_state = 'failed'` — porque foi isso que aconteceu: a operação
#     não concluiu;
#  4. **publica `failed` no canal do projeto**, para a aba que está aberta parar
#     de girar. Sem cabo, o usuário só descobriria dando F5 (e nada de polling —
#     tarefa 8.4).
#
# ## O prazo é generoso de propósito
#
# 60 minutos é muito mais do que qualquer uma das quatro operações leva. Se o
# prazo fosse curto, este job destravaria padrão de operação **ainda em
# andamento** — e duas escritas concorrentes na mesma subárvore é pior do que o
# problema que ele resolve. Prazo longo erra para o lado seguro: no máximo o
# usuário espera uma hora antes da recuperação automática.
class UnlockStaleTemplatesJob < ApplicationJob
  queue_as :low_priority

  class StaleUnlockFailed < StandardError; end

  DEFAULT_TIMEOUT_MINUTES = 60

  def self.timeout_minutes
    ENV.fetch('AVAILABILITY_LOCK_TIMEOUT_MINUTES', DEFAULT_TIMEOUT_MINUTES).to_i
  end

  def self.job_identifier(template_id) = "availability_template:#{template_id}"

  def perform
    limite = self.class.timeout_minutes.minutes.ago
    # `locked_at` nulo com `is_locked` verdadeiro é estado impossível pelo
    # caminho normal (o `lock!` grava os dois juntos), mas se acontecer o padrão
    # está travado sem prazo — e é justamente o caso que precisa sair.
    presos = AvailabilityTemplate.where(is_locked: true)
                                 .where('locked_at IS NULL OR locked_at < ?', limite)

    liberados = 0
    falhas = []
    presos.find_each do |template|
      liberar(template)
      liberados += 1
    rescue StandardError => e
      # Um padrão que não pôde ser destravado não pode impedir que os outros
      # sejam — mas **não é engolido**: as falhas são acumuladas e relançadas ao
      # fim do laço (contrato D-C). O Sidekiq retenta, e a varredura é
      # idempotente: quem já saiu não é selecionado de novo.
      Rails.logger.error("[UnlockStaleTemplatesJob] falha ao destravar #{template.id}: #{e.class}: #{e.message}")
      falhas << "#{template.id}: #{e.class}: #{e.message}"
    end

    Rails.logger.info("[UnlockStaleTemplatesJob] #{liberados} padrão(ões) destravado(s) " \
                      "por exceder #{self.class.timeout_minutes} min de bloqueio")

    raise StaleUnlockFailed, "não foi possível destravar #{falhas.size}: #{falhas.join(' | ')}" if falhas.any?

    liberados
  end

  private

  def liberar(template)
    travado_desde = template.locked_at
    duracao = travado_desde.present? ? ((Time.current - travado_desde) / 60).round : nil
    motivo = if travado_desde.present?
               'A operação em segundo plano não terminou: o padrão estava bloqueado desde ' \
                 "#{travado_desde.in_time_zone.strftime('%d/%m/%Y %H:%M')} (#{duracao} min), acima do limite de " \
                 "#{self.class.timeout_minutes} min. O bloqueio foi liberado automaticamente; " \
                 'confira o resultado antes de repetir a operação.'
             else
               'O padrão estava bloqueado sem registro de quando. O bloqueio foi liberado ' \
                 'automaticamente; confira o resultado antes de repetir a operação.'
             end

    # `update_all`: isto não é edição do usuário e não deve gerar versão de
    # `paper_trail` nem disparar validação sobre um registro em estado ruim.
    AvailabilityTemplate.where(id: template.id).update_all(
      is_locked: false, locked_at: nil, locked_message: nil, locked_by_id: nil,
      job_state: 'failed', job_progress: nil,
      job_report: { 'state' => 'failed', 'reason' => 'lock_timeout',
                    'message' => motivo,
                    'locked_at' => travado_desde&.iso8601,
                    'locked_for_minutes' => duracao,
                    'timeout_minutes' => self.class.timeout_minutes,
                    'released_at' => Time.current.iso8601 },
      updated_at: Time.current
    )

    Rails.logger.warn("[UnlockStaleTemplatesJob] padrão #{template.id} destravado — #{motivo}")

    # A tela que estava aberta precisa parar de girar. `project_id` nulo (padrão
    # do catálogo global) simplesmente não tem canal de projeto para receber — o
    # `Sfg::JobProgress` já trata isso e devolve sem publicar.
    Sfg::JobProgress.publish(project_id: template.project_id,
                             job_id: self.class.job_identifier(template.id),
                             status: 'failed', error: motivo)
  end
end
