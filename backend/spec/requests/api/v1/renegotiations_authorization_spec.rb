# frozen_string_literal: true

require 'rails_helper'

# S9 / tarefa 4.22 — **autorização NO SERVIDOR** (D-17, D-23, D-34).
#
# No legado a única autorização que existia estava nos gates das **views**: o
# botão sumia, e a rota continuava respondendo. Qualquer requisição feita fora da
# tela fazia tudo. Este arquivo prova que a supressão na tela é conveniência e a
# recusa é do servidor.
RSpec.describe 'S9 — autorização no servidor' do
  let(:dono) { create(:user, :gerente) }
  let(:project) { create_project_with_owner(dono) }
  let(:renegotiation) do
    create(:renegotiation, project: project,
                           provider: create(:provider, project: project),
                           company: create(:company, project: project))
  end

  describe 'sem sessão' do
    it 'todas as rotas do domínio respondem 401' do
      rotas = [
        [:get, '/api/v1/renegotiations'],
        [:get, "/api/v1/renegotiations/#{renegotiation.id}"],
        [:post, '/api/v1/renegotiations'],
        [:get, "/api/v1/renegotiations/#{renegotiation.id}/installments"],
        [:get, "/api/v1/renegotiations/#{renegotiation.id}/payments"],
        [:get, "/api/v1/renegotiations/#{renegotiation.id}/attachments"]
      ]

      rotas.each do |verbo, caminho|
        send(verbo, caminho)
        expect(response).to have_http_status(:unauthorized), "#{verbo.upcase} #{caminho} respondeu #{response.status}"
      end
    end
  end

  describe '`user_is_readonly` (DEC-18.6)' do
    let(:leitor) { create(:user, :gerente) }

    before do
      Seeds::Reference::Permissions.call!
      Membership.create!(project: project, user: leitor, role: 'participante')
      leitor.update!(current_project_id: project.id)
      # A concessão é a mesma que `spec/requests/api/v1/catalogs_authorization_spec.rb`
      # usa — o catálogo de permissões é semeado como referência.
      UserPermission.create!(user: leitor, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)
    end

    let(:headers) { auth_headers(leitor, project: project) }

    it 'LÊ tudo' do
      get '/api/v1/renegotiations', headers: headers
      expect(response).to have_http_status(:ok)

      get "/api/v1/renegotiations/#{renegotiation.id}/installments", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'NÃO cria, NÃO edita e NÃO exclui — mesmo chamando a API direto' do
      parcela = create(:renegotiation_installment, renegotiation: renegotiation,
                                                   due_date: Date.new(2025, 1, 10))

      escritas = [
        [:post, '/api/v1/renegotiations', {}],
        [:put, "/api/v1/renegotiations/#{renegotiation.id}", { title: 'x' }],
        [:delete, "/api/v1/renegotiations/#{renegotiation.id}", {}],
        [:post, "/api/v1/renegotiations/#{renegotiation.id}/installments",
         { due_date: '2025-06-10', main_value: 1 }],
        [:put, "/api/v1/renegotiations/#{renegotiation.id}/installments/#{parcela.id}", { main_value: 2 }],
        [:delete, "/api/v1/renegotiations/#{renegotiation.id}/installments/#{parcela.id}", {}],
        [:post, "/api/v1/renegotiations/#{renegotiation.id}/payments",
         { renegotiation_installment_id: parcela.id, date: '2025-01-10',
           installment_paid_value_with_interest_cm: 1 }],
        [:post, "/api/v1/renegotiations/#{renegotiation.id}/attachments", {}],
        [:delete, "/api/v1/renegotiations/#{renegotiation.id}/attachments/#{SecureRandom.uuid}", {}]
      ]

      escritas.each do |verbo, caminho, params|
        send(verbo, caminho, params: params, headers: headers)
        expect(response).to have_http_status(:forbidden),
                            "#{verbo.upcase} #{caminho} respondeu #{response.status}"
        expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')
      end

      expect(::Renegotiation.exists?(renegotiation.id)).to be(true)
      expect(parcela.reload.main_value).to eq(1000)
    end
  end

  describe 'DEC-99 — OG e Admin enxergam todos os projetos' do
    it 'o OG lê a renegociação de um projeto em que não participa, escolhendo o projeto' do
      og = create(:user, :og)

      get '/api/v1/renegotiations', headers: auth_headers(og, project: project)

      # `Project.visible_to` já resolve isto; o exemplo existe para que uma
      # mudança futura no escopo não derrube a regra sem aviso.
      expect(response).to have_http_status(:ok)
    end
  end
end
