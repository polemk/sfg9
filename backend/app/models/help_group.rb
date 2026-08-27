# frozen_string_literal: true

# S12 / DB-588, DB-367, BE-358 — primeiro nível da central de ajuda.
#
# `user_id` **não existe aqui** (BE-358): o `permit` do legado
# (`help_groups_controller.rb`) aceitava `:user_id` numa tabela que **não tem a
# coluna** — um formulário que a enviasse causaria `UnknownAttributeError`. Não
# se porta um campo cuja única possibilidade é falhar.
class HelpGroup < ApplicationRecord
  has_many :categories, class_name: 'HelpCategory', dependent: :destroy, inverse_of: :group
  has_many :items, through: :categories

  validates :title, presence: true, length: { maximum: 255 },
                    uniqueness: { case_sensitive: false }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_title
  before_validation :assign_position, on: :create

  # Ordem **persistida** (DB-367). O legado ordenava por `title ASC` na view:
  # renomear um grupo reordenava o menu inteiro sem ninguém pedir.
  scope :ordered, -> { order(:position, :title) }

  private

  def normalize_title
    self.title = title.to_s.strip.presence
  end

  def assign_position
    self.position = (self.class.maximum(:position) || -1) + 1 if position.blank? || position.zero?
  end
end
