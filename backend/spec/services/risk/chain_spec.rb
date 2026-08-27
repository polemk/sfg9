# frozen_string_literal: true

require 'rails_helper'

# S7 / **BE-265, BE-255, OPS-235** — os goldens `M1` e `M5`: **a cadeia de
# saldos** e o cartão "última movimentação".
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `create_risk_operations` e `create_risk_movements` estão entre as **24
# migrations que nunca subiram** (`analise-dump-producao.md` §1): a última
# migration aplicada em produção é de **25/05/2022**, o sistema rodou em uso até
# **31/05/2025**, e **não existe uma única operação nem um único movimento no
# dump**.
#
# **Estes goldens travam a LEITURA do fonte de 2022**, arquivo e linha citados
# em cada exemplo. Eles **não** provam que o número está certo — provam que não
# mudamos o que o código de 2022 fazia. Onde não houve produção, o teste tem uma
# **fonte**, não um **oráculo**.
#
# Comparar com a **S6**: lá as tabelas rodaram três anos e o dump serviu de
# oráculo (28.099 linhas × 33 colunas, zero divergência). **Aqui esse recurso
# não existe.**
RSpec.describe 'Risk::Calculator#recalculate_chain — golden M1' do
  let!(:cenario) { cenario_m1 }
  let(:operacao) { cenario[:operation] }

  # --- BE-264 -------------------------------------------------------------
  describe 'o movimento automático de liberação (BE-264)' do
    it 'nasce no after_create, com a data de emissão e o capital' do
      # Fonte: `../sfg/app/models/risk_operation.rb:39-52`.
      liberacao = cenario[:liberacao]
      expect(liberacao.movement_type.integration_key).to eq(RiskMovementType::RELEASE_KEY)
      expect(liberacao.date).to eq(Date.new(2026, 3, 1))
      expect(liberacao.movement_value).to eq(100_000.00)
    end

    it 'NÃO nasce para tipo com pré-faturamento, nem para operação estática' do
      # `:40` — `if !self.operation_type.has_pre_faturamento?`.
      m2 = cenario_m2
      expect(m2[:pre].movements).to be_empty
      expect(m2[:antecipacao].movements).to be_empty
    end

    it 'levanta erro de NEGÓCIO quando o tipo funcional não existe (B-09)' do
      # No legado, `RiskMovementType.liberação_de_recurso_id` faz `.first.id` e
      # dá `NoMethodError` em `nil` — 500 depois do INSERT da operação.
      control = create(:risk_control, risk_operation_type: create(:risk_operation_type, title: 'sem tipo funcional'))
      autor = create(:user)

      # A criação é direta, **sem a factory**: o `before(:create)` dela ressemeia
      # os tipos funcionais de propósito, e aqui o cenário é justamente a
      # ausência deles.
      RiskMovement.delete_all
      RiskMovementType.where(integration_key: RiskMovementType::RELEASE_KEY).delete_all

      expect {
        RiskOperation.create!(risk_control: control, project: control.project,
                              company: control.company, carrier: control.carrier,
                              operation_type: control.risk_operation_type,
                              user_id: autor.id, title: 'sem tipo funcional',
                              issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30),
                              operation_value: 1_000.00, original_balance: 0)
      }.to raise_error(RiskMovementType::MissingFunctionalType, /liberacao_do_recurso/)
    end
  end

  # --- BE-263 / DEC-01 ----------------------------------------------------
  describe 'o sinal do saldo inicial (BE-263 — DEC-01, melhoria DECLINADA)' do
    it 'grava 100.000,00 informado como −100.000,00' do
      # Fonte: `risk_operation.rb:34` — `(-1) * self.original_balance.abs`.
      expect(operacao.original_balance).to eq(-100_000.00)
    end

    it 'mantém o sinal negativo mesmo quando o valor chega já negativo' do
      operacao.update!(original_balance: -55_000.00)
      expect(operacao.reload.original_balance).to eq(-55_000.00)
    end
  end

  # --- BE-265 — o golden da cadeia ----------------------------------------
  describe 'a cadeia (BE-265) — fonte: risk_operation.rb:98-111' do
    it 'produz 0,00 → 2.500,00 → −27.500,00, com sequence 1, 2, 3' do
      movimentos = operacao.movements.order(:sequence).to_a

      expect(movimentos.map(&:sequence)).to eq([1, 2, 3])
      expect(movimentos.map(&:balance)).to eq([0.00, 2_500.00, -27_500.00])
      expect(movimentos.map { |m| m.movement_type.credit_type_value }).to eq([1, 1, -1])
    end

    it 'grava o último saldo no cache risk_operations.balance' do
      # `:110` — `self.balance = prev_bal`.
      expect(operacao.reload.balance).to eq(-27_500.00)
    end

    it 'usa a ordem (date asc, created_at asc) — nunca id' do
      # Reordenar por `id` muda saldo quando dois movimentos têm a mesma data.
      esperada = operacao.movements.chain_order.pluck(:id)
      expect(operacao.movements.order(:sequence).pluck(:id)).to eq(esperada)
    end

    # --- 3.3 — inserir no meio -------------------------------------------
    it 'renumera e reescreve os saldos quando um movimento entra NO MEIO' do
      RiskMovement.create!(risk_operation: operacao, movement_type: tipo_de_movimento('juros'),
                           date: Date.new(2026, 3, 10), movement_value: 1_000.00,
                           balance: 0, user_id: cenario[:user].id)

      movimentos = operacao.movements.order(:sequence).to_a
      expect(movimentos.map(&:sequence)).to eq([1, 2, 3, 4])
      expect(movimentos.map(&:balance)).to eq([0.00, 1_000.00, 3_500.00, -26_500.00])
      expect(operacao.reload.balance).to eq(-26_500.00)
    end

    # --- 3.4 — excluir a liberação ---------------------------------------
    it 'permite excluir o movimento automático de liberação, e NÃO o recria' do
      # **Replicado**: o `after_create` só roda no create da operação. É assim
      # que o operador corrige um capital liberado em duas parcelas.
      cenario[:liberacao].destroy!

      movimentos = operacao.movements.order(:sequence).to_a
      expect(movimentos.map(&:movement_type).map(&:integration_key)).to eq(%w[juros liquidacao])
      expect(movimentos.map(&:sequence)).to eq([1, 2])
      expect(movimentos.map(&:balance)).to eq([-97_500.00, -127_500.00])
      expect(operacao.reload.balance).to eq(-127_500.00)
    end

    # --- 3.5 — os três casos que continuam permitidos ---------------------
    it 'aceita movimento que ZERA o saldo, saldo negativo e operação ENCERRADA' do
      # T-D4 / DEC-35 — `is_ended` é rótulo: não bloqueia movimento nem
      # prorrogação, e não tira a operação de `operations_on`.
      operacao.update!(is_ended: true)

      zera = RiskMovement.create!(risk_operation: operacao, movement_type: tipo_de_movimento('juros'),
                                  date: Date.new(2026, 5, 1), movement_value: 27_500.00,
                                  balance: 0, user_id: cenario[:user].id)

      expect(zera.reload.balance).to eq(0.00)
      expect(operacao.reload.balance).to eq(0.00)
      expect(operacao.is_ended).to be(true)
      expect(Risk::Calculator.operations_on(cenario[:control], Date.new(2026, 5, 1))).to include(operacao)
    end
  end

  # --- OPS-235 ------------------------------------------------------------
  describe 'a persistência da cadeia (OPS-235)' do
    it 'pula as validações — a janela de datas de BE-274 NÃO é reaplicada' do
      # **Consequência preservada.** No legado a persistência é
      # `RiskMovement.import … validate: false` (`:109`); aqui é `upsert_all`,
      # que também pula. Reaplicar a janela faria recálculo legítimo de dado
      # histórico falhar.
      #
      # Prova: encolhe a janela por baixo (`update_columns`, sem validação) e
      # recalcula — a cadeia é reescrita mesmo com movimentos fora da janela.
      operacao.update_columns(due_date: Date.new(2026, 3, 20))
      expect { operacao.save! }.not_to raise_error
      expect(operacao.movements.order(:sequence).pluck(:balance)).to eq([0.00, 2_500.00, -27_500.00])
    end

    it 'escreve a cadeia inteira em UMA instrução (Princípio 9)' do
      consultas = []
      assinatura = lambda { |_n, _s, _f, _i, payload|
        consultas << payload[:sql] if payload[:sql]&.include?('risk_movements') && payload[:sql].start_with?('INSERT')
      }

      ActiveSupport::Notifications.subscribed(assinatura, 'sql.active_record') do
        operacao.save!
      end

      expect(consultas.size).to be <= 1
    end

    it 'não reescreve nada quando a cadeia já está correta' do
      antes = operacao.movements.order(:sequence).pluck(:id, :balance, :sequence, :updated_at)
      operacao.save!
      expect(operacao.movements.order(:sequence).pluck(:id, :balance, :sequence, :updated_at)).to eq(antes)
    end
  end

  # --- BE-255 / golden M5 -------------------------------------------------
  describe 'Risk::Calculator.last_movement — golden M5 (BE-255)' do
    it 'devolve o movimento de MAIOR sequence, com sinal, total e saldo inicial' do
      # Fonte: `../sfg/app/controllers/pub/risk_operations_controller.rb:163-176`.
      payload = Risk::Calculator.last_movement(operacao)

      expect(payload[:movement_type]).to eq('Liquidação')
      expect(payload[:movement_value]).to eq(30_000.00)
      expect(payload[:movement_value_sign]).to eq(-1)
      expect(payload[:sequence]).to eq(3)
      expect(payload[:total_balance]).to eq(-27_500.00)
      expect(payload[:original_balance]).to eq(-100_000.00)
    end

    it 'devolve payload VAZIO para operação sem movimento — não 500' do
      # No legado `@last_movement.date` em `nil` derruba a abertura do detalhe,
      # e o par estático recém-criado é exatamente esse caso.
      m2 = cenario_m2
      expect(Risk::Calculator.last_movement(m2[:pre])).to eq({})
      expect(Risk::Calculator.last_movement(nil)).to eq({})
    end
  end

  # --- BE-266 × BE-265: os dois convivem ----------------------------------
  describe 'balance × balance_on — os dois números convivem (BE-266)' do
    it 'operação SEM movimento tem balance = original_balance e balance_on = 0' do
      solta = create(:risk_operation, risk_control: cenario[:control],
                                      operation_value: 0, original_balance: 100_000.00)
      solta.movements.destroy_all
      solta.save!

      expect(solta.reload.balance).to eq(-100_000.00)
      expect(solta.balance_on(Date.new(2026, 12, 31))).to eq(0)
    end
  end
end
