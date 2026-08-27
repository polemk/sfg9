# frozen_string_literal: true

# S0 / BE-041, BE-042, BE-018, BE-520, OPS-086 — catálogo e concessão de permissão.
#
# Permissão é **consulta**, nunca cópia (ver `Authorization::PermissionResolver`).
# Este serviço só escreve: concede e revoga, sempre com trava de hierarquia e
# sempre gravando na trilha.
#
# **A trilha** é o `paper_trail` (DEC-59): `UserTypePermission` e `UserPermission`
# são versionados, `whodunnit` é o usuário REAL (`true_user` na impersonação) e o
# motivo vai em `versions.reason`. Não existe `AuditEvent` e
# `permission_audit_logs` continua sem produtor — decisão DS0-1 revista pelo
# DEC-59.
class PermissionsService
  class << self
    include ApiResponseHandler

    def catalog
      success_response({ permissions: Permission.active.ordered.map { |p| serialize_permission(p) } }, 200)
    end

    # Permissões de um PAPEL, com o default de cada chave.
    #
    # BE-041: a autorização usa o **usuário real** (`true_user`), nunca o
    # personificado — senão o OG personificando um Colaborador perderia a tela, e
    # pior, um Colaborador personificado herdaria a leitura do OG.
    def for_user_type(actor:, user_type:)
      unless Authorization::Hierarchy.can_view_user_type?(actor, user_type)
        return forbidden('Papel fora do seu alcance de hierarquia.', code: 'HIERARCHY_LOCKED')
      end

      rows = UserTypePermission.where(user_type_id: user_type.id).index_by(&:permission_id)

      success_response({
                         user_type: { id: user_type.id, name: user_type.name,
                                      hierarchy_level: user_type.hierarchy_level },
                         editable: Authorization::Hierarchy.can_edit_user_type?(actor, user_type),
                         permissions: Permission.active.ordered.map do |p|
                           row = rows[p.id]
                           serialize_permission(p).merge(
                             granted: row.present? && row.granted?,
                             # DEC-108 — a tela precisa do NÚMERO para a permissão de
                             # limite. `nil` é "sem limite", e é diferente de `0`.
                             limit_value: p.limit? ? row&.limit_value : nil
                           )
                         end
                       }, 200)
    end

    # `PUT /api/v1/user_types/:id/permissions/:key` — DEC-18.2.
    #
    # A trava: o ator só edita papéis de hierarquia **inferior** à sua. OG
    # alcança todos, inclusive o próprio OG; Admin nunca alcança OG nem outro
    # Admin (lateral) nem a si mesmo; Gerente nem chega aqui (a matriz nega).
    #
    # **DEC-108 — duas formas de chamada, uma rota.** Para uma permissão
    # `conditional` o que manda é `granted`; para uma `limit`
    # (`max_users_amount`, `max_invitations_amount`) o que manda é `limit_value`,
    # e `granted` fica `true` porque numa permissão de teto ele não decide nada.
    # `limit_value` nulo é **sem limite**, e é diferente de `0`.
    def set_user_type_permission(actor:, user_type:, key:, granted: nil, limit_value: :unset, reason: nil)
      unless Authorization::Hierarchy.can_edit_user_type?(actor, user_type)
        return forbidden('Você não pode editar permissões deste papel.', code: 'HIERARCHY_LOCKED')
      end

      permission = Permission.active.find_by(key: key)
      return not_found_response('Permissão', genero: :feminino) if permission.nil?

      if permission.limit?
        return validation_error_response('Informe `limit_value` para uma permissão de limite.') if limit_value == :unset
        if limit_value.present? && limit_value.to_i.negative?
          return validation_error_response('O teto não pode ser negativo.')
        end
      elsif granted.nil?
        return validation_error_response('Informe `granted` para uma permissão condicional.')
      end

      granted = true if permission.limit?

      with_audit_reason(reason) do
        record = UserTypePermission.find_or_initialize_by(user_type_id: user_type.id, permission_id: permission.id)
        record.granted = granted
        record.limit_value = normalize_limit(limit_value) if permission.limit?
        record.save!
      end

      # FE-027 / IMP-A18 — **a mudança passa a ter efeito imediato na tela.**
      #
      # No legado, revogar uma permissão só aparecia depois que a pessoa recarregava:
      # a tela mantinha o botão que ela não podia mais usar, e o servidor recusava
      # quando ela clicasse. O aviso vai para cada usuário do papel e o React Query
      # refaz a leitura — Princípio 10, sem `setInterval`.
      #
      # Emitido **fora** do `with_audit_reason` e depois do `save!`: um broadcast
      # dentro da transação chegaria ao cliente antes do COMMIT, e a releitura
      # devolveria o valor antigo.
      notify_user_type(user_type.id, permission.key, granted)

      success_response({
                         user_type_id: user_type.id,
                         key: permission.key,
                         granted: granted,
                         limit_value: permission.limit? ? normalize_limit(limit_value) : nil
                       }, 200)
    end

    # `PUT /api/v1/users/:id/permissions/:key` — BE-018.
    #
    # **O `:id` do usuário PASSA A MANDAR.** No legado, `permissions_controller.rb:55-57`
    # descartava o `:id` e alcançava qualquer linha de `Ability` — o **D-34**, o
    # vetor mais direto de escalação de privilégio. Aqui o alvo é carregado,
    # a hierarquia é checada contra o papel DELE, e nada mais é alcançável.
    def set_user_permission(actor:, target_user:, key:, granted: nil, limit_value: :unset, reason: nil)
      return not_found_response('Usuário') if target_user.nil?

      unless Authorization::Hierarchy.can_edit_user_permissions?(actor, target_user)
        return forbidden('Você não pode editar permissões deste usuário.', code: 'HIERARCHY_LOCKED')
      end

      permission = Permission.active.find_by(key: key)
      return not_found_response('Permissão', genero: :feminino) if permission.nil?

      if permission.limit?
        return validation_error_response('Informe `limit_value` para uma permissão de limite.') if limit_value == :unset
        if limit_value.present? && limit_value.to_i.negative?
          return validation_error_response('O teto não pode ser negativo.')
        end

        # DEC-108 — no override de USUÁRIO o teto é a exceção nominal: gravar
        # `limit_value` vazio não é "sem limite", é **remover o override** e
        # voltar a valer o do papel. Sem isso não haveria como desfazer a exceção.
        granted = normalize_limit(limit_value).present?
      elsif granted.nil?
        return validation_error_response('Informe `granted` para uma permissão condicional.')
      end

      with_audit_reason(reason) do
        record = UserPermission.find_or_initialize_by(
          user_id: target_user.id, permission_id: permission.id, source: 'manual', source_id: nil
        )
        record.limit_value = normalize_limit(limit_value) if permission.limit?
        if granted
          record.granted_at = Time.current
          record.revoked_at = nil
        else
          record.granted_at ||= Time.current
          record.revoked_at = Time.current
        end
        record.save!
      end

      notify_user(target_user.id, permission.key, granted)

      success_response({
                         user_id: target_user.id,
                         key: permission.key,
                         granted: granted,
                         effective: Authorization::PermissionResolver.new(target_user.reload).granted?(permission.key)
                       }, 200)
    end

    def for_user(target_user:)
      resolver = Authorization::PermissionResolver.new(target_user)
      success_response({
                         user_id: target_user.id,
                         permissions: Permission.active.ordered.map do |p|
                           serialize_permission(p).merge(
                             granted: resolver.granted?(p.key),
                             # DEC-108 — o teto EFETIVO da pessoa: override dela se
                             # houver, senão o do papel. `nil` = sem limite.
                             limit_value: p.limit? ? resolver.limit_for(p.key) : nil
                           )
                         end
                       }, 200)
    end

    private

    # Aviso pelo Action Cable. **Nunca derruba a escrita**: a permissão já foi
    # gravada e auditada quando este método roda; um Redis fora do ar não pode
    # transformar uma concessão bem-sucedida em erro 500 para quem clicou.
    def notify_user(user_id, key, granted)
      PermissionsChannel.publish_changed(user_id, key: key, granted: granted)
    rescue StandardError => e
      Rails.logger.warn("[PermissionsService] broadcast falhou: #{e.class}: #{e.message}")
    end

    def notify_user_type(user_type_id, key, granted)
      PermissionsChannel.publish_user_type_changed(user_type_id, key: key, granted: granted)
    rescue StandardError => e
      Rails.logger.warn("[PermissionsService] broadcast falhou: #{e.class}: #{e.message}")
    end

    # `versions.reason` só é preenchido dentro deste bloco — o motivo pertence ao
    # ato, não à sessão inteira.
    def with_audit_reason(reason)
      previous = PaperTrail.request.controller_info || {}
      PaperTrail.request.controller_info = previous.merge(reason: reason.presence)
      yield
    ensure
      PaperTrail.request.controller_info = previous
    end

    def serialize_permission(permission)
      { id: permission.id, key: permission.key, title: permission.title,
        description: permission.description, sort_order: permission.sort_order,
        # DEC-108 — a tela renderiza toggle ou campo numérico a partir daqui. Não
        # há lista escrita no cliente: o tipo vem do servidor junto com a chave.
        kind: permission.kind }
    end

    # `""` e `nil` viram `nil` (sem limite / sem override); qualquer outra coisa
    # vira inteiro. `:unset` só chega em permissão condicional, onde é ignorado.
    def normalize_limit(value)
      return nil if value == :unset || value.nil? || value.to_s.strip.empty?

      value.to_i
    end

    def forbidden(message, code: 'FORBIDDEN')
      error_response(message, 403, details: { code: code })
    end
  end
end
