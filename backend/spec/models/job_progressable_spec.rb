# frozen_string_literal: true

require 'rails_helper'

# S13 / OPS-463, OPS-127, DB-460 — progresso de job **na entidade**.
RSpec.describe JobProgressable do
  # Este exemplo existe por causa de uma perda REAL e silenciosa, em 25/08/2026: a
  # migration que criou `job_state`/`job_progress` rodou; logo depois a padronização
  # de chave primária **recriou `projects`**, as colunas foram junto e o `schema.rb`
  # foi redumpado sem elas — com a versão do schema ainda apontando para a migration
  # que as tinha criado. A migration constava como executada e a coluna não existia.
  #
  # Nada reprovava: `zeitwerk:check` passa, `rspec` passa (um `scope` que cita a
  # coluna só é avaliado quando alguém o chama) e o defeito só apareceria quando o
  # primeiro job tentasse publicar progresso — em produção, no meio de um import.
  it 'todo model que inclui o concern TEM as colunas que ele exige' do
    Rails.application.eager_load!

    models = ApplicationRecord.descendants.select { |m| m.include?(described_class) && m.table_exists? }
    expect(models).not_to be_empty, 'nenhum model usa JobProgressable — o concern virou código morto?'

    faltando = models.filter_map do |model|
      ausentes = %w[job_state job_progress] - model.column_names
      "#{model.name}: #{ausentes.join(', ')}" if ausentes.any?
    end

    expect(faltando).to be_empty,
                        "Colunas de progresso ausentes: #{faltando.join('; ')}. " \
                        'Uma migration concorrente pode ter recriado a tabela.'
  end

  describe '#live_progress_percent' do
    let(:project) { create_project_with_owner(create(:user)) }

    it 'devolve nil quando NÃO há job — o legado devolvia 100' do
      # `live_progress_percent` do legado devolvia 100 com job nil: entidade que nunca
      # rodou nada aparecia como concluída na tela.
      expect(project.live_progress_percent).to be_nil
      expect(project.ongoing_job?).to be(false)
    end

    it 'devolve o número real enquanto roda' do
      project.update_columns(job_state: 'running', job_progress: 37)
      expect(project.live_progress_percent).to eq(37)
      expect(project.ongoing_job?).to be(true)
    end

    it 'devolve 100 só quando terminou de verdade — o legado devolvia 0 no fim' do
      project.update_columns(job_state: 'done', job_progress: 98)
      expect(project.live_progress_percent).to eq(100)
    end

    it 'não desenha barra quando o job falhou' do
      project.update_columns(job_state: 'failed', job_progress: 42)
      expect(project.live_progress_percent).to be_nil
      expect(project.failed_job?).to be(true)
    end
  end

  describe 'Sfg::JobProgress' do
    let(:project) { create_project_with_owner(create(:user)) }

    it 'grava na entidade e publica no canal com o contrato que o front lê' do
      publicado = nil
      allow(ProjectProgressChannel).to receive(:publish) { |_, payload| publicado = payload }

      Sfg::JobProgress.step(project_id: project.id, job_id: 'importacao', record: project,
                            current: 3, total: 4, message: 'Importando 3 de 4')

      expect(project.reload.job_state).to eq('running')
      expect(project.job_progress).to eq(75)
      # `status`, não `state`: o `useJobProgress.ts` lê `status`, e emitir `state`
      # deixava a barra em "running" para sempre, inclusive na falha.
      expect(publicado[:status]).to eq('running')
      expect(publicado[:type]).to eq('job_progress')
      expect(publicado[:percent]).to eq(75)
    end

    it 'conclusão sem número é 100 — barra parada em 87% com "concluído" ao lado faz duvidar' do
      allow(ProjectProgressChannel).to receive(:publish)
      Sfg::JobProgress.publish(project_id: project.id, job_id: 'x', status: 'done', record: project)
      expect(project.reload.job_progress).to eq(100)
    end

    it 'recusa estado que não existe, em vez de publicar lixo no canal' do
      expect { Sfg::JobProgress.publish(project_id: project.id, job_id: 'x', status: 'pendente') }
        .to raise_error(ArgumentError, /status inválido/)
    end
  end
end
