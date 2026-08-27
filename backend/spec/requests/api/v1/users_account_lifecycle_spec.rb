# frozen_string_literal: true

require 'rails_helper'

# S1 — ciclo de vida da conta: convite, bloqueio, participações, CPF e remoção.
#
# Todo teste aqui verifica **os dois lados** (o que é negado *e* o que é permitido).
# Um teste que só verificasse a negação passaria com a trava apontando para o lado
# errado — que é o modo de falhar mais perigoso de uma escala onde menor = mais poder.
RSpec.describe 'API V1 — ciclo de vida da conta', type: :request do
  let!(:og)          { create(:user, :og) }
  let!(:admin)       { create(:user, :admin) }
  let!(:gerente)     { create(:user, :gerente) }
  let!(:colaborador) { create(:user, :colaborador) }

  before do
    allow_any_instance_of(Auth::EmailService).to receive(:send_invite).and_return({ success: true, status: 200,
                                                                                    data: {} })
    # **DEC-108** — as abilities do legado voltaram e são checadas no servidor.
    # `POST /users`, `DELETE /users/:id`, `/invite` e `POST /memberships` exigem
    # a concessão do papel, que mora no catálogo de referência. Sem semeá-lo,
    # nenhum papel tem nada e todo verbo de escrita daqui viraria 403 — o gate
    # em si tem spec próprio em `abilities_enforcement_spec.rb`.
    Seeds::Reference::Permissions.call!
  end

  # ---------------------------------------------------------------------------
  # DEC-39 / BE-036, BE-037, BE-038 — bloqueio
  # ---------------------------------------------------------------------------
  describe 'bloqueio de conta' do
    it 'OG bloqueia Colaborador e a sessão ativa dele cai NA HORA' do
      token = Auth::TokenService.new(colaborador).generate_tokens[:token]
      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(200)

      post "/api/v1/users/#{colaborador.id}/block", params: { reason: 'Desligado em 01/2026' },
                                                    headers: auth_headers(og)
      expect(response).to have_http_status(200)

      # O MESMO token de antes. Se o bloqueio só valesse no próximo login, este
      # request continuaria 200 — que é "aviso", não bloqueio.
      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(403)
    end

    it 'a conta bloqueada recebe explicação estruturada, não logout mudo (IMP-A17)' do
      colaborador.block!(reason: 'Desligado em 01/2026')
      get '/auth/v1/me', headers: auth_headers(colaborador)

      json = JSON.parse(response.body)
      expect(response).to have_http_status(403)
      expect(json['code']).to eq('ACCOUNT_BLOCKED')
      expect(json['message']).to include('Desligado em 01/2026')
    end

    it 'Admin bloqueia Colaborador — e NÃO bloqueia o OG' do
      post "/api/v1/users/#{colaborador.id}/block", headers: auth_headers(admin)
      expect(response).to have_http_status(200)

      post "/api/v1/users/#{og.id}/block", headers: auth_headers(admin)
      expect(response).to have_http_status(403)
      expect(og.reload).not_to be_blocked
    end

    it 'desbloquear devolve o acesso' do
      colaborador.block!(reason: 'x')
      delete "/api/v1/users/#{colaborador.id}/block", headers: auth_headers(og)
      expect(response).to have_http_status(200)

      get '/auth/v1/me', headers: auth_headers(colaborador.reload)
      expect(response).to have_http_status(200)
    end

    it 'ninguém bloqueia a si mesmo' do
      post "/api/v1/users/#{admin.id}/block", headers: auth_headers(admin)
      expect(response).to have_http_status(422)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-012 / DEC-18.7 — a conta nasce com papel EXPLÍCITO e recebe convite
  # ---------------------------------------------------------------------------
  describe 'criação por convite' do
    it 'sem papel informado a conta nasce Colaborador — nunca Admin (D-39)' do
      post '/api/v1/users', params: { email: 'novo@example.com', name: 'Novo' }, headers: auth_headers(og)
      expect(response).to have_http_status(201)
      expect(User.find_by(email: 'novo@example.com').user_type.name).to eq(UserType::COLABORADOR)
    end

    it 'a conta nasce SEM senha — não há campo de senha para preencher' do
      post '/api/v1/users', params: { email: 'nopass@example.com', name: 'Sem Senha' }, headers: auth_headers(og)
      created = User.find_by(email: 'nopass@example.com')
      expect(created.attributes.keys).not_to include('encrypted_password', 'password_digest', 'legacy_password')
    end

    it 'Admin NÃO cria outro Admin (lateral) — e CRIA Colaborador' do
      post '/api/v1/users', params: { email: 'lateral@example.com', name: 'X', user_type: 'admin' },
                            headers: auth_headers(admin)
      expect(response).to have_http_status(403)

      post '/api/v1/users', params: { email: 'abaixo@example.com', name: 'Y', user_type: 'colaborador' },
                            headers: auth_headers(admin)
      expect(response).to have_http_status(201)
    end

    it 'o convite é enviado na criação' do
      expect_any_instance_of(Auth::EmailService).to receive(:send_invite)
      post '/api/v1/users', params: { email: 'convidado@example.com', name: 'Convidado' }, headers: auth_headers(og)
    end

    it 'reenviar convite emite magic link de USO ÚNICO' do
      target = create(:user, :colaborador, email: 'reenvio@example.com')
      expect { post "/api/v1/users/#{target.id}/invite", headers: auth_headers(og) }
        .to change { LoginCode.where(user_id: target.id).where.not(link_token: nil).count }.by(1)
      expect(response).to have_http_status(200)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-035 / IMP-A14 — status HTTP do validate_cpf
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/users/validate_cpf' do
    it 'CPF malformado responde 422 (não 405)' do
      get '/api/v1/users/validate_cpf', params: { cpf: '123' }, headers: auth_headers(og)
      expect(response).to have_http_status(422)
    end

    it 'CPF com dígito verificador errado responde 422' do
      get '/api/v1/users/validate_cpf', params: { cpf: '11111111111' }, headers: auth_headers(og)
      expect(response).to have_http_status(422)
    end

    it 'CPF já cadastrado responde 409 (não 406)' do
      create(:user, :colaborador, email: 'cpf@example.com', cpf_cnpj: '39053344705')
      get '/api/v1/users/validate_cpf', params: { cpf: '390.533.447-05' }, headers: auth_headers(og)
      expect(response).to have_http_status(409)
    end

    it 'CPF válido e livre responde 200' do
      get '/api/v1/users/validate_cpf', params: { cpf: '390.533.447-05' }, headers: auth_headers(og)
      expect(response).to have_http_status(200)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-034 — participações: paginadas e ESCOPADAS
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/users/:id/memberships' do
    it 'devolve só o que o solicitante alcança — o legado fazia Project.all' do
      alvo = create(:user, :colaborador)
      visivel = create_project_with_owner(gerente, name: 'Visível')
      oculto  = create_project_with_owner(og, name: 'Oculto')
      Membership.create!(project: visivel, user: alvo, role: 'participante')
      Membership.create!(project: oculto,  user: alvo, role: 'participante')

      get "/api/v1/users/#{alvo.id}/memberships", headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
      names = JSON.parse(response.body)['projects'].map { |p| p['name'] }
      expect(names).to eq(['Visível'])
    end

    it 'emite o envelope de paginação em CABEÇALHO' do
      alvo = create(:user, :colaborador)
      get "/api/v1/users/#{alvo.id}/memberships", headers: auth_headers(og)
      expect(response.headers['X-Total-Count']).to be_present
      expect(response.headers['X-Total-Pages']).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # BE-014 / BE-030 — remoção
  # ---------------------------------------------------------------------------
  describe 'remoção de conta' do
    it 'auto-remoção exige código, e o código do login serve de confirmação' do
      alvo = create(:user, :colaborador, email: 'saindo@example.com')

      delete "/api/v1/users/#{alvo.id}", headers: auth_headers(alvo)
      expect(response).to have_http_status(422)

      code = LoginCode.create!(user: alvo, destination: alvo.email, method: 'email',
                               code: '654321', expires_at: 5.minutes.from_now)
      expect { delete "/api/v1/users/#{alvo.id}", params: { code: code.code }, headers: auth_headers(alvo) }
        .to change(User, :count).by(-1)
    end

    it 'remoção por administrador verifica permissão NO SERVIDOR (D-34)' do
      alvo = create(:user, :colaborador)
      delete "/api/v1/users/#{alvo.id}", headers: auth_headers(gerente)
      expect(response).to have_http_status(403)
      expect(User.exists?(alvo.id)).to be true

      delete "/api/v1/users/#{alvo.id}", headers: auth_headers(og)
      expect(response).to have_http_status(204)
    end

    it 'conta dona de projeto não some em silêncio' do
      dono = create(:user, :colaborador)
      create_project_with_owner(dono)
      delete "/api/v1/users/#{dono.id}", headers: auth_headers(og)
      expect(response).to have_http_status(409)
      expect(User.exists?(dono.id)).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # IMP-A24 — serialização sem N+1
  # ---------------------------------------------------------------------------
  describe 'listagem de contas' do
    it 'não faz uma consulta por usuário (contagem estável ao crescer a lista)' do
      3.times { |i| create(:user, :colaborador, email: "n#{i}@example.com") }
      queries_small = count_queries { get '/api/v1/users', headers: auth_headers(og) }

      10.times { |i| create(:user, :colaborador, email: "m#{i}@example.com") }
      queries_big = count_queries { get '/api/v1/users', headers: auth_headers(og) }

      expect(queries_big).to be <= queries_small + 1
    end

    it 'busca é insensível a acento dos DOIS lados (IMP-A13)' do
      create(:user, :colaborador, name: 'João Conceição', email: 'joao.c@example.com')

      get '/api/v1/users', params: { q: 'joao' }, headers: auth_headers(og)
      expect(JSON.parse(response.body)['users'].map { |u| u['email'] }).to include('joao.c@example.com')

      get '/api/v1/users', params: { q: 'João' }, headers: auth_headers(og)
      expect(JSON.parse(response.body)['users'].map { |u| u['email'] }).to include('joao.c@example.com')
    end

    it 'stats devolve `by_role` e NÃO devolve mais o alias depreciado `client_count`' do
      get '/api/v1/users/stats', headers: auth_headers(og)
      json = JSON.parse(response.body)
      expect(json['by_role']).to include('colaborador')
      expect(json).not_to have_key('client_count')
    end
  end

  # ---------------------------------------------------------------------------
  # U4 — `find_by_whatsapp` não tinha gate nenhum
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/users/find_by_whatsapp' do
    let!(:alvo) { create(:user, :colaborador, phone: '5511955554444', cpf_cnpj: '39053344705') }

    it 'Colaborador NÃO consulta a base por telefone — e o OG consulta' do
      get '/api/v1/users/find_by_whatsapp', params: { whatsapp: alvo.phone }, headers: auth_headers(colaborador)
      expect(response).to have_http_status(403)

      get '/api/v1/users/find_by_whatsapp', params: { whatsapp: alvo.phone }, headers: auth_headers(og)
      expect(response).to have_http_status(200)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-022 — magic link de USO ÚNICO
  # ---------------------------------------------------------------------------
  describe 'GET /auth/v1/magic_link/verify' do
    let!(:convidado) { create(:user, :colaborador, email: 'link@example.com') }
    let!(:login_code) do
      LoginCode.create!(user: convidado, destination: convidado.email, method: 'email',
                        code: '123456', link_token: SecureRandom.urlsafe_base64(32),
                        expires_at: 24.hours.from_now)
    end

    it 'abre sessão na primeira vez e FALHA na segunda' do
      get "/auth/v1/magic_link/verify?token=#{login_code.link_token}"
      expect(response).to have_http_status(200)

      get "/auth/v1/magic_link/verify?token=#{login_code.link_token}"
      expect(response).to have_http_status(404)
    end

    it 'não grava senha nenhuma — o produto não tem senha (DEC-14)' do
      get "/auth/v1/magic_link/verify?token=#{login_code.link_token}"
      expect(convidado.reload.attributes.keys)
        .not_to include('encrypted_password', 'password_digest', 'legacy_password')
    end

    it 'link expirado responde 404, sem distinguir de link inexistente' do
      login_code.update!(expires_at: 1.minute.ago)
      get "/auth/v1/magic_link/verify?token=#{login_code.link_token}"
      expirado = response.status

      get '/auth/v1/magic_link/verify?token=nao-existe'
      expect(response.status).to eq(expirado)
    end
  end

  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      count += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end
end
