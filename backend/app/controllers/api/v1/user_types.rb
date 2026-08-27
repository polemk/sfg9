# frozen_string_literal: true

module Api
  module V1
    # S0 / BE-040, BE-041, BE-042, BE-520 — papéis e suas permissões.
    #
    # **DEC-18.2:** OG e Admin alcançam este recurso; o **Gerente não**. O Admin
    # edita apenas papéis de hierarquia **inferior** à dele — nunca o OG, nunca
    # outro Admin, nunca a si mesmo. É essa trava que fecha a autopromoção.
    #
    # **BE-041:** a autorização usa o **usuário real** (`acting_user` →
    # `true_user` na impersonação), nunca o personificado.
    class UserTypes < Grape::API
      helpers Api::V1::ControllerHelpers

      namespace :user_types do
        before do
          authenticate_user!
        end

        desc 'Lista os papéis visíveis ao ator' do
          summary 'Papéis'
          detail 'Filtrado por hierarquia: o Gerente não enxerga OG nem Admin (BE-504).'
        end
        get '' do
          types = Authorization::Hierarchy.visible_user_types(acting_user)
          {
            user_types: types.map do |t|
              { id: t.id, name: t.name, display_name: t.display_name,
                hierarchy_level: t.hierarchy_level, description: t.description }
            end
          }
        end

        route_param :id do
          desc 'Permissões padrão de um papel' do
            summary 'Permissões do papel'
            failure [{ code: 403, message: 'Papel fora do alcance de hierarquia' }]
          end
          get :permissions do
            authorize!('permissions', :read)
            user_type = UserType.find_by(id: params[:id])
            error!({ error: 'not_found', message: 'Papel não encontrado' }, 404) if user_type.nil?

            process_service_response(
              PermissionsService.for_user_type(actor: acting_user, user_type: user_type)
            )
          end

          desc 'Concede ou revoga uma permissão do papel' do
            summary 'Editar permissão do papel'
            detail 'Trava de hierarquia (DEC-18.2). Revogar tem efeito imediato em quem JÁ existe — a permissão é ' \
                   'resolvida por consulta, nunca clonada no usuário (fecha D-35).'
            failure [{ code: 403, message: 'Papel fora do alcance de hierarquia' }]
          end
          params do
            requires :key, type: String, desc: 'Chave da permissão'
            # DEC-108 — `granted` deixou de ser obrigatório: duas das sete
            # permissões são **limite** (`max_users_amount`,
            # `max_invitations_amount`) e nelas o que muda é o número. Exigir os
            # dois faria a tela mandar um booleano que ninguém lê. O serviço
            # recusa a combinação errada com 422.
            optional :granted, type: Boolean, desc: 'Permissão condicional: true concede, false revoga'
            optional :limit_value, type: Integer, desc: 'Permissão de limite: o teto. Vazio = sem limite.'
            optional :reason, type: String, desc: 'Motivo — vai para a trilha de auditoria'
          end
          put 'permissions/:key' do
            authorize!('permissions', :update)
            user_type = UserType.find_by(id: params[:id])
            error!({ error: 'not_found', message: 'Papel não encontrado' }, 404) if user_type.nil?

            process_service_response(
              PermissionsService.set_user_type_permission(
                actor: acting_user,
                user_type: user_type,
                key: params[:key],
                granted: params[:granted],
                limit_value: params.key?(:limit_value) ? params[:limit_value] : :unset,
                reason: params[:reason]
              )
            )
          end
        end
      end
    end
  end
end
