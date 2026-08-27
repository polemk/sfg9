# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.6, 10.8, 10.9 — o catálogo de indicadores pela API.
#
# Este arquivo é o par de servidor do **BE-717**, o gap de segurança confirmado:
# no legado **nenhum** dos três controllers de indicador tem um único
# `before_action` de permissão — toda a autorização é de view, e `user_is_readonly`
# só desabilita botões. Qualquer sessão autenticada podia `POST /indicators`.
RSpec.describe 'API V1 Indicators', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, user_type: UserType.og) }
  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  let!(:projeto) { create_project_with_owner(gerente, slug: 'ind-a', name: 'Indicadores A') }

  describe 'GET /api/v1/indicators' do
    before do
      create(:indicator, title: 'MARGEM')
      create(:indicator, title: 'ATRASO')
      create(:indicator, :specific, title: 'SO DO PROJETO', project: projeto)
    end

    it 'lista só os GLOBAIS, em ordem alfabética' do
      get '/api/v1/indicators', headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |i| i['title'] }).to eq(%w[ATRASO MARGEM])
    end

    # No legado o front manda `l=50, o=0` fixos e **nunca incrementa o offset**:
    # a lista trunca em 50 indicadores sem aviso nenhum, e não há total.
    it 'a paginação é REAL e o total vem no cabeçalho (DEC-62)' do
      get '/api/v1/indicators', params: { page: 1, per_page: 1 }, headers: auth_headers(gerente)

      expect(JSON.parse(response.body).size).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('2')
      expect(response.headers['X-Total-Pages']).to eq('2')
    end

    # BE-312 / achado A-5 do DEC-85: `get_ordering_key("key")` devolvia
    # `"integration_key"`, coluna inexistente → `PG::UndefinedColumn` (500).
    it 'ordenar por "Chave" FUNCIONA — no legado era 500' do
      get '/api/v1/indicators', params: { ordering_keys: ['key'], ordering_style: ['down'] },
                                headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |i| i['key'] }).to eq(%w[margem atraso])
    end

    it 'chave de ordenação desconhecida é ignorada, não 500' do
      get '/api/v1/indicators', params: { ordering_keys: ['drop'], ordering_style: ['up'] },
                                headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
    end

    it 'traz a contagem de lançamentos — o número que a confirmação de exclusão usa (FE-315)' do
      margem = Indicator.find_by(title: 'MARGEM')
      create(:indicator_entry, project: projeto, indicator: margem, month: 1)

      get '/api/v1/indicators', headers: auth_headers(gerente)
      linha = JSON.parse(response.body).find { |i| i['title'] == 'MARGEM' }
      expect(linha['entries_count']).to eq(1)
    end

    # **DEC-18.4** — o menu esconde a tela de administração do catálogo, não o
    # dado do catálogo. Sem isto todo dropdown do papel mais numeroso quebra.
    it 'o COLABORADOR lê o catálogo global (DEC-18.4)' do
      get '/api/v1/indicators', headers: auth_headers(colaborador)

      expect(response).to have_http_status(200)
    end

    # **C1, regra 4** — catálogo global não é escopado por projeto.
    it 'não exige projeto corrente: o catálogo global é SEM escopo (C1 regra 4)' do
      sem_projeto = create(:user, user_type: UserType.colaborador)

      get '/api/v1/indicators', headers: auth_headers(sem_projeto)
      expect(response).to have_http_status(200)
    end

    it 'sem sessão é 401' do
      get '/api/v1/indicators'
      expect(response).to have_http_status(401)
    end
  end

  describe 'GET /api/v1/indicators/:id' do
    it 'devolve 404 ESTRUTURADO para id inexistente — no legado era 500 sempre (BE-313)' do
      get "/api/v1/indicators/#{SecureRandom.uuid}", headers: auth_headers(gerente)

      expect(response).to have_http_status(404)
      expect(JSON.parse(response.body)).to include('error', 'message')
    end

    it 'id malformado é 404, não `PG::InvalidTextRepresentation` → 500' do
      get '/api/v1/indicators/nao-e-uuid', headers: auth_headers(gerente)
      expect(response).to have_http_status(404)
    end
  end

  describe 'POST /api/v1/indicators' do
    it 'cria um global e devolve o título já em CAIXA ALTA sem acento (DEC-89)' do
      post '/api/v1/indicators', params: { title: 'Inadimplência' }, headers: auth_headers(gerente)

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['title']).to eq('INADIMPLENCIA')
      expect(corpo['key']).to eq('inadimplencia')
      expect(corpo['scope']).to eq('global')
    end

    it '`scope: project` cria o específico do PROJETO CORRENTE e a conexão' do
      post '/api/v1/indicators', params: { title: 'Só deste', scope: 'project' },
                                 headers: auth_headers(gerente, project: projeto)

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['project_id']).to eq(projeto.id)
      expect(ProjectIndicatorConnection.where(project: projeto, indicator_id: corpo['id']).count).to eq(1)
    end

    # C1: o projeto vem do servidor. No legado `project_id` estava no `permit` e
    # vinha do formulário — dava para criar indicador dentro de projeto alheio.
    it 'o `project_id` do CORPO é ignorado — o projeto vem do servidor (C1)' do
      alheio = create_project_with_owner(create(:user, user_type: UserType.gerente), slug: 'ind-b')

      post '/api/v1/indicators', params: { title: 'Tentativa', scope: 'project', project_id: alheio.id },
                                 headers: auth_headers(gerente, project: projeto)

      expect(JSON.parse(response.body)['project_id']).to eq(projeto.id)
    end

    it 'título duplicado é 422 com a mensagem do legado' do
      create(:indicator, title: 'MARGEM')

      post '/api/v1/indicators', params: { title: 'margem' }, headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to match(/Já utilizado/)
    end

    # **BE-717.** É o exemplo que prova que a autorização deixou de ser de view.
    it 'o COLABORADOR recebe 403 ao criar — no legado ele criava (autorização só na view)' do
      post '/api/v1/indicators', params: { title: 'Do colaborador' }, headers: auth_headers(colaborador)

      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('ROLE_REQUIRED')
    end
  end

  describe 'PUT /api/v1/indicators/:id' do
    let!(:indicador) { create(:indicator, title: 'ORIGINAL') }

    it 'renomeia e a chave permanece congelada (DEC-85)' do
      put "/api/v1/indicators/#{indicador.id}", params: { title: 'Novo nome' }, headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo['title']).to eq('NOVO NOME')
      expect(corpo['key']).to eq('original')
    end

    it 'o COLABORADOR recebe 403' do
      put "/api/v1/indicators/#{indicador.id}", params: { title: 'X' }, headers: auth_headers(colaborador)
      expect(response).to have_http_status(403)
    end
  end

  describe 'PUT /api/v1/indicators/:id/activation — BE-319' do
    it 'desativa' do
      indicador = create(:indicator, title: 'ATIVO')

      put "/api/v1/indicators/#{indicador.id}/activation", params: { is_active: false },
                                                           headers: auth_headers(og)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['is_active']).to be(false)
    end

    it 'id inexistente é 404 — no legado era `nil.is_active=` → 500' do
      put "/api/v1/indicators/#{SecureRandom.uuid}/activation", params: { is_active: true },
                                                                headers: auth_headers(og)
      expect(response).to have_http_status(404)
    end
  end

  describe 'GET /api/v1/indicators/:id/deletion_impact — FE-315, o D-66 na copy' do
    it 'diz quantos lançamentos e quais projetos, ANTES de qualquer escrita' do
      indicador = create(:indicator, title: 'COM HISTORICO')
      create(:indicator_entry, project: projeto, indicator: indicador, month: 1)
      create(:indicator_entry, project: projeto, indicator: indicador, month: 2)

      get "/api/v1/indicators/#{indicador.id}/deletion_impact", headers: auth_headers(gerente)

      corpo = JSON.parse(response.body)
      expect(corpo['entries_count']).to eq(2)
      expect(corpo['projects'].map { |p| p['name'] }).to include(projeto.name)
      expect(indicador.reload.discarded_at).to be_nil
    end
  end

  describe 'DELETE /api/v1/indicators/:id — exclusão LÓGICA (D-66)' do
    let!(:indicador) { create(:indicator, title: 'PARA EXCLUIR') }
    let!(:lancamento) { create(:indicator_entry, project: projeto, indicator: indicador, month: 4, value: 123) }

    it 'os lançamentos SOBREVIVEM e a resposta diz quantos' do
      delete "/api/v1/indicators/#{indicador.id}", headers: auth_headers(og)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['entries_preserved']).to eq(1)
      expect(lancamento.reload.value).to eq(123)
    end

    it 'o indicador some da listagem depois' do
      delete "/api/v1/indicators/#{indicador.id}", headers: auth_headers(og)

      get '/api/v1/indicators', headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |i| i['id'] }).not_to include(indicador.id)
    end

    it 'o COLABORADOR recebe 403' do
      delete "/api/v1/indicators/#{indicador.id}", headers: auth_headers(colaborador)
      expect(response).to have_http_status(403)
    end
  end

  # ---------------------------------------------------------------------------
  # C3 — a hierarquia verificada nos DOIS sentidos, papel a papel.
  describe 'autorização (C3) — os dois lados de cada papel' do
    let(:indicador) { create(:indicator, title: 'PARA TESTE') }

    {
      'og' => true, 'admin' => true, 'gerente' => true, 'colaborador' => false
    }.each do |papel, pode_escrever|
      it "#{papel} #{pode_escrever ? 'ESCREVE' : 'NÃO escreve'}, e LÊ em qualquer caso" do
        ator = create(:user, user_type: UserType.find_by(name: papel))

        get '/api/v1/indicators', headers: auth_headers(ator)
        expect(response).to have_http_status(200)

        post '/api/v1/indicators', params: { title: "Do #{papel}" }, headers: auth_headers(ator)
        expect(response).to have_http_status(pode_escrever ? 201 : 403)

        delete "/api/v1/indicators/#{indicador.id}", headers: auth_headers(ator)
        expect(response).to have_http_status(pode_escrever ? 200 : 403)
      end
    end
  end
end
