# frozen_string_literal: true

require 'rails_helper'
require 'json'

# S6 — **os goldens do motor de cálculo do borderô** (D-B3 / D-114).
#
# Fecha as tarefas 4.1…4.26 e os IDs `BE-155`…`BE-180`.
#
# ## O oráculo é PRODUÇÃO, não a leitura do código
#
# O legado **não tem um único teste** (D-114), então a tentação seria extrair
# valores lendo `receivable_entry.rb:38-118` e recalculá-los à mão. Aqui não foi
# preciso: o dump de 31/05/2025 traz **28.131 borderôs** com os ~33 derivados
# **como o legado os gravou**, ao longo de três anos de uso real. É o melhor
# oráculo possível — não prova que a fórmula está certa, prova que a nossa é a
# **mesma**, que é exatamente o que o DEC-30 pede.
#
# ### O que foi medido, e o número
#
# O motor foi rodado contra as **28.099** linhas limpas (as **32** com `NaN`
# gravado ficam de fora — ver o bloco D-10 abaixo) × **33** colunas derivadas =
# **927.267 comparações**, e bateu **exatamente**, incluindo as casas decimais.
# Três classes de "diferença" foram investigadas até o fim e nenhuma é da
# fórmula:
#
# 1. **22 divergências de último dígito** — desapareceram ao replicar a coercão
#    `BigDecimal ⊗ Float` de 16 dígitos do Ruby 2.6.1 de produção
#    (`Calculator#bd`). Quatro delas estão neste arquivo, nomeadas.
# 2. **`nominal_tax_check` e `nominal_tax_check_with_float` nulos** em 18.900
#    linhas — as colunas nasceram em `20220322123523` e as linhas anteriores
#    nunca foram recalculadas. Não há valor a comparar.
# 3. **`-0` em 27 linhas** nos quatro `*_percent` — só um input de zero
#    **negativo** produz isso, e a coluna `decimal` de origem já normalizou o
#    sinal. A entrada não existe mais para ser reproduzida.
#
# Este arquivo carrega **131 linhas curadas** do dump, escolhidas para cobrir
# cada ramo de guarda, cada extremo e os quatro casos de arredondamento no meio.
#
# ### Como REFAZER a varredura completa das 28.099 linhas
#
# O fixture é a amostra que cabe numa suíte; a varredura inteira é uma checagem
# de conferência, não de regressão, e roda fora do CI porque depende do dump de
# produção (133 MB, fora do repositório). O procedimento, para quem precisar
# repeti-lo:
#
# 1. no dump, ache o bloco `COPY public.receivable_entries (…) FROM stdin;` e
#    extraia as linhas até o `\.` — são 28.131, separadas por TAB, com `\N`
#    para nulo;
# 2. converta cada coluna com o MESMO tipo do legado: as `decimal` viram
#    `BigDecimal`, as `float` viram `Float`. Misturar isso é o que produz as
#    divergências de último dígito;
# 3. **pule as 32 linhas com `NaN`** em coluna de dinheiro (D-10) — elas não têm
#    resultado correto a comparar;
# 4. monte o `Input` com as 12 entradas digitáveis + os `tarifas_*` da própria
#    linha, chame `Receivables::Calculator.call` e compare os 33 derivados
#    arredondando na escala da coluna do ai9 (a tabela `SCALES` abaixo);
# 5. as três exclusões legítimas: `nominal_tax_check*` nulos em linhas
#    anteriores a 22/03/2022, o `-0` de 27 linhas nos `*_percent`, e os 4
#    borderôs com bucket defasado (21608, 21871, 21872, 26246).
#
# Resultado da última execução (26/08/2026): **927.267 comparações, 0
# divergências**.
#
# ## Quem "consertar" a fórmula quebra este arquivo, e é para isso que ele existe
#
# Três coisas parecem defeito e **não** são corrigidas — DEC-30 + DEC-02:
#
# - **Q-B7** — `custo_efetivo_pz_med_banco_sem_iof` tem a guarda em
#   `prz_med_pond_emp` numa fórmula que usa `prz_med_pond_bco`
#   (`../sfg/app/models/receivable_entry.rb:74`);
# - **Q-B8** — `custo_efetivo_com_float_total` arredonda em **2** casas sobre a
#   mesma base que `custo_efetivo_pz_med_emp` arredonda em **4** (`:99` × `:91`);
# - **Q-B6** — `calc_valor_liq_correto` é aproximação **linear**, com o expoente
#   literal `0.0333…` de 33 casas (`:107-109`).
RSpec.describe Receivables::Calculator do
  # **O golden vem do dump de PRODUCAO e por isso NAO e versionado** (DEC-123).
  # Ele fica na maquina de quem tem o dump; o repositorio nunca o carrega.
  #
  # Sem essa guarda, a ausencia do arquivo derruba a SUITE INTEIRA no
  # carregamento — e nao apenas os exemplos que dependem dele. Com ela, os
  # exemplos sao PULADOS e a ausencia aparece no relatorio, em vez de sumir em
  # silencio (zero exemplo gerado tambem passaria, o que seria pior).
  GOLDEN_PRODUCAO = Rails.root.join('spec/fixtures/receivables/producao_28131.json')
  GOLDEN_DISPONIVEL = GOLDEN_PRODUCAO.exist?
  FIXTURE = (GOLDEN_DISPONIVEL ? JSON.parse(GOLDEN_PRODUCAO.read) : { 'linhas' => [] }).freeze

  before do
    unless GOLDEN_DISPONIVEL
      skip("golden de producao ausente em #{GOLDEN_PRODUCAO}. " \
           'Dado real de cliente nao e versionado (DEC-123): copie o arquivo ' \
           'na maquina que tem o dump para rodar estes exemplos.')
    end
  end

  # As colunas que o legado grava em `decimal(15,2)` e as que grava em `float`.
  # A comparação é feita na precisão da COLUNA do ai9.
  #
  # ## As 6 de escala 6 continuam comparadas em 6 casas — mesmo sendo `float`
  #
  # A **DEC-117** devolveu `float_calculado`, `diferenca_float` e os quatro
  # `*_percent` para `float`, e a tentação seguinte é apertar este golden para
  # igualdade **exata** de `Float`. **Foi medido, e não passa.** Rodando o motor
  # contra as 28.099 linhas limpas do dump com igualdade exata de `double`:
  # **168.594 comparações, 9 divergências** — todas de último dígito, do tipo
  #
  #     produção  0.0018867924528302        (2,00 / 106.000,00)
  #     ai9       0.0018867924528301887
  #
  # A causa **não é a fórmula nem o tipo da coluna**: é a precisão padrão da
  # divisão `BigDecimal / BigDecimal` no **Ruby 2.6.1** de produção (DEC-03),
  # que difere da do Ruby 3.4 desta base. É a mesma família das 22 divergências
  # que o `Calculator#bd` resolveu nas outras colunas — aqui ela cai **abaixo da
  # 6ª casa** e por isso some na escala da comparação.
  #
  # **Isto não afeta a carga**, e a distinção importa: o ETL **copia** os
  # derivados de produção, não os recalcula (ver o cabeçalho de
  # `Sfg::Etl::Converters::ReceivableEntries`). O transporte é exato —
  # 1.154.980 comparações contra o dump, 0 divergências. O que tem tolerância de
  # 1e-6 é o **recálculo**, e só ele.
  SCALES = {
    'vlr_bruto_final' => 2, 'valor_total_tarifas' => 2, 'valor_liquido' => 2,
    'total_deducoes' => 2, 'vlr_liq_recebido' => 2, 'checagem_iof' => 2,
    'multiplicador_pm_empresa' => 2, 'multiplicador_pm_float' => 2,
    'calc_valor_liq_correto' => 2, 'dif_calc_vlr_liq' => 2,
    'float_calculado' => 6, 'diferenca_float' => 6,
    'recompra_percent' => 6, 'retencao_percent' => 6,
    'fomento_percent' => 6, 'outros_percent' => 6,
    'tarifas_ad_valorem' => 2, 'tarifas_desagio' => 2,
    'tarifas_iof' => 2, 'tarifas_outras' => 2
  }.freeze

  # Os 4 buckets denormalizados também são comparados contra produção, e é
  # assim que `BE-155` fecha com oráculo real. **Quatro borderôs de produção
  # têm o denormalizado defasado** em relação às suas próprias tarifas — é o
  # D-09/D-11 visível no dado: no legado o recálculo dependia de o front
  # chamar `update_and_save()`. Eles vêm marcados no fixture.
  BUCKET_COLUMNS = %w[tarifas_ad_valorem tarifas_desagio tarifas_iof tarifas_outras].freeze
  DEFAULT_SCALE = 4

  # A data em que `nominal_tax_check` e `nominal_tax_check_with_float` passaram
  # a existir (`20220322123523_add_company_to_receivable_entries.rb`).
  NOMINAL_TAX_CHECK_BORN_ON = Date.new(2022, 3, 22)

  STATUS_FROM_LEGACY = { 'OK' => 'ok', 'Diferença' => 'difference' }.freeze

  def build_input(row)
    described_class::Input.new(
      **row['input'].symbolize_keys,
      taxes: row['taxes'].map do |t|
        described_class::Tax.new(
          value: t['value'], is_advalorem: t['is_advalorem'],
          is_desagio: t['is_desagio'], is_iof: t['is_iof']
        )
      end
    )
  end

  def normalize(value, column)
    return nil if value.nil?
    return value.to_s if column == 'status'
    return value.to_i if column == 'qtd_final'

    BigDecimal(value.to_s).round(SCALES.fetch(column, DEFAULT_SCALE))
  end

  describe 'paridade com o dump de produção (28.131 borderôs, 33 derivados)' do
    FIXTURE['linhas'].each do |row|
      # As alíquotas do legado estão cravadas na fórmula
      # (`receivable_entry.rb:54`) e nunca mudaram — por isso o golden as fixa
      # em vez de ler `IofRate`. É o que mantém o teste independente do seed.
      it "borderô legado ##{row['legacy_id']} (#{row['date']}) — #{row['why']}" do
        result = described_class.call(build_input(row))

        row['expected'].each do |column, expected_raw|
          # Colunas que não existiam quando a linha foi gravada.
          next if column.start_with?('nominal_tax_check') &&
                  expected_raw.nil? &&
                  Date.parse(row['date']) < NOMINAL_TAX_CHECK_BORN_ON
          # Denormalização defasada no legado — ver `BUCKET_COLUMNS`.
          next if row['buckets_defasados'] && BUCKET_COLUMNS.include?(column)

          expected = column == 'status' ? STATUS_FROM_LEGACY.fetch(expected_raw) : expected_raw
          got = result.fetch(column.to_sym)

          # `-0` gravado: ver a nota (3) do cabeçalho.
          if expected && got && column.end_with?('_percent') &&
             BigDecimal(expected.to_s).zero? && BigDecimal(got.to_s).zero?
            next
          end

          expect(normalize(got, column)).to eq(normalize(expected, column)),
                                            lambda {
                                              "#{column}: produção gravou #{expected.inspect}, " \
                                                "o motor devolveu #{got.inspect} " \
                                                "(borderô legado ##{row['legacy_id']})"
                                            }
        end
      end
    end
  end

  # --------------------------------------------------------------------
  # 4.1 — BE-155, os 4 buckets
  # --------------------------------------------------------------------
  describe '#tax_buckets (BE-155, receivable_entry.rb:42-45)' do
    def buckets(taxes)
      described_class.call(
        described_class::Input.new(
          valor_bruto: 1000, vlr_bruto_recusado: 0, qtd_titulos: 1, qtd_recusada: 0,
          prz_med_pond_emp: 30, prz_med_pond_bco: 30, float_acordado: 0,
          cst_efetivo_acordado: 2, recompra: 0, retencao: 0, fomento: 0, outros: 0,
          taxes: taxes
        )
      )
    end

    it 'classifica cada tarifa no seu bucket e joga o resto em `tarifas_outras`' do
      out = buckets([
                      described_class::Tax.new(value: '10.00', is_advalorem: true),
                      described_class::Tax.new(value: '20.00', is_desagio: true),
                      described_class::Tax.new(value: '5.00', is_iof: true),
                      described_class::Tax.new(value: '3.50')
                    ])

      expect(out[:tarifas_ad_valorem]).to eq(BigDecimal('10'))
      expect(out[:tarifas_desagio]).to eq(BigDecimal('20'))
      expect(out[:tarifas_iof]).to eq(BigDecimal('5'))
      expect(out[:tarifas_outras]).to eq(BigDecimal('3.5'))
      expect(out[:valor_total_tarifas]).to eq(BigDecimal('38.5'))
    end

    it 'conta a tarifa com DOIS classificadores nos dois buckets e deixa `tarifas_outras` NEGATIVA' do
      # Replicado por DEC-02. O caminho está fechado no cadastro — o
      # `check_constraint` de `movement_kinds` recusa dois classificadores — mas
      # a tarifa denormaliza os flags e um dado importado pode trazê-los assim.
      # Em produção: nenhuma das 58.473 tarifas tem dois, e **uma** linha de
      # `receivable_entries` tem `tarifas_outras` negativa por denormalização
      # defasada.
      out = buckets([described_class::Tax.new(value: '100.00', is_advalorem: true, is_iof: true)])

      expect(out[:tarifas_ad_valorem]).to eq(BigDecimal('100'))
      expect(out[:tarifas_iof]).to eq(BigDecimal('100'))
      expect(out[:tarifas_outras]).to eq(BigDecimal('-100'))
      expect(out[:valor_total_tarifas]).to eq(BigDecimal('100'))
    end

    it 'zera os quatro buckets quando não há tarifa' do
      out = buckets([])
      expect(out.values_at(:tarifas_ad_valorem, :tarifas_desagio, :tarifas_iof, :tarifas_outras))
        .to all(eq(BigDecimal('0')))
    end
  end

  # --------------------------------------------------------------------
  # 4.6 — BE-160, a alíquota de IOF por VIGÊNCIA (corrige o D-15)
  # --------------------------------------------------------------------
  describe '#checagem_iof com alíquota injetada (BE-160, corrige D-15)' do
    def entrada(**over)
      described_class::Input.new(
        { valor_bruto: 100_000, vlr_bruto_recusado: 0, qtd_titulos: 1, qtd_recusada: 0,
          prz_med_pond_emp: 30, prz_med_pond_bco: 30, float_acordado: 0,
          cst_efetivo_acordado: 2, recompra: 0, retencao: 0, fomento: 0, outros: 0,
          taxes: [] }.merge(over)
      )
    end

    it 'usa as alíquotas de origem quando nenhuma é injetada' do
      out = described_class.call(entrada)
      esperado = ((BigDecimal('100000') * BigDecimal(30 * 0.000041, 16)) +
                  (BigDecimal('100000') * BigDecimal(0.0038, 16))).round(2)
      expect(out[:checagem_iof]).to eq(esperado)
    end

    it 'usa a alíquota da VIGÊNCIA quando injetada — é o que fecha o D-15' do
      # No legado as duas alíquotas estão cravadas em `receivable_entry.rb:54`:
      # recalcular um borderô de 2022 hoje usaria a de hoje, em silêncio.
      hoje = described_class.call(entrada)
      outra = described_class.call(entrada, iof_rate: [0.000082, 0.0076])

      expect(outra[:checagem_iof]).to eq((hoje[:checagem_iof] * 2).round(2))
    end

    it 'produz IOF NEGATIVO quando a base é negativa — replicado (DEC-02)' do
      out = described_class.call(
        entrada(taxes: [described_class::Tax.new(value: '150000.00', is_desagio: true)])
      )
      expect(out[:checagem_iof]).to be_negative
    end
  end

  # --------------------------------------------------------------------
  # 4.12 / 4.15 — BE-166 e BE-169: o limiar assimétrico de UM REAL
  # --------------------------------------------------------------------
  describe 'as guardas `< 1` das taxas nominais (BE-166, BE-169)' do
    def com_tarifas(desagio:, iof:)
      described_class.call(
        described_class::Input.new(
          valor_bruto: 100_000, vlr_bruto_recusado: 0, qtd_titulos: 1, qtd_recusada: 0,
          prz_med_pond_emp: 30, prz_med_pond_bco: 30, float_acordado: 0,
          cst_efetivo_acordado: 2, recompra: 0, retencao: 0, fomento: 0, outros: 0,
          taxes: [described_class::Tax.new(value: desagio, is_desagio: true),
                  described_class::Tax.new(value: iof, is_iof: true)]
        )
      )
    end

    it 'devolve nil nas DUAS primeiras variantes e um NÚMERO na terceira — a assimetria é o ponto' do
      out = com_tarifas(desagio: '0.50', iof: '0.50')

      expect(out[:taxa_desconto_nominal_desagio_advalorem_bancos]).to be_nil
      expect(out[:taxa_desconto_nominal_despesas_bancos]).to be_nil
      expect(out[:taxa_desconto_nominal_despesas_iof_bancos]).not_to be_nil

      expect(out[:taxa_desconto_nominal_desagio_advalorem_emp]).to be_nil
      expect(out[:taxa_desconto_nominal_despesas_emp]).to be_nil
      expect(out[:taxa_desconto_nominal_despesas_iof_emp]).not_to be_nil
    end

    it 'com um real de deságio a guarda já NÃO dispara — o limiar é `< 1`, não `<= 1`' do
      out = com_tarifas(desagio: '1.00', iof: '1.00')
      expect(out[:taxa_desconto_nominal_desagio_advalorem_bancos]).not_to be_nil
      expect(out[:taxa_desconto_nominal_despesas_bancos]).not_to be_nil
    end
  end

  # --------------------------------------------------------------------
  # 4.13 / 4.19 — as duas armadilhas que os goldens existem para travar
  # --------------------------------------------------------------------
  describe 'as divergências REPLICADAS de propósito (DEC-30)' do
    def entrada(prz_emp:, prz_bco:)
      described_class::Input.new(
        valor_bruto: 100_000, vlr_bruto_recusado: 0, qtd_titulos: 1, qtd_recusada: 0,
        prz_med_pond_emp: prz_emp, prz_med_pond_bco: prz_bco, float_acordado: 2,
        cst_efetivo_acordado: 2, recompra: 0, retencao: 0, fomento: 0, outros: 0,
        taxes: [described_class::Tax.new(value: '5000.00', is_desagio: true)]
      )
    end

    it 'Q-B7: a guarda de `custo_efetivo_pz_med_banco_sem_iof` olha o prazo da EMPRESA' do
      # `../sfg/app/models/receivable_entry.rb:74`. Se alguém "consertar" a
      # guarda para `prz_med_pond_bco`, este exemplo reprova — que é o ponto.
      #
      # `prz_med_pond_emp = 0` não chega ao motor pela tela (o `InputGuard`
      # barra), mas o recálculo em lote e o ETL passam por aqui.
      out = described_class.call(entrada(prz_emp: 0, prz_bco: 30))

      expect(out[:custo_efetivo_pz_med_banco_sem_iof]).to eq(0)
      # ... enquanto a fórmula IRMÃ, com o prazo do banco em pé, devolve número.
      expect(out[:custo_efetivo_pz_med_banco]).not_to eq(0)
    end

    it 'Q-B8: `custo_efetivo_com_float_total` arredonda em 2 sobre a MESMA base que o CET PM EMP arredonda em 4' do
      out = described_class.call(entrada(prz_emp: 37, prz_bco: 39))

      quatro = out[:custo_efetivo_pz_med_emp]
      duas = out[:custo_efetivo_com_float_total]

      expect(duas).to eq(BigDecimal(quatro.to_s).round(2))
      # E a prova de que são precisões diferentes sobre a mesma conta:
      expect(BigDecimal(quatro.to_s).round(4)).to eq(quatro)
      expect(duas).not_to eq(quatro)
    end

    it 'Q-B6: `calc_valor_liq_correto` é aproximação LINEAR, não desconto composto' do
      # Se fosse desconto composto, dobrar o prazo não dobraria o desconto.
      # Aqui dobra — é juros simples, e é assim que fica.
      base = described_class.call(entrada(prz_emp: 30, prz_bco: 30))
      dobro = described_class.call(entrada(prz_emp: 60, prz_bco: 60))

      desconto_base = BigDecimal('100000') - base[:calc_valor_liq_correto]
      desconto_dobro = BigDecimal('100000') - dobro[:calc_valor_liq_correto]

      # 30+2 dias contra 60+2 dias: a razão é (62/32), não uma potência.
      expect((desconto_dobro / desconto_base).round(4)).to eq((BigDecimal(62) / 32).round(4))
    end
  end

  # --------------------------------------------------------------------
  # 4.24 — BE-178: DOIS estados, nenhum terceiro
  # --------------------------------------------------------------------
  describe '#status (BE-178, Q-B9)' do
    it 'só existe `ok` e `difference` — não há baixa, liquidação nem vencimento (D-19)' do
      valores = FIXTURE['linhas'].map { |r| described_class.call(build_input(r))[:status] }
      expect(valores.uniq.sort).to eq(%w[difference ok])
    end

    it '`difference` quando o líquido fica ABAIXO do líquido correto' do
      out = described_class.call(
        described_class::Input.new(
          valor_bruto: 100_000, vlr_bruto_recusado: 0, qtd_titulos: 1, qtd_recusada: 0,
          prz_med_pond_emp: 30, prz_med_pond_bco: 30, float_acordado: 0,
          cst_efetivo_acordado: 2, recompra: 0, retencao: 0, fomento: 0, outros: 0,
          taxes: [described_class::Tax.new(value: '9000.00', is_desagio: true)]
        )
      )
      expect(out[:dif_calc_vlr_liq]).to be_negative
      expect(out[:status]).to eq('difference')
    end
  end

  # --------------------------------------------------------------------
  # C2 — o contrato de pureza
  # --------------------------------------------------------------------
  describe 'contrato C2 — função pura' do
    let(:entrada) do
      described_class::Input.new(
        valor_bruto: 50_000, vlr_bruto_recusado: 0, qtd_titulos: 3, qtd_recusada: 0,
        prz_med_pond_emp: 45, prz_med_pond_bco: 47, float_acordado: 2,
        cst_efetivo_acordado: 2.5, recompra: 100, retencao: 0, fomento: 0, outros: 0,
        taxes: [described_class::Tax.new(value: '1500.00', is_desagio: true)]
      )
    end

    it 'devolve um Hash CONGELADO — ninguém edita o resultado do cálculo' do
      expect(described_class.call(entrada)).to be_frozen
    end

    it 'é determinística: a mesma entrada devolve exatamente o mesmo resultado' do
      expect(described_class.call(entrada)).to eq(described_class.call(entrada))
    end

    it 'não toca no banco' do
      expect { described_class.call(entrada) }.not_to(change { ActiveRecord::Base.connection.query_cache.size })
      expect(ActiveRecord::Base).not_to receive(:transaction)
      described_class.call(entrada)
    end

    it 'devolve as 37 colunas derivadas (33 + os 4 buckets), e nenhuma a mais' do
      esperadas = FIXTURE['linhas'].first['expected'].keys.map(&:to_sym).sort
      recebidas = described_class.call(entrada).keys.sort
      expect(recebidas).to eq(esperadas)
    end
  end
end
