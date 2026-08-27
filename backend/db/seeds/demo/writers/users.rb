# frozen_string_literal: true

module Demo
  module Writers
    # O elenco de `demo-seed-design.md` §9 — seis usuários que **demonstram a
    # matriz de autorização** (DEC-18) trocando de conta ao vivo.
    #
    # Papéis na escala do ai9 (DEC-41, menor = mais poder): OG=1, Admin=2,
    # Gerente=3, Colaborador=4. O sexto recebe `user_is_readonly`, a única das 17
    # abilities do legado que sobreviveu (DEC-18.6) — mesmos dados, nenhum botão
    # de escrita.
    class Users < Base
      def self.requires = %w[User UserType]

      def call
        ledger.cast.each do |member|
          user_type = ::UserType.find_by(name: member[:role])
          if user_type.nil?
            io.puts "   ⚠ papel `#{member[:role]}` ausente — #{member[:email]} não foi criado"
            next
          end

          user = upsert!(::User, find_by: { email: member[:email] }, attributes: {
                           name: member[:name],
                           phone: member[:phone],
                           user_type_id: user_type.id,
                           provider: nil,
                           provider_uid: nil
                         })

          apply_readonly!(user, member[:readonly])
        end
      end

      private

      # `source: 'manual'` de propósito: é o mesmo par que
      # `PermissionsService.set_user_permission` usa, então desligar a permissão
      # pela tela de Permissões atinge **esta** linha, e não cria uma segunda.
      def apply_readonly!(user, readonly)
        return unless defined?(::Permission) && defined?(::UserPermission)

        permission = ::Permission.find_by(key: 'user_is_readonly')
        return if permission.nil?

        record = ::UserPermission.find_or_initialize_by(
          user_id: user.id, permission_id: permission.id, source: 'manual', source_id: nil
        )
        return if !readonly && record.new_record?

        record.granted_at ||= Time.current
        if readonly
          record.revoked_at = nil
        elsif record.revoked_at.nil?
          # Só revoga o que está concedido. Carimbar `revoked_at = Time.current` a
          # cada execução torna o seed **não idempotente** — a linha muda toda vez,
          # e o `paper_trail` ganha uma versão nova por rodada. Foi assim que a
          # segunda execução apareceu com "1 atualizado".
          record.revoked_at = Time.current
        end

        if record.new_record?
          record.save!
          @created += 1
        elsif record.changed?
          record.save!
          @updated += 1
        else
          @unchanged += 1
        end
      end
    end
  end
end
