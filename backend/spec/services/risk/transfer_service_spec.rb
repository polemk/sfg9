# frozen_string_literal: true

require 'rails_helper'

# S7 / **BE-275, BE-276** — golden `M2`: a **transferência pré ↔ antecipação**.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `create_risk_movements` e `create_risk_operations` estão entre as **24
# migrations que nunca subiram** (`analise-dump-producao.md` §1). **Nenhuma
# transferência existiu em produção** — e, pior, a que está escrita no legado
# **não funcionaria**: `on_duplicate_key_update: [:date, movement_value]`
# (`../sfg/app/models/risk_movement.rb:40`) tem `movement_value` **sem os
# dois-pontos**, ou seja uma variável local inexistente. Editar um movimento
# com par levanta `NameError` (D-97).
#
# Fonte deste golden: `risk_movement.rb:45-65`. Ele trava a **leitura** dessa
# fonte, não um comportamento observado.
RSpec.describe Risk::TransferService do
  let!(:cenario) { cenario_m2 }
  let(:pre) { cenario[:pre] }
  let(:antecipacao) { cenario[:antecipacao] }
  let(:autor) { cenario[:user] }

  describe 'golden M2 — pré −10.000,00 e antecipação +10.000,00' do
    let!(:resultado) do
      described_class.call(operation: pre,
                           attrs: { date: Date.new(2026, 4, 10), movement_value: 10_000.00,
                                    observation: 'Antecipação de abril' },
                           actor: autor)
    end

    it 'grava as duas pontas com os sinais opostos' do
      expect(resultado[:status]).to eq(201)

      saida = resultado[:data]
      entrada = saida.pair_movement

      expect(saida.movement_type.integration_key).to eq(RiskMovementType::TRANSFER_OUT_KEY)
      expect(saida.movement_type.credit_type_code).to eq('C')
      expect(saida.balance).to eq(-10_000.00)

      expect(entrada.movement_type.integration_key).to eq(RiskMovementType::TRANSFER_IN_KEY)
      expect(entrada.movement_type.credit_type_code).to eq('D')
      expect(entrada.balance).to eq(10_000.00)
    end

    it 'espelha data, valor e observação, e cruza o pair_id' do
      saida = resultado[:data]
      entrada = saida.pair_movement

      expect(entrada.date).to eq(saida.date)
      expect(entrada.movement_value).to eq(saida.movement_value)
      expect(entrada.observation).to eq(saida.observation)
      expect(entrada.pair_id).to eq(saida.id)
      expect(saida.pair_id).to eq(entrada.id)
    end

    it 'atualiza o cache de saldo das DUAS operações' do
      expect(pre.reload.balance).to eq(-10_000.00)
      expect(antecipacao.reload.balance).to eq(10_000.00)
    end

    it 'copia projeto, empresa e portador DA OPERAÇÃO em cada ponta (BE-272)' do
      entrada = resultado[:data].pair_movement
      expect(entrada.project_id).to eq(antecipacao.project_id)
      expect(entrada.company_id).to eq(antecipacao.company_id)
      expect(entrada.carrier_id).to eq(antecipacao.carrier_id)
    end
  end

  describe 'sem par, NADA é gravado — a meia transferência do legado morre aqui' do
    it 'recusa com 422 e não deixa movimento nenhum' do
      # No legado o par nasce no `after_create` do movimento de saída: sem
      # `pair_operation`, `pair_operation.id` levanta `NoMethodError` **depois**
      # do INSERT — o movimento de saída fica gravado, o saldo da pré fica
      # errado para sempre e não há nada do outro lado.
      pre.update_columns(pair_id: nil)

      resultado = described_class.call(operation: pre.reload,
                                       attrs: { date: Date.new(2026, 4, 10), movement_value: 10_000.00 },
                                       actor: autor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('par de antecipação')
      expect(RiskMovement.count).to eq(0)
      expect(pre.reload.balance).to eq(0)
    end
  end

  describe 'Q-R11 — o sentido é UM só, e isso é REPLICADO' do
    it 'transferir A PARTIR da antecipação não gera contrapartida' do
      # `risk_movement.rb:46` exige `self.risk_operation.is_pre?`. Parece
      # esquecimento e é o comportamento: o fluxo do produto é pré →
      # antecipação. O default registrado no `proposal.md` é "replicar".
      resultado = described_class.call(operation: antecipacao,
                                       attrs: { date: Date.new(2026, 4, 10), movement_value: 5_000.00 },
                                       actor: autor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to eq(described_class::NOT_PRE)
    end

    it 'pelo MovementService, o lançamento direto do tipo de transferência cai aqui' do
      resultado = Risk::MovementService.create(
        project: cenario[:project], operation_id: pre.id,
        attrs: { movement_type_id: RiskMovementType.transfer_out.id,
                 date: Date.new(2026, 4, 10), movement_value: 7_000.00 },
        actor: autor
      )

      expect(resultado[:status]).to eq(201)
      expect(resultado[:data].pair_movement).to be_present
    end
  end

  describe 'BE-276 — o espelho na edição (a correção do D-97)' do
    let!(:saida) do
      described_class.call(operation: pre,
                           attrs: { date: Date.new(2026, 4, 10), movement_value: 10_000.00 },
                           actor: autor)[:data]
    end

    it 'editar data e valor espelha no par — no legado isto é NameError' do
      saida.update!(date: Date.new(2026, 5, 5), movement_value: 12_345.67)

      entrada = saida.reload.pair_movement.reload
      expect(entrada.date).to eq(Date.new(2026, 5, 5))
      expect(entrada.movement_value).to eq(12_345.67)
      expect(entrada.balance).to eq(12_345.67)
      expect(saida.balance).to eq(-12_345.67)
    end

    it 'excluir a transferência apaga o par' do
      resultado = Risk::MovementService.destroy(project: cenario[:project],
                                                operation_id: pre.id, id: saida.id)

      expect(resultado[:status]).to eq(200)
      expect(RiskMovement.count).to eq(0)
      expect(pre.reload.balance).to eq(0)
      expect(antecipacao.reload.balance).to eq(0)
    end
  end

  describe 'a operação estática aceita movimento em qualquer data (B-08)' do
    it 'não dispara a janela de BE-274, porque não há janela' do
      resultado = described_class.call(operation: pre,
                                       attrs: { date: Date.new(2099, 1, 1), movement_value: 1.00 },
                                       actor: autor)
      expect(resultado[:status]).to eq(201)
    end
  end
end
