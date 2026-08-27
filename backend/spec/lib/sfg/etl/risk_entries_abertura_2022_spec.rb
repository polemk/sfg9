# frozen_string_literal: true

require 'rails_helper'

# **DEC-129.2** — *"manter como é no legado"* (palavras do usuário).
#
# Medido no dump de 31/05/2025: **4.082 linhas** (161 limites, 19 projetos,
# **R$ 4.884.851.467,94**), de 28/01/2022 a 14/04/2022, guardam um total
# **não-zero** com as duas parcelas correspondentes **zeradas**. O conversor
# derivava os totais das parcelas: a contagem continuava batendo (4.082/4.082) e
# a **abertura por modalidade sumia**.
#
# São duas peças, e nenhuma delas sozinha resolve:
#
#   1. o **conversor** copia o total da origem quando as parcelas vêm zeradas;
#   2. o **model** (`RiskEntry#derive_scope_and_totals`) para de recalcular zero
#      por cima — sem isso o `save!` do motor desfaz a cópia em silêncio.
#
# Este arquivo prova as duas, e prova também o lado que **não** muda: total da
# origem que diverge das parcelas por qualquer outro motivo continua derivado.
RSpec.describe 'DEC-129.2 — a abertura por modalidade de 2022 sobrevive à carga' do
  let(:de_para) do
    {
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[companies 3] => 'bbbbbbbb-0000-4000-8000-000000000002',
      %w[risk_controls 9] => 'cccccccc-0000-4000-8000-000000000003'
    }
  end

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    duplo
  end

  subject(:conversor) { Sfg::Etl::Converters::RiskEntries.new(run) }

  # Uma linha do período: parcelas ZERADAS, totais preenchidos. É a forma exata
  # das 4.082.
  def linha_de_2022(**sobrescritas)
    {
      'id' => 1234, 'project_id' => 7, 'company_id' => 3, 'risk_control_id' => 9,
      'date' => '2022-02-15', 'risk_control_title' => 'Limite Banco X',
      'observacoes' => nil, 'has_safegold_management' => 1,
      'created_at' => '2022-02-15 09:00:00', 'updated_at' => '2022-02-15 09:00:00',
      'vencidos_value' => '0.00', 'a_vencer_value' => '0.00',
      'liquidacao_value' => '0.00', 'descontos_value' => '0.00',
      'comissaria_vencidos_value' => '0.00', 'comissaria_a_vencer_value' => '0.00',
      'fomento_vencidos_value' => '0.00', 'fomento_a_vencer_value' => '0.00',
      'intercompany_vencidos_value' => '0.00', 'intercompany_a_vencer_value' => '0.00',
      'total_carteira_value' => '1200000.00', 'total_reducoes_value' => '0.00',
      'comissaria_total_value' => '750000.00', 'fomento_total_value' => '450000.00',
      'intercompany_total_value' => '0.00'
    }.merge(sobrescritas)
  end

  describe 'o conversor' do
    it 'PRESERVA o total da origem quando as duas parcelas vêm zeradas' do
      convertido = conversor.convert(linha_de_2022)

      expect(convertido[:comissaria_total_value]).to eq(BigDecimal('750000.00'))
      expect(convertido[:fomento_total_value]).to eq(BigDecimal('450000.00'))
      expect(convertido[:total_carteira_value]).to eq(BigDecimal('1200000.00'))
    end

    it 'liga a chave que impede o model de recalcular zero por cima' do
      expect(conversor.convert(linha_de_2022)[:preserve_legacy_totals]).to be(true)
    end

    it 'DERIVA das parcelas quando elas têm valor — o comportamento normal não muda' do
      linha = linha_de_2022('comissaria_vencidos_value' => '100.00',
                            'comissaria_a_vencer_value' => '250.00',
                            'comissaria_total_value' => '999999.00')

      # A origem diz 999.999,00 e as parcelas dizem 350,00. Aqui o legado gravou
      # um total inconsistente, e copiá-lo seria propagar o erro.
      expect(conversor.convert(linha)[:comissaria_total_value]).to eq(BigDecimal('350.00'))
    end

    it 'não liga a chave quando não houve nada a preservar' do
      linha = linha_de_2022('total_carteira_value' => '0.00', 'comissaria_total_value' => '0.00',
                            'fomento_total_value' => '0.00')

      expect(conversor.convert(linha)).not_to have_key(:preserve_legacy_totals)
    end

    it 'zero na origem com parcelas zeradas continua zero — não é "preservar", é o valor' do
      linha = linha_de_2022('fomento_total_value' => '0.00')
      expect(conversor.convert(linha)[:fomento_total_value]).to eq(0)
    end

    it 'LISTA cada modalidade preservada, com o valor da origem e as parcelas que faltaram' do
      linhas = conversor.anomalies(linha_de_2022)

      expect(linhas.map { |l| l[:key] }.uniq).to eq(['risk_entries:legacy_total_without_installments'])
      expect(linhas.size).to eq(3) # carteira, comissária e fomento — as três com total não-zero
      expect(linhas.map { |l| l[:line] }.join).to include('comissaria_vencidos_value + comissaria_a_vencer_value')
      expect(linhas.map { |l| l[:line] }.join).to include('750000.0')
    end

    it 'não lista nada quando as parcelas têm valor' do
      linha = linha_de_2022('vencidos_value' => '1200000.00', 'total_carteira_value' => '1200000.00',
                            'comissaria_total_value' => '0.00', 'fomento_total_value' => '0.00')

      expect(conversor.anomalies(linha)).to be_empty
    end

    it 'a chave está ASSINADA em `decisions.yml` — sem isso o dry-run aborta' do
      decisoes = Sfg::Etl::Decisions.load
      expect(decisoes).to be_registered('risk_entries:legacy_total_without_installments')
    end
  end

  # ==========================================================================
  # A segunda metade: o model. Sem ela o conversor grava e o `save!` desfaz.
  # ==========================================================================
  describe 'RiskEntry#derive_scope_and_totals' do
    let(:project) { create(:project) }
    let(:company) { create(:company, project: project) }
    let(:risk_control) { create(:risk_control, project: project) }

    def nova_posicao(**atributos)
      RiskEntry.new({ company: company, risk_control: risk_control, date: Date.new(2022, 2, 15),
                      vencidos_value: 0, a_vencer_value: 0, liquidacao_value: 0, descontos_value: 0,
                      comissaria_vencidos_value: 0, comissaria_a_vencer_value: 0,
                      fomento_vencidos_value: 0, fomento_a_vencer_value: 0,
                      intercompany_vencidos_value: 0, intercompany_a_vencer_value: 0 }.merge(atributos))
    end

    it 'PRESERVA o total quando a carga pede — e é isso que faz a cópia chegar ao banco' do
      posicao = nova_posicao(comissaria_total_value: 750_000, preserve_legacy_totals: true)
      posicao.save!

      expect(posicao.reload.comissaria_total_value).to eq(750_000)
    end

    it 'RECALCULA por padrão — a regra da tela não muda' do
      posicao = nova_posicao(comissaria_total_value: 750_000)
      posicao.save!

      expect(posicao.reload.comissaria_total_value).to eq(0)
    end

    it 'continua derivando o escopo mesmo com a chave ligada — integridade não é dado do cliente' do
      posicao = nova_posicao(comissaria_total_value: 750_000, preserve_legacy_totals: true)
      posicao.save!

      expect(posicao.project_id).to eq(project.id)
      expect(posicao.risk_control_title).to eq(risk_control.title)
    end
  end
end
