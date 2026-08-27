# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class MagicLogin < Grape::API
        namespace :magic_login do
          # POST /auth/v1/magic_login/request_code
          resource :request_code do
            desc 'Solicita código de acesso via email ou WhatsApp' do
              summary 'Solicitar código de login'
              detail 'Envia um código de acesso para o email ou WhatsApp informado após verificações de segurança.'
              success [code: 200, message: 'Código enviado']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 429, message: 'Muitas tentativas' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            params do
              requires :identifier, type: String, desc: 'Email ou telefone'
              requires :method, type: String, values: %w[email whatsapp], desc: 'Método de envio'
            end

            # O `rescue StandardError` que existia aqui devolvia `e.message` e um campo
            # `stage` no corpo do 500 — foi ele que expôs
            # "undefined local variable or method 'current_ip'" para qualquer chamador,
            # contra o `api/CONTRATO.md` §3 (resposta de erro não carrega estrutura
            # interna). Exceção não tratada é trabalho do `rescue_from :all` do
            # `Api::Auth::V1::Base`, que responde `{error, message}` e manda o backtrace
            # para o log.
            post do
              identifier = params[:identifier].strip
              delivery_method = params[:method].downcase

              check_brute_force!(identifier, current_ip)
              check_rate_limit!(identifier, delivery_method)
              # O cooldown de 30 s é cobrado AQUI, antes de existir usuário nenhum.
              # Enquanto ele morava no `MagicLoginService` (atrás de
              # `user.can_request_new_code?`), o segundo pedido devolvia 422 para conta
              # real e 200 para conta inexistente — a tela de login virava um
              # verificador de "esta pessoa é cliente do Safegold?" (D-QA-01).
              check_code_cooldown!(identifier, delivery_method)

              # Armado ANTES do serviço, de propósito: o relógio precisa começar mesmo
              # quando nada é enviado (destino sem conta, conta bloqueada, falha de
              # entrega). Se só o caminho de sucesso armasse, a diferença voltaria no
              # pedido seguinte.
              start_code_cooldown!(identifier, delivery_method)

              result = ::Auth::MagicLoginService.new(
                identifier: identifier,
                method: delivery_method,
                ip_address: current_ip,
                user_agent: current_user_agent
              ).execute!

              process_service_response(result)
            end
          end

          # POST /auth/v1/magic_login/validate_code
          resource :validate_code do
            desc 'Valida código de acesso e realiza login' do
              summary 'Validar código e logar'
              detail 'Valida o código enviado ao usuário e realiza o login, retornando tokens e dados do usuário.'
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

            post do
              identifier = params[:identifier].strip
              code = params[:code].strip
              method = params[:method].downcase

              # Verificações de segurança
              check_brute_force!(identifier, current_ip)

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

          # POST /auth/v1/magic_login/can_resend
          resource :can_resend do
            desc 'Verifica se pode solicitar novo código' do
              summary 'Checar status de reenvio'
              detail 'Verifica se o usuário pode solicitar um novo código e o tempo restante para reenvio.'
              success [code: 200, message: 'Status verificado']
              failure [
                { code: 400, message: 'Dados inválidos' }
              ]
            end

            params do
              requires :identifier, type: String, desc: 'Email ou telefone'
              requires :method, type: String, values: %w[email whatsapp], desc: 'Método de envio'
            end

            post do
              identifier = params[:identifier].strip
              method = params[:method].downcase

              # Lê o MESMO cooldown do `request_code`, e não a tabela `login_codes`.
              #
              # Consultando `LoginCode`, este endpoint era o D-QA-01 por outra porta:
              # só existe `LoginCode` para quem tem conta, então
              # `can_resend: false` respondia "esta pessoa é cliente do Safegold" com a
              # mesma clareza que o 422 do pedido de código. Agora a chave é o destino
              # digitado, normalizado — armado no pedido, exista conta ou não.
              time_until_resend = code_cooldown_remaining(identifier, method)
              can_resend = time_until_resend.zero?

              process_service_response({
                                         status: 200,
                                         data: {
                                           can_resend: can_resend,
                                           time_until_resend: time_until_resend
                                         }
                                       })
            end
          end
        end

        # Normalização feita via LoginCode.normalize_destination_value
      end
    end
  end
end
