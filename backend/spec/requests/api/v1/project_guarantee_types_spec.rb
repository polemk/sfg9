# frozen_string_literal: true

require 'rails_helper'

# S3 / BE-700..BE-706 — tipos de garantia. **O catálogo que respondia para
# anônimo** (D-23).
RSpec.describe 'Tipos de garantia', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }
  let(:gerente) { create(:user, :gerente) }
  let(:colaborador) { create(:user, :colaborador) }

  # BE-700 / 4.1.1 — o defeito literal: `requires_current_user? == false`.
  it 'sem credencial → 401 (D-23)' do
    create(:project_guarantee_type)
    get '/api/v1/project_guarantee_types'
    expect(response).to have_http_status(:unauthorized)
  end

  # BE-701 — o gate og/admin/gerente só existia na VIEW.
  it 'sem papel autorizado a criação é 403 NO SERVIDOR (BE-701)' do
    post '/api/v1/project_guarantee_types', params: { title: 'Aval' }, headers: auth_headers(colaborador)
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)['code']).to eq('ROLE_REQUIRED')
  end

  # BE-702 — no legado o inexistente dava `MissingTemplate` → 500.
  it 'inexistente → 404, e id malformado também (BE-702)' do
    get "/api/v1/project_guarantee_types/#{SecureRandom.uuid}", headers: auth_headers(og)
    expect(response).to have_http_status(:not_found)

    get '/api/v1/project_guarantee_types/nao-e-uuid', headers: auth_headers(og)
    expect(response).to have_http_status(:not_found)
  end

  # BE-703 — este era o único controller do legado que NÃO sobrescrevia o
  # `user_id` do corpo.
  describe 'POST (BE-703)' do
    it 'grava o autor da SESSÃO e ignora o `user_id` do corpo' do
      intruso = create(:user, :admin)
      post '/api/v1/project_guarantee_types',
           params: { title: 'Alienação Fiduciária', user_id: intruso.id }, headers: auth_headers(gerente)

      expect(response).to have_http_status(:created)
      tipo = ProjectGuaranteeType.find(JSON.parse(response.body)['id'])
      expect(tipo.user_id).to eq(gerente.id)
      expect(tipo.integration_key).to eq('alienacao_fiduciaria')
    end

    it 'título único no banco (DB-084)' do
      create(:project_guarantee_type, title: 'Aval')
      post '/api/v1/project_guarantee_types', params: { title: 'Aval' }, headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # 4.3.9 / BE-704 / DC-22 — a chave de integração é congelada.
  describe 'PUT — chave de integração CONGELADA (DC-22)' do
    it 'renomear o título NÃO altera a `integration_key`' do
      tipo = create(:project_guarantee_type, title: 'Aval')
      expect(tipo.integration_key).to eq('aval')

      put "/api/v1/project_guarantee_types/#{tipo.id}", params: { title: 'Aval Solidário' },
                                                        headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      corpo = JSON.parse(response.body)
      expect(corpo['title']).to eq('Aval Solidário')
      expect(corpo['integration_key']).to eq('aval')
    end

    it 'a chave muda quando vem EXPLICITAMENTE no corpo' do
      tipo = create(:project_guarantee_type, title: 'Aval')
      put "/api/v1/project_guarantee_types/#{tipo.id}", params: { integration_key: 'aval_solidario' },
                                                        headers: auth_headers(og)
      expect(JSON.parse(response.body)['integration_key']).to eq('aval_solidario')
    end
  end

  # 4.3.6 / BE-705 — tipo em uso → 422 real.
  describe 'DELETE (BE-705)' do
    it 'declara a garantia de projeto como bloqueio, e exclui quando não há uso' do
      expect(ProjectGuaranteeType.blocking_dependents.keys).to eq(['ProjectGuarantee'])

      tipo = create(:project_guarantee_type)
      delete "/api/v1/project_guarantee_types/#{tipo.id}", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
    end
  end

  # BE-706 — as duas rotas RESPONDEM (no legado davam `MissingTemplate` → 500).
  it 'GET da lista e do detalhe respondem 200 (BE-706)' do
    tipo = create(:project_guarantee_type)

    get '/api/v1/project_guarantee_types', headers: auth_headers(colaborador)
    expect(response).to have_http_status(:ok)

    get "/api/v1/project_guarantee_types/#{tipo.id}", headers: auth_headers(colaborador)
    expect(response).to have_http_status(:ok)
  end

  # DEC-86 — semeados como PROVISÓRIOS.
  describe 'seed de referência (DEC-86 / DB-558)' do
    it 'semeia os 8 tipos marcados como provisórios e é idempotente' do
      primeira = Seeds::Reference::GuaranteeTypes.call!
      expect(primeira.created).to eq(8)
      expect(ProjectGuaranteeType.provisional.count).to eq(8)

      segunda = Seeds::Reference::GuaranteeTypes.call!
      expect(segunda).to be_idempotent
      expect(ProjectGuaranteeType.count).to eq(8)
    end

    it 'a lista é a MESMA do seed de demonstração — os dois convergem, não duplicam' do
      demo = Rails.root.join('db/seeds/demo/ledger/ancillary.rb').read
      Seeds::Reference::GuaranteeTypes::TITLES.each do |titulo|
        expect(demo).to include("'#{titulo}'"),
                        "'#{titulo}' saiu do seed de referência e ficou fora de " \
                        '`Demo::Ledger::Ancillary::GUARANTEE_TYPES` — as duas listas têm de mudar juntas'
      end
    end

    it 'o seed NÃO desfaz o que o usuário arrumou na tela' do
      Seeds::Reference::GuaranteeTypes.call!
      tipo = ProjectGuaranteeType.find_by!(title: 'Aval')
      tipo.update!(is_active: false, sort_order: 99, is_provisional: false)

      Seeds::Reference::GuaranteeTypes.call!

      tipo.reload
      expect(tipo.is_active).to be(false)
      expect(tipo.sort_order).to eq(99)
      expect(tipo.is_provisional).to be(false)
    end

    it 'a tela recebe `is_provisional` para poder avisar' do
      Seeds::Reference::GuaranteeTypes.call!
      get '/api/v1/project_guarantee_types', headers: auth_headers(colaborador)
      expect(JSON.parse(response.body)).to all(include('is_provisional' => true))
    end
  end
end
