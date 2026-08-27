# frozen_string_literal: true

require 'rails_helper'

# S5 — **os golden tests dos agregados** (`L3` e `L4`).
#
# O que este arquivo trava, além dos números:
#
# 1. **Que os dois ramos NÃO são iguais.** O `design.md` da fatia afirma que
#    `company.rb` ≡ `project.rb` linha a linha; conferido na fonte, **não são**.
#    Os dois erros de rótulo do D-95 existem só no caminho da EMPRESA. DEC-01
#    manda replicar os dois comportamentos, e há exemplo para cada um.
# 2. **Que as quatro chaves de `total_limits_on` são a mesma string** — o que
#    parece bug de porte e é o que `company.rb:79-82` devolve.
# 3. **A divisão protegida**: total zero com utilizado positivo → "100.00%".
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
RSpec.describe Risk::AggregateService do
  # ---------------------------------------------------------------------------
  # Cenário L3 — agregado por tipo
  # ---------------------------------------------------------------------------
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/company.rb:45-82,114-195`
  # e `../sfg/app/models/project.rb:472-493,540-640`.
  describe 'scenario L3 — aggregate by type' do
    let(:project) { create(:project) }
    let(:company) { create(:company, project: project) }
    let(:tipo) { create(:risk_operation_type, title: 'L3 sem pré') }

    let!(:ativo_a) do
      create(:risk_control, project: project, company: company,
                            risk_operation_type: tipo, limite: 200_000.00, taxa: 2.00)
    end
    let!(:ativo_b) do
      create(:risk_control, project: project, company: company,
                            risk_operation_type: tipo, limite: 300_000.00, taxa: 3.00)
    end
    let!(:inativo) do
      create(:risk_control, project: project, company: company,
                            risk_operation_type: tipo, limite: 100_000.00, taxa: 1.00,
                            is_active: false)
    end

    describe '#limite_total_on (BE-249)' do
      it 'sums ONLY the active controls and ignores the date' do
        expect(described_class.limite_total_on(company, tipo, Date.current)).to eq(500_000.00)
        expect(described_class.limite_total_on(company, tipo, Date.new(1999, 1, 1))).to eq(500_000.00)
      end

      it 'gives the same number for the project scope' do
        expect(described_class.limite_total_on(project, tipo, Date.current)).to eq(500_000.00)
      end

      it 'brings the deactivated control back the moment it is activated (BE-236)' do
        inativo.activate!
        expect(described_class.limite_total_on(company, tipo, Date.current)).to eq(600_000.00)
      end
    end

    describe '#perc_limite_utilizado_on (BE-249) — the protected division' do
      it 'returns "0.00%" when there is no utilisation' do
        expect(described_class.perc_limite_utilizado_on(company, tipo, Date.current)).to eq('0.00%')
      end

      it 'returns "100.00%" when total is 0 and utilisation is positive' do
        # É por isso que limite ZERO continua sendo um cadastro válido: é ele
        # que mantém este ramo vivo (`company.rb:37-39`).
        zerado = create(:risk_operation_type, title: 'L3 limite zero')
        control = create(:risk_control, project: project, company: company,
                                        risk_operation_type: zerado, limite: 0, taxa: 0)
        # `operation_value: 0` **de propósito**: desde a S7 a operação nasce com
        # o movimento "Liberação do Recurso" de `operation_value`
        # (`BE-264`, `risk_operation.rb:39-52`). Com o capital padrão da
        # factory a cadeia começaria em 100.000,00 e este cenário deixaria de
        # medir o ramo da divisão protegida. Capital zero é cadastro válido
        # (Q-R7, "replicar as ausências").
        operacao = create(:risk_operation, risk_control: control, original_balance: 0, operation_value: 0)
        credito = create(:risk_movement_type, :credito, title: 'L3 crédito')
        encadear_movimentos!(operacao, [{ date: Date.new(2026, 3, 10), type: credito, value: 5_000.00 }])

        data = Date.new(2026, 3, 31)
        expect(described_class.limite_total_on(company, zerado, data)).to eq(0)
        expect(described_class.limite_utilizado_on(company, zerado, data)).to eq(5_000.00)
        expect(described_class.perc_limite_utilizado_on(company, zerado, data)).to eq('100.00%')
      end

      it 'returns "0.00%" when total is 0 and utilisation is NOT positive' do
        zerado = create(:risk_operation_type, title: 'L3 zero sem uso')
        create(:risk_control, project: project, company: company,
                              risk_operation_type: zerado, limite: 0, taxa: 0)

        expect(described_class.limite_total_on(company, zerado, Date.current)).to eq(0)
        expect(described_class.perc_limite_utilizado_on(company, zerado, Date.current)).to eq('0.00%')
      end
    end

    # --- BE-251 -------------------------------------------------------------
    describe '#total_limits_on (BE-251)' do
      subject(:linha) do
        described_class.total_limits_on(company, Date.current)[:limits].find { |l| l[:id] == tipo.id }
      end

      it 'returns the SAME string in liq, perc_liq, pre and perc_pre — REPLICATED (company.rb:79-82)' do
        perc = linha[:perc_util]
        expect(linha[:liq]).to eq(perc)
        expect(linha[:perc_liq]).to eq(perc)
        expect(linha[:pre]).to eq(perc)
        expect(linha[:perc_pre]).to eq(perc)
      end

      it 'carries the aggregate numbers of the type' do
        expect(linha[:total]).to eq(500_000.00)
        expect(linha[:util]).to eq(0)
        expect(linha[:disp]).to eq(500_000.0)
      end

      it 'reports has_risk_controls as 0/1, like the legacy .to_i' do
        resultado = described_class.total_limits_on(company, Date.current)
        expect(resultado[:has_risk_controls]).to eq(1)
        expect([0, 1]).to include(resultado[:has_risk_controls])
      end
    end

    # --- BE-250 -------------------------------------------------------------
    describe '#controls_info_on (BE-250) — D-95 REPLICATED on the company branch' do
      let!(:operacao) do
        # `operation_value: 0` pelo mesmo motivo do cenário acima: a S7 trouxe o
        # movimento automático de liberação, e este exemplo mede o D-95, não a
        # cadeia.
        create(:risk_operation, risk_control: ativo_a, original_balance: 0, operation_value: 0,
                                issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30))
      end
      let(:data) { Date.new(2026, 3, 31) }

      before do
        credito = create(:risk_movement_type, :credito, title: 'D95 crédito')
        # saldo −8.000 → utilizado +8.000
        encadear_movimentos!(operacao, [{ date: Date.new(2026, 3, 10), type: credito, value: 8_000.00 }])
      end

      it 'puts the UTILISED amount in the "Liquidável" and "Pré" labels — D-95 (a)' do
        cabecalho = described_class.controls_info_on(company, data).find { |i| i[:id] == tipo.id }
        linha = cabecalho[:rcs].find { |r| r[:id] == ativo_a.id }

        utilizado_formatado = Risk::Money.brl(linha[:limits][:limite_utilizado])
        expect(linha[:limits][:formatted_limite_liquidavel]).to start_with("#{utilizado_formatado} - ")
        expect(linha[:limits][:formatted_limite_pre]).to start_with("#{utilizado_formatado} - ")
        # QA: isto é intencional (DEC-01). Não abra bug.
        expect(linha[:limits][:limite_utilizado]).to eq(8_000.00)
      end

      it 'puts a MONETARY value in perc_liq/perc_pre of the type header — D-95 (b)' do
        cabecalho = described_class.controls_info_on(company, data).find { |i| i[:id] == tipo.id }

        expect(cabecalho[:perc_liq]).to eq(Risk::Money.brl(cabecalho[:liq]))
        expect(cabecalho[:perc_pre]).to eq(Risk::Money.brl(cabecalho[:pre]))
        # E o `perc_util`, ao lado, é de fato um percentual — a assimetria é o defeito.
        expect(cabecalho[:perc_util]).to eq(Risk::Money.brl(cabecalho[:limite_utilizado_percent]))
      end

      it 'does NOT reproduce D-95 on the project branch — the two are different in the legacy' do
        cabecalho = described_class.controls_info_on(project, data).find { |i| i[:id] == tipo.id }
        linha = cabecalho[:rcs].first

        # Aqui cada rótulo recebe o próprio valor (`project.rb:602-603`).
        expect(linha[:limits][:formatted_limite_liquidavel])
          .to start_with("#{Risk::Money.brl(linha[:limits][:limite_liquidavel])} - ")
        # E o cabeçalho recebe o PERCENTUAL, não o valor monetário.
        expect(cabecalho[:perc_liq]).to eq(Risk::Money.brl(cabecalho[:limite_liquidavel_percent]))
      end

      it 'aggregates one line per CARRIER on the project branch, not one per control' do
        # `rc_info[:id]` é `nil` de propósito no ramo do projeto.
        cabecalho = described_class.controls_info_on(project, data).find { |i| i[:id] == tipo.id }
        expect(cabecalho[:rcs].map { |r| r[:id] }).to all(be_nil)
        expect(cabecalho[:rcs].map { |r| r[:carrier_id] }.uniq.size).to eq(cabecalho[:rcs].size)
      end

      it 'uses a WEIGHTED average rate on the project branch and rc.taxa on the company branch' do
        por_empresa = described_class.controls_info_on(company, data).find { |i| i[:id] == tipo.id }
        linha_empresa = por_empresa[:rcs].find { |r| r[:id] == ativo_a.id }
        expect(linha_empresa[:limits][:taxa]).to eq(ativo_a.taxa)

        por_projeto = described_class.controls_info_on(project, data).find { |i| i[:id] == tipo.id }
        linha_projeto = por_projeto[:rcs].find { |r| r[:carrier_id] == ativo_a.carrier_id }
        # Um limite só para o portador: a ponderada é a própria taxa.
        expect(linha_projeto[:limits][:taxa]).to be_within(0.0001).of(ativo_a.taxa.to_f)
      end

      it 'omits types that have no control at all' do
        outro = create(:risk_operation_type, title: 'L3 sem limite')
        ids = described_class.controls_info_on(company, data).map { |i| i[:id] }
        expect(ids).not_to include(outro.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cenário L4 — decisão B-02: as duas verdades da desativação
  # ---------------------------------------------------------------------------
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/risk_control.rb:73-75`
  # (`#operations`, cego a `is_active`) × `company.rb:5` (`active_risk_controls`).
  describe 'scenario L4 — the two divergent readings of deactivation (B-02)' do
    let!(:cenario) { cenario_l1 }
    let(:control) { cenario[:control] }
    let(:operation) { cenario[:operation] }
    let(:data) { Date.new(2026, 3, 31) }

    before { control.deactivate! }

    it 'REMOVES the control from the console summary' do
      resumo = described_class.controls_info_on(cenario[:company], data)
      expect(resumo.flat_map { |i| i[:rcs] }.map { |r| r[:id] }).not_to include(control.id)

      expect(described_class.limite_total_on(cenario[:company], cenario[:type], data)).to eq(0)
    end

    it 'KEEPS the operation listed by RiskControl#operations — do not unify' do
      # `#operations` do legado busca por (projeto, empresa, portador, tipo) e
      # **não olha `is_active`** (`risk_control.rb:73-75`). Unificar as duas
      # leituras muda exposição financeira.
      expect(control.operations).to include(operation)
      expect(Risk::Calculator.operations_on(control, data)).to include(operation)
      expect(Risk::Calculator.limite_utilizado_on(control, data)).to eq(-2_500.00)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-252 — limites livres numa data
  # ---------------------------------------------------------------------------
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/company.rb:29-31`.
  describe '#available_for_entry_on (BE-252)' do
    let(:project) { create(:project) }
    let(:company) { create(:company, project: project) }

    it 'lists an active control with no operation in the window' do
      control = create(:risk_control, project: project, company: company)
      expect(described_class.available_for_entry_on(company, Date.current)).to include(control)
    end

    it 'NEVER lists a control of a pre-billing type — the static pair is always in the window' do
      tipo = create(:risk_operation_type, :com_pre, title: 'BE252 com pré')
      control = create(:risk_control, project: project, company: company, risk_operation_type: tipo)

      [Date.new(1900, 1, 1), Date.current, Date.new(2100, 1, 1)].each do |data|
        expect(described_class.available_for_entry_on(company, data)).not_to include(control)
      end
    end

    it 'does not list a control that already has an operation on the date' do
      control = create(:risk_control, project: project, company: company)
      create(:risk_operation, risk_control: control,
                              issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30))

      expect(described_class.available_for_entry_on(company, Date.new(2026, 4, 1))).not_to include(control)
      expect(described_class.available_for_entry_on(company, Date.new(2026, 7, 1))).to include(control)
    end

    it 'ignores inactive controls' do
      control = create(:risk_control, project: project, company: company, is_active: false)
      expect(described_class.available_for_entry_on(company, Date.current)).not_to include(control)
    end
  end

  # ---------------------------------------------------------------------------
  # Formatação — Risk::Money
  # ---------------------------------------------------------------------------
  describe Risk::Money do
    it 'formats like the legacy to_currency minus the "R$" prefix' do
      expect(described_class.brl(1_234.5)).to eq('1.234,50')
      expect(described_class.brl(-27_500)).to eq('-27.500,00')
      expect(described_class.brl(0.5)).to eq('0,50')
      expect(described_class.brl(0)).to eq('0,00')
      expect(described_class.brl(1_000_000)).to eq('1.000.000,00')
    end

    it 'formats percent with a DOT, like sprintf("%.2f")' do
      expect(described_class.percent(13.75)).to eq('13.75%')
      expect(described_class.percent(100)).to eq('100.00%')
      expect(described_class.percent(0)).to eq('0.00%')
    end
  end
end
