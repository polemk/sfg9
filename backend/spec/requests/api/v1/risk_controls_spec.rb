# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-230..BE-241, BE-252 — **limites de risco** pela borda HTTP.
#
# Cobre: CRUD, o `q` que passa a filtrar (IMP-R3), a imutabilidade de empresa,
# portador e tipo (B-01), a exclusão que responde **422 real** e não 202
# (D-24/D-98), o escopo por projeto (**C1**) e a autorização (**C3**).
RSpec.describe 'API V1 Risk controls', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro_gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'rc-a', name: 'Risco A') }
  let!(:projeto_b) { create_project_with_owner(outro_gerente, slug: 'rc-b', name: 'Risco B') }

  let(:empresa_a) { create(:company, project: projeto_a, title: 'Empresa A') }
  let(:empresa_b) { create(:company, project: projeto_b, title: 'Empresa B') }

  let(:portador_alfa) { create(:carrier, title: 'Banco Alfa') }
  let(:portador_beta) { create(:carrier, title: 'Banco Beta') }
  let(:tipo) { create(:risk_operation_type, title: 'Fomento') }
  let(:tipo_com_pre) { create(:risk_operation_type, :com_pre, title: 'Comissária') }

  let!(:limite_a) do
    create(:risk_control, project: projeto_a, company: empresa_a, carrier: portador_alfa,
                          risk_operation_type: tipo, limite: 200_000, taxa: 2.55)
  end
  let!(:limite_b) do
    create(:risk_control, project: projeto_b, company: empresa_b, carrier: portador_beta,
                          risk_operation_type: tipo, limite: 500_000, taxa: 1.10)
  end

  # ---------------------------------------------------------------------------
  # BE-230 — lista
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/risk_controls' do
    it 'lists ONLY the current project (C1)' do
      get '/api/v1/risk_controls', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |c| c['id'] }).to eq([limite_a.id])
    end

    it 'IMP-R3 — the `q` parameter actually filters now' do
      create(:risk_control, project: projeto_a, company: empresa_a,
                            carrier: create(:carrier, title: 'Banco Ômega'), risk_operation_type: tipo)

      get '/api/v1/risk_controls', params: { q: 'alfa' }, headers: auth_headers(gerente, project: projeto_a)

      corpo = JSON.parse(response.body)
      expect(corpo.map { |c| c['id'] }).to eq([limite_a.id])
      expect(response.headers['X-Total-Count']).to eq('1')
    end

    it 'emits the real total in the pagination envelope (DEC-62)' do
      3.times do |i|
        create(:risk_control, project: projeto_a, company: empresa_a,
                              carrier: create(:carrier, title: "Extra #{i}"), risk_operation_type: tipo)
      end

      get '/api/v1/risk_controls', params: { per_page: 2 }, headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('4')
      expect(response.headers['X-Total-Pages']).to eq('2')
    end

    it 'filters by type, carrier and company inside the scope' do
      get '/api/v1/risk_controls', params: { carrier_id: portador_beta.id },
                                   headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body)).to be_empty
    end

    it 'requires a session' do
      get '/api/v1/risk_controls'
      expect(response).to have_http_status(401)
    end
  end

  describe 'GET /api/v1/risk_controls/:id' do
    it 'answers 404 for an id of ANOTHER project — same as a nonexistent id (C1)' do
      get "/api/v1/risk_controls/#{limite_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)

      get "/api/v1/risk_controls/#{SecureRandom.uuid}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end

    it 'answers 404 (not 500) for a malformed id' do
      get '/api/v1/risk_controls/nao-e-uuid', headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-234 — criação
  # ---------------------------------------------------------------------------
  describe 'POST /api/v1/risk_controls' do
    let(:portador_novo) { create(:carrier, title: 'Banco Novo') }

    before { ProjectToCarrierConnection.create!(project: projeto_a, carrier: portador_novo) }

    it 'creates the control, stamps the author from the SESSION and derives the title' do
      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: portador_novo.id,
                     risk_operation_type_id: tipo.id, limite: '150000.00', taxa: '3.2500' },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['title']).to eq('Banco Novo')
      expect(RiskControl.find(corpo['id']).user_id).to eq(gerente.id)
    end

    it 'opens the static pair for a pre-billing type (BE-241)' do
      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: portador_novo.id,
                     risk_operation_type_id: tipo_com_pre.id, limite: '100000', taxa: '2',
                     original_balance: '50000', original_balance_pre: '30000' },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(201)
      control = RiskControl.find(JSON.parse(response.body)['id'])
      expect(control.risk_operations.where(is_static: true).count).to eq(2)
    end

    it 'refuses a company from ANOTHER project (C1)' do
      post '/api/v1/risk_controls',
           params: { company_id: empresa_b.id, carrier_id: portador_novo.id,
                     risk_operation_type_id: tipo.id, limite: '1', taxa: '1' },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to match(/Empresa não encontrada/)
    end

    it 'refuses a carrier that is not connected to the project' do
      solto = create(:carrier, title: 'Portador Solto')
      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: solto.id,
                     risk_operation_type_id: tipo.id, limite: '1', taxa: '1' },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to match(/não está conectado/)
    end

    it 'refuses a duplicate (company, carrier, type) with 422, not 500' do
      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: portador_alfa.id,
                     risk_operation_type_id: tipo.id, limite: '1', taxa: '1' },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(422)
    end

    it 'ACCEPTS limite zero' do
      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: portador_novo.id,
                     risk_operation_type_id: tipo.id, limite: '0', taxa: '0' },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(201)
    end

    it 'IGNORES a project_id sent in the body — it is not even declared' do
      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: portador_novo.id,
                     risk_operation_type_id: tipo.id, limite: '1', taxa: '1',
                     project_id: projeto_b.id },
           headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(201)
      expect(RiskControl.find(JSON.parse(response.body)['id']).project_id).to eq(projeto_a.id)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-235 — atualização (B-01)
  # ---------------------------------------------------------------------------
  describe 'PUT /api/v1/risk_controls/:id' do
    it 'updates limite and taxa' do
      put "/api/v1/risk_controls/#{limite_a.id}", params: { limite: '999000.00', taxa: '4.5' },
                                                  headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(200)
      expect(limite_a.reload.limite).to eq(999_000.00)
    end

    it 'REFUSES to change the company, the carrier or the type — 422 (B-01)' do
      %i[company_id carrier_id risk_operation_type_id].each do |campo|
        valor = case campo
                when :company_id then create(:company, project: projeto_a).id
                when :carrier_id then portador_beta.id
                else create(:risk_operation_type).id
                end

        put "/api/v1/risk_controls/#{limite_a.id}", params: { campo => valor },
                                                    headers: auth_headers(gerente, project: projeto_a), as: :json

        expect(response).to have_http_status(422), "#{campo} deveria ser imutável"
        expect(JSON.parse(response.body)['details']['immutable']).to include(campo.to_s)
      end
    end

    it 'answers 404 for a control of another project' do
      put "/api/v1/risk_controls/#{limite_b.id}", params: { limite: '1' },
                                                  headers: auth_headers(gerente, project: projeto_a), as: :json
      expect(response).to have_http_status(404)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-236 / BE-237
  # ---------------------------------------------------------------------------
  describe 'PUT /api/v1/risk_controls/:id/activate and /deactivate' do
    it 'deactivates and the control leaves the console summary (B-02)' do
      put "/api/v1/risk_controls/#{limite_a.id}/deactivate",
          headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(200)
      expect(limite_a.reload.is_active).to be(false)

      get '/api/v1/risk_controls/summary', params: { company_id: empresa_a.id },
                                           headers: auth_headers(gerente, project: projeto_a)
      infos = JSON.parse(response.body)['controls_info']
      expect(infos.flat_map { |i| i['rcs'] }.map { |r| r['id'] }).not_to include(limite_a.id)
    end

    it 'activates again and the control returns to the aggregate immediately' do
      limite_a.deactivate!
      put "/api/v1/risk_controls/#{limite_a.id}/activate",
          headers: auth_headers(gerente, project: projeto_a), as: :json

      expect(response).to have_http_status(200)
      expect(limite_a.reload.is_active).to be(true)

      get '/api/v1/risk_controls/summary', params: { company_id: empresa_a.id },
                                           headers: auth_headers(gerente, project: projeto_a)
      infos = JSON.parse(response.body)['controls_info']
      expect(infos.flat_map { |i| i['rcs'] }.map { |r| r['id'] }).to include(limite_a.id)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-238 — exclusão
  # ---------------------------------------------------------------------------
  describe 'DELETE /api/v1/risk_controls/:id' do
    it 'deletes a control with no dependents' do
      delete "/api/v1/risk_controls/#{limite_a.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
      expect(RiskControl.exists?(limite_a.id)).to be(false)
    end

    it 'answers 422 REAL when blocked — never 202 (D-24 / D-98)' do
      create(:risk_operation, risk_control: limite_a)

      delete "/api/v1/risk_controls/#{limite_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to match(/operação\(ões\) de risco/i)
      expect(RiskControl.exists?(limite_a.id)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-232 / BE-252 — combos
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/risk_controls/carriers' do
    it 'lists the carriers connected to the project of the company' do
      get '/api/v1/risk_controls/carriers', params: { company_id: empresa_a.id },
                                            headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |c| c['id'] }).to include(portador_alfa.id)
      expect(JSON.parse(response.body).map { |c| c['id'] }).not_to include(portador_beta.id)
    end

    it 'answers 404 (not 500) for a company of another project' do
      get '/api/v1/risk_controls/carriers', params: { company_id: empresa_b.id },
                                            headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end
  end

  describe 'GET /api/v1/risk_controls/filters' do
    it 'lists ONLY carriers that have an ACTIVE control, with uniq' do
      limite_extra = create(:risk_control, project: projeto_a, company: empresa_a,
                            carrier: portador_alfa,
                            risk_operation_type: create(:risk_operation_type, title: 'Outro tipo'))

      get '/api/v1/risk_controls/filters', headers: auth_headers(gerente, project: projeto_a)

      ids = JSON.parse(response.body).map { |c| c['id'] }
      # Dois limites do MESMO portador produzem UMA linha.
      expect(ids).to eq([portador_alfa.id])

      limite_a.deactivate!
      limite_extra.deactivate!
      get '/api/v1/risk_controls/filters', headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body)).to be_empty
    end
  end

  describe 'GET /api/v1/risk_controls/available (BE-252)' do
    it 'lists a control with no operation on the date' do
      get '/api/v1/risk_controls/available', params: { company_id: empresa_a.id, date: '2026-04-01' },
                                             headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |c| c['id'] }).to include(limite_a.id)
    end

    it 'NEVER lists a pre-billing control — the static pair is always in the window' do
      portador_novo = create(:carrier, title: 'Pre Novo')
      ProjectToCarrierConnection.create!(project: projeto_a, carrier: portador_novo)
      com_pre = create(:risk_control, project: projeto_a, company: empresa_a,
                                      carrier: portador_novo, risk_operation_type: tipo_com_pre)

      get '/api/v1/risk_controls/available', params: { company_id: empresa_a.id, date: '2026-04-01' },
                                             headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |c| c['id'] }).not_to include(com_pre.id)
    end
  end

  # ---------------------------------------------------------------------------
  # C3 — autorização, os DOIS lados
  # ---------------------------------------------------------------------------
  describe 'authorisation (C3)' do
    it 'lets the Colaborador who participates READ the controls' do
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')
      get '/api/v1/risk_controls', headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(200)
    end

    it 'lets the Colaborador who participates WRITE — the matrix says CRUD for the four roles' do
      # A linha `risk_controls` da matriz é `CRUD CRUD CRUD CRUD`: no grupo
      # "Projeto" o gate é a PARTICIPAÇÃO (C1), não o papel (C3). Este exemplo
      # existe para que ninguém "endureça" o gate por intuição — mudar isso é
      # mudar a matriz, que é contrato (DEC-18).
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')
      portador_novo = create(:carrier, title: 'Colab Novo')
      ProjectToCarrierConnection.create!(project: projeto_a, carrier: portador_novo)

      post '/api/v1/risk_controls',
           params: { company_id: empresa_a.id, carrier_id: portador_novo.id,
                     risk_operation_type_id: tipo.id, limite: '1', taxa: '1' },
           headers: auth_headers(colaborador, project: projeto_a), as: :json

      expect(response).to have_http_status(201)
    end

    it 'answers 404 for a user with NO membership in the project — same as a nonexistent project' do
      estranho = create(:user, user_type: UserType.colaborador)
      get '/api/v1/risk_controls', headers: auth_headers(estranho, project: projeto_a)
      expect(response).to have_http_status(404)

      get '/api/v1/risk_controls', headers: auth_headers(estranho).merge('X-Project-Id' => SecureRandom.uuid)
      expect(response).to have_http_status(404)
    end

    it 'blocks WRITE for a readonly user, on the SERVER (FE-248)' do
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')
      permissao = Permission.find_by(key: 'user_is_readonly')
      UserPermission.create!(user: colaborador, permission: permissao,
                             source: 'manual', granted_at: Time.current)

      put "/api/v1/risk_controls/#{limite_a.id}", params: { limite: '1' },
                                                  headers: auth_headers(colaborador, project: projeto_a), as: :json

      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')

      # E a LEITURA continua funcionando.
      get '/api/v1/risk_controls', headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(200)
    end
  end
end
