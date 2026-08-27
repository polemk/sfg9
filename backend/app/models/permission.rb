# frozen_string_literal: true

class Permission < ApplicationRecord
  # Catálogo é lista curta e quase estática; versionar não pesa e mudar o
  # catálogo muda o que todo mundo pode fazer (DEC-59).
  has_paper_trail ignore: %i[updated_at]

  # DEC-108 — o catálogo tem dois tipos, exatamente como o legado tinha
  # (`AbilityFactory.conditional` / `AbilityFactory.limit`): booleano e teto
  # numérico. Um `granted` booleano não guarda "50".
  KIND_CONDITIONAL = 'conditional'
  KIND_LIMIT = 'limit'
  KINDS = [KIND_CONDITIONAL, KIND_LIMIT].freeze

  has_many :user_permissions, dependent: :destroy

  validates :key, presence: true, uniqueness: true
  validates :title, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:sort_order, :created_at) }
  scope :limits, -> { where(kind: KIND_LIMIT) }

  def limit?
    kind == KIND_LIMIT
  end
end
