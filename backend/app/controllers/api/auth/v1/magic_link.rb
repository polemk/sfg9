# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class MagicLink < Grape::API
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

        namespace :magic_link do
          desc 'Valida magic link e retorna JWT' do
            summary 'Verificar magic link'
            detail <<~DESC
              Troca um `link_token` (enviado por email ou WhatsApp) por um par de tokens JWT.

              **Como usar:** o token chega via query param na URL do link enviado ao usuário:
              `GET /auth/v1/magic_link/verify?token=<link_token>`

              **Regras:**
              - O token é de uso único — após ser validado, qualquer tentativa de reutilizá-lo retorna 404
              - O token expira em 24 horas
              - A validação é atômica: o token só é marcado como usado se o JWT for gerado com sucesso

              **Resposta de sucesso (200):**
              ```json
              {
                "token": "<jwt_access_token>",
                "user": { ... }
              }
              ```

              **Erros:** todos os casos inválidos (expirado, já usado, não encontrado) retornam 404
              para evitar que atacantes distingam o motivo da rejeição.
            DESC
            success [code: 200, message: 'Autenticado com sucesso — retorna token e user (o refresh vai em cookie HttpOnly)']
            failure [
              { code: 400, message: 'Token ausente ou em branco' },
              { code: 404, message: 'Link inválido, expirado ou já utilizado' },
              { code: 500, message: 'Erro interno no servidor' }
            ]
          end

          params do
            requires :token, type: String, desc: 'Token do magic link (recebido via URL no email ou WhatsApp)'
          end

          get :verify do
            header 'Cache-Control', 'no-store, no-cache, must-revalidate'
            header 'Pragma', 'no-cache'
            result = ::Auth::MagicLinkVerifyService.call(params[:token])
            process_auth_response(result)
          end
        end
      end
    end
  end
end
