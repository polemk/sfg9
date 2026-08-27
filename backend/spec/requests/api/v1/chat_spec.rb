require 'rails_helper'

RSpec.describe 'Api::V1::Chat', type: :request do
  let!(:flow) { create(:chat_flow, :onboarding, is_default: true) }

  # Bloco 8 do trim (AI9-007, DEC-13.2): o assistente EXIGE login. Até aqui
  # `/chat/*` estava na allowlist pública do `Api::Root` — herança do chat de
  # captação (AI9-006), removido no Bloco 6. Todo exemplo abaixo manda token.
  let!(:user) { create(:user) }
  let(:token) { Auth::TokenService.new(user).generate_tokens[:token] }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  describe 'GET /chat/session' do
    context 'with new session' do
      it 'creates a session and returns session info' do
        get '/chat/session', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        # The API should return some form of session identifier
        expect(json).to have_key('session_id').or have_key('id')
      end

      it 'grava o dono da sessão — sem dono não há isolamento' do
        get '/chat/session', headers: headers

        session = ChatSession.find(JSON.parse(response.body)['session_id'])
        expect(session.user_id).to eq(user.id)
      end
    end

    # Bloco 6 do trim (AI9-006): saíram daqui os describes de `GET /chat/messages`
    # e `POST /chat/message` (endpoints do chat público de captação, removidos com
    # o `Lead`) e o caso "reusa a sessão do lead" — sem lead não há por onde
    # reconhecer quem voltou. Bloco 8: a sessão volta a ter dono (o `User`), mas
    # continua sempre nova — o DEC-20 abriu mão da retomada de propósito.
  end

  # ---------------------------------------------------------------------------
  # O portão do Bloco 8: assistente de console é por usuário.
  #
  # `session_id` é inteiro sequencial vindo do parâmetro. Entre os Blocos 6 e 8
  # `chat_sessions` não tinha dono nenhum e o endpoint era público: trocar o
  # número lia e continuava a conversa de outra pessoa.
  # ---------------------------------------------------------------------------
  describe 'isolamento por usuário' do
    let!(:outro) { create(:user) }
    let(:token_do_outro) { Auth::TokenService.new(outro).generate_tokens[:token] }

    it 'responde 401 sem token' do
      get '/chat/session'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'responde 401 sem token também em POST /chat/input' do
      post '/chat/input', params: { session_id: 1, input: 'oi' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'não deixa outro usuário continuar a conversa (404, nunca 200)' do
      get '/chat/session', headers: headers
      session_id = JSON.parse(response.body)['session_id']

      post '/chat/input',
           params: { session_id: session_id, input: 'e a conversa do outro?' },
           headers: { 'Authorization' => "Bearer #{token_do_outro}" }

      expect(response).to have_http_status(:not_found)
    end

    it 'não deixa outro usuário mandar imagem para a sessão alheia' do
      get '/chat/session', headers: headers
      session_id = JSON.parse(response.body)['session_id']

      post '/chat/upload',
           params: {
             session_id: session_id,
             file: Rack::Test::UploadedFile.new(StringIO.new('x'), 'image/png', original_filename: 'a.png')
           },
           headers: { 'Authorization' => "Bearer #{token_do_outro}" }

      expect(response).to have_http_status(:not_found)
    end

    it 'sessão órfã (anterior ao dono) é inalcançável' do
      orfa = create(:chat_session, chat_flow: flow)
      expect(orfa.user_id).to be_nil

      post '/chat/input', params: { session_id: orfa.id, input: 'oi' }, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # Os nós de auto-login do fluxo (Ai::Nodes::Redirect com `auto_auth`) carregam
  # credenciais no payload. Antes desta correção o refresh_token saía inteiro no
  # corpo — e nenhum cookie era emitido, então a sessão criada pelo chat não
  # sobrevivia a um reload. O endpoint deixou de ser público no Bloco 8, mas o
  # corpo continua indo para log de proxy: o tratamento permanece.
  describe 'nós de auto-login do fluxo (secure_auth_nodes!)' do
    let(:tokens) { Auth::TokenService.new(user).generate_tokens }

    def responder_com_no_de_auth
      allow_any_instance_of(Ai::FlowEngine).to receive(:process!).and_return(
        [{
          id: SecureRandom.uuid,
          type: 'redirect',
          action: 'navigate',
          url: '/dashboard',
          auth: {
            token: tokens[:token],
            refresh_token: tokens[:refresh_token],
            user_name: 'Visitante',
            user_email: 'visitante@ai9.dev'
          }
        }]
      )
    end

    it 'não devolve o refresh_token no corpo e o manda para cookie HttpOnly' do
      responder_com_no_de_auth
      get '/chat/session', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(tokens[:refresh_token])

      set_cookie = response.headers['Set-Cookie'].to_s
      expect(set_cookie).to include('refresh_token=')
      expect(set_cookie.downcase).to include('httponly')
      expect(set_cookie).to include('path=/auth/v1')
    end

    it 'emite também o cookie do cable, para o WebSocket subir' do
      responder_com_no_de_auth
      get '/chat/session', headers: headers

      set_cookie = response.headers['Set-Cookie'].to_s
      expect(set_cookie).to include('cable_token=')
      expect(set_cookie).to include('path=/cable')
      # cable_token nunca no corpo
      expect(JSON.parse(response.body).to_s).not_to include('cable_token')
    end

    it 'preserva o resto do nó de auth — o widget ainda precisa do access' do
      responder_com_no_de_auth
      get '/chat/session', headers: headers

      auth = JSON.parse(response.body)['responses'].first['auth']
      expect(auth['token']).to eq(tokens[:token])
      expect(auth['user_name']).to eq('Visitante')
      expect(auth).not_to have_key('refresh_token')
    end

    it 'não emite cookie nenhum quando o fluxo não tem nó de auth' do
      allow_any_instance_of(Ai::FlowEngine).to receive(:process!).and_return(
        [{ id: SecureRandom.uuid, type: 'text', content: 'Olá' }]
      )
      get '/chat/session', headers: headers

      set_cookie = response.headers['Set-Cookie'].to_s
      expect(set_cookie).not_to include('refresh_token=')
      expect(set_cookie).not_to include('cable_token=')
    end
  end

  # ---------------------------------------------------------------------------
  # O CONTEXTO DE AMBIENTE CHEGA AO AGENTE (DEC-13.2).
  #
  # É por este fio que o assistente sabe em que tela a pessoa está e qual projeto
  # ela selecionou — e é por ele que a conversa deixa de começar com "em que tela
  # você está?". O `context` do corpo **não é parâmetro declarado** no endpoint;
  # se um dia a configuração do Grape passar a descartar o que não foi declarado,
  # nada quebra visivelmente: o agente volta a perguntar, e ninguém liga uma
  # coisa à outra. Por isso o fio tem spec próprio.
  # ---------------------------------------------------------------------------
  describe 'contexto de ambiente no POST /chat/input' do
    let!(:agente) do
      create(:chat_flow,
             name: 'assistente-de-teste',
             kind: :ai_agent,
             agent_config: { 'model' => 'claude-opus-5', 'system_prompt' => 'Você ajuda.' })
    end
    let!(:sessao) { ChatSession.create!(chat_flow: agente, user: user) }

    it 'repassa tela, projeto e menu para o AgentService' do
      recebido = nil
      allow(Ai::AgentService).to receive(:respond) do |_sessao, _entrada, **kwargs|
        recebido = kwargs[:context]
        [{ id: SecureRandom.uuid, type: 'text', content: 'ok' }]
      end

      post '/chat/input',
           params: {
             session_id: sessao.id,
             input: 'o que é este campo?',
             context: { current_page: '/risk-controls', tela_atual: 'Limites', projeto_selecionado: 'Carteira A' }
           },
           headers: headers

      # 201: é o default do Grape para POST, e o widget não distingue.
      expect(response).to have_http_status(:created)
      expect(recebido).to be_present
      expect(recebido['tela_atual']).to eq('Limites')
      expect(recebido['projeto_selecionado']).to eq('Carteira A')
    end
  end
end
