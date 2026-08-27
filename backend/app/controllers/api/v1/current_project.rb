# frozen_string_literal: true

module Api
  module V1
    # S2 / BE-412 — o **seletor de projeto** da topbar.
    #
    # É a interface direta do contrato **C1**: o projeto corrente é **estado de
    # servidor** (`users.current_project_id`, revalidado contra `memberships` a
    # cada request por `current_project!`), nunca cookie.
    #
    # O que o legado fazia e **não** é portado:
    #
    #  - o cookie `cached_info` (**D-28**), escrito pelo servidor E pelo cliente,
    #    com codificações diferentes, 4 dias de vida, **nenhuma flag de
    #    segurança** — e carregando o tenant. Um cookie que decide escopo é um
    #    cookie que o cliente edita (DB-396 / OPS-392);
    #  - a heurística de "selecionar a **segunda** opção do select" quando o
    #    cookie não batia com o usuário. Não havia justificativa; havia um
    #    `index` errado.
    #
    # **Projeto inexistente e projeto sem participação respondem o MESMO status**
    # (404, via `project_not_found!`). Distinguir 403 de 404 transformaria este
    # endpoint num oráculo de existência de ids (DC-08, condição 2).
    class CurrentProject < Grape::API
      helpers Api::V1::ControllerHelpers

      namespace :current_project do
        before do
          authenticate_user!
        end

        desc 'Projeto corrente e as opções do seletor' do
          summary 'Seletor de projeto'
          detail 'Devolve o projeto corrente (ou `null`) e SÓ os projetos em que o usuário participa.'
        end
        get '' do
          authorize!('console', :read)

          scope = Project.visible_to(current_user).order(:name)
          {
            current: Api::Entities::ProjectOption.represent(current_project),
            projects: Api::Entities::ProjectOption.represent(scope)
          }
        end

        desc 'Troca o projeto corrente' do
          summary 'Trocar de projeto'
          failure [{ code: 404, message: 'Projeto inexistente OU sem participação — o mesmo status, de propósito' }]
        end
        params do
          requires :project_id, type: String, desc: 'UUID de um projeto em que o usuário participa'
        end
        put '' do
          authorize!('console', :read)

          # A verdade é a linha de `memberships`, sempre. `for_member` é o mesmo
          # escopo que `current_project!` usa para revalidar — se divergisse, o
          # seletor conseguiria gravar um projeto que a leitura recusa.
          project = Project.visible_to(current_user).find_by(id: params[:project_id])
          project_not_found! if project.nil?

          current_user.update!(current_project_id: project.id)
          Api::Entities::ProjectOption.represent(project)
        end
      end
    end
  end
end
