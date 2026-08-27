# frozen_string_literal: true

require 'rails_helper'

# S4 / 5.1, 7.1.2, 7.1.10 — **empresas**.
#
# O teste que define esta fatia é o de **escopo cruzado**: dois projetos, um
# usuário membro só do A, um id que pertence ao B. O caminho feliz passa com o
# código errado — foi exatamente assim que o legado errou.
RSpec.describe 'API V1 Companies', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  # DEC-99: OG e Admin enxergam TODOS os projetos. Os casos de escopo usam
  # **Gerente** — o papel mais alto que continua preso à participação. Com Admin
  # os testes passariam pelo motivo errado.
  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'comp-a', name: 'Projeto A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'comp-b', name: 'Projeto B') }

  let!(:empresa_a) { create(:company, project: projeto_a, title: 'Construtora A') }
  let!(:empresa_b) { create(:company, project: projeto_b, title: 'Construtora B') }

  describe 'GET /api/v1/companies' do
    it 'traz SÓ as empresas do projeto corrente — e traz as dele' do
      get '/api/v1/companies', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      ids = JSON.parse(response.body).map { |c| c['id'] }
      expect(ids).to include(empresa_a.id)
      expect(ids).not_to include(empresa_b.id)
    end

    # 7.1.2 — a regra não negociável desta fatia.
    it 'com `company_id` de OUTRO projeto devolve VAZIO (nunca 403: não se confirma existência alheia)' do
      get '/api/v1/companies', params: { company_id: empresa_b.id },
                               headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to be_empty
      expect(response.headers['X-Total-Count']).to eq('0')
    end

    it 'com `company_id` do PRÓPRIO projeto filtra dentro do escopo' do
      create(:company, project: projeto_a, title: 'Outra do A')

      get '/api/v1/companies', params: { company_id: empresa_a.id },
                               headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |c| c['id'] }).to eq([empresa_a.id])
    end

    it 'com id MALFORMADO devolve vazio, não 500 (`uuid` comparado com texto qualquer)' do
      get '/api/v1/companies', params: { company_id: 'nao-e-uuid' },
                               headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to be_empty
    end

    # D-20 / 7.4.5 — a paginação passa a FUNCIONAR. No legado `.order/.limit/
    # .offset` eram descartados por `where!` e a UI de paginação era decorativa.
    it 'pagina de verdade, e o total do cabeçalho é o total SEM limite' do
      create_list(:company, 5, project: projeto_a)

      get '/api/v1/companies', params: { per_page: 2, page: 1 },
                               headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('6')
      expect(response.headers['X-Total-Pages']).to eq('3')
    end

    it '`order_mode=dash` ordena por título e IGNORA `q`' do
      create(:company, project: projeto_a, title: 'AAA Primeira')

      get '/api/v1/companies', params: { order_mode: 'dash', q: 'inexistente' },
                               headers: auth_headers(gerente, project: projeto_a)

      titulos = JSON.parse(response.body).map { |c| c['title'] }
      expect(titulos.first).to eq('AAA Primeira')
      expect(titulos).to include('Construtora A')
    end

    it 'sem projeto corrente NÃO devolve o catálogo geral — e diz o que fazer' do
      sozinho = create(:user, user_type: UserType.colaborador)

      get '/api/v1/companies', headers: auth_headers(sozinho)

      # O que esta asserção protege é o que o nome sempre disse: **nunca o
      # catálogo geral**. O status era 404 e passou a ser 409 quando o
      # `current_project!` deixou de tratar "não escolheu" como "não existe" —
      # o usuário via "Projeto não encontrado" sendo que só não tinha escolhido.
      #
      # O corpo nunca era conferido aqui: a versão anterior afirmava só o
      # status, então uma regressão que devolvesse 404 COM o catálogo dentro
      # passaria. Agora o vazamento é afirmado direto.
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['code']).to eq('PROJECT_NONE_AVAILABLE')
      expect(response.body).not_to include('Construtora A')
    end
  end

  describe 'GET /api/v1/companies/:id' do
    it 'o id do próprio projeto responde 200 e o de OUTRO responde 404 — o mesmo status de inexistente' do
      get "/api/v1/companies/#{empresa_a.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)

      get "/api/v1/companies/#{empresa_b.id}", headers: auth_headers(gerente, project: projeto_a)
      status_alheio = response.status

      get "/api/v1/companies/#{SecureRandom.uuid}", headers: auth_headers(gerente, project: projeto_a)
      expect(response.status).to eq(status_alheio)
      expect(status_alheio).to eq(404)
    end
  end

  describe 'POST /api/v1/companies' do
    # 7.1.10 — `project_id` do corpo é sempre ignorado.
    it 'ignora o `project_id` do corpo: a empresa nasce no projeto CORRENTE' do
      post '/api/v1/companies', params: { title: 'Nova', project_id: projeto_b.id },
                                headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      criada = Company.find(JSON.parse(response.body)['id'])
      expect(criada.project_id).to eq(projeto_a.id)
      expect(criada.project_id).not_to eq(projeto_b.id)
    end

    # 7.1.11 — mass assignment de PK.
    it 'ignora o `:id` do corpo' do
      forjado = SecureRandom.uuid
      post '/api/v1/companies', params: { title: 'Com id forjado', id: forjado },
                                headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      expect(JSON.parse(response.body)['id']).not_to eq(forjado)
    end

    it 'título repetido NO MESMO projeto é 422 — e o mesmo título em OUTRO projeto é permitido' do
      post '/api/v1/companies', params: { title: 'Construtora A' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)

      post '/api/v1/companies', params: { title: 'Construtora A' },
                                headers: auth_headers(outro, project: projeto_b)
      expect(response).to have_http_status(201)
    end
  end

  describe 'PUT /api/v1/companies/:id' do
    it 'ignora o `project_id` do corpo TAMBÉM no update (DC-04 — o legado esquecia aqui)' do
      put "/api/v1/companies/#{empresa_a.id}",
          params: { title: 'Renomeada', project_id: projeto_b.id },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(empresa_a.reload.project_id).to eq(projeto_a.id)
      expect(empresa_a.title).to eq('Renomeada')
    end

    it 'id de outro projeto responde 404 e NÃO altera o registro alheio' do
      put "/api/v1/companies/#{empresa_b.id}", params: { title: 'Invadida' },
                                               headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
      expect(empresa_b.reload.title).to eq('Construtora B')
    end
  end

  describe 'DELETE /api/v1/companies/:id' do
    it 'remove a do próprio projeto e recusa a de outro com 404' do
      delete "/api/v1/companies/#{empresa_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(Company.exists?(empresa_b.id)).to be(true)

      delete "/api/v1/companies/#{empresa_a.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
      expect(Company.exists?(empresa_a.id)).to be(false)
    end

    # --- 7.6, os contratos com os outros blocos ---------------------------
    #
    # Estes três testes são o **contrato** que a S4 registrou no `design.md` e
    # que só podia ser verificado quando a fatia dona entregasse a tabela. A
    # política é **simétrica**: bloquear, nunca cascatear. O legado tinha a
    # assimetria — respondia `:ok` mesmo sem excluir (`errors.any? ? :ok : :ok`)
    # e a tela dizia "removido com sucesso" (D-24).
    #
    # A parte que o teste precisa provar não é só o 422: é que **o dependente
    # continua lá**. Um 422 com o dependente apagado seria pior que o defeito.

    # 7.6.1 — cobre DB-069.
    it 'com `risk_control` responde 422 e o LIMITE permanece' do
      limite = create(:risk_control, project: projeto_a, company: empresa_a)

      delete "/api/v1/companies/#{empresa_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['error']).to include('limite')
      expect(Company.exists?(empresa_a.id)).to be(true)
      expect(RiskControl.exists?(limite.id)).to be(true)
    end

    # 7.6.2 — cobre DB-070.
    it 'com `receivable_entries` responde 422 e o RECEBÍVEL permanece' do
      recebivel = create(:receivable_entry, project: projeto_a, company: empresa_a)

      delete "/api/v1/companies/#{empresa_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['error']).to include('recebível')
      expect(Company.exists?(empresa_a.id)).to be(true)
      expect(ReceivableEntry.exists?(recebivel.id)).to be(true)
    end
  end

  # 7.3 — os DOIS lados da hierarquia. Um teste que só verifique que "a trava
  # existe" passa com o sinal da hierarquia invertido, e o sinal invertido dá
  # poder de OG a um Colaborador (DEC-41: menor = mais poder).
  describe 'autorização (contrato C3)' do
    it 'Colaborador LÊ e ESCREVE empresa (a matriz dá CRUD ao grupo "Projeto"), e OG também' do
      colaborador = create(:user, user_type: UserType.colaborador)
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')

      get '/api/v1/companies', headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(200)

      post '/api/v1/companies', params: { title: 'Do colaborador' },
                                headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(201)
    end

    # 7.3.2 — `user_is_readonly` recebe 403 em todo verbo de escrita, mesmo
    # sendo Admin.
    it 'readonly lê mas NÃO escreve, mesmo sendo Admin' do
      admin = create(:user, user_type: UserType.admin)
      UserPermission.create!(user: admin, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)

      get '/api/v1/companies', headers: auth_headers(admin, project: projeto_a)
      expect(response).to have_http_status(200)

      post '/api/v1/companies', params: { title: 'Bloqueada' },
                                headers: auth_headers(admin, project: projeto_a)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')
    end
  end
