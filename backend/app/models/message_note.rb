# frozen_string_literal: true

# S2 / BE-528 — uma fala na thread da mensagem administrativa.
#
# `user_id` nulo significa **veio do remetente**; preenchido significa **veio do
# administrador**. É por esse nulo, e só por ele, que o legado distingue os dois
# lados da conversa (`note.rb:62-64`) — e é o que a máquina de estados consulta.
class MessageNote < ApplicationRecord
  # **NÃO é versionado** (DEC-59 / DEC-78 #1). A lista de models na trilha de
  # auditoria é deliberada e curta, e vive num lugar só:
  # `Sfg::AuditTrail::VERSIONED`. Mensagem administrativa, fala da thread e
  # observador são **atendimento** — não são auditoria financeira nem de
  # acesso, que são os dois critérios de entrada. O motivo está escrito em
  # `Sfg::AuditTrail::EXCLUDED`, e o spec da trilha reprova quem versionar sem
  # declarar.

  DESCRIPTION_MAX = 500

  belongs_to :admin_message, inverse_of: :notes
  belongs_to :user, optional: true

  # DEC-58 / P-088 — a citação aninhada é portada **sem consumidor de UI**,
  # como no legado. Não há campo, hidden input nem parâmetro que escreva
  # `quoted_note_id`; a coluna, a associação e a resolução de raiz existem para
  # que acrescentar a funcionalidade depois seja aditivo.
  belongs_to :quoted, class_name: 'MessageNote', foreign_key: :quoted_note_id,
                      optional: true, inverse_of: false
  belongs_to :top_parent, class_name: 'MessageNote', foreign_key: :top_parent_quote_id,
                          optional: true, inverse_of: :quotes
  has_many :quotes, class_name: 'MessageNote', foreign_key: :top_parent_quote_id,
                    dependent: :nullify, inverse_of: :top_parent

  validates :description, presence: true, length: { maximum: DESCRIPTION_MAX }
  validates :author_name, presence: true
  validates :author_email, presence: true

  before_save :resolve_top_parent
  after_create :advance_message_state

  scope :roots, -> { where(top_parent_quote_id: nil) }

  # Quem escreveu: `true` = administrador.
  def from_admin?
    user_id.present?
  end

  private

  # `note.rb:16-27`: a raiz da árvore é a raiz do citado, ou o próprio citado
  # quando ele já é raiz. Sem consumidor hoje (ver a nota da associação).
  def resolve_top_parent
    return if quoted_note_id.nil?

    pai = MessageNote.find_by(id: quoted_note_id)
    return if pai.nil?

    self.top_parent_quote_id = pai.top_parent_quote_id || quoted_note_id
  end

  # Transições automáticas 2 e 3 (`note.rb:66-83`), preservadas:
  #  - **1ª resposta do administrador** numa mensagem "Lido" → "Respondido";
  #  - **resposta do remetente** depois de uma fala do administrador → "Aberto".
  def advance_message_state
    m = admin_message
    return if m.nil?

    if from_admin?
      return unless m.state == 'read'
      return unless m.notes.where(user_id: user_id).count == 1

      m.update_columns(state: 'answered', updated_at: Time.current)
    else
      anteriores = m.notes.where.not(id: id).order(:created_at, :id)
      return if anteriores.empty?
      return unless anteriores.last.from_admin?

      m.update_columns(state: 'open', updated_at: Time.current)
    end
  end
end
