# frozen_string_literal: true

require 'rails_helper'

# **DEC-129.3** — *"dado migrado que não é alcançável pela interface é dado
# perdido na prática"*.
#
# Medido no dump de 31/05/2025: **51 lançamentos** de indicador em **13 pares**
# (projeto, indicador) sem linha em `project_indicator_connections`. A grade do
# ai9 é montada pelas conexões — é a ausência dela que faz o indicador sumir da
# tela sem apagar lançamento nenhum (Q-R31). Sem conexão, esses 51 carregariam e
# **nunca apareceriam**: contagem batendo, dado invisível.
#
# Se há lançamento, alguém usou aquele indicador naquele projeto. O que sumiu foi
# a conexão, e criá-la restaura a visibilidade sem tocar em lançamento nenhum.
RSpec.describe 'DEC-129.3 — o lançamento sem conexão' do
  let(:de_para) do
    {
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[indicators 11] => 'bbbbbbbb-0000-4000-8000-000000000002',
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003'
    }
  end

  let(:origem) { instance_double(Sfg::Etl::Source::Base) }

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    allow(duplo).to receive(:source).and_return(origem)
    duplo
  end

  subject(:conversor) { Sfg::Etl::Converters::IndicatorEntries.new(run) }

  let(:lancamento) do
    { 'id' => 501, 'project_id' => 7, 'indicator_id' => 11, 'year' => 2024, 'month' => 3,
      'value' => '1500.00', 'title' => 'INADIMPLENCIA', 'key' => 'inadimplencia',
      'value_type' => 'Dinheiro', 'user_id' => 3,
      'created_at' => '2024-03-31 10:00:00', 'updated_at' => '2024-03-31 10:00:00' }
  end

  before { allow(origem).to receive(:table?).with('project_indicator_connections').and_return(true) }

  describe 'o relatório' do
    it 'LISTA o lançamento cujo par não tem conexão na origem' do
      allow(origem).to receive(:ordered_rows).with('project_indicator_connections').and_return([])

      anomalia = conversor.anomalies(lancamento).find { |a| a.is_a?(Hash) }

      expect(anomalia[:key]).to eq('indicator_entries:connection_missing')
      expect(anomalia[:line]).to include('projeto 7')
      expect(anomalia[:line]).to include('indicador 11')
    end

    it 'NÃO lista quando a conexão existe na origem' do
      allow(origem).to receive(:ordered_rows).with('project_indicator_connections')
                                             .and_return([{ 'id' => 1, 'project_id' => 7, 'indicator_id' => 11 }])

      expect(conversor.anomalies(lancamento)).to be_empty
    end

    it 'lê `project_indicator_connections` UMA vez, não uma por lançamento' do
      allow(origem).to receive(:ordered_rows).with('project_indicator_connections').and_return([])

      3.times { conversor.anomalies(lancamento) }

      expect(origem).to have_received(:ordered_rows).with('project_indicator_connections').once
    end

    it 'a chave está ASSINADA em `decisions.yml` — sem isso o dry-run aborta' do
      expect(Sfg::Etl::Decisions.load).to be_registered('indicator_entries:connection_missing')
    end
  end

  # ==========================================================================
  # O gancho que RESTAURA. Roda no destino, depois de os lançamentos entrarem.
  # ==========================================================================
  describe '.post_load!' do
    let(:project) { create(:project) }
    let(:indicator) { create(:indicator) }
    let(:company) { create(:company, project: project) }

    def lancar!(ano: 2024, mes: 3)
      IndicatorEntry.create!(project: project, indicator: indicator, year: ano, month: mes,
                             value: 1500, title: indicator.title, key: indicator.key,
                             value_type: indicator.value_type)
    end

    it 'CRIA a conexão que falta para o par que tem lançamento' do
      lancar!

      expect { Sfg::Etl::Converters::IndicatorEntries.post_load! }
        .to change { ProjectIndicatorConnection.where(project: project, indicator: indicator).count }
        .from(0).to(1)
    end

    it 'a conexão criada nasce SEM `legacy_id` — é o que a distingue das migradas' do
      lancar!
      Sfg::Etl::Converters::IndicatorEntries.post_load!

      conexao = ProjectIndicatorConnection.find_by(project: project, indicator: indicator)
      expect(conexao.legacy_id).to be_nil
    end

    it 'não escreve nada na segunda execução — o gancho é idempotente (RESUME=0)' do
      lancar!
      Sfg::Etl::Converters::IndicatorEntries.post_load!

      expect { Sfg::Etl::Converters::IndicatorEntries.post_load! }
        .not_to(change { ProjectIndicatorConnection.count })
    end

    it 'não toca em conexão que já existe' do
      conexao = ProjectIndicatorConnection.create!(project: project, indicator: indicator, legacy_id: 42)
      lancar!

      Sfg::Etl::Converters::IndicatorEntries.post_load!

      expect(ProjectIndicatorConnection.count).to eq(1)
      expect(conexao.reload.legacy_id).to eq(42)
    end

    it 'não cria conexão para par sem lançamento nenhum' do
      indicator # o indicador existe, mas ninguém lançou nada nele neste projeto

      expect { Sfg::Etl::Converters::IndicatorEntries.post_load! }
        .not_to(change { ProjectIndicatorConnection.count })
    end

    it 'devolve o relatório com a contagem e os pares restaurados' do
      lancar!
      resultado = Sfg::Etl::Converters::IndicatorEntries.post_load!

      expect(resultado[:criadas]).to eq(1)
      expect(resultado[:pares].first).to include(project.id, indicator.id)
      expect(resultado[:note]).to include('DEC-129.3')
    end

    it 'um par com VÁRIOS lançamentos ganha UMA conexão' do
      lancar!(mes: 3)
      lancar!(mes: 4)
      lancar!(mes: 5)

      Sfg::Etl::Converters::IndicatorEntries.post_load!

      expect(ProjectIndicatorConnection.where(project: project, indicator: indicator).count).to eq(1)
    end
  end
end
