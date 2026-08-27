# frozen_string_literal: true

require 'rails_helper'

# S9 / BE-195 — **o cálculo único** (contrato C2), do lado da persistência.
#
# O golden test das FÓRMULAS está em `formulas_golden_spec.rb`. Este arquivo prova
# o que envolve o banco: que a gravação levanta em vez de engolir (D-79), que a
# apuração ao vivo das vencidas substitui o cron (D-54 / OPS-190), e que a prévia
# e a gravação passam pelo mesmo caminho (C2).
RSpec.describe Renegotiations::AggregateService do
  let(:user) { create(:user, :og) }
  let(:project) { create_project_with_owner(user) }
  let(:renegotiation) do
    create(:renegotiation, project: project,
                           provider: create(:provider, project: project),
                           company: create(:company, project: project),
                           total_debt: 3000)
  end

  def parcela(mes, main: 1000, **extra)
    create(:renegotiation_installment, renegotiation: renegotiation,
                                       due_date: Date.new(2025, mes, 10), main_value: main, **extra)
  end

  describe '.recalculate!' do
    it 'persiste os agregados e é IDEMPOTENTE' do
      parcela(1)
      parcela(2)

      described_class.recalculate!(renegotiation, today: Date.new(2025, 2, 15), broadcast: false)
      primeiro = renegotiation.reload.attributes.except('updated_at')

      described_class.recalculate!(renegotiation, today: Date.new(2025, 2, 15), broadcast: false)
      expect(renegotiation.reload.attributes.except('updated_at')).to eq(primeiro)
    end

    it 'LEVANTA em vez de engolir a falha (D-79)' do
      # `Renegotiation#update_values!` do legado fazia `self.save` — sem bang.
      # Falha de validação descartava o recálculo em SILÊNCIO, e o agregado e a
      # parcela divergiam sem ninguém saber.
      parcela(1)
      renegotiation.update_column(:kind, 'Financeiro')
      allow(renegotiation).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(renegotiation))

      expect do
        described_class.recalculate!(renegotiation, broadcast: false)
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'emite o broadcast UMA vez, DEPOIS do commit' do
      # Emitido dentro da transação, o assinante recarrega e lê o estado anterior.
      expect(RenegotiationChannel).to receive(:publish_changed).once.with(renegotiation)
      described_class.recalculate!(renegotiation)
    end

    it 'grava a contagem de vencidas junto com o resto' do
      parcela(1) # venceu
      parcela(12) # a vencer

      described_class.recalculate!(renegotiation, today: Date.new(2025, 6, 1), broadcast: false)

      expect(renegotiation.reload.overdue_installments).to eq(1)
      expect(renegotiation.due_installments).to eq(2)
    end
  end

  describe '.live_overdue_for — o que substitui o cron diário (OPS-190 / D-54)' do
    it 'apura na CONSULTA, numa consulta só para a página inteira' do
      parcela(1)
      parcela(2)
      # A coluna fica MENTINDO, como ficava entre uma execução do cron e a outra.
      renegotiation.update_column(:overdue_installments, 0)

      contagens = described_class.live_overdue_for(::Renegotiation.where(id: renegotiation.id),
                                                   today: Date.new(2025, 6, 1))

      expect(contagens[renegotiation.id]).to eq(2)
    end

    it 'usa a MESMA definição de "vencida" do agregado persistido' do
      # Duas definições seriam duas respostas para a mesma pergunta. O escopo
      # `RenegotiationInstallment.overdue` é o único lugar onde ela existe.
      parcela(1)
      paga = parcela(2)
      create(:renegotiation_payment, renegotiation_installment: paga, renegotiation: renegotiation,
                                     project: project, installment_paid_value_with_interest_cm: 1000)
      Renegotiations::RecalculateInstallment.call!(paga, broadcast: false)

      described_class.recalculate!(renegotiation, today: Date.new(2025, 6, 1), broadcast: false)
      ao_vivo = described_class.live_overdue_for(::Renegotiation.where(id: renegotiation.id),
                                                 today: Date.new(2025, 6, 1))

      # A paga não conta como vencida em nenhuma das duas.
      expect(renegotiation.reload.overdue_installments).to eq(1)
      expect(ao_vivo[renegotiation.id]).to eq(1)
    end
  end

  describe '.preview — o contrato C2' do
    it 'NÃO persiste nada' do
      antes = renegotiation.attributes.dup

      described_class.preview(renegotiation,
                              draft_installments: [{ due_date: Date.new(2025, 1, 10), main_value: 1000,
                                                     interest_value: 0, monetary_correction_value: 0 }])

      expect(renegotiation.reload.attributes).to eq(antes)
      expect(renegotiation.installments.count).to eq(0)
    end

    it 'produz o MESMO agregado que a gravação produziria, campo a campo' do
      rascunho = { due_date: Date.new(2025, 1, 10), main_value: 1234.56,
                   interest_value: 78.9, monetary_correction_value: 12.34 }

      previa = described_class.preview(renegotiation, draft_installments: [rascunho],
                                                      today: Date.new(2025, 2, 15))
      previa.delete(:preview_installments)

      Renegotiations::CreateInstallmentsBatch.call(renegotiation: renegotiation, attrs: rascunho)
      gravado = described_class.compute(renegotiation.reload, today: Date.new(2025, 2, 15))

      # Se este exemplo reprovar, a simulação e o salvamento passaram a produzir
      # números diferentes — que é o defeito mais fácil de introduzir nesta tela.
      expect(previa).to eq(gravado)
    end

    it '`replacing_id` tira a parcela em EDIÇÃO da conta' do
      existente = parcela(1, main: 1000)

      previa = described_class.preview(
        renegotiation,
        draft_installments: [{ due_date: Date.new(2025, 1, 10), main_value: 2000,
                               interest_value: 0, monetary_correction_value: 0 }],
        replacing_id: existente.id
      )

      # 2000, e não 3000: a versão velha saiu do cálculo. Sem isto a prévia da
      # edição somaria as duas versões da mesma parcela.
      expect(previa[:main_value]).to eq(2000)
    end
  end

  describe 'os campos persistidos' do
    it 'a lista de PERSISTED_FIELDS cobre tudo o que as fórmulas produzem' do
      # Acrescentar um campo às fórmulas sem acrescentá-lo aqui faria o número
      # sumir da tela sem erro nenhum. Este exemplo é o portão disso.
      produzidos = described_class.compute(renegotiation).keys
      expect(produzidos - described_class::PERSISTED_FIELDS).to be_empty
    end

    it 'todo campo persistido existe como coluna' do
      expect(described_class::PERSISTED_FIELDS.map(&:to_s) - ::Renegotiation.column_names).to be_empty
    end
  end
end
