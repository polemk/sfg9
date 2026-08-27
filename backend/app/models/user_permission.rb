# frozen_string_literal: true

# Override de permissão no nível do USUÁRIO. Ver `Authorization::PermissionResolver`
# para a ordem de resolução.
class UserPermission < ApplicationRecord
  # Trilha de auditoria (DEC-59): conceder e revogar permissão é o ato
  # administrativo que mais importa auditar.
  has_paper_trail ignore: %i[updated_at]

  belongs_to :user
  belongs_to :permission

  validates :source, presence: true
  validates :granted_at, presence: true

  scope :active, -> { where(revoked_at: nil) }
end
