# frozen_string_literal: true

# S12 / DB-589, DB-368, BE-355, BE-356 — segundo nível da central de ajuda.
#
# **O slug é coluna, não cálculo** (DB-368). No legado `normalized_title` era
# computado em runtime (`help_category.rb:8-10`) e usado como slug de navegação:
# duas categorias cujos títulos transliteram igual produziam o mesmo slug, e
# renomear uma **quebrava o deep-link da outra**. Aqui o slug nasce na criação,
# é único no banco e **não muda ao renomear** — que é o ponto inteiro de um
# deep-link.
class HelpCategory < ApplicationRecord
  belongs_to :group, class_name: 'HelpGroup', foreign_key: :help_group_id, inverse_of: :categories
  has_many :items, class_name: 'HelpItem', dependent: :destroy, inverse_of: :category

  validates :title, presence: true, length: { maximum: 255 },
                    uniqueness: { scope: :help_group_id, case_sensitive: false,
                                  message: 'já existe neste grupo' }
  validates :slug, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_title
  before_validation :assign_slug, on: :create
  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :title) }

  private

  def normalize_title
    self.title = title.to_s.strip.presence
  end

  # Desambiguação explícita: `duvidas`, `duvidas-2`, `duvidas-3`. O sufixo é
  # numérico e determinístico — nada de `SecureRandom`, senão o slug deixa de
  # ser legível e o deep-link deixa de dizer para onde vai.
  def assign_slug
    return if slug.present?

    base = I18n.transliterate(title.to_s).parameterize.presence || 'categoria'
    candidato = base
    n = 1
    while self.class.where(slug: candidato).exists?
      n += 1
      candidato = "#{base}-#{n}"
    end
    self.slug = candidato
  end

  def assign_position
    return if position.present? && !position.zero?

    self.position = (self.class.where(help_group_id: help_group_id).maximum(:position) || -1) + 1
  end
end
