module Api
  module V1
    module Defaults
      extend ActiveSupport::Concern

      included do
        # Prefix & Version
        prefix "api"
        version "v1", using: :path
        default_format :json
        format :json
        
        # Helpers
        helpers Api::V1::ControllerHelpers

        helpers do
          def permitted_params
            @permitted_params ||= declared(params, include_missing: false)
          end

          def logger
            Rails.logger
          end

          # Authentication Helper
          def current_user
            # Check if authentication was already performed by middleware or Api::Root
            return env['api.current_user'] if env['api.current_user']

            token = request.headers['Authorization'].to_s.split(' ').last
            return nil unless token
            
            begin
              payload = nil
              payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
              payload ||= Auth::TokenService.new(nil).decode_token(token)

              # Mesma correção do gate central (`api/root.rb`): o decodificador do
              # Warden não consulta a `jwt_denylist`, e como está sempre definido
              # ele vence o `||=`. Sem esta linha, um token já revogado pelo «Sair»
              # continuaria autenticando por AQUI — é a segunda porta do mesmo
              # D-QA-02, a que fica aberta quando o gate central foi pulado (rota
              # na allowlist de `public_paths`) e o endpoint chama `current_user`
              # mesmo assim.
              #
              # `::Auth`, com os dois-pontos, pela mesma razão de `api/root.rb`:
              # daqui de dentro de `module Api` o nome `Auth::TokenService`
              # resolveria para `Api::Auth::TokenService`, que não existe, e o
              # `NameError` cairia no `rescue` abaixo virando "sem usuário".
              payload = nil if payload && ::Auth::TokenService.revoked?(payload)

              if payload && payload['sub']
                @current_user = User.find_by(id: payload['sub'])
                env['api.current_user'] = @current_user
                @current_user
              else
                nil
              end
            rescue => e
              logger.error "Auth Error in Defaults: #{e.message}"
              nil
            end
          end

          def authenticate!
            return if current_user || env['api.current_client']
            error!('Unauthorized', 401) 
          end
        end

        # Exception Handling
        rescue_from ActiveRecord::RecordNotFound do |e|
          error!({ error: 'Not Found', message: e.message }, 404)
        end
      end
    end
  end
end
