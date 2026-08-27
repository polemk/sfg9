# frozen_string_literal: true

require 'rails_helper'

# **DEC-128.3** — os 32 borderôs com `NaN` são **recalculados pelo motor**.
#
# Diferente da tarifa (DEC-120, que entra NULA): aqui o `NaN` está nos campos
# derivados, e recalcular **não inventa dado** — restaura o que o próprio cálculo
# deveria ter gravado, pelo mesmo motor que a tela usa (contrato **C2**).
#
# A forma da linha deste arquivo é a de `legacy_id = 18097` no dump de
# 31/05/2025: `recompra` com `NaN` (campo em branco da tela — `parseFloat("")`),
# `total_deducoes`, `vlr_liq_recebido` e `recompra_percent` contaminados, e o
# resto íntegro.
#
# O que este arquivo trava, e que é o mais fácil de perder depois:
#
#   * só as colunas **não finitas** são substituídas — as derivadas íntegras
#     continuam COPIADAS (DEC-30), senão a carga apagaria a evidência do D-09;
#   * `NaN` numa **dedução digitável** entra 0,00, que é o que o servidor do
#     legado já fazia com campo em branco;
#   * `NaN` em `valor_bruto` é **outra coisa** e tem chave de decisão própria —
#     ali não há derivado a restaurar.
RSpec.describe 'DEC-128.3 — os 32 borderôs com `NaN` nos derivados' do
  let(:de_para) do
    {
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[companies 3] => 'bbbbbbbb-0000-4000-8000-000000000002',
      %w[carriers 5] => 'cccccccc-0000-4000-8000-000000000003'
    }
  end

  let(:origem) { instance_double(Sfg::Etl::Source::Base) }

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    allow(duplo).to receive(:source).and_return(origem)
    duplo
  end

  subject(:conversor) { Sfg::Etl::Converters::ReceivableEntries.new(run) }

  # Uma tarifa de deságio, que é o que o borderô 18097 tem.
  let(:tarifas) do
    [{ 'id' => 900, 'receivable_entry_id' => 18_097, 'value' => '7076.90',
       'is_advalorem' => 0, 'is_desagio' => 1, 'is_iof' => 0 }]
  end

  before do
    allow(origem).to receive(:table?).with('receivable_taxes').and_return(true)
    allow(origem).to receive(:ordered_rows).with('receivable_taxes').and_return(tarifas)
  end

  # `valor_bruto − tarifas = 712.527,90`, que é o `valor_liquido` que produção
  # gravou nessa linha (e que chegou ÍNTEGRO — só os que dependem de `recompra`
  # foram contaminados).
  def bordero(**sobrescritas)
    {
      'id' => 18_097, 'project_id' => 7, 'company_id' => 3, 'carrier_id' => 5,
      'wallet_id' => nil, 'receivable_kind_id' => nil, 'resource_source_id' => nil, 'user_id' => nil,
      'date' => '2022-06-10', 'data_credito' => '2022-06-12', 'nro_bordero' => 'F-76',
      'contrato' => nil, 'description' => nil, 'observacoes' => nil,
      'has_safegold_management' => 1, 'status' => 'OK', 'legacy_id' => nil,
      'created_at' => '2022-06-10 09:00:00', 'updated_at' => '2022-06-10 09:00:00',

      'valor_bruto' => '719604.80', 'vlr_bruto_recusado' => '0.00',
      'qtd_titulos' => 12, 'qtd_recusada' => 0,
      'prz_med_pond_emp' => '25.32', 'prz_med_pond_bco' => '25.32',
      'float_acordado' => '0', 'cst_efetivo_acordado' => '1.2', 'nominal_tax' => '1.2',

      'recompra' => 'NaN', 'retencao' => '0.00', 'fomento' => '0.00', 'outros' => '0.00',

      'vlr_bruto_final' => '719604.80', 'qtd_final' => 12,
      'float_calculado' => '0.0', 'diferenca_float' => '0.0', 'checagem_iof' => '2705.34',
      'valor_total_tarifas' => '7076.90', 'valor_liquido' => '712527.90',
      'tarifas_ad_valorem' => '0.00', 'tarifas_desagio' => '7076.90',
      'tarifas_iof' => '0.00', 'tarifas_outras' => '0.00',
      'recompra_percent' => 'NaN', 'retencao_percent' => '0', 'fomento_percent' => '0',
      'outros_percent' => '0',
      'total_deducoes' => 'NaN', 'vlr_liq_recebido' => 'NaN',
      'calc_valor_liq_correto' => '711000.00', 'dif_calc_vlr_liq' => '1527.90',
      'nominal_tax_check' => '1.16', 'nominal_tax_check_with_float' => '1.16'
    }.merge(sobrescritas)
  end

  describe 'as entradas digitáveis' do
    it '`NaN` numa DEDUÇÃO entra 0,00 — campo em branco da tela, e o legado já o somava como zero' do
      expect(conversor.convert(bordero)[:recompra]).to eq(0)
    end

    it 'dedução íntegra continua como está' do
      expect(conversor.convert(bordero('retencao' => '144.54'))[:retencao]).to eq(BigDecimal('144.54'))
    end

    it '`NaN` em `valor_bruto` entra 0,00 — não há de onde tirar a raiz da conta de volta' do
      expect(conversor.convert(bordero('valor_bruto' => 'NaN'))[:valor_bruto]).to eq(0)
    end
  end

  describe 'os derivados' do
    it 'RECALCULA `total_deducoes` pelo motor C2' do
      # recompra + retenção + fomento + outros, todos zero depois do saneamento.
      expect(conversor.convert(bordero)[:total_deducoes]).to eq(0)
    end

    it 'RECALCULA `vlr_liq_recebido` — líquido menos as deduções' do
      expect(conversor.convert(bordero)[:vlr_liq_recebido]).to eq(BigDecimal('712527.90'))
    end

    it 'RECALCULA `recompra_percent` e o devolve como `float` (DEC-117)' do
      convertido = conversor.convert(bordero)

      expect(convertido[:recompra_percent]).to eq(0.0)
      expect(convertido[:recompra_percent]).to be_a(Float)
    end

    it 'NÃO recalcula os derivados que chegaram íntegros — eles continuam COPIADOS (DEC-30)' do
      # `calc_valor_liq_correto` da origem é 711.000,00; o motor daria outro
      # número. Copiar é o que preserva a evidência do D-09.
      convertido = conversor.convert(bordero)

      expect(convertido[:calc_valor_liq_correto]).to eq(BigDecimal('711000.00'))
      expect(convertido[:valor_liquido]).to eq(BigDecimal('712527.90'))
      expect(convertido[:tarifas_desagio]).to eq(BigDecimal('7076.90'))
    end

    it 'borderô SEM `NaN` não passa pelo motor — nada muda no caminho normal' do
      limpo = bordero('recompra' => '100.00', 'recompra_percent' => '0.014',
                      'total_deducoes' => '100.00', 'vlr_liq_recebido' => '712427.90')
      convertido = conversor.convert(limpo)

      expect(convertido[:total_deducoes]).to eq(BigDecimal('100.00'))
      expect(convertido[:vlr_liq_recebido]).to eq(BigDecimal('712427.90'))
      expect(convertido[:recompra_percent]).to eq(0.014)
    end

    # DEC-120: a tarifa de valor desconhecido fica FORA da soma — não é o mesmo
    # que somar zero, e é este conversor que alimenta o motor com ela.
    it 'a tarifa com `NaN` fica FORA da soma do recálculo (DEC-120)' do
      allow(origem).to receive(:ordered_rows).with('receivable_taxes').and_return(
        tarifas + [{ 'id' => 901, 'receivable_entry_id' => 18_097, 'value' => 'NaN',
                     'is_advalorem' => 0, 'is_desagio' => 1, 'is_iof' => 0 }]
      )

      # Com a tarifa desconhecida de fora, o líquido do motor continua sendo
      # bruto − 7.076,90 — e é dele que sai o `vlr_liq_recebido`.
      expect(conversor.convert(bordero)[:vlr_liq_recebido]).to eq(BigDecimal('712527.90'))
    end
  end

  describe 'o relatório — origem e recalculado lado a lado' do
    it 'LISTA os derivados com o valor de origem e o recalculado' do
      linha = conversor.anomalies(bordero)
              .find { |a| a.is_a?(Hash) && a[:key] == 'custom:receivable_entries_nan_derived' }

      expect(linha[:line]).to include('total_deducoes: NaN -> 0.0')
      expect(linha[:line]).to include('vlr_liq_recebido: NaN -> 712527.9')
      expect(linha[:line]).to include('Receivables::Calculator')
    end

    it 'o valor listado é EXATAMENTE o gravado — a lista sai do próprio `convert`' do
      gravado = conversor.convert(bordero)
      linha = conversor.anomalies(bordero)
              .find { |a| a.is_a?(Hash) && a[:key] == 'custom:receivable_entries_nan_derived' }

      expect(linha[:line]).to include(gravado[:vlr_liq_recebido].to_s('F'))
    end

    it 'LISTA a dedução zerada, com o motivo' do
      linhas = conversor.anomalies(bordero).select { |a| a.is_a?(Hash) }
      texto = linhas.map { |l| l[:line] }.join

      expect(texto).to include('`recompra`')
      expect(texto).to include('campo em branco')
    end

    it '`valor_bruto` com `NaN` sai em chave de decisão PRÓPRIA' do
      chaves = conversor.anomalies(bordero('valor_bruto' => 'NaN'))
                        .select { |a| a.is_a?(Hash) }.map { |a| a[:key] }

      expect(chaves).to include('custom:receivable_entries_nan_input')
    end

    it 'borderô íntegro não gera nenhuma anomalia de `NaN`' do
      limpo = bordero('recompra' => '0.00', 'recompra_percent' => '0',
                      'total_deducoes' => '0.00', 'vlr_liq_recebido' => '712527.90')
      chaves = conversor.anomalies(limpo).select { |a| a.is_a?(Hash) }.map { |a| a[:key] }

      expect(chaves).not_to include('custom:receivable_entries_nan_derived')
      expect(chaves).not_to include('custom:receivable_entries_nan_input')
    end

    it 'as duas chaves estão ASSINADAS em `decisions.yml`' do
      decisoes = Sfg::Etl::Decisions.load

      expect(decisoes).to be_registered('custom:receivable_entries_nan_derived')
      expect(decisoes).to be_registered('custom:receivable_entries_nan_input')
    end
  end

  # ==========================================================================
  # A última rede. Medida ao executar contra o dump, não deduzida.
  # ==========================================================================
  describe 'o borderô recalculado é gravável — e era isto que a carga não conseguia' do
    # A forma de `legacy_id = 22591`: a RAIZ é `NaN`, e por tabela `NaN` desce
    # para todo derivado que dependa dela.
    let(:raiz_corrompida) do
      bordero('valor_bruto' => 'NaN', 'vlr_bruto_final' => 'NaN', 'valor_liquido' => 'NaN',
              'nominal_tax_check' => 'NaN', 'nominal_tax_check_with_float' => 'NaN',
              'calc_valor_liq_correto' => 'NaN', 'dif_calc_vlr_liq' => 'NaN')
    end

    it 'nenhum atributo sai não finito' do
      convertido = conversor.convert(raiz_corrompida)
      nao_finitos = convertido.select { |_k, v| Receivables::InputGuard.nonfinite?(v) }

      expect(nao_finitos).to be_empty
    end

    # Com `valor_bruto` zerado, `nominal_tax_check` divide por zero e o motor
    # devolve `Infinity`. A coluna aceita nulo — e o legado já a tem nula em
    # 18.900 linhas —, então entra NULO: "não sei", e não um número inventado.
    it 'derivado que continua infinito depois do recálculo entra NULO onde a coluna aceita' do
      expect(conversor.convert(raiz_corrompida)[:nominal_tax_check]).to be_nil
    end

    it 'onde a coluna é `null: false`, entra zero em vez de nulo' do
      expect(conversor.convert(raiz_corrompida)[:valor_bruto]).to eq(0)
      expect(conversor.convert(raiz_corrompida)[:vlr_bruto_final]).not_to be_nil
    end

    # O portão de verdade: o `ReceivableEntry` recusava esta linha inteira por
    # `derived_values_must_be_finite`, e a carga fechava 28.130 de 28.131.
    # Perder o borderô por causa de uma taxa apurada e trocar um dado ausente
    # por um borderô ausente é o oposto de "nada se perde".
    it 'a validação do model ACEITA o borderô — a linha deixa de ser recusada' do
      registro = ReceivableEntry.new(conversor.convert(raiz_corrompida).except(:legacy_id))
      registro.valid?

      expect(registro.errors[:base].join).not_to include('infinito')
    end
  end
end
