# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class CodeValidation < Grape::API
        namespace :code_validation do
          # POST /auth/v1/code_validation
          resource '' do
            desc 'Valida código de acesso (alias para magic_login/validate_code)' do
              summary 'Validar código e logar (alias)'
              detail 'Valida o código enviado ao usuário e realiza o login. Alias de magic_login/validate_code.'
              success [code: 200, message: 'Login realizado']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 401, message: 'Código inválido' },
                { code: 429, message: 'Muitas tentativas' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            params do
              requires :identifier, type: String, desc: 'Email ou telefone'
              requires :code, type: String, desc: 'Código de 6 dígitos'
              requires :method, type: String, values: %w[email whatsapp], desc: 'Método de envio'
            end

            post '', http_codes: [
              [200, 'Login realizado'],
              [400, 'Dados inválidos'],
              [401, 'Código inválido'],
              [429, 'Muitas tentativas'],
              [500, 'Erro interno']
            ] do
              identifier = params[:identifier].strip
              code = params[:code].strip
              method = params[:method].downcase

              # Verificações de segurança
              check_brute_force!(identifier, current_ip)

              # `::` obrigatório. Sem ele o lookup léxico acha `Api::Auth` (o módulo que
              # envolve este arquivo) antes de chegar no `Auth` de topo, e procura por
              # `Api::Auth::CodeValidationService`, que não existe — era o 500 deste
              # endpoint. O `code_validation_spec.rb` escondia isso criando a constante
              # ausente com `Api::Auth.const_set(...)` dentro do próprio teste.
              # Mesma família do tropeço que a 4.13 achou no `root.rb` e a 4.25 no
              # `TokenService`.
              result = ::Auth::CodeValidationService.new(
                identifier: identifier,
                code: code,
                method: method,
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
end
