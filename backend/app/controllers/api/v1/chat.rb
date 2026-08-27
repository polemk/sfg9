module Api
  module V1
    class Chat < Grape::API


      prefix "chat"
      format :json

      helpers Api::V1::ControllerHelpers

      # Bloco 8 do trim (AI9-007, DEC-13.2) — O ASSISTENTE PASSA A EXIGIR LOGIN.
      #
      # Até aqui `/chat/*` (e `/api/v1/chat/*`) estava na allowlist pública do
      # `Api::Root` — as duas entradas saíram do `root.rb` neste bloco. Era
      # herança do chat público de CAPTAÇÃO, que morreu com o AI9-006 no Bloco 6.
      # O DEC-13.2 define o que ficou como assistente do usuário INTERNO, dentro
      # do console: widget de console não é widget de site.
      #
      # O `Api::Root#before` já responde 401 sem token. Este `authenticate_user!`
      # é cinto e suspensório — e é ele que popula `current_user` para o escopo
      # de dono abaixo.
      before { authenticate_user! }

      # Sessão de outro dono cai em `find_by -> nil -> 404`. Este `rescue_from`
      # cobre o resto (`ChatFlow.find`), que sem ele virava 500 no
      # `rescue_from :all` do `Api::Root`.
      rescue_from ActiveRecord::RecordNotFound do |_e|
        error!({ error: 'not_found', message: 'Não encontrado' }, 404)
      end

      helpers do
        # Toda leitura de sessão passa por aqui. NUNCA
        # `ChatSession.find(params[:session_id])`: `session_id` é inteiro
        # sequencial vindo do parâmetro e, entre os Blocos 6 e 8, a sessão não
        # tinha dono — trocar o número lia e continuava a conversa de outra
        # pessoa (IDOR). Sessão de outro (ou órfã, anterior ao `user_id`)
        # responde 404, nunca 200.
        def sessao_do_dono!(session_id)
          session = current_user.chat_sessions.find_by(id: session_id)
          error!({ error: 'not_found', message: 'Sessão não encontrada' }, 404) unless session
          session
        end

        # Os nós de auto-login do fluxo (Ai::Nodes::Redirect com `auto_auth`)
        # montam `auth: { token, refresh_token, ... }` dentro do payload. O
        # endpoint deixou de ser público neste bloco, mas o refresh no corpo
        # continua indo parar em log de proxy e continua legível por XSS — o
        # tratamento abaixo permanece por isso.
        # É o mesmo vazamento que o rollout fechou no /auth/v1, sobrevivendo aqui.
        #
        # Além do vazamento havia o outro lado: como este caminho não passa pelo
        # process_auth_response, nenhum cookie era emitido. Quem entrava pelo
        # chat ficava com um access em memória e nada para renová-lo — a sessão
        # morria no primeiro reload.
        #
        # Aqui os dois cookies são emitidos com os mesmos atributos do fluxo
        # /auth/v1, e o refresh sai do corpo. O resto do nó de auth continua
        # (o widget precisa do access e do nome para seguir).
        def secure_auth_nodes!(responses)
          Array(responses).each do |resp|
            next unless resp.is_a?(Hash)

            auth = resp[:auth] || resp['auth']
            next unless auth.is_a?(Hash)

            refresh = auth[:refresh_token] || auth['refresh_token']
            next if refresh.blank?

            cookies['refresh_token'] = {
              value: refresh,
              path: '/auth/v1',
              httponly: true,
              secure: Rails.env.production?,
              same_site: :lax,
              expires: ::Auth::TokenService::REFRESH_TTL.from_now
            }
            # Cookie do handshake do Action Cable — mesmo usuário do refresh
            sub = begin
              ::Auth::TokenService.new(nil).decode_token(refresh, verify_exp: false)['sub']
            rescue StandardError
              nil
            end
            if sub.present?
              cookies['cable_token'] = {
                value: ::Auth::TokenService.new(nil).cable_token_for(sub),
                path: '/cable',
                httponly: true,
                secure: Rails.env.production?,
                same_site: :lax,
                expires: ::Auth::TokenService::CABLE_TTL.from_now
              }
            end
            auth.delete(:refresh_token)
            auth.delete('refresh_token')
          end
          responses
        end
      end

      resource :session do
        desc "Start or retrieve a chat session"
        params do
          optional :flow_id, type: String, desc: "Flow ID to use"
          optional :is_test, type: Boolean, default: false, desc: "Mark session as test (skips FlowMatcher)"
        end
        get do
          # 1. Find Flow (specific or default)
          if params[:flow_id].present?
            target_flow = ChatFlow.find(params[:flow_id])
          else
            target_flow = ChatFlow.find_by(is_default: true) || ChatFlow.first
          end
          error!('No Chat Flow defined', 404) unless target_flow
          
          # 2. Create session
          #
          # Bloco 6 do trim (AI9-006): a reutilização de sessão era indexada pelo
          # LEAD (`ChatSession.where(lead: lead)`). Sem lead não há por onde
          # reconhecer quem voltou — `where(lead: nil)` casaria com QUALQUER
          # sessão órfã e entregaria a conversa de um estranho.
          #
          # Bloco 8: a sessão nasce COM DONO (`current_user`). Continua sendo
          # sempre uma sessão nova — retomar conversa depois de fechar a aba foi
          # conscientemente abandonado no DEC-20, junto com a trilha auditável.
          # O dono aqui existe para ISOLAR, não para retomar.
          session = if params[:is_test]
                      current_user.chat_sessions.create!(chat_flow: target_flow, context: { is_test: true })
                    else
                      current_user.chat_sessions.create!(chat_flow: target_flow)
                    end

          # Merge context from metadata into session
          if params[:metadata].present?
            begin
              metadata_hash = params[:metadata].is_a?(String) ? JSON.parse(params[:metadata]) : params[:metadata]
              session.update(context: (session.context || {}).merge(metadata_hash))
            rescue StandardError
              nil
            end
          end
          
          # 3. Process Engine (Init) — route by flow kind
          if target_flow.ai_agent?
            # AI Agent: return a welcome message (no node processing)
            msg = target_flow.agent_config&.dig('welcome_message').presence || 'Olá! Como posso ajudar?'
            responses = [{ id: SecureRandom.uuid, type: 'text', content: msg }]
          else
            engine = Ai::FlowEngine.new(session)
            responses = engine.process!
          end
          
          {
            session_id: session.id,
            responses: secure_auth_nodes!(responses),
            persona_name: session.chat_flow.persona_name,
            persona_description: session.chat_flow.persona_description,
            persona_avatar: session.chat_flow.persona_avatar
          }
        end
      end

      resource :input do
        desc "Send input to the chat session"
        params do
          requires :session_id, type: Integer, desc: "Session ID"
          requires :input, type: String, desc: "User input"
          optional :origin_node_id, type: String, desc: "Node ID for temporal jump"
        end
        post do
          session = sessao_do_dono!(params[:session_id])
          input_text = params[:input]

          # 1. Check for Global Triggers (skip if processing a test session)
          triggered_flow = nil
          unless session.test?
            if session.chat_flow.ai_agent?
              # If we are talking to a free-text AI Agent, DO NOT use semantic flow matching
              # because regular conversational inputs will randomly trigger other flows.
              # Only allow strict keyword matching to switch flows.
              triggered_flow = Ai::FlowMatcher.match_by_keyword(input_text)
            else
              triggered_flow = Ai::FlowMatcher.match(input_text)
            end
          end
          
          if triggered_flow && triggered_flow.id != session.chat_flow_id
            session.update!(chat_flow: triggered_flow, current_step_id: nil)
            
            # If the NEW flow is an AI Agent, return its welcome message instead of passing the trigger phrase to the LLM
            if triggered_flow.ai_agent?
              msg = triggered_flow.agent_config&.dig('welcome_message').presence || 'Olá! Como posso ajudar?'
              return { 
                session_id: session.id, 
                responses: [{ id: SecureRandom.uuid, type: 'text', content: msg }],
                persona_name: triggered_flow.persona_name,
                persona_description: triggered_flow.persona_description,
                persona_avatar: triggered_flow.persona_avatar
              }
            end
          end

          # 2. Route by flow kind
          if session.chat_flow.ai_agent?
            # AI Agent path: call provider API via AgentService
            responses = Ai::AgentService.respond(session, input_text, context: params[:context])
          else
            # Chatbot path: walk through flow nodes via FlowEngine
            engine = Ai::FlowEngine.new(session, input_text, origin_node_id: params[:origin_node_id])
            responses = engine.process!
          end
          
          { 
            session_id: session.id, 
            responses: secure_auth_nodes!(responses),
            persona_name: session.chat_flow.persona_name,
            persona_description: session.chat_flow.persona_description,
            persona_avatar: session.chat_flow.persona_avatar
          }
        end
      end
      resource :upload do
        desc "Upload an image and get AI response" do
          summary 'Send image for AI Vision processing'
          detail 'Accepts multipart/form-data with an image file. The image is base64-encoded and sent to the AI provider for Vision analysis.'
        end
        params do
          requires :session_id, type: Integer, desc: "Session ID"
          requires :file, type: File, desc: "Image file (JPEG, PNG, or WebP, max 5MB)"
          optional :caption, type: String, desc: "Optional text caption for the image"
        end
        post do
          # Bloco 8 do trim: a checagem de DONO vem antes das validações de
          # arquivo. Na ordem anterior (MIME e tamanho primeiro) um `session_id`
          # alheio com um arquivo inválido respondia **422**, não 404 — e 422 diz
          # "sua imagem não presta", o que confirma que a sessão existe. Quem não
          # é dono não pode distinguir sessão inexistente de sessão de terceiro.
          session = sessao_do_dono!(params[:session_id])

          # Validate MIME type
          allowed_mimes = %w[image/jpeg image/png image/webp].freeze
          file_data = params[:file]
          content_type = file_data[:type]

          unless allowed_mimes.include?(content_type)
            error!({ errors: [{ code: 'invalid_mime', message: "Tipo de arquivo não suportado. Use JPEG, PNG ou WebP." }] }, 422)
          end

          # Validate file size (5MB max)
          max_size = 5 * 1024 * 1024
          file_content = File.read(file_data[:tempfile].path, mode: 'rb')
          if file_content.bytesize > max_size
            error!({ errors: [{ code: 'file_too_large', message: "Arquivo excede o limite de 5MB." }] }, 422)
          end

          # Only AI Agent flows support vision
          unless session.chat_flow.ai_agent?
            error!({ errors: [{ code: 'unsupported', message: "Upload de imagem disponível apenas para agentes IA." }] }, 422)
          end

          # Base64-encode the image
          base64_data = Base64.strict_encode64(file_content)
          image_data = { base64: base64_data, mime_type: content_type }

          caption = params[:caption].presence || ''

          # Route through AgentService with image data
          context = params[:context]
          if context.is_a?(String)
            begin
              context = JSON.parse(context)
            rescue StandardError
              nil
            end
          end

          responses = Ai::AgentService.respond(session, caption, image_data: image_data, context: context)

          {
            session_id: session.id,
            responses: secure_auth_nodes!(responses),
            persona_name: session.chat_flow.persona_name,
            persona_description: session.chat_flow.persona_description,
            persona_avatar: session.chat_flow.persona_avatar
          }
        end
      end
    end
  end
end
