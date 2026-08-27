# frozen_string_literal: true

# Permissão padrão de um PAPEL (BE-042). Ver a migration para o porquê da tabela
# e para como ela faz o D-35 desaparecer por construção.
class UserTypePermission < ApplicationRecord
  has_paper_trail ignore: %i[updated_at]

  belongs_to :user_type
  belongs_to :permission

  validates :user_type_id, uniqueness: { scope: :permission_id }

  scope :granted, -> { where(granted: true) }
end
