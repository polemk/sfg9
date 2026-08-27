# frozen_string_literal: true

module Api
  module V1
    # S0 / BE-041, DB-008 — catálogo de permissões.
    #
    # Montado em `namespace :permissions` por `api/v1/base.rb`.
    class Permissions < Grape::API
      helpers Api::V1::ControllerHelpers

      # GET /api/v1/permissions — o catálogo. Recurso administrativo: OG e Admin
      # (DEC-18.2). O Gerente não alcança.
      desc 'Catálogo de permissões' do
        summary 'Lista as permissões existentes'
      end
      get '' do
        authenticate_user!
        authorize!('permissions', :read)
        process_service_response(PermissionsService.catalog)
      end

      resource :me do
        desc 'Minhas permissões' do
          summary 'Permissões efetivas do usuário atual'
        end
        # Sem `authorize!`: qualquer sessão lê as PRÓPRIAS permissões — é o que
        # o front usa para esconder botão. Resolvido por consulta (nunca
        # congelado no usuário), então revogação vale na requisição seguinte.
        get '' do
          authenticate_user!
          process_service_response(PermissionsService.for_user(target_user: current_user))
        end
      end
    end
  end
end
