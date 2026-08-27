# frozen_string_literal: true

require 'rails_helper'

# S5 — **os golden tests do motor de exposição**.
#
# > O teste não existe para provar que a fórmula está certa — existe para
# > **reprovar quem a 'consertar' depois** sem passar por uma DEC.
#
# **O que isso significa, com honestidade: nao ha oraculo.** Estes valores foram
# conferidos contra o **fonte de 2022** — arquivo e linha citados em cada
# cenario —, e nao contra comportamento observado. O golden trava a LEITURA do
# codigo de 2022; ele nao prova que o numero esta certo, prova que nao mudamos o
# que o legado fazia. A DEC-103b manda espelhar, e e isso que esta feito.
#
# **A marca serve de ponteiro:** no dia em que um numero sair estranho, ela diz
# em segundos que a resposta esta no fonte de 2022, e nao numa base de producao
# que nunca teve estes registros.
#
# O esquema tipado de risco **nunca subiu**: `change_risk_control_fields`,
# `create_risk_operation_types`, `create_risk_operations` e
# `create_risk_movements` estão entre as **24 migrations que nunca rodaram**
# (`analise-dump-producao.md` §1). Não existe uma única operação, um único
# movimento nem um único limite tipado no dump.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115
#
# A **DEC-115** reescreveu a tarefa que pedia conferir estes goldens *"contra o
# legado, com o dump carregado"*: **não existe oráculo**, e o usuário confirmou
# que não há outra base (*"nao tem, a tabela de excel que tinha foi perdida"*).
# A conferência que vale é **contra a FONTE de 2022** — o código que rodou — e a
# marca por cenário, abaixo, é exatamente o que a DEC-115 manda registrar: este
# golden tem **fonte, não oráculo**.
#
# **A marca NÃO promove nada a `verified`.** A régua desta migração é "a saída
# foi comparada com dado de produção e bateu", e para esta família isso é
# permanentemente impossível. Dissolver a distinção contaminaria os 11
# `verified` da S9, que valem 47.170 comparações reais contra o dump.
#
# **O que é validado EM produção, e vai sem marca:** as 4 famílias de limite
# (`auto_liquidavel`, `comissaria`, `fomento`, `intercompany`) e as taxas —
# 600 registros reais, três anos de uso.
#
# `DEC-01` (sinal invertido) e `DEC-02` (aritmética em float) são melhorias
# **DECLINADAS pelo usuário** (`improvements-log.md`, D-93 e D-104). O
# comportamento estranho **é o requisito**. Se algum destes exemplos falhar
# porque alguém achou o número "errado", a mudança precisa de uma decisão
# registrada — não de um `git commit`.
RSpec.describe Risk::Calculator do
  # ---------------------------------------------------------------------------
  # Cenário L1 — tipo SEM pré-faturamento
  # ---------------------------------------------------------------------------
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/risk_control.rb:115-160`
  # e `../sfg/app/models/risk_operation.rb:92-96,103-111`.
  describe 'scenario L1 — type without pre-billing' do
    let!(:cenario) { cenario_l1 }
    let(:control) { cenario[:control] }
    let(:operation) { cenario[:operation] }

    # --- BE-266 -------------------------------------------------------------
    describe '#balance_on (BE-266)' do
      it 'returns 0 before the first movement, NOT original_balance' do
        # A linha mais fácil de "consertar sem querer" do bloco.
        # `../sfg/app/models/risk_operation.rb:92-96` devolve 0 quando não há
        # movimento até a data — mesmo com `original_balance = -100.000,00`.
        expect(described_class.balance_on(operation, Date.new(2026, 2, 28))).to eq(0)
        expect(operation.original_balance).to eq(-100_000.00)
      end

      it 'returns the balance of the last movement up to the date' do
        expect(described_class.balance_on(operation, Date.new(2026, 3, 31))).to eq(2_500.00)
        expect(described_class.balance_on(operation, Date.new(2026, 5, 1))).to eq(-27_500.00)
      end

      it 'returns 0.00 on the release date — the chain zeroes the initial balance' do
        expect(described_class.balance_on(operation, Date.new(2026, 3, 1))).to eq(0.00)
      end
    end

    # --- BE-242 -------------------------------------------------------------
    describe '#operations_on (BE-242)' do
      it 'uses a CLOSED interval on both ends' do
        expect(described_class.operations_on(control, Date.new(2026, 3, 1))).to include(operation)
        expect(described_class.operations_on(control, Date.new(2026, 6, 30))).to include(operation)
        expect(described_class.operations_on(control, Date.new(2026, 2, 28))).not_to include(operation)
        expect(described_class.operations_on(control, Date.new(2026, 7, 1))).not_to include(operation)
      end

      it 'still includes ENDED operations — there is no is_ended filter here (DEC-35)' do
        operation.update!(is_ended: true)
        expect(described_class.operations_on(control, Date.new(2026, 3, 31))).to include(operation)
      end
    end

    # --- BE-243 · DEC-01 ----------------------------------------------------
    describe '#limite_utilizado_on (BE-243) — the × (−1) is REPLICATED' do
      it 'produces NEGATIVE utilisation while the operation is in debit' do
        # Saldo devedor de 2.500,00 vira utilização de −2.500,00. Parece errado
        # e é o requisito: DEC-01, melhoria declinada.
        expect(described_class.limite_utilizado_on(control, Date.new(2026, 3, 31))).to eq(-2_500.00)
      end

      it 'produces POSITIVE utilisation after the settlement flips the sign' do
        expect(described_class.limite_utilizado_on(control, Date.new(2026, 5, 1))).to eq(27_500.00)
      end
    end

    # --- BE-244 / BE-245 ----------------------------------------------------
    describe '#limite_liquidavel_on and #limite_pre_on without pre-billing' do
      it 'makes liquidavel EQUAL to utilizado — it sums every operation in the window' do
        # É o `else` de `risk_control.rb:131-133`: sem pré-faturamento não há
        # filtro por subtipo, então os dois números são o mesmo.
        data = Date.new(2026, 5, 1)
        expect(described_class.limite_liquidavel_on(control, data))
          .to eq(described_class.limite_utilizado_on(control, data))
      end

      it 'returns 0 for limite_pre_on' do
        expect(described_class.limite_pre_on(control, Date.new(2026, 5, 1))).to eq(0)
      end
    end

    # --- BE-246 · DEC-02 ----------------------------------------------------
    describe '#limite_disponivel_on (BE-246) — the .to_f is REPLICATED' do
      it 'returns 202500.0 as a Float while utilisation is negative' do
        resultado = described_class.limite_disponivel_on(control, Date.new(2026, 3, 31))
        expect(resultado).to eq(202_500.0)
        # O TIPO faz parte do contrato: trocar por BigDecimal mudaria o número
        # que a tela imprime em outros casos (DEC-02).
        expect(resultado).to be_a(Float)
      end

      it 'returns 172500.0 as a Float after the settlement' do
        resultado = described_class.limite_disponivel_on(control, Date.new(2026, 5, 1))
        expect(resultado).to eq(172_500.0)
        expect(resultado).to be_a(Float)
      end
    end

    # --- BE-247 / BE-248 ----------------------------------------------------
    describe '#vencidos_on and #a_vencer_on (BE-247, BE-248)' do
      it 'does NOT invert the sign — the opposite convention of limite_utilizado_on' do
        data = Date.new(2026, 5, 1)
        # A operação não está encerrada, então cai em `a_vencer_on`.
        expect(described_class.a_vencer_on(control, data)).to eq(-27_500.00)
        expect(described_class.vencidos_on(control, data)).to eq(0)
        # E o mesmo saldo, com o sinal invertido, em `limite_utilizado_on`.
        expect(described_class.limite_utilizado_on(control, data)).to eq(27_500.00)
      end

      it 'moves the operation to vencidos_on when it is flagged as ended' do
        operation.update!(is_ended: true)
        data = Date.new(2026, 5, 1)
        expect(described_class.vencidos_on(control, data)).to eq(-27_500.00)
        expect(described_class.a_vencer_on(control, data)).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cenário L2 — tipo COM pré-faturamento
  # ---------------------------------------------------------------------------
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/risk_control.rb:18-64`
  # (o `after_create` do par estático) e `:126-156` (os dois buckets).
  describe 'scenario L2 — type WITH pre-billing' do
    let!(:cenario) { cenario_l2 }
    let(:control) { cenario[:control] }

    it 'opens the static pair with the balances CROSSED correctly (BE-241)' do
      # A pré recebe `original_balance_pre`; a antecipação recebe
      # `original_balance`. Invertê-los põe o saldo inicial no bucket errado.
      # Gravados NEGATIVOS (DEC-01).
      expect(cenario[:pre].original_balance).to eq(-30_000.00)
      expect(cenario[:antecipacao].original_balance).to eq(-50_000.00)
      expect(cenario[:pre].pair_id).to eq(cenario[:antecipacao].id)
      expect(cenario[:antecipacao].pair_id).to eq(cenario[:pre].id)
    end

    it 'gives the static pair NULL dates instead of the ±2000-year sentinels (B-08)' do
      expect(cenario[:pre].issue_date).to be_nil
      expect(cenario[:pre].due_date).to be_nil
      expect(cenario[:pre].is_static).to be(true)
    end

    it 'returns 0.00 for balance_on of a static operation on ANY date' do
      # Não há movimento, logo `balance_on` devolve 0 — **não**
      # `original_balance`. Consequência: o saldo inicial configurado no limite
      # NÃO entra no agregado. É assim que o painel calcula hoje.
      [Date.new(1900, 1, 1), Date.current, Date.new(2100, 1, 1)].each do |data|
        expect(described_class.balance_on(cenario[:pre], data)).to eq(0.00)
        expect(described_class.balance_on(cenario[:antecipacao], data)).to eq(0.00)
      end
    end

    it 'includes the static pair in the window on ANY date (OPS-233 / B-08)' do
      [Date.new(1900, 1, 1), Date.current, Date.new(2100, 1, 1)].each do |data|
        ids = described_class.operations_on(control, data).pluck(:id)
        expect(ids).to include(cenario[:pre].id, cenario[:antecipacao].id)
      end
    end

    it 'keeps limite_utilizado_on at 0.00 — the configured initial balance does NOT count' do
      expect(described_class.limite_utilizado_on(control, Date.current)).to eq(0.00)
      expect(described_class.limite_liquidavel_on(control, Date.current)).to eq(0.00)
      expect(described_class.limite_pre_on(control, Date.current)).to eq(0.00)
    end

    it 'splits liquidavel and pre by subtype once there are movements' do
      debito = create(:risk_movement_type, :debito, title: 'L2 débito')
      encadear_movimentos!(cenario[:antecipacao],
                           [{ date: Date.new(2026, 4, 1), type: debito, value: 10_000.00 }])
      encadear_movimentos!(cenario[:pre],
                           [{ date: Date.new(2026, 4, 1), type: debito, value: 4_000.00 }])

      data = Date.new(2026, 4, 30)
      # antecipação: −50.000 + 10.000 = −40.000 → liquidável = +40.000
      expect(described_class.limite_liquidavel_on(control, data)).to eq(40_000.00)
      # pré: −30.000 + 4.000 = −26.000 → pré = +26.000
      expect(described_class.limite_pre_on(control, data)).to eq(26_000.00)
      # utilizado é a soma dos dois buckets
      expect(described_class.limite_utilizado_on(control, data)).to eq(66_000.00)
    end
  end
end
