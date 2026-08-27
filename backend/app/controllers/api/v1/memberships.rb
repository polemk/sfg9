# frozen_string_literal: true

module Api
  module V1
    # S0 / BE-099, BE-044, BE-045, BE-046 — participação em projeto.
    #
    # **Escopo, contrato C1:** o projeto vem SEMPRE de `current_project!`. Não há
    # `project_id` em nenhum `params do` deste arquivo — nem no corpo, nem na
    # rota. É essa ausência que fecha a família D-01/D-16/D-29.
    #
    # **Autorização, contrato C3:** `authorize!('memberships', …)` — OG, Admin e
    # Gerente criam e removem (DEC-18.5); Colaborador só lê.
    class Memberships < Grape::API
      helpers Api::V1::ControllerHelpers

      namespace :memberships do
        before do
          authenticate_user!
        end

        desc 'Lista os membros do projeto corrente' do
          summary 'Membros do projeto'
          detail 'Escopado por `current_project!`. Paginação por cabeçalho.'
        end
        params do
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!('memberships', :read)
          project = current_project!
          result = MembershipService.index(project: project, params: params)
          set_pagination_headers(result[:data][:total], result[:data][:page], result[:data][:per_page])
          process_service_response(result)
        end

        desc 'Autocomplete de candidatos a membro' do
          summary 'Candidatos'
          detail 'Não lista quem já é membro. Termo vazio devolve lista válida.'
        end
        params do
          optional :q, type: String, desc: 'Termo de busca (pode vir vazio)'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get :candidates do
          authorize!('memberships', :create)
          # DEC-108 — `may_modify_public_entries`. No legado o rótulo era
          # «Modificar dados em Módulos» e o **único** consumidor era a caixa
          # «Adicionar Membro» do detalhe do projeto
          # (`projects/detail/tabs/_tab_geral.html.erb:76`). É esse efeito que foi
          # portado — o autocomplete e a criação, que são a mesma caixa.
          require_permission!('may_modify_public_entries')
          project = current_project!
          result = MembershipService.candidates(project: project, actor: acting_user, params: params)
          set_pagination_headers(result[:data][:total], result[:data][:page], result[:data][:per_page])
          process_service_response(result)
        end

        desc 'Adiciona um usuário ao projeto corrente' do
          summary 'Criar participação'
          failure [
            { code: 403, message: 'Sem permissão, ou tentativa de auto-participação' },
            { code: 404, message: 'Projeto ou usuário inexistente' }
          ]
        end
        params do
          requires :user_id, type: String, desc: 'Usuário a adicionar'
          optional :role, type: String, values: Membership::ROLES, default: 'participante',
                          desc: 'Rótulo DESCRITIVO. Nunca consultado para autorizar (DEC-18.6).'
          # `:id` e `:project_id` NÃO são declarados de propósito.
        end
        post '' do
          authorize!('memberships', :create)
          # DEC-108 — o mesmo gate da caixa «Adicionar Membro», agora no servidor.
          # Remover membro **não** passa por aqui: no legado a remoção estava atrás
          # de `user_is_readonly`, não desta ability (`memberships/list/_widget.html.erb:23`).
          require_permission!('may_modify_public_entries')
          project = current_project!
          process_service_response(
            MembershipService.create(
              project: project,
              actor: acting_user,
              user_id: params[:user_id],
              role: params[:role]
            )
          )
        end

        desc 'Remove uma participação do projeto corrente' do
          summary 'Revogar participação'
          detail 'Não remove o dono do projeto nem a própria participação. Limpa o `current_project_id` de quem saiu.'
        end
        params do
          requires :id, type: String, desc: 'Id da participação'
        end
        delete ':id' do
          authorize!('memberships', :destroy)
          project = current_project!
          process_service_response(
            MembershipService.destroy(project: project, actor: acting_user, membership_id: params[:id])
          )
        end
      end
    end
  end
end
