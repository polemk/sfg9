# frozen_string_literal: true

require 'rails_helper'

# S4 / 5.3, 7.1.6, 7.4.7, 7.4.8 — **conexões projeto ↔ portador**.
#
# Quatro defeitos do lote do legado (`update_connections`) são verificados aqui
# **pela ausência deles**: `constantize` de parâmetro, `save` com retorno
# ignorado, só-o-último-item inspecionado e lote vazio derrubando a ação.
RSpec.describe 'API V1 Project carrier connections', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'conn-a', name: 'Conexões A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'conn-b', name: 'Conexões B') }

  let!(:portador1) { create(:carrier, title: 'Alfa') }
  let!(:portador2) { create(:carrier, title: 'Beta') }

  describe 'GET /candidates' do
    it 'lista o catálogo GLOBAL com o estado da conexão do projeto corrente resolvido' do
      create(:project_to_carrier_connection, project: projeto_a, carrier: portador1)

      get '/api/v1/project_carrier_connections/candidates', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      por_id = JSON.parse(response.body).index_by { |c| c['id'] }
      expect(por_id[portador1.id]['connected']).to be(true)
      expect(por_id[portador2.id]['connected']).to be(false)
    end

    it 'a conexão do projeto B não marca o candidato como conectado no projeto A' do
      create(:project_to_carrier_connection, project: projeto_b, carrier: portador2)

      get '/api/v1/project_carrier_connections/candidates', headers: auth_headers(gerente, project: projeto_a)

      por_id = JSON.parse(response.body).index_by { |c| c['id'] }
      expect(por_id[portador2.id]['connected']).to be(false)
    end
  end

  describe 'PUT /batch' do
    it 'conecta em lote, com resultado POR ITEM' do
      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'connect', carrier_ids: [portador1.id, portador2.id] },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo['applied']).to eq(2)
      expect(corpo['results'].size).to eq(2)
      expect(ProjectToCarrierConnection.for_project(projeto_a).count).to eq(2)
    end

    # 7.4.8 — lote com um item inválido: os DEMAIS são aplicados. No legado só o
    # último item era inspecionado e o lote respondia `:ok` mentindo.
    it 'um item inexistente é recusado e os demais são aplicados' do
      inexistente = SecureRandom.uuid

      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'connect', carrier_ids: [portador1.id, inexistente] },
          headers: auth_headers(gerente, project: projeto_a)

      corpo = JSON.parse(response.body)
      expect(corpo['applied']).to eq(1)
      expect(corpo['failed']).to eq(1)
      expect(ProjectToCarrierConnection.for_project(projeto_a).pluck(:carrier_id)).to eq([portador1.id])
    end

    it 'lote VAZIO responde 400 — no legado dava `NoMethodError` no `nil`' do
      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'connect', carrier_ids: [] },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(400)
    end

    it 'ação fora do conjunto fechado responde 400 — não há `constantize` de parâmetro' do
      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'Kernel', carrier_ids: [portador1.id] },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(400)
    end

    it 'conectar o que JÁ está conectado é sucesso, não erro nem duplicata' do
      create(:project_to_carrier_connection, project: projeto_a, carrier: portador1)

      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'connect', carrier_ids: [portador1.id] },
          headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body)['applied']).to eq(1)
      expect(ProjectToCarrierConnection.for_project(projeto_a).count).to eq(1)
    end

    it 'desconectar o que NÃO está conectado responde ok, não 500' do
      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'disconnect', carrier_ids: [portador1.id] },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['results'].first['message']).to include('Não estava conectado')
    end

    it 'desconectar portador com garantia no projeto é recusado, com a contagem na mensagem' do
      conexao = create(:project_to_carrier_connection, project: projeto_a, carrier: portador1)
      create(:project_guarantee, project: projeto_a, carrier: portador1)

      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'disconnect', carrier_ids: [portador1.id] },
          headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body)['failed']).to eq(1)
      expect(response.body).to include('1 garantia(s)')
      expect(ProjectToCarrierConnection.exists?(conexao.id)).to be(true)
    end

    # 7.1.6 — o lote roda no projeto CORRENTE, sempre. Não há `project_id` no
    # `params do` deste endpoint.
    it 'conectar a partir de um projeto sem participação responde 404' do
      projeto_c = create_project_with_owner(outro, slug: 'conn-c', name: 'Conexões C')

      put '/api/v1/project_carrier_connections/batch',
          params: { action_kind: 'connect', carrier_ids: [portador1.id] },
          headers: auth_headers(gerente).merge('X-Project-Id' => projeto_c.id.to_s)

      expect(response).to have_http_status(404)
      expect(ProjectToCarrierConnection.for_project(projeto_c)).to be_empty
    end
  end

  describe 'DELETE /:id' do
    it 'remove a conexão do próprio projeto' do
      conexao = create(:project_to_carrier_connection, project: projeto_a, carrier: portador1)

      delete "/api/v1/project_carrier_connections/#{conexao.id}",
             headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(204).or have_http_status(200)
      expect(ProjectToCarrierConnection.exists?(conexao.id)).to be(false)
    end

    it 'id de OUTRO projeto responde 404 e a conexão alheia permanece' do
      alheia = create(:project_to_carrier_connection, project: projeto_b, carrier: portador2)

      delete "/api/v1/project_carrier_connections/#{alheia.id}",
             headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
      expect(ProjectToCarrierConnection.exists?(alheia.id)).to be(true)
    end
  end

  # O outro lado da regra de fronteira com a S3: o portador é catálogo GLOBAL e
  # a conexão já estava declarada em `Carrier.blocking_dependents` antes de esta
  # tabela existir. A declaração passa a valer sozinha agora.
  describe 'o portador (catálogo global) fica bloqueado' do
    it 'excluir portador conectado a projeto responde 422 e o portador PERMANECE' do
      create(:project_to_carrier_connection, project: projeto_a, carrier: portador1)
      og = create(:user, user_type: UserType.og)

      delete "/api/v1/carriers/#{portador1.id}", headers: auth_headers(og)

      expect(response).to have_http_status(422)
      expect(response.body).to include('conexão(ões) de projeto')
      expect(Carrier.exists?(portador1.id)).to be(true)
    end
  end
end
