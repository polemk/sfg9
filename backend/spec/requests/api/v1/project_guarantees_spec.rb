# frozen_string_literal: true

require 'rails_helper'

# S4 / 5.4, 7.1.4, 7.1.5 — **garantias do projeto**.
#
# É aqui que mora o defeito literal do legado
# (`pub/project_guarantees_controller.rb:22`): a linha
#
#     @project_guarantees = ProjectGuarantee.where(id: params[:project_guarantee_id])
#
# **reatribuía** a relação escopada da linha anterior. O filtro de projeto
# desaparecia, e qualquer sessão lia a garantia de qualquer projeto pela query
# string. O primeiro exemplo deste arquivo é esse cenário.
RSpec.describe 'API V1 Project guarantees', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'gar-a', name: 'Garantias A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'gar-b', name: 'Garantias B') }

  let(:portador_a) { create(:carrier, title: 'Portador Conectado A') }
  let(:portador_b) { create(:carrier, title: 'Portador Conectado B') }
  let(:tipo) { create(:project_guarantee_type, title: 'Aval') }

  let!(:garantia_a) do
    create(:project_guarantee, project: projeto_a, carrier: portador_a, guarantee_type: tipo,
                               title: 'Aval do sócio', value: 250_000)
  end
  let!(:garantia_b) do
    create(:project_guarantee, project: projeto_b, carrier: portador_b, guarantee_type: tipo,
                               title: 'Alienação', value: 90_000)
  end

  describe 'GET /api/v1/project_guarantees' do
    # 7.1.4 — **o teste que define esta fatia**.
    it 'com `project_guarantee_id` de OUTRO projeto devolve VAZIO (D-29 — a linha 22 do legado)' do
      get '/api/v1/project_guarantees', params: { project_guarantee_id: garantia_b.id },
                                        headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to be_empty
      expect(response.headers['X-Total-Count']).to eq('0')
    end

    it 'com `project_guarantee_id` do PRÓPRIO projeto filtra dentro do escopo' do
      get '/api/v1/project_guarantees', params: { project_guarantee_id: garantia_a.id },
                                        headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |g| g['id'] }).to eq([garantia_a.id])
    end

    it 'a lista sem filtro traz só as do projeto corrente' do
      get '/api/v1/project_guarantees', headers: auth_headers(gerente, project: projeto_a)

      ids = JSON.parse(response.body).map { |g| g['id'] }
      expect(ids).to include(garantia_a.id)
      expect(ids).not_to include(garantia_b.id)
    end

    # D-32 — no legado a chave `title` devolvia `"risk_operations.title"`, tabela
    # fora do join: clicar em "Título" produzia erro de SQL.
    it 'ordena por "Título" SEM erro de SQL, nos dois sentidos' do
      create(:project_guarantee, project: projeto_a, carrier: portador_a, guarantee_type: tipo,
                                 title: 'AAA primeira')

      get '/api/v1/project_guarantees', params: { ordering_keys: ['title'], ordering_style: ['up'] },
                                        headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |g| g['title'] }.first).to eq('AAA primeira')

      get '/api/v1/project_guarantees', params: { ordering_keys: ['title'], ordering_style: ['down'] },
                                        headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |g| g['title'] }.first).to eq('Aval do sócio')
    end

    it 'ordena por portador e por tipo — as duas chaves que precisam do join' do
      %w[carrier guarantee_type value].each do |chave|
        get '/api/v1/project_guarantees', params: { ordering_keys: [chave], ordering_style: ['up'] },
                                          headers: auth_headers(gerente, project: projeto_a)
        expect(response).to have_http_status(200), "ordenar por #{chave} falhou"
      end
    end

    it 'chave de ordenação DESCONHECIDA é ignorada, nunca 500 (o legado fazia `nil + " "`)' do
      get '/api/v1/project_guarantees', params: { ordering_keys: ['risk_operations.title; DROP TABLE'] },
                                        headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
    end

    it 'busca no título da garantia E no do portador' do
      get '/api/v1/project_guarantees', params: { q: 'Conectado A' },
                                        headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body).map { |g| g['id'] }).to include(garantia_a.id)
    end
  end

  describe 'GET /api/v1/project_guarantees/available_carriers' do
    # BE-119 — **um único critério**: a conexão do projeto.
    it 'oferece só os portadores CONECTADOS ao projeto corrente' do
      solto = create(:carrier, title: 'Portador Sem Conexão')

      get '/api/v1/project_guarantees/available_carriers', headers: auth_headers(gerente, project: projeto_a)

      ids = JSON.parse(response.body).map { |c| c['id'] }
      expect(ids).to include(portador_a.id)
      expect(ids).not_to include(portador_b.id)
      expect(ids).not_to include(solto.id)
    end
  end

  describe 'POST /api/v1/project_guarantees' do
    it 'cria no projeto corrente, com o autor da SESSÃO' do
      post '/api/v1/project_guarantees',
           params: { title: 'Nova garantia', carrier_id: portador_a.id,
                     guarantee_type_id: tipo.id, value: '1000.50' },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      criada = ProjectGuarantee.find(JSON.parse(response.body)['id'])
      expect(criada.project_id).to eq(projeto_a.id)
      expect(criada.user_id).to eq(gerente.id)
      expect(criada.value).to eq(BigDecimal('1000.50'))
    end

    # 7.1.5
    it 'recusa com 422 um `carrier_id` NÃO conectado ao projeto corrente' do
      post '/api/v1/project_guarantees',
           params: { title: 'Do portador alheio', carrier_id: portador_b.id,
                     guarantee_type_id: tipo.id, value: '10' },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(response.body).to include('não está conectado')
    end

    it 'ignora `project_id` e `user_id` do corpo' do
      post '/api/v1/project_guarantees',
           params: { title: 'Com payload forjado', carrier_id: portador_a.id,
                     guarantee_type_id: tipo.id, value: '10',
                     project_id: projeto_b.id, user_id: outro.id },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      criada = ProjectGuarantee.find(JSON.parse(response.body)['id'])
      expect(criada.project_id).to eq(projeto_a.id)
      expect(criada.user_id).to eq(gerente.id)
    end

    it '`observation` longa NÃO é truncada (era string(255) com textarea na tela)' do
      texto = 'x' * 3000
      post '/api/v1/project_guarantees',
           params: { title: 'Com observação', carrier_id: portador_a.id,
                     guarantee_type_id: tipo.id, value: '10', observation: texto },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      expect(ProjectGuarantee.find(JSON.parse(response.body)['id']).observation.length).to eq(3000)
    end
  end

  describe 'PUT / DELETE' do
    it 'id de OUTRO projeto responde 404 nos dois verbos, e o registro alheio fica intacto' do
      put "/api/v1/project_guarantees/#{garantia_b.id}", params: { title: 'Invadida' },
                                                         headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(garantia_b.reload.title).to eq('Alienação')

      delete "/api/v1/project_guarantees/#{garantia_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(ProjectGuarantee.exists?(garantia_b.id)).to be(true)
    end

    it 'o update do próprio projeto funciona e não move de tenant' do
      put "/api/v1/project_guarantees/#{garantia_a.id}",
          params: { title: 'Atualizada', project_id: projeto_b.id },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(garantia_a.reload.title).to eq('Atualizada')
      expect(garantia_a.project_id).to eq(projeto_a.id)
    end
  end

  # BE-705 — o tipo de garantia é catálogo GLOBAL da S3 e passa a bloquear
  # sozinho quando há garantia usando. A regra já estava declarada lá; este
  # exemplo prova que ela passou a valer com a tabela desta fatia.
  describe 'o tipo de garantia (catálogo global) fica bloqueado' do
    it 'excluir um tipo em uso responde 422 e o tipo PERMANECE' do
      og = create(:user, user_type: UserType.og)

      delete "/api/v1/project_guarantee_types/#{tipo.id}", headers: auth_headers(og)

      expect(response).to have_http_status(422)
      expect(response.body).to include('garantia(s) de projeto')
      expect(ProjectGuaranteeType.exists?(tipo.id)).to be(true)
    end
  end
end
