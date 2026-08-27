# frozen_string_literal: true

# S2 / BE-526, BE-527, BE-531 — a **mensagem administrativa** (ticket).
#
# A engine `feedback19` **não vira engine** (DC-12): vira código do app. O que
# era `Livetat::Feedback19::Message` mora aqui, com o esquema corrigido pela
# migration e com duas armadilhas de origem mortas:
#
#  - `Feedback19::State`/`Context` resolviam registros em **variável de classe na
#    carga da classe** (`state.rb:6-13`). Um processo que subisse antes do seed
#    guardava `nil` para sempre, e um seed novo nunca era visto. Aqui as
#    situações e os contextos são **constantes**, não consulta.
#  - a unicidade dos tokens era um `loop` com `SELECT`
#    (`message.rb:150-168`). Aqui é índice único no banco, e a geração não
#    precisa conferir nada.
class AdminMessage < ApplicationRecord
  # **NÃO é versionado** (DEC-59 / DEC-78 #1). A lista de models na trilha de
  # auditoria é deliberada e curta, e vive num lugar só:
  # `Sfg::AuditTrail::VERSIONED`. Mensagem administrativa, fala da thread e
  # observador são **atendimento** — não são auditoria financeira nem de
  # acesso, que são os dois critérios de entrada. O motivo está escrito em
  # `Sfg::AuditTrail::EXCLUDED`, e o spec da trilha reprova quem versionar sem
  # declarar.

  # As 8 situações. A chave é estável (banco/API); o rótulo é pt-BR (tela).
  STATES = {
    'unread' => 'Não lido',
    'read' => 'Lido',
    'open' => 'Aberto',
    'evaluated' => 'Avaliado',
    'answered' => 'Respondido',
    'done' => 'Concluído',
    'closed' => 'Fechado',
    'rejected' => 'Rejeitado'
  }.freeze

  # Os 4 contextos.
  CONTEXTS = {
    'other' => 'Outros',
    'problem' => 'Problema',
    'contact' => 'Contato',
    'suggestion' => 'Sugestão'
  }.freeze

  # Situações que encerram a conversa (`message.rb:102-104`).
  TERMINAL_STATES = %w[done closed rejected].freeze

  MESSAGE_MAX = 500

  belongs_to :user, optional: true
  has_many :notes, -> { order(:created_at, :id) },
           class_name: 'MessageNote', dependent: :destroy, inverse_of: :admin_message

  validates :sender_name, presence: true, length: { in: 3..40 }
  validates :sender_email, presence: true,
                           format: { with: URI::MailTo::EMAIL_REGEXP, message: 'possui formato inválido' }
  validates :message, presence: true, length: { maximum: MESSAGE_MAX }
  validates :state, inclusion: { in: STATES.keys }
  validates :context, inclusion: { in: CONTEXTS.keys }
  validates :extra1_value, presence: true, if: :extra1_enabled?
  validates :extra2_value, presence: true, if: :extra2_enabled?

  before_validation :ensure_tokens
  after_create_commit :create_first_note

  scope :with_state, ->(state) { where(state: state) }
  scope :with_context, ->(context) { where(context: context) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :search, lambda { |term|
    next all if term.blank?

    like = "%#{term.to_s.strip.downcase}%"
    where('LOWER(sender_name) LIKE :q OR LOWER(sender_email) LIKE :q OR LOWER(message) LIKE :q', q: like)
  }

  def state_label
    STATES[state]
  end

  def context_label
    CONTEXTS[context]
  end

  def terminal?
    TERMINAL_STATES.include?(state)
  end

  def unread_notes_count
    notes.where(unread: true).count
  end

  # Transição automática 1 (`message.rb:106-115`): o administrador ABRE uma
  # mensagem "Não lido" e ela passa a "Lido" — mas só enquanto ele ainda não
  # respondeu nada nela.
  def mark_opened_by(admin)
    return if admin.nil?
    return unless state == 'unread'
    return if notes.where(user_id: admin.id).exists?

    update!(state: 'read', user_id: admin.id)
  end

  # Marca como lidas as notas do **outro lado** da conversa
  # (`message.rb:117-133`): quem lê é administrador → lê o que veio do
  # remetente (`user_id` nulo), e vice-versa.
  def mark_notes_read_for(admin)
    alvo = admin.present? ? notes.where(user_id: nil) : notes.where.not(user_id: nil)
    alvo.where(unread: true).update_all(unread: false, updated_at: Time.current)
  end

  private

  def ensure_tokens
    self.public_token ||= SecureRandom.uuid
    self.private_token ||= SecureRandom.uuid
  end

  # A conversa começa com a fala do remetente (`message.rb:83-96`): sem esta
  # nota, a tela de thread abre vazia e o corpo da mensagem some da timeline.
  def create_first_note
    return if notes.exists?

    notes.create!(
      description: message,
      author_name: sender_name,
      author_email: sender_email,
      user_id: nil,
      unread: true
    )
  end
end
