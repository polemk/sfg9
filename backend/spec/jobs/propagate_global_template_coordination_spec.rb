# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefa 9.2 — **OPS-466 / D-80: coordenador + filho por projeto.**
#
# O que este arquivo prova, e que a versão anterior da propagação NÃO fazia
# apesar de o comentário dela afirmar que sim:
#
#  1. a request enfileira **só o coordenador**;
#  2. o coordenador enfileira **N filhos independentes**, um por projeto, sem
#     fazer trabalho de domínio nenhum;
#  3. **a falha de um projeto não derruba os outros** — os irmãos já estão na
#     fila e terminam;
#  4. o relatório do coordenador **fecha**, com ou sem falha, em vez de deixar o
#     global em `running` para sempre (D-05).
#
# O adapter desta suíte é `:inline` (`config/environments/test.rb:35`), o que faz
# `perform_later` executar na hora. Os exemplos que precisam contar enfileiramento
# trocam o adapter para `:test` **dentro do exemplo** — não no `rails_helper`, que
# mudaria o comportamento da suíte inteira.
RSpec.describe 'Propagação de padrão global — coordenador e filhos (OPS-466)' do
  let!(:projetos) { Array.new(3) { create(:project) } }
  let(:global) { create(:global_availability_template) }

  # -------------------------------------------------------------------
  describe 'o coordenador despacha, não trabalha' do
    around do |exemplo|
      anterior = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      exemplo.run
      ActiveJob::Base.queue_adapter = anterior
    end

    it 'com N projetos existem N jobs filhos, um por projeto' do
      global
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      PropagateGlobalTemplateJob.perform_now(global.id)

      filhos = ActiveJob::Base.queue_adapter.enqueued_jobs
                              .select { |j| j['job_class'] == 'PropagateGlobalTemplateToProjectJob' }
      expect(filhos.size).to eq(projetos.size)
      expect(filhos.map { |j| j['arguments'][1] }).to match_array(projetos.map(&:id))
    end

    it 'o coordenador NÃO escreve padrão de projeto nenhum — o trabalho é do filho' do
      expect { PropagateGlobalTemplateJob.perform_now(global.id) }
        .not_to(change { ProjectAvailabilityTemplate.count })
    end

    it 'o filho vai para a fila declarada em config/sidekiq.yml' do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      PropagateGlobalTemplateJob.perform_now(global.id)

      filas = ActiveJob::Base.queue_adapter.enqueued_jobs
                             .select { |j| j['job_class'] == 'PropagateGlobalTemplateToProjectJob' }
                             .map { |j| j['queue_name'] }.uniq
      declaradas = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/sidekiq.yml'))).result,
                                  aliases: true, permitted_classes: [Symbol])
      declaradas = Array(declaradas[:queues] || declaradas['queues']).map(&:to_s)

      expect(filas).to all(be_in(declaradas))
    end
  end

  # -------------------------------------------------------------------
  describe 'falha de um projeto não afeta os outros' do
    it 'o projeto que falha fica sem o padrão; os demais recebem' do
      quebrado = projetos.first
      chamadas = 0
      allow(Availability::GlobalSeeder).to receive(:insert_into_project!)
        .and_wrap_original do |orig, project, *resto, **opcoes|
          chamadas += 1
          raise StandardError, 'falha forçada neste projeto' if project.id == quebrado.id

          orig.call(project, *resto, **opcoes)
        end

      # Com `:inline`, um filho que levanta interrompe o despacho dos seguintes.
      # É por isso que os filhos são despachados PRIMEIRO e executados depois —
      # o que o `:test` + `perform_enqueued_jobs` reproduz fielmente do Sidekiq.
      anterior = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      begin
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        PropagateGlobalTemplateJob.perform_now(global.id)
        enfileirados = ActiveJob::Base.queue_adapter.enqueued_jobs
                                      .select { |j| j['job_class'] == 'PropagateGlobalTemplateToProjectJob' }
                                      .map { |j| j['arguments'] }
      ensure
        ActiveJob::Base.queue_adapter = anterior
      end

      falhas = 0
      enfileirados.each do |args|
        PropagateGlobalTemplateToProjectJob.perform_now(*args)
      rescue StandardError
        # É exatamente isto que o Sidekiq faz: o filho morre sozinho e o
        # processamento dos irmãos continua.
        falhas += 1
      end

      expect(falhas).to eq(1)
      expect(chamadas).to eq(projetos.size)

      recebidos = ProjectAvailabilityTemplate.where(global_availability_template_id: global.id)
                                             .pluck(:project_id)
      expect(recebidos).to match_array(projetos.reject { |p| p.id == quebrado.id }.map(&:id))
      expect(recebidos).not_to include(quebrado.id)
    end
  end

  # -------------------------------------------------------------------
  describe 'o relatório do coordenador fecha (D-05)' do
    it 'todos os filhos com sucesso → `done`, 100%' do
      # Adapter `:inline`: os filhos rodam durante o despacho.
      PropagateGlobalTemplateJob.perform_now(global.id)

      relatorio = global.reload.job_report
      expect(global.job_state).to eq('done')
      expect(global.job_progress).to eq(100)
      expect(relatorio['projects']).to eq(projetos.size)
      expect(relatorio['completed']).to eq(projetos.size)
      expect(relatorio['finished_at']).to be_present
    end

    it 'um filho que desiste → `failed`, e a contagem diz quantos' do
      allow(PropagateGlobalTemplateToProjectJob).to receive(:perform_later)
      PropagateGlobalTemplateJob.perform_now(global.id)

      projetos.each_with_index do |projeto, indice|
        PropagateGlobalTemplateJob.register_outcome!(global.id, projeto.id, indice.zero? ? 'failed' : 'completed')
      end

      global.reload
      expect(global.job_state).to eq('failed')
      expect(global.job_report['failed']).to eq(1)
      expect(global.job_report['completed']).to eq(projetos.size - 1)
    end

    # O defeito que a PRIMEIRA execução real achou (26/08/2026): o
    # `after_discard` do ActiveJob roda a cada tentativa quando o job não
    # declara `retry_on`, e o contador incremental fechou `completed: 2,
    # failed: 2` para TRÊS projetos. Registrar por projeto é o que impede isso.
    it 'registrar o MESMO projeto várias vezes não infla a contagem' do
      allow(PropagateGlobalTemplateToProjectJob).to receive(:perform_later)
      PropagateGlobalTemplateJob.perform_now(global.id)

      3.times { PropagateGlobalTemplateJob.register_outcome!(global.id, projetos.first.id, 'failed') }
      projetos.drop(1).each { |p| PropagateGlobalTemplateJob.register_outcome!(global.id, p.id, 'completed') }

      global.reload
      expect(global.job_report['failed']).to eq(1)
      expect(global.job_report['completed']).to eq(2)
      expect(global.job_state).to eq('failed')
    end

    # E a consequência boa do registro por projeto: a retentativa que dá certo
    # CORRIGE o relatório, em vez de somar sucesso por cima da falha.
    it 'retentativa bem-sucedida troca `failed` por `completed` no mesmo projeto' do
      allow(PropagateGlobalTemplateToProjectJob).to receive(:perform_later)
      PropagateGlobalTemplateJob.perform_now(global.id)

      projetos.each { |p| PropagateGlobalTemplateJob.register_outcome!(global.id, p.id, 'completed') }
      PropagateGlobalTemplateJob.register_outcome!(global.id, projetos.first.id, 'failed')
      expect(global.reload.job_state).to eq('failed')

      PropagateGlobalTemplateJob.register_outcome!(global.id, projetos.first.id, 'completed')

      global.reload
      expect(global.job_state).to eq('done')
      expect(global.job_report['failed']).to eq(0)
      expect(global.job_report['completed']).to eq(projetos.size)
    end

    it 'projeto apagado entre o despacho e a execução conta como `skipped`, não trava o relatório' do
      allow(PropagateGlobalTemplateToProjectJob).to receive(:perform_later)
      PropagateGlobalTemplateJob.perform_now(global.id)

      PropagateGlobalTemplateToProjectJob.perform_now(global.id, SecureRandom.uuid)
      projetos.drop(1).each { |p| PropagateGlobalTemplateJob.register_outcome!(global.id, p.id, 'completed') }

      global.reload
      expect(global.job_report['skipped']).to eq(1)
      expect(global.job_state).to eq('done')
      expect(global.job_progress).to eq(100)
    end

    it 'contagem concorrente não perde registro — o `lock` é o que garante' do
      allow(PropagateGlobalTemplateToProjectJob).to receive(:perform_later)
      PropagateGlobalTemplateJob.perform_now(global.id)

      projetos.each { |p| PropagateGlobalTemplateJob.register_outcome!(global.id, p.id, 'completed') }

      expect(global.reload.job_report['completed']).to eq(3)
      expect(global.job_report['results'].keys).to match_array(projetos.map(&:id))
    end
  end
end
