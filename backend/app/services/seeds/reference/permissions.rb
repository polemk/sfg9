# frozen_string_literal: true

module Seeds
  module Reference
    # S0/S1 / DB-008, BE-505, OPS-009, OPS-541, F.4, F.6 — **DEC-108**.
    #
    # O **primeiro** seed de `permissions` da base ai9 (a tabela existia e estava
    # vazia). Idempotente: rodar duas vezes não duplica, não revoga concessão e
    # **não desfaz edição feita na tela** — o default do papel só é escrito
    # quando a linha ainda não existe.
    #
    # ## As 7 que voltam, e as 10 que ficam fora
    #
    # Das 17 abilities do legado sobrevivem as **7 com efeito real** — as que têm
    # pelo menos um call site fora de `ability_factory_decorator.rb` e dos seeds:
    #
    #   | ability                     | tipo   | call sites | onde, no legado |
    #   | --------------------------- | ------ | ---------: | --------------- |
    #   | `user_is_readonly`          | cond.  |        115 | ~30 views + `application_helper.rb:145` |
    #   | `may_create_users`          | cond.  |          5 | `my_account/_body.html.erb:13`, `role_type.rb:19,21`, `feedback19/messages_controller.rb:17,19` |
    #   | `max_users_amount`          | limit  |          3 | `application.rb:70`, `configuration.rb:48,56`, `registrations/index.html.erb:7` |
    #   | `max_invitations_amount`    | limit  |          2 | `application.rb:71`, `configuration.rb:49,57` |
    #   | `may_invite_users`          | cond.  |          1 | `registrations/index.html.erb:6` |
    #   | `may_delete_users`          | cond.  |          1 | `users/detail/tabs/_tab_geral.html.erb:3` |
    #   | `may_modify_public_entries` | cond.  |          1 | `projects/detail/tabs/_tab_geral.html.erb:76` |
    #
    # As outras 10 (`may_create/read/delete_public_entries`, as 4
    # `may_*_private_entries`, `may_read_users`, `max_private_entries_amount`,
    # `max_public_entries_amount`) têm **zero** call site fora do seed —
    # verificado ability por ability — e ficam descartadas.
    #
    # ## Os valores por papel
    #
    # Vêm de `../sfg/db/seeds.rb:40-95` (Admin 998, Gerente 888, Colaborador 799)
    # e de `../sfg/engines/auth19/db/seeds.rb:9-29` (OG 1111). Uma divergência
    # deliberada, registrada no `improvements-log.md`: **o OG não tem teto**.
    # O seed da engine dá ao OG `max_users_amount = 100` e `max_invitations_amount
    # = 200`, contra os 9999 do Admin. No legado nada disso era aplicado; aqui é.
    # Aplicar o literal deixaria o **fornecedor** (DEC-18.1) com teto MENOR que o
    # Admin do cliente — e a produção já tem 135 contas, então o OG nasceria
    # bloqueado no primeiro `POST /users` enquanto o Admin seguiria criando.
    # `NULL` = sem limite; `0` = nenhum permitido.
    module Permissions
      # `nil` em `limit` significa "sem limite"; `false`/`true` em `granted`
      # valem para as condicionais. A ordem das colunas é sempre
      # **[og, admin, gerente, colaborador]**, igual à `Authorization::Matrix`.
      ROLE_ORDER = %w[og admin gerente colaborador].freeze

      CATALOG = [
        {
          key: 'user_is_readonly',
          kind: Permission::KIND_CONDITIONAL,
          title: 'Somente leitura',
          description: 'Nega todo verbo de escrita (POST/PUT/PATCH/DELETE) ao usuário. Exceção: o aceite dos ' \
                       'Termos pelo próprio usuário nunca é bloqueado, senão o readonly fica trancado fora do ' \
                       'sistema (DC-09).',
          sort_order: 10,
          defaults: [false, false, false, false]
        },
        {
          key: 'may_create_users',
          kind: Permission::KIND_CONDITIONAL,
          title: 'Criar usuários',
          description: 'Permite criar contas direto, sem convite (POST /api/v1/users). No legado o gate existia ' \
                       'só na view; aqui é o servidor que recusa (DEC-108).',
          sort_order: 20,
          defaults: [true, true, false, false]
        },
        {
          key: 'may_invite_users',
          kind: Permission::KIND_CONDITIONAL,
          title: 'Convidar usuários',
          description: 'Permite emitir o convite de primeiro acesso por e-mail. É a única porta de entrada do ' \
                       'sistema desde que o cadastro público foi desligado (DEC-18.7).',
          sort_order: 30,
          defaults: [true, true, true, false]
        },
        {
          key: 'may_delete_users',
          kind: Permission::KIND_CONDITIONAL,
          title: 'Remover usuários',
          description: 'Permite excluir a conta de OUTRA pessoa. Encerrar a própria conta não depende desta ' \
                       'permissão — é direito do titular, provado por código (BE-014).',
          sort_order: 40,
          defaults: [true, true, false, false]
        },
        {
          key: 'may_modify_public_entries',
          kind: Permission::KIND_CONDITIONAL,
          title: 'Adicionar membros ao projeto',
          description: 'No legado o rótulo era «Modificar dados em Módulos», e o único lugar que a consultava era ' \
                       'a caixa «Adicionar Membro» do detalhe do projeto. É esse efeito que foi portado.',
          sort_order: 50,
          defaults: [true, true, true, false]
        },
        {
          key: 'max_users_amount',
          kind: Permission::KIND_LIMIT,
          title: 'Teto de contas no sistema',
          description: 'Número máximo de contas que podem existir. Criar a conta seguinte responde 422 quando o ' \
                       'total já alcançou o teto. Vazio = sem limite; 0 = nenhuma.',
          sort_order: 60,
          limits: [nil, 9999, 0, 0]
        },
        {
          key: 'max_invitations_amount',
          kind: Permission::KIND_LIMIT,
          title: 'Teto de convites em aberto',
          description: 'Número máximo de convites emitidos por você que podem estar pendentes ao mesmo tempo ' \
                       '(não usados e não expirados). Vazio = sem limite; 0 = nenhum.',
          sort_order: 70,
          limits: [nil, 9999, 50, 0]
        }
      ].freeze

      module_function

      def call!
        CATALOG.each do |attrs|
          permission = upsert_permission!(attrs)
          seed_role_defaults!(permission, attrs)
        end
        Permission.ordered
      end

      # O catálogo em si é do sistema: título, descrição e tipo são sempre
      # reescritos. O que **não** se reescreve é a concessão — isso é o
      # `seed_role_defaults!` abaixo.
      def upsert_permission!(attrs)
        permission = Permission.find_or_initialize_by(key: attrs[:key])
        permission.title = attrs[:title]
        permission.description = attrs[:description]
        permission.sort_order = attrs[:sort_order]
        permission.kind = attrs[:kind]
        permission.is_active = true if permission.new_record?
        permission.save!
        permission
      end

      # **Só cria o que falta.** Se um Admin já mexeu na tela de Permissões, o
      # seed do próximo deploy não pode desfazer — foi o motivo de o legado
      # precisar de `should_update_abilities` e de re-salvar todo mundo.
      def seed_role_defaults!(permission, attrs)
        ROLE_ORDER.each_with_index do |role_name, index|
          user_type = UserType.find_by(name: role_name)
          next if user_type.nil?

          record = UserTypePermission.find_or_initialize_by(user_type_id: user_type.id, permission_id: permission.id)
          next unless record.new_record?

          if permission.limit?
            # Numa permissão de limite o `granted` não decide nada: quem decide é
            # o `limit_value`. Fica `true` para a linha não parecer revogada.
            record.granted = true
            record.limit_value = attrs.fetch(:limits)[index]
          else
            record.granted = attrs.fetch(:defaults)[index]
          end
          record.save!
        end
      end
    end
  end
end
