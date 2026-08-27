# frozen_string_literal: true

module Api
  module Auth
    module V1
      module AuthHelpers
        def authenticate_user!
          @current_user = env['api.current_user']
          error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) unless @current_user
        end

        def current_user
          @current_user || env['api.current_user']
        end

        # Verifica se a sessão atual é de impersonação (via JWT claim)
        def impersonating?
          token_payload&.dig('impersonated_by').present?
        end

        # ID do usuário real (quem está impersonando)
        def true_user_id
          token_payload&.dig('impersonated_by')
        end

        # Usuário real (quem está impersonando)
        def true_user
          return nil unless impersonating?
          @true_user ||= User.find_by(id: true_user_id)
        end

        # Payload do JWT atual
        def token_payload
          return @token_payload if defined?(@token_payload)

          auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
          return nil unless auth_header.present?

          scheme, token = auth_header.split(' ')
          return nil unless scheme == 'Bearer' && token.present?

          begin
            if defined?(Warden::JWTAuth::TokenDecoder)
              begin
                decoded = Warden::JWTAuth::TokenDecoder.new.call(token)
                @token_payload = decoded if decoded
              rescue StandardError
                # Warden decode failed, try TokenService
              end
            end
            
            # Fallback
            if @token_payload.nil? || @token_payload['impersonated_by'].nil?
              token_service = ::Auth::TokenService.new(current_user || User.new)
              @token_payload = token_service.decode_token(token, verify_exp: false) 
            end
            
            Rails.logger.info "[AuthHelpers] Token payload: #{@token_payload.inspect}"
            @token_payload
          rescue StandardError => e
            Rails.logger.error "[AuthHelpers] Token decode error: #{e.message}"
            @token_payload = nil
          end
        end

        # --- Refresh e cable token em cookie HttpOnly -----------------------
        # Nenhum dos dois sai no JSON: vão em cookies HttpOnly, invisíveis ao
        # JavaScript. O Path estreita o alcance — o refresh só é enviado em
        # /auth/v1 (único prefixo que o consome) e o do cable só no handshake de
        # /cable, então as demais chamadas da API não carregam cookie nenhum.
        # SameSite=Lax cobre CSRF porque front e API são same-site: o install.sh
        # provisiona a API como subdomínio do domínio do front.

        REFRESH_COOKIE = 'refresh_token'
        REFRESH_COOKIE_PATH = '/auth/v1'
        CABLE_COOKIE = 'cable_token'
        CABLE_COOKIE_PATH = '/cable'

        def issue_refresh_cookie(token)
          cookies[REFRESH_COOKIE] = {
            value: token,
            path: REFRESH_COOKIE_PATH,
            httponly: true,
            secure: Rails.env.production?,
            same_site: :lax,
            expires: ::Auth::TokenService::REFRESH_TTL.from_now
          }
        end

        def clear_refresh_cookie
          cookies.delete REFRESH_COOKIE, path: REFRESH_COOKIE_PATH
        end

        def refresh_cookie_value
          cookies[REFRESH_COOKIE]
        end

        # Emite o cookie do cable (auth do WebSocket sem token na URL). O user_id
        # sai do próprio refresh recém-gerado, evitando uma query extra.
        def issue_cable_cookie(user_id)
          return if user_id.blank?

          cookies[CABLE_COOKIE] = {
            value: ::Auth::TokenService.new(nil).cable_token_for(user_id),
            path: CABLE_COOKIE_PATH,
            httponly: true,
            secure: Rails.env.production?,
            same_site: :lax,
            expires: ::Auth::TokenService::CABLE_TTL.from_now
          }
        end

        def clear_cable_cookie
          cookies.delete CABLE_COOKIE, path: CABLE_COOKIE_PATH
        end

        def cable_cookie_value
          cookies[CABLE_COOKIE]
        end

        # Ponto único de emissão. Extrai o refresh do payload do service, manda
        # para o cookie e garante que ele não vaza no corpo da resposta.
        #
        # Não dá para fazer isso num filtro `after` do Grape: o @body só é
        # atribuído depois de rodar os afters, então lá o corpo é nil.
        def process_auth_response(response)
          data = response[:data]
          raw_refresh = extract_refresh_token(data)
          if raw_refresh && (200..299).include?(response[:status])
            issue_refresh_cookie(raw_refresh)
            # Emite/rotaciona o cookie do cable junto — mesmo user do refresh.
            issue_cable_cookie(refresh_subject(raw_refresh))
          end
          strip_refresh_token!(data)
          process_service_response(response)
        end

        def refresh_subject(raw_refresh)
          ::Auth::TokenService.new(nil).decode_token(raw_refresh, verify_exp: false)['sub']
        rescue StandardError
          nil
        end

        def extract_refresh_token(data)
          return nil if data.nil?

          if data.is_a?(Grape::Entity)
            obj = data.object
            obj.respond_to?(:[]) ? (obj[:refresh_token] || obj['refresh_token']) : nil
          elsif data.respond_to?(:[])
            data[:refresh_token] || data['refresh_token']
          end
        end

        def strip_refresh_token!(data)
          target = data.is_a?(Grape::Entity) ? data.object : data
          return unless target.is_a?(Hash)

          target.delete(:refresh_token)
          target.delete('refresh_token')
        end

        def process_service_response(response)
          status response[:status]

          if (200..299).include?(response[:status])
            response[:data]
          else
            error!(error_payload_for(response), response[:status])
          end
        end

        # **Forma única de erro: `{error, message, code}`** (api/CONTRATO.md §3, FE-516).
        #
        # Antes o corpo era `{ error: <mensagem inteira> }` e o `code` era descartado no
        # caminho. O front lê `data.code` para decidir o que mostrar
        # (`lib/api/client.ts:93`), então um 403 de conta bloqueada chegava
        # indistinguível de um 403 qualquer — e virava logout mudo, que é o IMP-A17.
        #
        # `error` é o identificador estável (`account_blocked`), `message` é o texto para
        # o humano, `code` é a constante que o cliente casa. Não se troca um pelo outro.
        def error_payload_for(response)
          payload = {
            error: response[:error] || response[:message] || 'error',
            message: response[:message] || response[:error]
          }
          payload[:code] = response[:code] if response[:code]
          payload[:details] = response[:details] if response[:details]
          payload
        end
      end
    end
  end
end
