# frozen_string_literal: true

require 'rails_helper'

# S3 / tarefas 4.1.1 a 4.1.4 — **a família D-23** nos cinco catálogos globais.
#
# O legado tinha o gate de papel **só na view** (D-23/D-34): qualquer requisição
# fora da tela fazia tudo, e o `ProjectGuaranteeTypesController` chegava a
# declarar `requires_current_user? == false` — o endpoint respondia **para
# anônimo**.
#
# Estes exemplos varrem os CINCO recursos de uma vez, de propósito: um teste por
# recurso é o caminho para quatro estarem cobertos e o quinto não.
RSpec.describe 'Autorização dos catálogos globais', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }
  let(:admin) { create(:user, :admin) }
  let(:colaborador) { create(:user, :colaborador) }

  # Cada catálogo: caminho, corpo mínimo de criação e um registro existente.
  CATALOGOS = {
    '/api/v1/carriers' => -> { { title: 'Portador Novo' } },
    '/api/v1/carrier_groups' => -> { { title: 'Grupo Novo' } },
    '/api/v1/segments' => -> { { title: 'Segmento Novo' } },
    '/api/v1/sub_segments' => -> { { title: 'Subsegmento Novo' } },
    '/api/v1/project_guarantee_types' => -> { { title: 'Garantia Nova' } }
  }.freeze

  FABRICAS = {
    '/api/v1/carriers' => :carrier,
    '/api/v1/carrier_groups' => :carrier_group,
    '/api/v1/segments' => :segment,
    '/api/v1/sub_segments' => :sub_segment,
    '/api/v1/project_guarantee_types' => :project_guarantee_type
  }.freeze

  # 4.1.1 — o defeito LITERAL do legado.
  describe 'sem credencial' do
    it 'GET /api/v1/project_guarantee_types responde 401' do
      get '/api/v1/project_guarantee_types'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'os cinco catálogos respondem 401 sem credencial' do
      CATALOGOS.each_key do |path|
        get path
        expect(response).to have_http_status(:unauthorized), "#{path} respondeu #{response.status} para anônimo"
      end
    end
  end

  # 4.1.2 — DEC-18.4: o menu esconde a TELA, não o DADO.
  describe 'Colaborador' do
    it 'LÊ os cinco catálogos' do
      CATALOGOS.each_key do |path|
        get path, headers: auth_headers(colaborador)
        expect(response).to have_http_status(:ok), "#{path} negou leitura ao Colaborador"
      end
    end

    it 'NÃO escreve em nenhum dos cinco (POST/PUT/DELETE → 403)' do
      CATALOGOS.each do |path, corpo|
        registro = create(FABRICAS.fetch(path))

        post path, params: corpo.call, headers: auth_headers(colaborador)
        expect(response).to have_http_status(:forbidden), "POST #{path}"

        put "#{path}/#{registro.id}", params: { title: 'Alterado' }, headers: auth_headers(colaborador)
        expect(response).to have_http_status(:forbidden), "PUT #{path}"

        delete "#{path}/#{registro.id}", headers: auth_headers(colaborador)
        expect(response).to have_http_status(:forbidden), "DELETE #{path}"
      end
    end
  end

  # 4.1.4 — hierarquia nos DOIS sentidos (contrato C3).
  #
  # Um teste que só verifique "a trava existe" passa com a comparação de sinal
  # invertida — e a escala do ai9 é INVERTIDA em relação à do legado (menor =
  # mais poder). Por isso o mesmo exemplo afirma que o Admin ESCREVE.
  describe 'hierarquia (C3), nos dois sentidos' do
    it 'Admin escreve nos cinco; Colaborador não escreve em nenhum' do
      CATALOGOS.each do |path, corpo|
        post path, params: corpo.call, headers: auth_headers(admin)
        expect(response).to have_http_status(:created), "Admin não conseguiu criar em #{path}: #{response.body}"

        post path, params: corpo.call.merge(title: "#{corpo.call[:title]} 2"), headers: auth_headers(colaborador)
        expect(response).to have_http_status(:forbidden), "Colaborador criou em #{path}"
      end
    end
  end

  # 4.1.3 — `user_is_readonly` (DEC-18.6), promovido de flag de view a checagem
  # de servidor. Vale MESMO para Admin: o modificador é ortogonal ao papel.
  describe 'user_is_readonly' do
    def grant_readonly!(user)
      UserPermission.create!(user: user, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)
    end

    it 'nega escrita nos cinco catálogos mesmo sendo Admin, e mantém a leitura' do
      grant_readonly!(admin)

      CATALOGOS.each do |path, corpo|
        registro = create(FABRICAS.fetch(path))

        post path, params: corpo.call, headers: auth_headers(admin)
        expect(response).to have_http_status(:forbidden), "POST #{path}"
        expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')

        delete "#{path}/#{registro.id}", headers: auth_headers(admin)
        expect(response).to have_http_status(:forbidden), "DELETE #{path}"

        get path, headers: auth_headers(admin)
        expect(response).to have_http_status(:ok), "GET #{path} deveria continuar funcionando (#{response.status}: #{response.body[0, 200]})"
      end
    end

    it 'o MESMO Admin sem a concessão escreve normalmente' do
      post '/api/v1/segments', params: { title: 'Comércio' }, headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
    end
  end

  # OG é o papel do fornecedor (DEC-18.1) e alcança tudo.
  it 'OG escreve nos cinco' do
    CATALOGOS.each do |path, corpo|
      post path, params: corpo.call, headers: auth_headers(og)
      expect(response).to have_http_status(:created), "OG não conseguiu criar em #{path}: #{response.body}"
    end
  end
end