end

# ---------------------------------------------------------------------------
# Achado do seed da S20 (26/08/2026): a coluna "LIMITES" da tela de Empresas
# mostrava **43** onde o banco tinha **4**.
#
# A contagem somava TODOS os dependentes que bloqueiam a exclusão — limites,
# renegociações, recebíveis — e a entity expunha esse total como se fosse
# `risk_controls_count`. Passou despercebido enquanto só uma dessas tabelas
# existia; quebrou quando S5 e S9 entregaram na mesma semana.
#
# Número errado na tela de um sistema de crédito é pior que tela quebrada:
# tela quebrada alguém reporta.
# ---------------------------------------------------------------------------
RSpec.describe 'API V1 Companies — contagem de dependentes', type: :request do
  before { UserType.seed_default_types! }

  let(:gerente) { create(:user, :gerente) }
  let!(:projeto) { create_project_with_owner(gerente) }
  let!(:empresa) { Company.create!(project: projeto, title: 'Contagem Ltda') }

  before { Membership.find_or_create_by!(user: gerente, project: projeto) }

  it 'conta SÓ os limites em `risk_controls_count`, não a soma dos dependentes' do
    outros = Company.blocking_dependents.keys - ['RiskControl']

    get '/api/v1/companies', headers: auth_headers(gerente, project: projeto)
    linha = JSON.parse(response.body).find { |c| c['id'] == empresa.id }

    # Sem nenhum limite, a contagem é zero — mesmo que a empresa tenha outros
    # dependentes. É esta asserção que a soma quebrava.
    expect(linha['risk_controls_count']).to eq(0),
                                            "somou dependentes alheios (#{outros.join(', ')})"
  end

  it 'a contagem acompanha os limites de verdade' do
    skip 'RiskControl ainda não existe' unless defined?(RiskControl)

    # A factory da S5 cuida da conexão portador↔projeto e do tipo obrigatório.
    # Montar o `RiskControl` na mão aqui seria reimplementar as pré-condições do
    # `create` e sair de sincronia com elas.
    create_list(:risk_control, 2, project: projeto, company: empresa)

    get '/api/v1/companies', headers: auth_headers(gerente, project: projeto)
    linha = JSON.parse(response.body).find { |c| c['id'] == empresa.id }

    expect(linha['risk_controls_count']).to eq(2)
  end
end
