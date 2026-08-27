# frozen_string_literal: true

# S12 / DB-590, DB-369, BE-352, BE-362 — terceiro nível da central de ajuda.
#
# **Fonte única de conteúdo** (BE-362 / D-58). O legado tinha dois acervos: a
# coluna `help_items.description`, escrita até 04/2019, e a associação
# ActionText usada depois. `has_rich_text` **sobrescreve o leitor da coluna**,
# então nada criado depois de 04/2019 era encontrado por busca de conteúdo — e
# ninguém percebia, porque o item aparecia normalmente na tela. Aqui existe um
# campo só; a coluna não foi recriada, e `Help::LegacyImport` é quem funde os
# dois acervos legados nele.
#
# **Corpo vazio é rejeitado** (BE-352). No legado `validates :description,
# presence: true` **nunca falhava**: `has_rich_text` faz o leitor devolver um
# `ActionText::RichText` recém-construído, que é sempre "presente". A validação
# aqui olha o texto puro.
class HelpItem < ApplicationRecord
  has_rich_text :description

  belongs_to :category, class_name: 'HelpCategory', foreign_key: :help_category_id, inverse_of: :items
  # AUTOR — preservado na edição (FE-366). No legado o `user_id` viajava num
  # campo escondido sempre com o `current_user`, de modo que editar item de
  # outro autor **reescrevia a autoria**.
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  belongs_to :last_updated_user, class_name: 'User', optional: true, inverse_of: false
  has_one :group, through: :category

  validates :title, presence: true, length: { maximum: 255 },
                    uniqueness: { scope: :help_category_id, case_sensitive: false,
                                  message: 'já existe nesta categoria' }
  validate :corpo_nao_pode_ser_vazio

  before_validation :normalize_title
  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :title) }
  scope :with_body, -> { left_joins(:rich_text_description) }

  def description_html
    Contracts::Renderer.html(description)
  end

  def description_text
    Contracts::Renderer.text(description)
  end

  private

  def normalize_title
    self.title = title.to_s.strip.presence
  end

  def assign_position
    return if position.present? && !position.zero?

    self.position = (self.class.where(help_category_id: help_category_id).maximum(:position) || -1) + 1
  end

  def corpo_nao_pode_ser_vazio
    return if description_text.present?

    errors.add(:description, 'não pode ficar em branco')
  end
end
