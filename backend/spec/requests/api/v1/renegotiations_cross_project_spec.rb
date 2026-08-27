# frozen_string_literal: true

require 'rails_helper'

# S9 / tarefa 4.14 — **a suíte cross-project do contrato C1**.
#
# Um exemplo por endpoint que aceita id por parâmetro. O que cada um prova:
#
#  1. o id de **outro projeto** é recusado;
#  2. a resposta é **idêntica** à de um id inexistente — mesmo status e mesmo
#     corpo. Distinguir 403 de 404 transformaria a API num oráculo de existência:
#     um Colaborador de um projeto enumeraria os ids de todos os outros.
#
# É a família **D-01 / D-16 / D-29 / D-76 / D-100**, e no controller de
# renegociação do legado ela está escrita com todas as letras
# (`pub/renegotiations_controller.rb:23-24`):
#
#     @renegotiations = Renegotiation.where(project_id: current_user.default_project_id)
#     @renegotiations = Renegotiation.where(id: params[:renegotiation_id]) if !params[:renegotiation_id].nil?
#
# A segunda linha **reatribui** a relação e o filtro de projeto desaparece.
RSpec.describe 'S9 — escopo por projeto (contrato C1)' do
  # O invasor é OG de propósito: se ele fosse Colaborador, o exemplo poderia
  # passar pelo motivo errado (falta de papel) em vez de pelo escopo. OG tem
  # acesso a TODO recurso — o que ele não tem é acesso a registro de projeto que
  # não é o corrente.
  let(:invasor) { create(:user, :og) }
  let(:projeto_do_invasor) { create_project_with_owner(invasor) }
  let(:headers) { auth_headers(invasor, project: projeto_do_invasor) }

  let(:vitima) { create(:user, :og) }
  let(:projeto_alheio) { create_project_with_owner(vitima) }
  let(:alheia) do
    create(:renegotiation, project: projeto_alheio,
                           provider: create(:provider, project: projeto_alheio),
                           company: create(:company, project: projeto_alheio))
  end
  let(:parcela_alheia) do
    create(:renegotiation_installment, renegotiation: alheia, due_date: Date.new(2025, 1, 10))
  end
  let(:pagamento_alheio) do
    create(:renegotiation_payment, renegotiation_installment: parcela_alheia, renegotiation: alheia,
                                   project: projeto_alheio)
  end
  let(:anexo_alheio) { create(:renegotiation_attachment, renegotiation: alheia, author: vitima) }

  let(:inexistente) { SecureRandom.uuid }

  # Compara a resposta do id ALHEIO com a do id INEXISTENTE. Se as duas forem
  # iguais, o endpoint não vaza a existência do registro.
  def indistinguivel!(caminho_alheio, caminho_inexistente, verbo: :get, params: {})
    send(verbo, caminho_alheio, params: params, headers: headers)
    alheio = [response.status, response.body]

    send(verbo, caminho_inexistente, params: params, headers: headers)
    fantasma = [response.status, response.body]

    expect(alheio).to eq(fantasma)
    expect(alheio.first).to be >= 400
  end

  describe 'renegociação' do
    it 'search: `renegotiation_id` de outro projeto NÃO expõe nada' do
      alheia
      get '/api/v1/renegotiations', params: { renegotiation_id: alheia.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'search: id malformado devolve VAZIO, não a lista inteira' do
      create(:renegotiation, project: projeto_do_invasor,
                             provider: create(:provider, project: projeto_do_invasor),
                             company: create(:company, project: projeto_do_invasor))

      get '/api/v1/renegotiations', params: { renegotiation_id: 'nao-e-uuid' }, headers: headers
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'show' do
      indistinguivel!("/api/v1/renegotiations/#{alheia.id}", "/api/v1/renegotiations/#{inexistente}")
    end

    it 'general_values' do
      indistinguivel!("/api/v1/renegotiations/#{alheia.id}/general_values",
                      "/api/v1/renegotiations/#{inexistente}/general_values")
    end

    it 'update' do
      indistinguivel!("/api/v1/renegotiations/#{alheia.id}", "/api/v1/renegotiations/#{inexistente}",
                      verbo: :put, params: { title: 'invadido' })
      expect(alheia.reload.title).not_to eq('invadido')
    end

    it 'destroy' do
      alheia
      indistinguivel!("/api/v1/renegotiations/#{alheia.id}", "/api/v1/renegotiations/#{inexistente}",
                      verbo: :delete)
      expect(::Renegotiation.exists?(alheia.id)).to be(true)
    end
  end

  describe 'parcela' do
    let(:sob_alheia) { "/api/v1/renegotiations/#{alheia.id}/installments" }
    let(:sob_fantasma) { "/api/v1/renegotiations/#{inexistente}/installments" }

    it 'search' do
      parcela_alheia
      indistinguivel!(sob_alheia, sob_fantasma)
    end

    it 'create' do
      indistinguivel!(sob_alheia, sob_fantasma, verbo: :post,
                                                params: { due_date: '2025-05-10', main_value: 100 })
      expect(alheia.installments.count).to eq(0)
    end

    it 'update' do
      indistinguivel!("#{sob_alheia}/#{parcela_alheia.id}", "#{sob_fantasma}/#{inexistente}",
                      verbo: :put, params: { main_value: 999 })
      expect(parcela_alheia.reload.main_value).not_to eq(999)
    end

    it 'destroy' do
      parcela_alheia
      indistinguivel!("#{sob_alheia}/#{parcela_alheia.id}", "#{sob_fantasma}/#{inexistente}", verbo: :delete)
      expect(RenegotiationInstallment.exists?(parcela_alheia.id)).to be(true)
    end

    it 'batch_destroy' do
      parcela_alheia
      indistinguivel!("#{sob_alheia}/batch", "#{sob_fantasma}/batch", verbo: :delete,
                                                                      params: { 'renegotiation_installment_ids[]' => [parcela_alheia.id] })
      expect(RenegotiationInstallment.exists?(parcela_alheia.id)).to be(true)
    end

    it 'preview' do
      indistinguivel!("#{sob_alheia}/preview", "#{sob_fantasma}/preview", verbo: :post,
                                                                          params: { due_date: '2025-05-10', main_value: 100 })
    end
  end

  describe 'pagamento' do
    let(:sob_alheia) { "/api/v1/renegotiations/#{alheia.id}/payments" }
    let(:sob_fantasma) { "/api/v1/renegotiations/#{inexistente}/payments" }

    it 'search' do
      pagamento_alheio
      indistinguivel!(sob_alheia, sob_fantasma)
    end

    it 'create' do
      indistinguivel!(sob_alheia, sob_fantasma, verbo: :post,
                                                params: { renegotiation_installment_id: parcela_alheia.id,
                                                          date: '2025-01-10',
                                                          installment_paid_value_with_interest_cm: 10 })
      expect(RenegotiationPayment.where(renegotiation_id: alheia.id).count).to eq(0)
    end

    it 'update' do
      indistinguivel!("#{sob_alheia}/#{pagamento_alheio.id}", "#{sob_fantasma}/#{inexistente}",
                      verbo: :put, params: { installment_paid_value_with_interest_cm: 5 })
      expect(pagamento_alheio.reload.installment_paid_value_with_interest_cm).not_to eq(5)
    end

    it 'destroy' do
      pagamento_alheio
      indistinguivel!("#{sob_alheia}/#{pagamento_alheio.id}", "#{sob_fantasma}/#{inexistente}", verbo: :delete)
      expect(RenegotiationPayment.exists?(pagamento_alheio.id)).to be(true)
    end
  end

  describe 'anexo' do
    let(:sob_alheia) { "/api/v1/renegotiations/#{alheia.id}/attachments" }
    let(:sob_fantasma) { "/api/v1/renegotiations/#{inexistente}/attachments" }

    it 'search' do
      anexo_alheio
      indistinguivel!(sob_alheia, sob_fantasma)
    end

    it 'download — posse da URL NÃO é autorização' do
      indistinguivel!("#{sob_alheia}/#{anexo_alheio.id}/download", "#{sob_fantasma}/#{inexistente}/download")
    end

    it 'destroy — recusado ANTES da checagem de autoria' do
      # A ordem importa: conferir a autoria primeiro responderia 403 para um
      # anexo alheio, e o 403 confirma que ele existe.
      anexo_alheio
      indistinguivel!("#{sob_alheia}/#{anexo_alheio.id}", "#{sob_fantasma}/#{inexistente}", verbo: :delete)
      expect(RenegotiationAttachment.exists?(anexo_alheio.id)).to be(true)
    end
  end

  describe 'nenhum model do domínio declara default_scope' do
    it 'o escopo é aplicado NO ENDPOINT, sempre visível na leitura do código' do
      # `default_scope` vaza para `unscoped`, some sem avisar, quebra
      # `joins`/`includes` em silêncio e contamina job, seed e rake — que
      # legitimamente cruzam projetos. É por isso que o C1 o proíbe.
      [::Renegotiation, RenegotiationInstallment, RenegotiationPayment, RenegotiationAttachment].each do |model|
        expect(model.default_scopes).to be_empty, "#{model} declarou default_scope"
        expect(model).to be_project_scoped
      end
    end
  end
end
