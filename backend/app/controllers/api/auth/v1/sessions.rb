# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class Sessions < Grape::API
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
        namespace :sessions do


          # GET /auth/v1/sessions/status
          resource :status do
            desc 'Verifica status da sessão atual' do
              summary 'Status da sessão atual'
              detail 'Retorna informações sobre a sessão atual do usuário autenticado.'
              success [code: 200, message: 'Sessão válida']
              failure [
                { code: 401, message: 'Sessão inválida ou não autenticado' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            get do
              auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
              token = nil
              if auth_header.present?
                scheme, t = auth_header.split(' ')
                token = t if scheme == 'Bearer'
              end
              data = ::Auth::SessionsService.status({ token: token })
              if data[:status].between?(200, 299)
                user = @current_user
                if user.nil? && data[:data].is_a?(Hash) && data[:data][:user]
                   # Fallback: se o endpoint é público, @current_user é nil.
                   # O service retorna Api::Entities::User, que é um Grape::Entity.
                   user_obj = data[:data][:user]
                   uid = if user_obj.respond_to?(:object) && user_obj.object.respond_to?(:id)
                           user_obj.object.id
                         elsif user_obj.respond_to?(:id)
                           user_obj.id
                         elsif user_obj.is_a?(Hash)
                           user_obj[:id] || user_obj['id']
                         end
                   user = User.find_by(id: uid) if uid
                end
                csrf = ::Auth::CsrfService.new(user).generate if user
                payload = data[:data].is_a?(Hash) ? data[:data].merge({ csrf_token: csrf }) : { csrf_token: csrf }
                process_service_response({ status: 200, data: payload })
              else
                process_service_response(data)
              end
            end
          end

          # POST /auth/v1/sessions/refresh
          resource :refresh do
            desc 'Atualiza token de acesso' do
              summary 'Refresh de token JWT'
              detail 'Atualiza o token de acesso usando o refresh token do cookie HttpOnly '\
                     '(setado no login). O refresh nunca trafega no corpo da requisição/resposta.'
              success [code: 200, message: 'Token atualizado']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 401, message: 'Refresh token inválido' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            post do
              result = ::Auth::SessionsService.refresh({ refresh_token: refresh_cookie_value })
              # Rotaciona os cookies HttpOnly e remove o refresh do corpo da resposta.
              # O access_token sai pela Api::Entities::AuthSession, que o expõe.
              process_auth_response(result)
            end
          end

          # DELETE /auth/v1/sessions/logout
          resource :logout do
            desc 'Encerra sessão do usuário' do
              summary 'Logout do usuário'
              detail 'Revoga a sessão e invalida tokens ativos do usuário.'
              success [code: 200, message: 'Logout realizado']
              failure [
                { code: 401, message: 'Não autenticado' },
                { code: 422, message: 'Falha ao realizar logout' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            delete do
              auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
              token = nil
              if auth_header.present?
                scheme, t = auth_header.split(' ')
                token = t if scheme == 'Bearer'
              end
              result = ::Auth::SessionsService.logout({
                                                        token: token,
                                                        refresh_token: refresh_cookie_value,
                                                        cable_token: cable_cookie_value
                                                      })
              clear_refresh_cookie
              clear_cable_cookie
              process_service_response(result)
            end
          end
        end
      end
    end
  end
end
