# frozen_string_literal: true

require 'grape'

# Controller para impersonação de usuários
# Super/Admin podem "ver como" outro usuário
module Api
  module Auth
    module V1
      class Impersonate < Grape::API
        helpers Api::Auth::V1::AuthHelpers
        helpers Api::Auth::V1::SecurityHelpers

        namespace :impersonate do
          before do
            authenticate_user!
          end

          # POST /auth/v1/impersonate/start
          desc 'Inicia impersonação de outro usuário' do
            summary 'Impersonar usuário'
            detail 'Gera novos tokens JWT para o usuário alvo, com claim de impersonação. Requer permissão super ou admin.'
            success [code: 200, message: 'Impersonação iniciada']
            failure [
              { code: 401, message: 'Não autenticado' },
              { code: 403, message: 'Sem permissão para impersonar (403 vem ANTES de 404 — IMP-A28)' },
              { code: 404, message: 'Usuário não encontrado' },
              { code: 422, message: 'Motivo ausente, alvo é você mesmo, ou conta bloqueada' }
            ]
          end
          params do
            requires :user_id, type: String, desc: 'ID do usuário a ser impersonado'
            requires :reason, type: String, desc: 'Motivo — obrigatório, vai para a trilha de auditoria (DEC-18.3)'
          end
          post :start do
            process_auth_response(
              ::Auth::ImpersonateService.start(
                current_user, params[:user_id],
                reason: params[:reason],
                ip_address: current_ip
              )
            )
          end

          # POST /auth/v1/impersonate/stop
          desc 'Para impersonação e restaura sessão original' do
            summary 'Parar impersonação'
            detail 'Restaura os tokens JWT do usuário original. Requer que haja impersonação ativa.'
            success [code: 200, message: 'Impersonação encerrada']
            failure [
              { code: 401, message: 'Não autenticado' },
              { code: 404, message: 'Usuário original não encontrado' },
              { code: 422, message: 'Nenhuma impersonação ativa' }
            ]
          end
          post :stop do
            unless impersonating?
              error!({ error: 'not_impersonating', message: 'Nenhuma impersonação ativa' }, 422)
            end

            process_auth_response(
              ::Auth::ImpersonateService.stop(
                true_user_id,
                impersonated_id: current_user&.id,
                ip_address: current_ip
              )
            )
          end
        end
      end
    end
  end
end
