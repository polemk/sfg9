# frozen_string_literal: true

module Authorization
  # S0 / BE-042, BE-748 — permissão é **CONSULTA**, nunca cópia.
  #
  # Resolução, nesta ordem:
  #   1. default do papel — `user_type_permissions` (`granted` booleano);
  #   2. override do usuário — `user_permissions` com `revoked_at IS NULL`.
  #
  # É por resolver a cada request que o **D-35 desaparece por construção**: no
  # legado a `Role` clonava as 17 abilities no momento da atribuição, então
  # alterar a permissão do papel não alcançava quem já existia. Aqui não há o que
  # alcançar — não existe cópia.
  #
  # **Sem `define_method`, sem metaprogramação em runtime** (BE-748): o legado
  # gerava um método por ability a cada instanciação de `AbilityFactory`.
  #
  # Memoização: só **dentro da requisição**. Uma instância por request; nada é
  # gravado no usuário nem em cache entre requests — senão a revogação demoraria
  # a valer, que é exatamente o defeito que se está fechando.
  #
  # **Limite conhecido e deliberado:** o override do usuário só CONCEDE; não há
  # "negar para este usuário o que o papel concede". Se algum dia precisar, o
  # lugar de resolvê-lo é aqui, com um terceiro estado explícito — não com uma
  # segunda tabela.
  #
  # **DEC-108 — o catálogo tem 7 chaves, e duas delas são LIMITE.** As
  # condicionais respondem por `granted?`; `max_users_amount` e
  # `max_invitations_amount` respondem por `limit_for` / `limit_exceeded?`,
  # porque um booleano não guarda "50".
  class PermissionResolver
    def initialize(user)
      @user = user
      @cache = {}
    end

    def granted?(key)
      return false if @user.nil?

      @cache.fetch(key.to_s) do
        @cache[key.to_s] = user_override?(key) || role_default?(key)
      end
    end

    # Todas as chaves ativas do usuário. Uma consulta por fonte, sem N+1.
    def keys
      @keys ||= (role_default_keys + user_override_keys).uniq.sort
    end

    def readonly?
      granted?('user_is_readonly')
    end

    # DEC-108 — o teto de uma permissão do tipo `limit`.
    #
    # Devolve um `Integer` ou `nil`, e os dois significam coisas **diferentes**:
    #
    #  - `nil` = **sem limite** (é o que o OG tem, ver o seed de referência);
    #  - `0`   = **nenhum permitido** (é o que o legado dá ao Gerente e ao
    #    Colaborador em `max_users_amount`, `db/seeds.rb:79,94`).
    #
    # Quem consome tem de distinguir os dois — tratar `nil` como zero trancaria
    # justamente o papel que não deveria ter teto. A ordem de resolução é a
    # mesma das condicionais: override do usuário primeiro, default do papel
    # depois.
    def limit_for(key)
      @limits ||= {}
      return @limits[key.to_s] if @limits.key?(key.to_s)

      @limits[key.to_s] = user_override_limit(key) || role_default_limit(key)
    end

    # `true` quando `contagem` já alcançou (ou passou) o teto — ou seja, quando
    # a próxima criação deve ser recusada. Sem teto, nunca estoura.
    def limit_exceeded?(key, count)
      limit = limit_for(key)
      return false if limit.nil?

      count >= limit
    end

    private

    def user_override_limit(key)
      return nil if @user.nil?

      UserPermission.active
                    .joins(:permission)
                    .where(user_id: @user.id, permissions: { key: key.to_s, is_active: true })
                    .where.not(limit_value: nil)
                    .pick(:limit_value)
    end

    def role_default_limit(key)
      return nil if @user&.user_type_id.blank?

      UserTypePermission.where(user_type_id: @user.user_type_id)
                        .joins(:permission)
                        .where(permissions: { key: key.to_s, is_active: true })
                        .pick(:limit_value)
    end

    def user_override?(key)
      UserPermission.active
                    .joins(:permission)
                    .where(user_id: @user.id, permissions: { key: key.to_s, is_active: true })
                    .exists?
    end

    def role_default?(key)
      return false if @user.user_type_id.blank?

      UserTypePermission.granted
                        .joins(:permission)
                        .where(user_type_id: @user.user_type_id, permissions: { key: key.to_s, is_active: true })
                        .exists?
    end

    def user_override_keys
      UserPermission.active
                    .joins(:permission)
                    .where(user_id: @user.id, permissions: { is_active: true })
                    .pluck('permissions.key')
    end

    def role_default_keys
      return [] if @user.user_type_id.blank?

      UserTypePermission.granted
                        .joins(:permission)
                        .where(user_type_id: @user.user_type_id, permissions: { is_active: true })
                        .pluck('permissions.key')
    end
  end
end
