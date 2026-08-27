# frozen_string_literal: true

module Authorization
  # S0 / BE-042, BE-520, DB-006 — a trava de hierarquia do contrato **C3**.
  #
  # Vive separada da `Matrix` porque depende do **alvo**, não só do ator: "Admin
  # pode editar permissões" é matriz; "Admin pode editar as permissões DESTE
  # papel" é hierarquia.
  #
  # ### A escala, e por que o sinal importa mais que a trava
  #
  # **Menor = mais poder** (DEC-41): OG=1, Admin=2, Gerente=3, Colaborador=4.
  # Toda comparação aqui é `ator.hierarchy_level < alvo.hierarchy_level`.
  #
  # Inverter esse sinal **dá poder de OG a um Colaborador** — e passa em qualquer
  # teste que verifique só que "a trava existe", porque ela continua existindo,
  # apontando para o lado errado. Por isso todo teste de hierarquia desta fatia
  # verifica os **dois** lados: o que é negado *e* o que é permitido.
  module Hierarchy
    module_function

    # Papéis cujas permissões o ator pode editar (DEC-18.2).
    #
    #  - **OG** alcança todos, inclusive o próprio OG;
    #  - **Admin** alcança **estritamente abaixo** — nunca o OG, nunca outro
    #    Admin (lateral), nunca a si mesmo. É isso que fecha a autopromoção;
    #  - **Gerente** e **Colaborador** não alcançam a tela (a `Matrix` já nega).
    def can_edit_user_type?(actor, target_type)
      return false if actor.nil? || target_type.nil?
      return false unless Matrix.allow?(role_of(actor), 'permissions', :update)
      return true if actor.og?

      level_of(actor) < target_type.hierarchy_level
    end

    # Papéis cujas permissões o ator pode VER. Mais largo que editar de
    # propósito: o Admin vê a própria linha (leitura) mas não a edita, e continua
    # sem enxergar a do OG — no legado só o OG via o RoleType OG
    # (`permissions_controller.rb:17-21`).
    def can_view_user_type?(actor, target_type)
      return false if actor.nil? || target_type.nil?
      return false unless Matrix.allow?(role_of(actor), 'permissions', :read)
      return true if actor.og?

      level_of(actor) <= target_type.hierarchy_level
    end

    # Mesma trava aplicada ao override de permissão de um USUÁRIO
    # (`PUT /api/v1/users/:id/permissions/:key`).
    #
    # No legado o `:id` do usuário era **descartado** (`permissions_controller.rb:55-57`),
    # então qualquer linha de `Ability` era alcançável por URL — o **D-34**, o
    # vetor mais direto de escalação. Aqui o alvo manda.
    def can_edit_user_permissions?(actor, target_user)
      return false if actor.nil? || target_user&.user_type.nil?

      can_edit_user_type?(actor, target_user.user_type)
    end

    # DEC-18.3 — impersonação: OG e Admin, sempre para hierarquia **inferior**.
    # Nunca o OG, nunca lateral, nunca a si mesmo, e não encadeia (quem já está
    # impersonando não inicia outra).
    def can_impersonate?(actor, target_user)
      return false if actor.nil? || target_user.nil?
      return false if actor.id == target_user.id
      return false unless Matrix.allow?(role_of(actor), 'impersonation', :create)
      return false if target_user.user_type.nil?

      level_of(actor) < target_user.user_type.hierarchy_level
    end

    # Papéis que o ator enxerga no filtro de usuários (BE-504).
    #
    # OG vê todos. Os demais veem o próprio nível **para baixo** — por isso o
    # filtro de um Gerente não devolve OG nem Admin, mas devolve Colaborador.
    def visible_user_types(actor)
      return UserType.ordered_by_hierarchy if actor&.og?
      return UserType.none if actor&.user_type.nil?

      UserType.where('hierarchy_level >= ?', level_of(actor)).ordered_by_hierarchy
    end

    def level_of(user)
      user.user_type.hierarchy_level
    end

    def role_of(user)
      user.user_type&.name
    end
  end
end
