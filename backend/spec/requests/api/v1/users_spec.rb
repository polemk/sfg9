require 'rails_helper'

RSpec.describe 'API V1 Users', type: :request do
  let!(:og_user) { create(:user, :og) }
  let!(:colaborador_user) { create(:user, :colaborador, phone: '5548999999999') }
  let(:og_token) { Auth::TokenService.new(og_user).generate_tokens[:token] }
  let(:colaborador_token) { Auth::TokenService.new(colaborador_user).generate_tokens[:token] }

  before do
    # **DEC-108** — as abilities do legado voltaram e são checadas no servidor.
    # `POST /users`, `DELETE /users/:id`, `/invite` e `POST /memberships` exigem
    # a concessão do papel, que mora no catálogo de referência. Sem semeá-lo,
    # nenhum papel tem nada e todo verbo de escrita daqui viraria 403 — o gate
    # em si tem spec próprio em `abilities_enforcement_spec.rb`.
    Seeds::Reference::Permissions.call!
  end

  describe 'GET /api/v1/users' do
    context 'as OG user' do
      it 'returns users list' do
        get '/api/v1/users', headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json['users']).to be_present
      end

      it 'filters by query' do
        get '/api/v1/users', params: { q: og_user.name }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        ids = JSON.parse(response.body)['users'].map { |u| u['id'] }
        expect(ids).to include(og_user.id)
      end
    end

    context 'as Colaborador user' do
      it 'returns forbidden' do
        get '/api/v1/users', headers: { 'Authorization' => "Bearer #{colaborador_token}" }
        expect(response).to have_http_status(403)
      end
    end

    context 'unauthenticated' do
      it 'returns forbidden/unauthorized' do
        get '/api/v1/users'
        expect(response).to have_http_status(403).or have_http_status(401)
      end
    end
  end

  describe 'GET /api/v1/users/:id' do
    context 'as OG user' do
      it 'returns user details' do
        get "/api/v1/users/#{colaborador_user.id}", headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)['id']).to eq(colaborador_user.id)
      end
    end
  end

  describe 'GET /api/v1/users/find_by_whatsapp' do
    context 'when user exists' do
      it 'returns success' do
        get '/api/v1/users/find_by_whatsapp', params: { whatsapp: colaborador_user.phone }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
      end
    end

    context 'when user does not exist' do
      it 'returns 404' do
        get '/api/v1/users/find_by_whatsapp', params: { whatsapp: '000000000' }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'POST /api/v1/users' do
    let(:new_user_params) { { email: 'new@example.com', name: 'New User' } }

    context 'as OG user' do
      it 'creates a user' do
        expect {
          post '/api/v1/users', params: new_user_params, headers: { 'Authorization' => "Bearer #{og_token}" }
        }.to change(User, :count).by(1)
        expect(response).to have_http_status(201)
      end
    end

    context 'as Colaborador user' do
      it 'returns forbidden' do
        post '/api/v1/users', params: new_user_params, headers: { 'Authorization' => "Bearer #{colaborador_token}" }
        expect(response).to have_http_status(403)
      end
    end
  end

  describe 'PUT /api/v1/users/:id' do
    context 'as OG user' do
      it 'updates user' do
        put "/api/v1/users/#{colaborador_user.id}", params: { name: 'Updated Name' }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(colaborador_user.reload.name).to eq('Updated Name')
      end

      it 'updates custom_variables' do
        put "/api/v1/users/#{colaborador_user.id}", params: { custom_variables: { 'score' => '10' } }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(colaborador_user.reload.custom_variables).to eq({ 'score' => '10' })
      end

      it 'updates custom_variables via PATCH' do
        patch "/api/v1/users/#{colaborador_user.id}", params: { custom_variables: { 'interest' => 'coding' } }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(colaborador_user.reload.custom_variables).to eq({ 'interest' => 'coding' })
      end
    end
  end

  describe 'DELETE /api/v1/users/:id' do
    context 'as OG user' do
      it 'deletes user' do
        expect {
          delete "/api/v1/users/#{colaborador_user.id}", headers: { 'Authorization' => "Bearer #{og_token}" }
        }.to change(User, :count).by(-1)
        expect(response).to have_http_status(204)
      end
    end
  end

  describe 'GET /api/v1/users/stats' do
    context 'as OG user' do
      it 'returns stats' do
        get '/api/v1/users/stats', headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
      end
    end
  end

  # ==========================================================================
  # FE-019 — "Membro padrão"
  # ==========================================================================
  #
  # A marca põe a pessoa em TODOS os projetos: nos que existem, pelo
  # `DefaultMemberJob`; nos que vierem, pelo `LinkDefaultMembersJob`. É a
  # permissão mais larga que o cadastro concede.
  #
  # Ela chegou à migração pela metade: o model já disparava o job e a listagem
  # já mostrava o selo, mas **o endpoint não aceitava o parâmetro** — o efeito
  # estava pronto e não havia como acioná-lo. No legado o campo existia no
  # formulário e era desenhado só para OG e Admin
  # (`users/helper/_body.html.erb:17`).
  describe 'is_default_member (FE-019)' do
    let!(:alvo) { create(:user, :colaborador, email: 'alvo-membro@exemplo.com') }

    # O matcher de ActiveJob exige o adaptador `:test`, e a suíte roda no
    # adaptador de verdade. Trocado só aqui, e devolvido depois.
    around do |exemplo|
      anterior = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      exemplo.run
      ActiveJob::Base.queue_adapter = anterior
    end

    it 'OG marca, e o job de vinculação é enfileirado' do
      expect do
        put "/api/v1/users/#{alvo.id}",
            params: { is_default_member: true },
            headers: { 'Authorization' => "Bearer #{og_token}" }
      end.to have_enqueued_job(DefaultMemberJob).with(alvo.id)

      expect(response).to have_http_status(200)
      expect(alvo.reload.is_default_member).to be(true)
    end

    it 'OG desmarca — `false` é um valor, não ausência' do
      alvo.update!(is_default_member: true)

      put "/api/v1/users/#{alvo.id}",
          params: { is_default_member: false },
          headers: { 'Authorization' => "Bearer #{og_token}" }

      expect(response).to have_http_status(200)
      expect(alvo.reload.is_default_member).to be(false)
    end

    # **Pela API, o portão de OG/Admin já é da matriz** — `users` é `CRUD CRUD R -`
    # (`authorization/matrix.rb:74`), então Gerente e Colaborador levam 403 antes
    # de o serviço ser chamado. Escrevi este exemplo com um Colaborador e ele
    # falhou por 403, não por ignorar o campo: o caminho não existe.
    #
    # O portão no serviço continua valendo a pena porque `UsersService` também é
    # chamado de console e de seed, onde não há matriz nenhuma. É lá que ele se
    # prova — e ele IGNORA o campo em vez de recusar, porque recusar viraria erro
    # um payload que no legado nem chegava a existir (o campo não era desenhado
    # para quem não podia).
    it 'fora da API, ator sem poder tem o campo ignorado — o resto passa' do
      gerente = create(:user, :gerente)

      resposta = UsersService.update(
        { id: alvo.id, name: 'Nome Novo', is_default_member: true }, actor: gerente
      )

      expect(resposta[:status]).to eq(200)
      expect(alvo.reload.is_default_member).to be(false)
      expect(alvo.name).to eq('Nome Novo')
    end

    it 'fora da API, um Admin muda' do
      admin = create(:user, :admin)

      UsersService.update({ id: alvo.id, is_default_member: true }, actor: admin)

      expect(alvo.reload.is_default_member).to be(true)
    end

    it 'na CRIAÇÃO também, e só para quem pode' do
      post '/api/v1/users',
           params: { email: 'nasce-marcado@exemplo.com', name: 'Nasce Marcado',
                     user_type: 'colaborador', is_default_member: true },
           headers: { 'Authorization' => "Bearer #{og_token}" }

      expect(response).to have_http_status(201)
      expect(User.find_by(email: 'nasce-marcado@exemplo.com').is_default_member).to be(true)
    end
  end

end
