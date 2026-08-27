# frozen_string_literal: true

require 'rails_helper'

# S6 / `BE-160` (parte de dados) — **a alíquota de IOF com VIGÊNCIA**, que é a
# correção do **D-15**.
#
# ## O defeito, em uma linha do legado
#
# `../sfg/app/models/receivable_entry.rb:54` traz as duas alíquotas **cravadas
# dentro da fórmula**:
#
#     (vlr_bruto_final - v_advlr_iof) * (prz_med_pond_bco * 0.000041) +
#     (vlr_bruto_final - v_advlr_iof) * 0.0038
#
# Enquanto a alíquota nunca muda, funciona — e ela nunca mudou nos três anos de
# produção, o que é exatamente o motivo de o defeito nunca ter aparecido. No dia
# em que um decreto mudar a alíquota, **todo recálculo de borderô histórico
# passa a usar a alíquota de hoje**, em silêncio. Inclusive o recálculo em lote
# (`OPS-151`), que é justamente o que roda sobre a base inteira.
#
# `iof_rates` é a única tabela desta fatia que **não existe no legado**. O que
# este arquivo prova é que ela faz a única coisa que precisa fazer: devolver a
# alíquota **da data da operação**, e nunca duas.
RSpec.describe IofRate do
  # As alíquotas de origem, as mesmas de `receivable_entry.rb:54`.
  ORIGEM_DIARIA = BigDecimal('0.000041')
  ORIGEM_FIXA = BigDecimal('0.0038')
  # Uma segunda vigência **hipotética** — não há decreto real por trás dela.
  # Serve para tornar visível a diferença que o D-15 esconde: com uma alíquota
  # só, "usar a de hoje" e "usar a da data" produzem o mesmo número, e o
  # defeito fica indistinguível do acerto.
  NOVA_DIARIA = BigDecimal('0.000082')
  NOVA_FIXA = BigDecimal('0.0076')

  # Um borderô mínimo, sem tarifa de advalorem nem de deságio: assim a base do
  # IOF é o bruto final inteiro e o número esperado sai da conta na mão.
  def entrada(bruto: '100000.00', prazo_banco: '30')
    Receivables::Calculator::Input.new(
      valor_bruto: BigDecimal(bruto), vlr_bruto_recusado: 0,
      qtd_titulos: 10, qtd_recusada: 0,
      prz_med_pond_emp: BigDecimal('28'), prz_med_pond_bco: BigDecimal(prazo_banco),
      float_acordado: BigDecimal('2'), cst_efetivo_acordado: BigDecimal('2.5'),
      recompra: 0, retencao: 0, fomento: 0, outros: 0, taxes: []
    )
  end

  # ====================================================================
  # `effective_on` — a resolução por data
  # ====================================================================
  describe '.effective_on' do
    let!(:origem) do
      create(:iof_rate, daily_rate: ORIGEM_DIARIA, fixed_rate: ORIGEM_FIXA,
                        valid_from: Date.new(2016, 1, 1), valid_to: Date.new(2024, 12, 31))
    end
    let!(:nova) do
      create(:iof_rate, daily_rate: NOVA_DIARIA, fixed_rate: NOVA_FIXA,
                        valid_from: Date.new(2025, 1, 1), valid_to: nil)
    end

    it 'devolve o par [diária, fixa] da vigência da data' do
      # Par de `Float`, não de `BigDecimal`, porque é o que o
      # `Receivables::Calculator` consome — ele não conhece `ActiveRecord` nem
      # `BigDecimal` na entrada das alíquotas.
      expect(described_class.effective_on(Date.new(2022, 6, 15))).to eq([0.000041, 0.0038])
      expect(described_class.effective_on(Date.new(2025, 6, 15))).to eq([0.000082, 0.0076])
    end

    it 'os limites da vigência são INCLUSIVOS nos dois lados' do
      # Um borderô lançado no primeiro ou no último dia da vigência não pode
      # cair no vazio: `valid_from: ..data` e `valid_to >= data`.
      expect(described_class.effective_record_on(Date.new(2016, 1, 1))).to eq(origem)
      expect(described_class.effective_record_on(Date.new(2024, 12, 31))).to eq(origem)
      expect(described_class.effective_record_on(Date.new(2025, 1, 1))).to eq(nova)
    end

    it '`valid_to` nulo é vigência ABERTA — vale para qualquer data futura' do
      expect(described_class.effective_record_on(Date.new(2099, 12, 31))).to eq(nova)
    end

    it 'devolve nil quando NÃO há linha vigente para a data' do
      expect(described_class.effective_on(Date.new(2015, 12, 31))).to be_nil
      expect(described_class.effective_record_on(Date.new(2015, 12, 31))).to be_nil
    end

    it 'aceita string e `Time`, e devolve nil em vez de levantar com lixo' do
      # A data chega de um `ReceivableEntry#date`, mas também de rake, console
      # e ETL. Levantar `Date::Error` aqui derrubaria um lote inteiro por causa
      # de uma linha com data ruim.
      expect(described_class.effective_on('2022-06-15')).to eq([0.000041, 0.0038])
      expect(described_class.effective_on(Time.zone.local(2025, 3, 1))).to eq([0.000082, 0.0076])
      expect(described_class.effective_on('não é data')).to be_nil
    end
  end

  describe 'sem NENHUMA linha cadastrada' do
    it 'devolve nil' do
      expect(described_class.count).to eq(0)
      expect(described_class.effective_on(Date.current)).to be_nil
    end

    it 'o `Receivables::Calculator` cai nas alíquotas de ORIGEM e o borderô continua calculável' do
      # É deliberado: um borderô **não pode deixar de ser calculável** porque o
      # seed não rodou. O `Calculator` recebe `iof_rate: nil` e usa
      # `LEGACY_DAILY_IOF_RATE`/`LEGACY_FIXED_IOF_RATE`, que são as duas
      # constantes de `receivable_entry.rb:54`.
      #
      # A conta: 100.000,00 × (30 × 0,000041) = 123,00 · 100.000,00 × 0,0038 =
      # 380,00 · total 503,00.
      resultado = Receivables::Calculator.call(entrada, iof_rate: described_class.effective_on(Date.current))

      expect(resultado[:checagem_iof]).to eq(BigDecimal('503.00'))
      expect(Receivables::Calculator::LEGACY_DAILY_IOF_RATE).to eq(0.000041)
      expect(Receivables::Calculator::LEGACY_FIXED_IOF_RATE).to eq(0.0038)
    end

    it 'com uma vigência DIFERENTE cadastrada, a data fora dela ainda cai na origem' do
      # É o que separa "não achei" de "achei zero". Uma data anterior à
      # primeira vigência usa a alíquota de origem — 503,00 —, e não a da
      # vigência mais próxima, que daria 1.006,00.
      create(:iof_rate, daily_rate: NOVA_DIARIA, fixed_rate: NOVA_FIXA, valid_from: Date.new(2025, 1, 1))

      antiga = Receivables::Calculator.call(entrada,
                                            iof_rate: described_class.effective_on(Date.new(2020, 1, 1)))
      vigente = Receivables::Calculator.call(entrada,
                                             iof_rate: described_class.effective_on(Date.new(2025, 6, 1)))

      expect(antiga[:checagem_iof]).to eq(BigDecimal('503.00'))
      expect(vigente[:checagem_iof]).to eq(BigDecimal('1006.00'))
    end
  end

  # ====================================================================
  # As duas validações de coerência
  # ====================================================================
  describe 'coerência do período' do
    it 'recusa `valid_to` anterior a `valid_from`' do
      registro = build(:iof_rate, valid_from: Date.new(2025, 6, 1), valid_to: Date.new(2025, 1, 1))

      expect(registro).not_to be_valid
      expect(registro.errors[:valid_to].join).to include('não pode ser anterior ao início da vigência')
    end

    it 'aceita `valid_to` IGUAL a `valid_from` — vigência de um dia é vigência' do
      expect(build(:iof_rate, valid_from: Date.new(2025, 6, 1), valid_to: Date.new(2025, 6, 1))).to be_valid
    end

    it 'o `check_constraint` do banco recusa o período invertido mesmo BURLANDO o model' do
      # `iof_rates_period_check`. Segunda camada, pelo mesmo motivo de sempre:
      # o caminho que grava não é só a tela.
      registro = create(:iof_rate, valid_from: Date.new(2025, 1, 1), valid_to: Date.new(2025, 12, 31))

      expect {
        ActiveRecord::Base.transaction(requires_new: true) do
          registro.update_columns(valid_to: Date.new(2024, 1, 1))
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /iof_rates_period_check/)
    end
  end

  describe 'vigências sobrepostas' do
    # Duas alíquotas vigentes na mesma data dariam **dois resultados para o
    # mesmo borderô** conforme a ordem da consulta — `effective_record_on`
    # ordena por `valid_from DESC` e pega a primeira, então o "vencedor" seria
    # decidido por um detalhe de índice. É o tipo de ambiguidade que só aparece
    # depois, no número, quando ninguém mais lembra desta tabela.
    let!(:existente) do
      create(:iof_rate, valid_from: Date.new(2020, 1, 1), valid_to: Date.new(2024, 12, 31))
    end

    it 'recusa vigência que começa DENTRO de outra' do
      registro = build(:iof_rate, valid_from: Date.new(2022, 1, 1), valid_to: Date.new(2026, 1, 1))

      expect(registro).not_to be_valid
      expect(registro.errors[:base].join).to include('Já existe uma alíquota de IOF vigente neste período')
    end

    it 'recusa vigência que TERMINA dentro de outra' do
      expect(build(:iof_rate, valid_from: Date.new(2018, 1, 1), valid_to: Date.new(2021, 1, 1))).not_to be_valid
    end

    it 'recusa vigência que ENGOLE outra' do
      expect(build(:iof_rate, valid_from: Date.new(2019, 1, 1), valid_to: Date.new(2030, 1, 1))).not_to be_valid
    end

    it 'recusa vigência ABERTA que alcança uma existente' do
      # `valid_to` nulo é tratado como 31/12/9999 na checagem — sem isso, a
      # vigência aberta passaria por não ter fim para comparar.
      expect(build(:iof_rate, valid_from: Date.new(2023, 1, 1), valid_to: nil)).not_to be_valid
    end

    it 'recusa vigência IDÊNTICA' do
      expect(build(:iof_rate, valid_from: Date.new(2020, 1, 1), valid_to: Date.new(2024, 12, 31))).not_to be_valid
    end

    it 'aceita vigência ENCOSTADA, sem sobrepor' do
      # 01/01/2025 começa no dia seguinte ao fim da anterior. É o caso normal:
      # um decreto entra em vigor no dia em que o anterior deixa de valer.
      expect(build(:iof_rate, valid_from: Date.new(2025, 1, 1), valid_to: nil)).to be_valid
      expect(build(:iof_rate, valid_from: Date.new(2015, 1, 1), valid_to: Date.new(2019, 12, 31))).to be_valid
    end

    it 'a EDIÇÃO do próprio registro não conflita consigo mesma' do
      # O `where.not(id: id)` da validação. Sem ele, salvar de novo o mesmo
      # registro seria recusado por sobrepor a si próprio — e a linha ficaria
      # impossível de corrigir.
      existente.note = 'Alíquota de origem'
      expect(existente).to be_valid
      expect(existente.save).to be(true)
    end

    it 'a exclusividade também exige alíquotas presentes e numéricas' do
      expect(build(:iof_rate, daily_rate: nil)).not_to be_valid
      expect(build(:iof_rate, fixed_rate: nil)).not_to be_valid
      expect(build(:iof_rate, valid_from: nil)).not_to be_valid
    end
  end

  # ====================================================================
  # D-15 — o ponto do model
  # ====================================================================
  describe 'D-15 — um borderô de 2022 recalculado HOJE usa a alíquota DE 2022' do
    before do
      create(:iof_rate, daily_rate: ORIGEM_DIARIA, fixed_rate: ORIGEM_FIXA,
                        valid_from: Date.new(2016, 1, 1), valid_to: Date.new(2024, 12, 31))
      create(:iof_rate, daily_rate: NOVA_DIARIA, fixed_rate: NOVA_FIXA,
                        valid_from: Date.new(2025, 1, 1), valid_to: nil)
    end

    it '`checagem_iof` difere conforme a DATA do borderô, com a mesma entrada' do
      # O mesmo `Input`, palavra por palavra. A única variável é a data com que
      # a alíquota foi resolvida — e é isso que o legado não tinha como fazer,
      # porque a alíquota era literal na fórmula.
      #
      # 2022: 100.000 × (30 × 0,000041) + 100.000 × 0,0038 = 123,00 + 380,00 = 503,00
      # 2025: 100.000 × (30 × 0,000082) + 100.000 × 0,0076 = 246,00 + 760,00 = 1.006,00
      antigo = Receivables::Calculator.call(entrada,
                                            iof_rate: described_class.effective_on(Date.new(2022, 6, 15)))
      novo = Receivables::Calculator.call(entrada,
                                          iof_rate: described_class.effective_on(Date.new(2025, 6, 15)))

      expect(antigo[:checagem_iof]).to eq(BigDecimal('503.00'))
      expect(novo[:checagem_iof]).to eq(BigDecimal('1006.00'))
      expect(antigo[:checagem_iof]).not_to eq(novo[:checagem_iof])
    end

    it 'o borderô GRAVADO em 2022 recalculado hoje continua com o número de 2022' do
      # O caminho real do defeito: `Receivables::BulkRecalculateJob` roda hoje
      # sobre a base inteira. Se a alíquota fosse resolvida por `Date.current`,
      # os 28.131 borderôs históricos seriam reescritos com o número errado —
      # e ninguém veria, porque o job não compara com nada.
      entry = create(:receivable_entry, date: Date.new(2022, 6, 15),
                                        valor_bruto: BigDecimal('100000.00'),
                                        prz_med_pond_emp: BigDecimal('28'),
                                        prz_med_pond_bco: BigDecimal('30'))

      hoje = Receivables::Calculator.call(entry.calculator_input,
                                          iof_rate: described_class.effective_on(Date.current))
      na_data = Receivables::Calculator.call(entry.calculator_input,
                                             iof_rate: described_class.effective_on(entry.date))

      expect(na_data[:checagem_iof]).to eq(BigDecimal('503.00'))
      expect(hoje[:checagem_iof]).to eq(BigDecimal('1006.00'))
    end

    it 'só `checagem_iof` muda — a alíquota não contamina os outros derivados' do
      # `checagem_iof` é uma COLUNA DE CONFERÊNCIA: ela não entra em
      # `valor_total_tarifas` nem em `valor_liquido`, que somam a tarifa de IOF
      # efetivamente lançada (`tarifas_iof`). Se um dia entrar, todo o resto do
      # borderô passa a depender da vigência — e este exemplo cai primeiro.
      antigo = Receivables::Calculator.call(entrada,
                                            iof_rate: described_class.effective_on(Date.new(2022, 6, 15)))
      novo = Receivables::Calculator.call(entrada,
                                          iof_rate: described_class.effective_on(Date.new(2025, 6, 15)))

      diferentes = antigo.keys.reject { |k| antigo[k] == novo[k] }
      expect(diferentes).to eq([:checagem_iof])
    end
  end

  describe 'ordenação da listagem' do
    it '`ordered` traz a vigência mais RECENTE primeiro' do
      antiga = create(:iof_rate, valid_from: Date.new(2016, 1, 1), valid_to: Date.new(2024, 12, 31))
      recente = create(:iof_rate, valid_from: Date.new(2025, 1, 1))

      expect(described_class.ordered.to_a).to eq([recente, antiga])
    end
  end
end
