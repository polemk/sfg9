# frozen_string_literal: true

module Seeds
  module Reference
    # S0 / DB-006, DB-502, BE-504, OPS-507, OPS-541, F.2, F.6
    #
    # Seed de referência **versionado e idempotente** dos 4 papéis do Safegold na
    # escala do ai9 (DEC-41). Rodar duas vezes não duplica, não reescreve papel
    # já atribuído a usuário e não recria os tipos removidos.
    #
    # A escala mora em `UserType::SAFEGOLD_HIERARCHY` — **um** lugar só.
    module UserTypes
      DESCRIPTIONS = {
        UserType::OG => 'OG — super-usuário do fornecedor (Livetat). Não é papel de cliente (DEC-18.1).',
        UserType::ADMIN => 'Administrador do cliente — todos os recursos, limitado por hierarquia inferior',
        UserType::GERENTE => 'Gestor operacional — cadastro e projetos; não alcança Permissões nem o grupo Admin',
        UserType::COLABORADOR => 'Usuário final por projeto — leitura dos catálogos globais e operação dos projetos em que participa'
      }.freeze

      # Tipos que o seed original do ai9 trazia e que o Safegold NÃO usa
      # (DEC-41 parte 2). Não são recriados; se sobrarem de uma base antiga, os
      # usuários que apontam para eles caem em Colaborador — a mesma regra da
      # migration, para que os dois caminhos convirjam no mesmo estado.
      REMOVED = %w[client free visitor].freeze

      module_function

      # **Busca por nome SEM diferenciar maiúscula de minúscula.**
      #
      # Este é o conserto de um seed que se anunciava idempotente e não era. A
      # validação do model é `uniqueness: { case_sensitive: false }`, mas as
      # buscas aqui eram `find_by(name:)` e `where(name:)`, que no Postgres
      # diferenciam. Numa base com `OG` gravado, procurar `og` não achava nada, o
      # `UserType.new` seguia adiante e o `save!` levava as DUAS mensagens de
      # uma vez:
      #
      #     Registro inválido: Name já está em uso, Hierarchy level já está em uso
      #
      # As duas juntas são a assinatura exata deste defeito: o nome bate pela
      # validação insensível, e o nível bate porque a linha que já o ocupa é a
      # mesma que a busca não encontrou.
      #
      # Não é hipótese — o próprio model já convivia com isso: `og?` compara
      # `name.to_s.downcase`, ou seja, sempre soube que a caixa varia.
      def por_nome(nomes)
        UserType.where('LOWER(name) IN (?)', Array(nomes).map(&:downcase))
      end

      def call!(io: nil)
        ActiveRecord::Base.transaction do
          park_removed_levels!
          upsert_roles!
          reassign_users_of_removed_types!(io)
          drop_removed_types!
        end
        por_nome(UserType::SAFEGOLD_HIERARCHY.keys).ordered_by_hierarchy
      end

      # Os níveis 2 e 4 podem estar ocupados por `client`/`free` numa base
      # antiga, e `hierarchy_level` é único. Estacionar fora da faixa útil
      # libera o insert sem apagar nada antes da hora.
      def park_removed_levels!
        por_nome(REMOVED).find_each.with_index do |type, i|
          type.update_columns(hierarchy_level: 9000 + i, updated_at: Time.current)
        end
      end

      def upsert_roles!
        UserType::SAFEGOLD_HIERARCHY.each do |name, level|
          type = por_nome(name).first || UserType.new
          # A caixa é NORMALIZADA de propósito: uma base que tinha `OG` sai
          # daqui com `og`. Deixar como estava manteria o sistema funcionando
          # (as comparações do model são em minúsculas) e manteria também a
          # armadilha, para a próxima pessoa que escrevesse um `find_by`.
          type.name = name
          type.description = DESCRIPTIONS.fetch(name)
          type.hierarchy_level = level
          type.save!
        end
      end

      def reassign_users_of_removed_types!(io = nil)
        removed_ids = por_nome(REMOVED).pluck(:id)
        return if removed_ids.empty?

        fallback = UserType.colaborador
        User.where(user_type_id: removed_ids).find_each do |user|
          # DEC-18.8: nem promovido nem bloqueado em silêncio — sai na lista.
          io&.puts("EXCEÇÃO DEC-18.8: #{user.display_identifier} perdeu o tipo removido → colaborador")
          user.update_columns(user_type_id: fallback.id, updated_at: Time.current)
        end
      end

      def drop_removed_types!
        por_nome(REMOVED).delete_all
      end
    end
  end
end
