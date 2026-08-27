# frozen_string_literal: true

require 'rails_helper'

# S9 — **pagamentos**.
#
# ⚠ **DEC-53: backend SIM, tela NÃO.** A aba PAGAMENTOS não é portada (no legado
# ela está comentada). Estas rotas existem, são alcançáveis por URL — e é por isso
# que este arquivo prova que elas passam por autorização e escopo como qualquer
# outro recurso. Backend sem tela **sem** dono de autorização foi como o P-022
# nasceu no legado.
#
# Cobre a tarefa 4.18 (cascata única e reversão).
RSpec.describe 'API::V1::RenegotiationPayments' do
  let(:user) { create(:user, :og) }
  let(:project) { create_project_with_owner(user) }
  let(:headers) { auth_headers(user, project: project) }
  let(:renegotiation) do
    create(:renegotiation, project: project,
                           provider: create(:provider, project: project),
                           company: create(:company, project: project))
  end
  let!(:parcela) do
    create(:renegotiation_installment, renegotiation: renegotiation,
                                       due_date: Date.new(2025, 1, 10), main_value: 1000)
  end
  let(:base) { "/api/v1/renegotiations/#{renegotiation.id}/payments" }

  describe 'POST' do
    it 'lança o pagamento, calcula days_late e propaga até a renegociação' do
      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-20',
                           installment_paid_value_with_interest_cm: 600, late_payment_value: 25 },
                 headers: headers

      expect(response).to have_http_status(:created)
      corpo = JSON.parse(response.body)
      expect(corpo['days_late']).to eq(10)
      expect(corpo['total_paid_value'].to_d).to eq(625)
      expect(corpo['payment_number']).to eq(1)

      expect(parcela.reload.paid_value).to eq(625)
      expect(parcela.late_payment_value).to eq(25)
      expect(parcela.installment_total_value).to eq(1025) # a mora entra no DEVIDO
      expect(parcela.pending_value).to eq(400)            # e se cancela: 1000 - 600
      expect(renegotiation.reload.paid_value).to eq(625)  # "R$ Pago" CONTA a mora
      expect(renegotiation.remaining_value).to eq(400)    # "R$ A Pagar" a ignora
    end

    it 'aceita data RETROATIVA (D-B12) — no legado o campo era travado em "hoje"' do
      post base, params: { renegotiation_installment_id: parcela.id, date: '2024-12-01',
                           installment_paid_value_with_interest_cm: 100 }, headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['days_late']).to eq(0)
    end

    it 'recusa valor ACIMA do pendente da parcela (D-52)' do
      # ⚠ Isto MUDA o que hoje é aceito. No legado não havia checagem em camada
      # nenhuma: o "pendente" era só rótulo do seletor na tela.
      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 1500 }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to include('pendente da parcela')
      expect(parcela.reload.paid_value).to eq(0)
    end

    it 'desconta o que OUTROS pagamentos já lançaram ao aplicar o teto' do
      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 600 }, headers: headers
      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 500 }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parcela.reload.payments.count).to eq(1)
    end

    it 'recusa mora NEGATIVA' do
      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 100, late_payment_value: -50 },
                 headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'recusa parcela de OUTRA renegociação (4.15 / D-52)' do
      outra = create(:renegotiation, project: project, provider: create(:provider, project: project),
                                     company: create(:company, project: project), integration_key: 'outra')
      alheia = create(:renegotiation_installment, renegotiation: outra, due_date: Date.new(2025, 1, 10))

      post base, params: { renegotiation_installment_id: alheia.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 100 }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(RenegotiationPayment.count).to eq(0)
    end

    it 'quita a parcela quando o pendente chega a zero' do
      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 1000 }, headers: headers

      expect(parcela.reload.is_paid).to be(true)
      expect(renegotiation.reload.state).to eq('Liquidado')
    end
  end

  describe 'PUT' do
    let!(:pagamento) do
      create(:renegotiation_payment, renegotiation_installment: parcela, renegotiation: renegotiation,
                                     project: project, installment_paid_value_with_interest_cm: 400)
    end

    it 'não deixa mudar a PARCELA pela URL (BE-222)' do
      outra_parcela = create(:renegotiation_installment, renegotiation: renegotiation,
                                                         due_date: Date.new(2025, 2, 10))

      put "#{base}/#{pagamento.id}",
          params: { renegotiation_installment_id: outra_parcela.id,
                    installment_paid_value_with_interest_cm: 500 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(pagamento.reload.renegotiation_installment_id).to eq(parcela.id)
    end

    it 'salvar SEM alterar o valor não é recusado pelo próprio teto' do
      put "#{base}/#{pagamento.id}", params: { date: '2025-01-15' }, headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'DELETE' do
    it 'REABRE a parcela e recalcula a renegociação' do
      pagamento = create(:renegotiation_payment, renegotiation_installment: parcela,
                                                 renegotiation: renegotiation, project: project,
                                                 installment_paid_value_with_interest_cm: 1000)
      Renegotiations::RecalculateInstallment.call!(parcela)
      expect(parcela.reload.is_paid).to be(true)

      delete "#{base}/#{pagamento.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(parcela.reload.is_paid).to be(false)
      expect(parcela.pending_value).to eq(1000)
      expect(renegotiation.reload.paid_value).to eq(0)
    end
  end

  describe 'a cascata roda UMA vez por operação (4.18)' do
    it 'criar, editar e excluir disparam um recálculo cada' do
      # No legado o `after_save` do pagamento chamava a parcela, que chamava a
      # renegociação — e o controller ainda fazia `update` + `save`, disparando a
      # corrente duas vezes.
      allow(Renegotiations::AggregateService).to receive(:recalculate!).and_call_original

      post base, params: { renegotiation_installment_id: parcela.id, date: '2025-01-10',
                           installment_paid_value_with_interest_cm: 400 }, headers: headers
      expect(Renegotiations::AggregateService).to have_received(:recalculate!).once

      pagamento_id = JSON.parse(response.body)['id']

      put "#{base}/#{pagamento_id}", params: { installment_paid_value_with_interest_cm: 500 },
                                     headers: headers
      expect(Renegotiations::AggregateService).to have_received(:recalculate!).twice

      delete "#{base}/#{pagamento_id}", headers: headers
      expect(Renegotiations::AggregateService).to have_received(:recalculate!).thrice
    end

    it 'falha no meio da cascata REVERTE a operação inteira (D-79)' do
      # Testado no SERVIÇO, e não pela rota, de propósito: o `rescue` do Grape
      # transformaria a exceção em 500 e o exemplo passaria a medir o tratamento
      # de erro do framework em vez da transação, que é o que está sob teste.
      quebrada = ::Renegotiation.new.tap { |r| r.errors.add(:base, 'agregado inválido') }
      allow(Renegotiations::AggregateService)
        .to receive(:recalculate!).and_raise(ActiveRecord::RecordInvalid.new(quebrada))

      resultado = RenegotiationPaymentService.create_payment(
        installment: parcela,
        attrs: { date: Date.new(2025, 1, 10), installment_paid_value_with_interest_cm: 400 },
        actor: user
      )

      # A falha é REPORTADA (422 com motivo), não engolida…
      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('agregado inválido')
      # …e a transação inteira é revertida. Com `save` sem bang (D-79) o
      # pagamento ficaria gravado e o agregado ficaria velho, em silêncio.
      expect(RenegotiationPayment.count).to eq(0)
      expect(parcela.reload.paid_value).to eq(0)
    end
  end

  describe 'GET' do
    it 'lista em ordem DETERMINÍSTICA e pagina (BE-222 / D-20)' do
      3.times do |i|
        create(:renegotiation_payment, renegotiation_installment: parcela, renegotiation: renegotiation,
                                       project: project, payment_number: i + 1,
                                       installment_paid_value_with_interest_cm: 10 * (i + 1),
                                       created_at: i.hours.ago)
      end

      get base, params: { per_page: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      corpo = JSON.parse(response.body)
      expect(corpo.size).to eq(2)
      expect(corpo.map { |p| p['installment_paid_value_with_interest_cm'].to_d }).to eq([30, 20])
      expect(response.headers['X-Total-Count']).to eq('3')
    end
  end
end
