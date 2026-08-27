# frozen_string_literal: true

require 'grape'
require_relative './v1/controller_helpers'
require 'grape-swagger'
require 'grape-swagger-entity'

module Api
  class Root < Grape::API
    format :json
    # Sem prefixo/version global; cada módulo define seu próprio prefixo e versão

    before do
      # ATENCAO: nao reintroduza um bypass por header aqui.
      # Ate 01/08/2026 este bloco honrava 'X-Skip-Auth: 1' e qualquer pessoa lia a base
      # inteira sem login. Endpoint publico entra na allowlist abaixo, sempre
      # por rota — nunca por cabecalho, que o cliente controla.

      # Ignora autenticação para webhooks, swagger e endpoints públicos de auth
      public_paths = [
        %r{^/swagger_doc},
        %r{^/api/v1/countries/?$},
        # **Só os webhooks que EXISTEM.** `messages-upsert`, `send-message` e
        # `messages-update` estavam aqui e foram removidos: o
        # `whats/v1/webhooks.rb` declara apenas os quatro abaixo. Enquanto a rota
        # nao existe, a entrada e inofensiva — 404 antes de qualquer coisa. O
        # problema e o dia em que alguem redeclarar um `resource` com esse nome:
        # ele nasce **sem autenticacao**, e ninguem vai procurar o motivo aqui.
        #
        # Ha spec cruzando esta lista contra os `resource` realmente declarados.
        #
        # **Só os RECEPTORES entram aqui.** Quem chama estes três é a Evolution,
        # que não tem sessão nossa para apresentar — por isso pulam o gate.
        #
        # `config` NÃO é receptor: é o painel que diz à Evolution para onde
        # mandar evento, e estava nesta lista até 26/08/2026. O efeito não era o
        # que se esperaria de uma rota "pública" — era o oposto, e era mudo.
        # Estando aqui, o `before` fazia `next` e **nunca preenchia
        # `@current_user`**; aí o próprio endpoint (`whats/v1/webhooks.rb:79`)
        # confere `@current_user&.og?`, achava `nil` e respondia **401 para todo
        # mundo, OG inclusive** — medido com token válido. Ou seja: o registro do
        # webhook era **impossível pelo app**, e por isso a instância `AI9_VINAO`
        # ficou com o placeholder `https://tst` e `events: []` do lado da
        # Evolution. Sem `CONNECTION_UPDATE` registrado, o pareamento acontecia e
        # a tela nunca ficava sabendo — o sintoma que o usuário relatou.
        #
        # Fora da lista, `config` autentica normalmente e o `og?` do endpoint
        # volta a ter o que conferir.
        %r{^/whats/v1/webhooks/qrcode-updated/?$},
        %r{^/whats/v1/webhooks/connection-update/?$},
        %r{^/whats/v1/webhooks/logout-instance/?$},
        %r{^/auth/v1/magic_login/request_code/?$},
        %r{^/auth/v1/magic_login/validate_code/?$},
        %r{^/auth/v1/code_validation/?$},
        %r{^/auth/v1/magic_login/can_resend/?$},
        %r{^/auth/v1/oauth/google_url/?$},
        %r{^/auth/v1/oauth/facebook_url/?$},
        %r{^/auth/v1/oauth/callback/?$},
        # DEC-49: `pre_register` e `complete_registration` SAÍRAM daqui e os
        # endpoints foram desmontados em `api/auth/v1/registration.rb`. Junto
        # com `visitor_signup` e `visitor_signup_with_link`, eram as 4 rotas de
        # AUTO-CADASTRO. Entrada no sistema é só por convite (DEC-18.7); rota
        # que não existe não reabre por engano de configuração, que é como o
        # D-39 voltaria sozinho.
        %r{^/auth/v1/verify_code/?$},
        %r{^/auth/v1/sessions/status/?$},
        # O refresh é chamado JUSTAMENTE quando o access token expirou, então
        # exigir auth aqui torna o refresh token inalcançável e prende a sessão
        # ao TTL do access. Auth::SessionsService#refresh valida o refresh por
        # conta própria (assinatura + claim type:'refresh') e não usa current_user.
        %r{^/auth/v1/sessions/refresh/?$},
        # DEC-49: `visitor_signup` e `visitor_signup_with_link` saíram — ver a
        # nota acima. O tipo `visitor` também não existe mais (DEC-41).
        %r{^/auth/v1/magic_link/verify/?$},
        # S12 / BE-330 — Termos de Uso e Política de Privacidade são leitura
        # pública por natureza: quem ainda não tem conta precisa ler antes de
        # aceitar. Só GET, e só o texto vigente — o console de publicação é
        # `/api/v1/contract_versions`, que exige sessão E papel (DEC-38).
        %r{^/api/v1/public/contracts(/.*)?$},
        %r{^/api/v1/public/chat(/.*)?$},
        # Bloco 8 do trim (AI9-007, DEC-13.2): `^/api/v1/chat(/.*)?$` e
        # `^/chat(/.*)?$` SAÍRAM desta allowlist. Eram herança do chat público de
        # captação (AI9-006, removido no Bloco 6): deixavam `/chat/session` e
        # `/chat/input` abertos a qualquer um, e como `chat_sessions` ficou sem
        # dono entre os Blocos 6 e 8, um `session_id` inteiro chutado no
        # parâmetro lia e continuava a conversa de outra pessoa.
        # O assistente do DEC-13.2 é do usuário INTERNO: exige token.
        # O que sobra público em `/api/v1/public/chat` é só o `routing`, que
        # devolve mapeamento de rota→agente e não toca em sessão.
        %r{^/api/v1/flows/contextual/?$},

        # status exige auth para gerar CSRF corretamente
      ]
      next if public_paths.any? { |regex| request.path =~ regex }

      # Centraliza autenticação: Warden/Devise JWT ou decoder próprio; fallback para ClientApplication
      user = nil
      user = env['warden'].authenticate if defined?(Warden) && env['warden']

      unless user
        auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
        error!({ error: 'unauthorized', message: 'Authorization header ausente' }, 401) if auth_header.blank?

        scheme, token = auth_header.split(' ')
        unless scheme == 'Bearer' && token.present?
          error!({ error: 'unauthorized', message: 'Formato do Authorization inválido' },
                 401)
        end

        begin
          payload = nil
          payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
          payload ||= Auth::TokenService.new(nil).decode_token(token, verify_exp: true)

          # **A revogação é conferida AQUI, fora dos dois decodificadores.**
          #
          # `Warden::JWTAuth::TokenDecoder` NÃO consulta a `jwt_denylist` — o
          # próprio `token_service.rb:63` já avisava isso por escrito. E ele está
          # sempre definido, então a linha acima vence SEMPRE, e o `||=` que
          # escolheria o `Auth::TokenService#decode_token` (o único dos dois que
          # checa revogação) nunca roda. Resultado medido (D-QA-02): «Sair»
          # gravava o `jti` na denylist, `Auth::TokenService.revoked?` respondia
          # `true`, e este gate seguia aceitando o MESMO access token até ele
          # expirar — até 15 min de sessão viva depois de a pessoa sair, num
          # computador compartilhado.
          #
          # A checagem mora nesta linha, e não dentro de um dos decodificadores,
          # porque assim ela vale para os DOIS caminhos — inclusive se amanhã a
          # ordem entre eles mudar de novo. É a mesma correção que
          # `ApplicationCable::Connection` já fazia para o WebSocket.
          #
          # Ela derruba só o que precisa derrubar: `revoked?` recebe o payload já
          # decodificado, devolve `false` quando o `jti` vem vazio (token sem
          # `jti` não é revogável) e `false` quando a consulta à denylist falha.
          # Ou seja, `payload` só vira `nil` quando o `jti` DAQUELE token está na
          # denylist — token recém-emitido nunca cai aqui, e é por isso que um
          # login novo continua funcionando.
          #
          # **`::Auth`, com os dois-pontos na frente.** Esta classe vive dentro de
          # `module Api`, e `Api::Auth` EXISTE — é o namespace de
          # `Api::Auth::V1::Sessions`. Escrito sem o `::`, o Ruby resolve
          # lexicamente, encontra `Api::Auth`, não encontra `TokenService` dentro
          # dele e levanta `NameError` — que o `rescue StandardError` cinco linhas
          # abaixo engole em silêncio, deixando `user = nil`. Numa linha que roda
          # em TODA requisição autenticada, isso é **401 para todo mundo, token
          # recém-emitido inclusive**: foi assim que o app caiu em 26/08/2026.
          #
          # É invisível na leitura porque a linha logo acima tem o mesmo
          # `Auth::TokenService` sem `::` e nunca deu problema — só que ela nunca
          # chega a rodar, já que o decodificador do Warden sempre preenche
          # `payload` antes. O `::` é o que mantém esta checagem no caminho quente
          # sem repetir o apagão.
          payload = nil if payload && ::Auth::TokenService.revoked?(payload)

          user = User.find_by(id: payload['sub']) if payload && payload['sub']
        rescue StandardError
          user = nil
        end

        unless user
          @current_client = ClientApplication.active.find_by(token: token)
          error!({ error: 'unauthorized', message: 'Token inválido' }, 401) unless @current_client
          env['api.current_client'] = @current_client
          next
        end
      end

      # --- Conta bloqueada (DEC-39 / BE-038, IMP-A17) ----------------------
      # Barrada **no gate central**, e não em cada endpoint: bloqueio que depende de
      # cada rota lembrar de checar é bloqueio que vaza pela rota nova.
      #
      # 403 com `code`, não 401 mudo. O 401 faz o interceptor do front tentar renovar a
      # sessão, falhar e deslogar sem dizer nada — a pessoa vê a tela de login de volta
      # e não sabe se errou o código, se caiu a rede ou se perdeu o acesso. Com o
      # `ACCOUNT_BLOCKED` a tela de login explica o motivo.
      if user.respond_to?(:blocked?) && user.blocked?
        error!({
                 error: 'account_blocked',
                 message: user.blocked_reason.presence ||
                          'Sua conta está bloqueada. Fale com o administrador do projeto.',
                 code: 'ACCOUNT_BLOCKED'
               }, 403)
      end

      @current_user = user
      env['api.current_user'] = @current_user

      # --- Trilha de auditoria (DEC-59) -----------------------------------
      # `whodunnit` registra o usuário REAL. Numa sessão de impersonação o
      # `sub` do token é o impersonado, mas quem agiu foi quem impersonou — sem
      # isto a trilha diria que o Cliente Teste fez o que o OG fez, que é o
      # oposto do ponto de ter trilha (DEC-59 #3).
      true_user_id = impersonated_by_claim
      env['api.true_user_id'] = true_user_id
      PaperTrail.request.whodunnit = (true_user_id.presence || @current_user.id).to_s
      PaperTrail.request.controller_info = {
        impersonated_id: (true_user_id.present? ? @current_user.id.to_s : nil),
        ip_address: env['REMOTE_ADDR']
      }
    end

    # O `PaperTrail.request` vive num store por thread; sem limpar, a próxima
    # requisição atendida pela mesma thread herdaria o autor da anterior.
    after do
      PaperTrail.request.whodunnit = nil
      PaperTrail.request.controller_info = {}
    end

    helpers do
      def process_service_response(response)
        status response[:status]

        if (200..299).include?(response[:status])
          response[:data]
        else
          # Mesma forma `{error, message, code}` de `Api::V1::ControllerHelpers` — ver
          # o comentário lá. Duplicada aqui porque o `Api::Root` não inclui aquele
          # módulo; se as duas divergirem, o cliente passa a receber corpos diferentes
          # para o mesmo erro dependendo de onde o endpoint estiver montado.
          payload = {
            error: response[:error] || response[:message] || 'error',
            message: response[:message] || response[:error]
          }
          payload[:code] = response[:code] if response[:code]
          payload[:details] = response[:details] if response[:details]
          error!(payload, response[:status])
        end
      end

      attr_reader :current_user

      attr_reader :current_client

      # Claim `impersonated_by` do access token: o id de quem iniciou a
      # impersonação. `nil` em sessão normal.
      def impersonated_by_claim
        auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
        return nil if auth_header.blank?

        _scheme, token = auth_header.split(' ')
        return nil if token.blank?

        payload = nil
        begin
          payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
        rescue StandardError
          payload = nil
        end
        payload ||= begin
          ::Auth::TokenService.new(nil).decode_token(token, verify_exp: false)
        rescue StandardError
          nil
        end

        payload && payload['impersonated_by'].presence
      end
    end

    # Montando os módulos da API (cada um com seu prefixo e versão)
    mount Api::Auth::V1::Base     # /auth/v1/*
    mount Api::Whats::V1::Base    # /whats/v1/*
    mount Api::V1::Base
    mount Api::V1::Chat # Direct mount for debugging

      rescue_from :all do |e|
        if (e.is_a? Grape::Exceptions::MethodNotAllowed) ||
           e.message.include?('Mysql2::Error') ||
           (e.is_a? PG::Error)
          
           # Let specific handlers or default behavior take over?
           # Actually if we cover :all, we MUST handle it.
           # Converting to 500 is the default fallback here.
           # But MethodNotAllowed should be 405.
           # For now, I will just re-raise them so Grape handles or they bubble up (if Grape allows bubbling from :all).
           # But raising from :all might just crash.
           # Safest: error! e.message, 405 if MethodNotAllowed.
           
           if e.is_a?(Grape::Exceptions::MethodNotAllowed)
             error!({ error: e.message }, 405)
           end
           
           # Database errors -> 500 but log differently?
           # The original code intended to skip the "Exception Notifier" part but STILL returned 500 via the common error! call at the end.
           # So Mysql/PG errors were returning 500 with stacktrace.
           # That seems intentional for debugging?.
        end

        env = {}
        env['exception_notifier.exception_data'] = {
          api: 'API ERROR - POLEMK WHATS',
          message: e.message,
          user: 'No User.',
          environment: Rails.env
        }

        # Log de erro
        error_backtrace = "ERROR - API POLEMK: #{e.message} <br/> \n BACKTRACE: #{e.backtrace.join "\n"}"
        # File.write('/tmp/debug_log.txt', "[BaseController Error] #{e.message}\n", mode: 'a')
        Rails.logger.warn error_backtrace
        error!(error_backtrace, 500)
      end

    add_swagger_documentation(
      mount_path: '/swagger_doc',
      hide_documentation_path: true,
      format: :json,
      base_path: '/',
      info: {
        title: ENV.fetch('APP_NAME', 'Safegold'),
        description: "API do #{ENV.fetch('APP_NAME',
                                         'Safegold')} para integrações (WhatsApp/Evolution, Auth)."
      },
      security_definitions: {
        Bearer: {
          type: 'apiKey',
          name: 'Authorization',
          in: 'header',
          description: 'Token de autenticação no formato: Bearer {token}'
        }
      },
      security: [{ Bearer: [] }]
    )
  end
end
