# frozen_string_literal: true

require 'rails_helper'

# Contrato **C1** — escopo por projeto, aplicado NO ENDPOINT.
#
# Os exemplos usam `/api/v1/memberships`, que é o primeiro endpoint escopado da
# base. Cada regra é verificada nos **dois** lados: o que é negado e o que é
# permitido. Um teste que só verifique a negação passa com o escopo apontando
# para o projeto errado.
RSpec.describe 'Contrato C1 — escopo por projeto', type: :request do
  before do
    UserType.seed_default_types!
    # **DEC-108** — as abilities do legado voltaram e são checadas no servidor.
    # `POST /users`, `DELETE /users/:id`, `/invite` e `POST /memberships` exigem
    # a concessão do papel, que mora no catálogo de referência. Sem semeá-lo,
    # nenhum papel tem nada e todo verbo de escrita daqui viraria 403 — o gate
    # em si tem spec próprio em `abilities_enforcement_spec.rb`.
    Seeds::Reference::Permissions.call!
  end

  # DEC-99: OG e Admin enxergam TODOS os projetos, sem participação. Os casos de
  # escopo abaixo, portanto, são exercitados com **Gerente** — o papel mais alto
  # que continua preso à participação. Usar admin aqui faria os testes passarem
  # por motivo errado (ou falharem, como falharam quando a DEC-99 entrou).
  let(:admin) { create(:user, user_type: UserType.gerente) }
  let(:outro_admin) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  let!(:projeto_a) { create_project_with_owner(admin, slug: 'projeto-a', name: 'Projeto A') }
  let!(:projeto_b) { create_project_with_owner(outro_admin, slug: 'projeto-b', name: 'Projeto B') }

  # 5.2.1 — filtro por id de registro de OUTRO projeto devolve vazio/404, nunca
  # confirma a existência do registro alheio.
  describe 'id de outro projeto' do
    let!(:membro_a) { Membership.create!(project: projeto_a, user: colaborador, role: 'participante') }
    let!(:membro_b) { Membership.create!(project: projeto_b, user: colaborador, role: 'participante') }

    it 'a lista do projeto A NÃO traz a participação do projeto B — e TRAZ a do A' do
      get '/api/v1/memberships', headers: auth_headers(admin, project: projeto_a)

      expect(response).to have_http_status(200)
      ids = JSON.parse(response.body)['memberships'].map { |m| m['id'] }
      expect(ids).to include(membro_a.id)
      expect(ids).not_to include(membro_b.id)
    end

    it 'remover por id de OUTRO projeto responde 404 — e o id do próprio projeto funciona' do
      delete "/api/v1/memberships/#{membro_b.id}", headers: auth_headers(admin, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(Membership.exists?(membro_b.id)).to be(true)

      delete "/api/v1/memberships/#{membro_a.id}", headers: auth_headers(admin, project: projeto_a)
      expect(response).to have_http_status(204)
      expect(Membership.exists?(membro_a.id)).to be(false)
    end
  end

  # 5.2.2 — `project_id` do corpo é ignorado.
  describe 'project_id no corpo da requisição' do
    it 'é IGNORADO no create: a participação nasce no projeto CORRENTE' do
      post '/api/v1/memberships',
           params: { user_id: colaborador.id, project_id: projeto_b.id },
           headers: auth_headers(admin, project: projeto_a)

      expect(response).to have_http_status(201)
      membership = Membership.find(JSON.parse(response.body)['id'])
      expect(membership.project_id).to eq(projeto_a.id)
      expect(membership.project_id).not_to eq(projeto_b.id)
    end

    it 'é IGNORADO no delete: não alcança registro de outro projeto' do
      membro_b = Membership.create!(project: projeto_b, user: colaborador, role: 'participante')

      delete "/api/v1/memberships/#{membro_b.id}",
             params: { project_id: projeto_b.id },
             headers: auth_headers(admin, project: projeto_a)

      expect(response).to have_http_status(404)
      expect(Membership.exists?(membro_b.id)).to be(true)
    end
  end

  # 5.2.3 — condição 1 do DC-08.
  describe 'participação revogada' do
    it 'para de valer na requisição SEGUINTE, com o current_project_id ainda gravado' do
      admin.update!(current_project_id: projeto_a.id)

      get '/api/v1/memberships', headers: auth_headers(admin)
      expect(response).to have_http_status(200)

      # Revogação por fora (outro ator, outra sessão). Nada de logout.
      Membership.where(project: projeto_a, user: admin).delete_all
      expect(admin.reload.current_project_id).to eq(projeto_a.id)

      get '/api/v1/memberships', headers: auth_headers(admin)
      expect(response).to have_http_status(404)
    end
  end

  # 5.2.4 — condição 2 do DC-08: sem oráculo de existência de id.
  describe 'projeto inexistente x projeto sem participação' do
    it 'respondem o MESMO status' do
      inexistente = auth_headers(admin, project: projeto_a).merge('X-Project-Id' => '99999999')
      get '/api/v1/memberships', headers: inexistente
      status_inexistente = response.status

      sem_participacao = auth_headers(admin).merge('X-Project-Id' => projeto_b.id.to_s)
      get '/api/v1/memberships', headers: sem_participacao
      status_sem_participacao = response.status

      expect(status_inexistente).to eq(status_sem_participacao)
      expect(status_inexistente).to eq(404)
    end
  end

  # 5.2.5
  describe 'X-Project-Id' do
    before do
      Membership.create!(project: projeto_b, user: admin, role: 'participante')
      admin.update!(current_project_id: projeto_a.id)
    end

    it 'COM participação troca o escopo — SEM participação não troca' do
      alvo = create(:user, user_type: UserType.colaborador)

      # Com participação em B: o create cai em B.
      post '/api/v1/memberships', params: { user_id: alvo.id },
                                  headers: auth_headers(admin).merge('X-Project-Id' => projeto_b.id.to_s)
      expect(response).to have_http_status(201)
      expect(Membership.find(JSON.parse(response.body)['id']).project_id).to eq(projeto_b.id)

      # Sem participação num terceiro projeto: 404, e o escopo NÃO cai no
      # current_project_id como consolo.
      projeto_c = create_project_with_owner(outro_admin, slug: 'projeto-c')
      outro = create(:user, user_type: UserType.colaborador)
      post '/api/v1/memberships', params: { user_id: outro.id },
                                  headers: auth_headers(admin).merge('X-Project-Id' => projeto_c.id.to_s)
      expect(response).to have_http_status(404)
      expect(Membership.where(user: outro)).to be_empty
    end
  end

  # 5.2.6 — a prova de que não há `default_scope`.
  describe 'job que cruza projetos' do
    it 'funciona recebendo project_id explícito, sem sessão nem current_project!' do
      padrao = create(:user, user_type: UserType.colaborador)
      padrao.update!(is_default_member: true)

      # O job varreu TODOS os projetos ativos — impossível sob `default_scope`.
      expect(Membership.where(user: padrao).pluck(:project_id))
        .to contain_exactly(projeto_a.id, projeto_b.id)
    end
  end

  # 5.2.7 — DB-397: leitura não grava.
  describe 'leitura não grava o projeto corrente' do
    before { Membership.create!(project: projeto_b, user: admin, role: 'participante') }

    it 'nenhum GET escreve users.current_project_id' do
      admin.update!(current_project_id: projeto_a.id)

      get '/api/v1/memberships', headers: auth_headers(admin).merge('X-Project-Id' => projeto_b.id.to_s)
      expect(response).to have_http_status(200)

      # A requisição foi servida no escopo de B, e a preferência continua em A.
      expect(admin.reload.current_project_id).to eq(projeto_a.id)
    end
  end

  # 6.5 — conferência do contrato: ninguém pode ter criado um segundo mecanismo.
  describe 'nenhum model usa default_scope' do
    it 'a varredura de app/models volta vazia' do
      offenders = Dir[Rails.root.join('app/models/**/*.rb')].select do |file|
        File.read(file).match?(/^\s*default_scope\b/)
      end
      expect(offenders).to be_empty
    end
  end

  # DEC-99 — a exceção, verificada nos DOIS sentidos.
  describe 'OG e Admin (DEC-99)' do
    let(:og_user) { create(:user, user_type: UserType.og) }
    let(:admin_user) { create(:user, user_type: UserType.admin) }

    it 'entram em projeto SEM participação, e o Gerente no mesmo projeto NÃO entra' do
      # projeto_b não tem participação de ninguém abaixo.
      [og_user, admin_user].each do |u|
        get '/api/v1/memberships', headers: auth_headers(u).merge('X-Project-Id' => projeto_b.id.to_s)
        expect(response).to have_http_status(200), "#{u.user_type.name} deveria enxergar projeto sem participação"
      end

      gerente = create(:user, user_type: UserType.gerente)
      get '/api/v1/memberships', headers: auth_headers(gerente).merge('X-Project-Id' => projeto_b.id.to_s)
      expect(response).to have_http_status(404)
    end

    it 'projeto inexistente continua 404 até para OG — a exceção é de participação, não de existência' do
      get '/api/v1/memberships', headers: auth_headers(og_user).merge('X-Project-Id' => SecureRandom.uuid)
      expect(response).to have_http_status(404)
    end
  end
end

# ---------------------------------------------------------------------------
# Achado do usuário (26/08/2026): "se o projeto não estiver selecionado as
# lista bugam e mostram um erro genérico".
#
# Eram TRÊS situações caindo num 404 só. Estes casos travam a separação — e,
# principalmente, travam a metade que NÃO pode mudar: a anti-enumeração.
# ---------------------------------------------------------------------------
RSpec.describe 'C1 — projeto ausente x projeto inexistente', type: :request do
  before do
    UserType.seed_default_types!
    # **DEC-108** — as abilities do legado voltaram e são checadas no servidor.
    # `POST /users`, `DELETE /users/:id`, `/invite` e `POST /memberships` exigem
    # a concessão do papel, que mora no catálogo de referência. Sem semeá-lo,
    # nenhum papel tem nada e todo verbo de escrita daqui viraria 403 — o gate
    # em si tem spec próprio em `abilities_enforcement_spec.rb`.
    Seeds::Reference::Permissions.call!
  end

  let(:dono) { create(:user, :gerente) }
  def rota_escopada = '/api/v1/memberships'
  def corpo = JSON.parse(response.body)

  context 'quando o usuário participa de VÁRIOS projetos e não escolheu nenhum' do
    let!(:usuario) { create(:user, :gerente) }

    before do
      2.times { Membership.create!(user: usuario, project: create_project_with_owner(dono)) }
      usuario.update_column(:current_project_id, nil)
    end

    it 'responde 409 PROJECT_NOT_SELECTED, não 404' do
      get rota_escopada, headers: auth_headers(usuario)

      expect(response).to have_http_status(:conflict)
      expect(corpo['code']).to eq('PROJECT_NOT_SELECTED')
      # A mensagem diz o que fazer. "Projeto não encontrado" acusa o usuário de
      # um erro que ele não cometeu.
      expect(corpo['message']).to match(/escolha um projeto/i)
    end
  end

  context 'quando o usuário não participa de NENHUM projeto' do
    let!(:usuario) { create(:user, :colaborador) }

    it 'responde 409 PROJECT_NONE_AVAILABLE, mandando procurar um administrador' do
      get rota_escopada, headers: auth_headers(usuario)

      expect(response).to have_http_status(:conflict)
      expect(corpo['code']).to eq('PROJECT_NONE_AVAILABLE')
      expect(corpo['message']).to match(/administrador/i)
    end
  end

  context 'anti-enumeração — a metade que NÃO pode mudar' do
    let!(:usuario) { create(:user, :gerente) }
    let!(:meu) { create_project_with_owner(dono) }
    let!(:alheio) { create_project_with_owner(dono) }

    before { Membership.create!(user: usuario, project: meu) }

    it 'id de projeto ALHEIO e id INEXISTENTE devolvem a MESMA resposta' do
      get rota_escopada, headers: auth_headers(usuario).merge('X-Project-Id' => alheio.id.to_s)
      alheio_status = response.status
      alheio_corpo = corpo

      get rota_escopada, headers: auth_headers(usuario).merge('X-Project-Id' => SecureRandom.uuid)
      inexistente_status = response.status
      inexistente_corpo = corpo

      # Se isto divergir, o endpoint vira oráculo de existência de id: um
      # Colaborador enumera os projetos de todo mundo comparando respostas.
      expect(alheio_status).to eq(404)
      expect(inexistente_status).to eq(404)
      expect(alheio_corpo['code']).to eq('PROJECT_NOT_FOUND')
      expect(alheio_corpo).to eq(inexistente_corpo)
    end

    it 'id alheio NÃO cai no 409 de "não escolheu" — pedido explícito é 404' do
      get rota_escopada, headers: auth_headers(usuario).merge('X-Project-Id' => alheio.id.to_s)

      expect(response).to have_http_status(:not_found)
      expect(corpo['code']).not_to eq('PROJECT_NOT_SELECTED')
    end
  end
end
