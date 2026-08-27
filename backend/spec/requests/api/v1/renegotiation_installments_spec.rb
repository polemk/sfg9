# frozen_string_literal: true

require 'rails_helper'

# S9 — **parcelas**: criação única e em lote, prévia, edição, exclusão e o lote
# de exclusão.
#
# Cobre as tarefas 4.13 (prévia × gravação, campo a campo), 4.15 (coerência de
# pai), 4.16 (perda de dado do D-51) e 4.19 (paginação real).
RSpec.describe 'API::V1::RenegotiationInstallments' do
  let(:user) { create(:user, :og) }
  let(:project) { create_project_with_owner(user) }
  let(:provider) { create(:provider, project: project) }
  let(:company) { create(:company, project: project) }
  let(:headers) { auth_headers(user, project: project) }
  let(:renegotiation) do
    create(:renegotiation, project: project, provider: provider, company: company, total_debt: 3000)
  end
  let(:base) { "/api/v1/renegotiations/#{renegotiation.id}/installments" }

  describe 'POST — criação' do
    it 'cria UMA parcela com os derivados vindos do servidor' do
      post base, params: { due_date: '2025-01-10', main_value: 1000,
                           interest_value: 50, monetary_correction_value: 10 }, headers: headers

      expect(response).to have_http_status(:created)
      corpo = JSON.parse(response.body)
      expect(corpo['created']).to eq(1)
      parcela = corpo['installments'].first
      expect(parcela['main_value_with_interest'].to_d).to eq(1050)
      expect(parcela['main_value_with_interest_cm'].to_d).to eq(1060)
      expect(parcela['installment_total_value'].to_d).to eq(1060)
      expect(parcela['pending_value'].to_d).to eq(1060)
      expect(parcela['saldo'].to_d).to eq(-1060)
      expect(parcela['is_paid']).to be(false)
      expect(parcela['number']).to eq(1)
    end

    it 'cria um LOTE mensal com ajuste de fim de mês, numerado por vencimento' do
      post base, params: { due_date: '2025-01-31', main_value: 1000, multiple: true,
                           repetitions: 3, repetition_delay: 1, repetition_type: 'Meses' },
                 headers: headers

      expect(response).to have_http_status(:created)
      datas = renegotiation.installments.ordered.pluck(:due_date)
      # 31/01 >> 1 é 28/02, não 03/03 — mesmo comportamento do `+ 1.month`.
      expect(datas).to eq([Date.new(2025, 1, 31), Date.new(2025, 2, 28), Date.new(2025, 3, 31)])
      expect(renegotiation.installments.ordered.pluck(:number)).to eq([1, 2, 3])
      # Lote = mesma identidade e mesma cor (BE-217).
      expect(renegotiation.installments.pluck(:batch_token).uniq.size).to eq(1)
      expect(renegotiation.installments.pluck(:color).uniq.size).to eq(1)
    end

    it 'dá cor DIFERENTE ao segundo lote, e termina sempre (OPS-196)' do
      post base, params: { due_date: '2025-01-10', main_value: 1000 }, headers: headers
      post base, params: { due_date: '2025-02-10', main_value: 1000 }, headers: headers

      expect(renegotiation.installments.pluck(:color).uniq.size).to eq(2)
    end

    it 'recusa data ausente com 422, não 500 (BE-214)' do
      post base, params: { main_value: 1000 }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'recusa repetições não numéricas com 422 — o `to_i` do legado virava 0 e respondia 200' do
      post base, params: { due_date: '2025-01-10', main_value: 1000, multiple: true,
                           repetitions: 'abc', repetition_delay: 1, repetition_type: 'Meses' },
                 headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(renegotiation.installments.count).to eq(0)
    end

    it 'recusa intervalo ZERO com mais de uma parcela (N parcelas na mesma data)' do
      post base, params: { due_date: '2025-01-10', main_value: 1000, multiple: true,
                           repetitions: 3, repetition_delay: 0, repetition_type: 'Meses' },
                 headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('maior que zero')
      expect(renegotiation.installments.count).to eq(0)
    end

    it 'recusa principal ZERO com 422 de verdade (D-52)' do
      # No legado a validação existia, o retorno do `create` era ignorado, e a
      # resposta era 200 "criada com sucesso" sem ter criado nada.
      post base, params: { due_date: '2025-01-10', main_value: 0 }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(renegotiation.installments.count).to eq(0)
    end

    it 'recusa vencimento sobreposto e diz QUAL' do
      post base, params: { due_date: '2025-01-10', main_value: 1000 }, headers: headers
      post base, params: { due_date: '2025-01-10', main_value: 500 }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('10/01/2025')
      expect(renegotiation.installments.count).to eq(1)
    end
  end

  describe 'POST /preview — o contrato C2' do
    it 'a PRÉVIA e a GRAVAÇÃO produzem derivados idênticos, campo a campo (4.13)' do
      rascunho = { due_date: '2025-01-10', main_value: 1234.56,
                   interest_value: 78.9, monetary_correction_value: 12.34 }

      post "#{base}/preview", params: rascunho, headers: headers
      expect(response).to have_http_status(:ok)
      previa = JSON.parse(response.body)['installments'].first

      post base, params: rascunho, headers: headers
      expect(response).to have_http_status(:created)
      gravada = JSON.parse(response.body)['installments'].first

      # É o D-09 aplicado ao painel de parcela: a regra financeira deixa de
      # existir em dois lugares. Se este exemplo reprovar, alguém recalculou.
      %w[main_value_with_interest main_value_with_interest_cm installment_total_value
         paid_value saldo pending_value].each do |campo|
        expect(previa[campo].to_d).to eq(gravada[campo].to_d), "divergiu em #{campo}"
      end
      expect(previa['is_paid']).to eq(gravada['is_paid'])
    end

    it 'a prévia do LOTE devolve as mesmas datas que a gravação criaria' do
      rascunho = { due_date: '2025-01-31', main_value: 1000, multiple: true,
                   repetitions: 3, repetition_delay: 1, repetition_type: 'Meses' }

      post "#{base}/preview", params: rascunho, headers: headers
      datas_previa = JSON.parse(response.body)['installments'].map { |i| i['due_date'] }

      post base, params: rascunho, headers: headers
      expect(renegotiation.installments.ordered.pluck(:due_date).map(&:to_s)).to eq(datas_previa)
    end

    it 'a prévia devolve o AGREGADO resultante sem persistir nada' do
      post "#{base}/preview", params: { due_date: '2025-01-10', main_value: 1000 }, headers: headers

      corpo = JSON.parse(response.body)
      expect(corpo['renegotiation']['main_value'].to_d).to eq(1000)
      expect(corpo['renegotiation']['state']).to eq('Inconsistente') # 1000 < 3000 de dívida
      # Nada foi gravado.
      expect(renegotiation.reload.installments_count).to eq(0)
      expect(renegotiation.main_value).to eq(0)
    end

    it 'a prévia de EDIÇÃO tira a parcela velha da conta' do
      post base, params: { due_date: '2025-01-10', main_value: 1000 }, headers: headers
      parcela = renegotiation.installments.first

      post "#{base}/preview",
           params: { due_date: '2025-01-10', main_value: 2000, replacing_id: parcela.id },
           headers: headers

      # 2000, não 3000: a versão velha saiu do cálculo.
      expect(JSON.parse(response.body)['renegotiation']['main_value'].to_d).to eq(2000)
    end
  end

  describe 'GET — listagem' do
    it 'ordena por vencimento, aninha os pagamentos e PAGINA (D-20)' do
      3.times do |i|
        create(:renegotiation_installment, renegotiation: renegotiation,
                                           due_date: Date.new(2025, 3 - i, 10))
      end

      get base, params: { page: 1, per_page: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      corpo = JSON.parse(response.body)
      expect(corpo.size).to eq(2)
      expect(corpo.map { |i| i['due_date'] }).to eq(['2025-01-10', '2025-02-10'])
      expect(corpo.first).to have_key('payments')
      expect(response.headers['X-Total-Count']).to eq('3')
    end
  end

  describe 'PUT — edição' do
    it 'recalcula, renumera e REABRE parcela quitada quando o valor aumenta' do
      parcela = create(:renegotiation_installment, renegotiation: renegotiation,
                                                   due_date: Date.new(2025, 1, 10), main_value: 1000)
      create(:renegotiation_payment, renegotiation_installment: parcela, renegotiation: renegotiation,
                                     project: project, installment_paid_value_with_interest_cm: 1000)
      Renegotiations::RecalculateInstallment.call!(parcela)
      expect(parcela.reload.is_paid).to be(true)

      put "#{base}/#{parcela.id}", params: { main_value: 2000 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(parcela.reload.is_paid).to be(false)
      expect(parcela.pending_value).to eq(1000)
    end

    it 'reordena os números quando o vencimento muda de posição' do
      p1 = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 1, 10))
      p2 = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 2, 10))
      Renegotiations::RenumberInstallments.call(renegotiation)

      put "#{base}/#{p1.id}", params: { due_date: '2025-03-10' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(p2.reload.number).to eq(1)
      expect(p1.reload.number).to eq(2)
      expect(p1.month).to eq(3)
      expect(p1.year).to eq(2025)
    end
  end

  describe 'DELETE — exclusão' do
    it 'barra exclusão de parcela COM pagamento, dizendo o motivo' do
      parcela = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 1, 10))
      create(:renegotiation_payment, renegotiation_installment: parcela, renegotiation: renegotiation,
                                     project: project)

      delete "#{base}/#{parcela.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to include('pagamento lançado')
      expect(RenegotiationInstallment.exists?(parcela.id)).to be(true)
    end

    it 'remove e renumera as que sobraram' do
      p1 = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 1, 10))
      p2 = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 2, 10))
      Renegotiations::RenumberInstallments.call(renegotiation)

      delete "#{base}/#{p1.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(p2.reload.number).to eq(1)
      expect(renegotiation.reload.installments_count).to eq(1)
    end
  end

  describe 'DELETE /batch — o lote (4.16 / D-51)' do
    let!(:parcelas) do
      (1..3).map { |m| create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, m, 10)) }
    end

    it 'remove o lote inteiro numa transação e renumera' do
      delete "#{base}/batch",
             params: { 'renegotiation_installment_ids[]' => parcelas.first(2).map(&:id) }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['deleted']).to eq(2)
      expect(renegotiation.installments.reload.pluck(:number)).to eq([1])
    end

    it 'com UM id inválido no meio: NÃO apaga nada e diz por quê (D-51)' do
      # No legado o retorno era `inst.blank?` DEPOIS do `destroy_all` — sucesso
      # quando nada havia e "falha" quando apagou. O usuário via erro depois de
      # uma remoção bem-sucedida, reexecutava, e apagava parcelas a mais.
      ids = [parcelas[0].id, SecureRandom.uuid, parcelas[1].id]

      delete "#{base}/batch", params: { 'renegotiation_installment_ids[]' => ids }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to include('não pertencem a esta renegociação')
      expect(renegotiation.installments.reload.count).to eq(3)
    end

    it 'com id de OUTRA renegociação: não apaga nada (4.15)' do
      outra = create(:renegotiation, project: project, provider: provider, company: company,
                                     integration_key: 'outra')
      alheia = create(:renegotiation_installment, renegotiation: outra, due_date: Date.new(2025, 1, 10))

      delete "#{base}/batch",
             params: { 'renegotiation_installment_ids[]' => [parcelas[0].id, alheia.id] }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(renegotiation.installments.reload.count).to eq(3)
      expect(RenegotiationInstallment.exists?(alheia.id)).to be(true)
    end

    it 'com parcela QUE TEM pagamento: não apaga nada e nomeia a parcela' do
      Renegotiations::RenumberInstallments.call(renegotiation)
      create(:renegotiation_payment, renegotiation_installment: parcelas[1],
                                     renegotiation: renegotiation, project: project)

      delete "#{base}/batch",
             params: { 'renegotiation_installment_ids[]' => parcelas.map(&:id) }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to include('#2')
      expect(renegotiation.installments.reload.count).to eq(3)
    end

    it 'lote VAZIO não é sucesso' do
      delete "#{base}/batch", params: { 'renegotiation_installment_ids[]' => [] }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'coerência de pai no BANCO (4.15 / DB-192)' do
    it 'o Postgres recusa parcela cujo projeto difere do da renegociação' do
      outro_projeto = create(:project)

      expect do
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO renegotiation_installments
            (id, renegotiation_id, project_id, due_date, main_value, batch_token, created_at, updated_at)
          VALUES (gen_random_uuid(), '#{renegotiation.id}', '#{outro_projeto.id}',
                  '2025-01-10', 100, gen_random_uuid(), NOW(), NOW())
        SQL
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
