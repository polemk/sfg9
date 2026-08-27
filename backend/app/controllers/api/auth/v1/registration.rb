# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      # **DEC-49 — as 4 rotas de AUTO-CADASTRO foram removidas deste repositório.**
      #
      # Saíram daqui e da allowlist pública de `api/root.rb`:
      #
      #   POST /auth/v1/pre_register
      #   POST /auth/v1/complete_registration
      #   POST /auth/v1/visitor_signup
      #   POST /auth/v1/visitor_signup_with_link
      #
      # Entrada no sistema é **só por convite** (DEC-18.7). No legado,
      # `config/application.rb:84` definia `minimal_type_to_sign_up_through_web =
      # "Admin"`: qualquer pessoa na internet se cadastrava até a hierarquia 998.
      # É o **D-39**.
      #
      # Por que remover a rota em vez de desligar por configuração: rota que não
      # existe não reabre por engano. Com flag, o D-39 volta sozinho na primeira
      # vez que alguém copiar um `.env` de outro ambiente — que é exatamente
      # como esse defeito nasceu.
      #
      # Os serviços `PreRegisterService`, `CompleteRegistrationService` e
      # `VisitorSignupWithLinkService` foram apagados junto: serviço órfão é
      # convite a remontar a rota.
      #
      # O que sobra aqui é `verify_code`, que **não cria conta** — valida um
      # código já emitido para um usuário já existente.
      #
      # **`Auth::VerifyCodeService` também foi apagado.** Ele tinha um terceiro
      # desfecho, `requires_completion: true`, que mandava o frontend para a tela
      # "Completar cadastro" — e essa tela fazia `POST /auth/v1/complete_registration`,
      # rota que a DEC-49 removeu. Ou seja: o caminho existia, compilava, e terminava em
      # 404. Era o mesmo defeito de fronteira que derrubou o login em 25/08/2026, à
      # espera do primeiro usuário que caísse no ramo.
      #
      # `verify_code` agora delega ao `Auth::CodeValidationService`, o mesmo do
      # `magic_login/validate_code`: **uma** regra de validação de código no sistema,
      # não duas com tetos de tentativa diferentes.
      class Registration < Grape::API
        helpers do
          def process_service_response(response)
            status response[:status]

            if (200..299).include?(response[:status])
              response[:data]
            else
              error_payload = { error: response[:error] || response[:message] }
              error_payload[:details] = response[:details] if response[:details]
              error!(error_payload, response[:status])
            end
          end
        end

        resource :verify_code do
          desc 'Valida um código de acesso já emitido' do
            summary 'Verificar código'
            detail 'NÃO cria conta. Valida um código emitido para um usuário existente.'
            success [code: 200, message: 'Código válido']
            failure [
              { code: 400, message: 'Dados inválidos' },
              { code: 401, message: 'Código inválido ou expirado' },
              { code: 429, message: 'Muitas tentativas' }
            ]
          end

          params do
            requires :identifier, type: String
            requires :code, type: String
            requires :method, type: String, values: %w[email whatsapp]
          end

          post do
            identifier = params[:identifier].to_s.strip
            check_brute_force!(identifier, current_ip)

            result = ::Auth::CodeValidationService.new(
              identifier: identifier,
              code: params[:code].to_s.strip,
              method: params[:method].downcase,
              ip_address: current_ip,
              user_agent: current_user_agent
            ).execute!
            process_auth_response(result)
          end
        end
      end
    end
  end
end
