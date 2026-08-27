# frozen_string_literal: true

# S2 / BE-529 — quem recebe e-mail quando chega mensagem administrativa.
#
# `is_extern` **não existe aqui**: era campo morto no legado (defaultado em
# `set_defaults` e fora do `permit`). O único predicado avaliado de verdade é
# `is_internal` — observador não interno não recebe mensagem marcada como
# interna (`notification.rb:38`).
class Observer < ApplicationRecord
  # **NÃO é versionado** (DEC-59 / DEC-78 #1). A lista de models na trilha de
  # auditoria é deliberada e curta, e vive num lugar só:
  # `Sfg::AuditTrail::VERSIONED`. Mensagem administrativa, fala da thread e
  # observador são **atendimento** — não são auditoria financeira nem de
  # acesso, que são os dois critérios de entrada. O motivo está escrito em
  # `Sfg::AuditTrail::EXCLUDED`, e o spec da trilha reprova quem versionar sem
  # declarar.

  belongs_to :user
  belongs_to :last_updated_user, class_name: 'User', optional: true
  has_many :observer_contexts, dependent: :destroy, inverse_of: :observer

  validates :name, presence: true
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: 'possui formato inválido' },
                    uniqueness: { case_sensitive: false }
  # Observador sem contexto nenhum nunca recebe nada — é cadastro que parece
  # feito e não faz efeito. O legado já barrava isto no controller
  # (`observers_controller.rb:16`); aqui é regra do model, e vale para qualquer
  # caminho de escrita.
  validate :ao_menos_um_contexto

  before_validation :normalize_email

  def contexts
    observer_contexts.map(&:context)
  end

  # Substitui a lista de contextos de uma vez. A duplicata é barrada pelo
  # **índice único** `(observer_id, context)` — no legado era um `SELECT COUNT`
  # a cada save, e duas requisições concorrentes passavam as duas.
  def contexts=(list)
    desejados = Array(list).map(&:to_s).uniq & AdminMessage::CONTEXTS.keys
    if persisted?
      observer_contexts.where.not(context: desejados).destroy_all
      atuais = observer_contexts.reload.map(&:context)
      (desejados - atuais).each { |c| observer_contexts.create!(context: c) }
    else
      observer_contexts.clear
      desejados.each { |c| observer_contexts.build(context: c) }
    end
  end

  # Os observadores que devem ser notificados de uma mensagem.
  def self.for_message(admin_message)
    escopo = joins(:observer_contexts).where(observer_contexts: { context: admin_message.context })
    escopo = escopo.where(is_internal: true) if admin_message.is_internal?
    escopo.distinct
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def ao_menos_um_contexto
    return if observer_contexts.reject(&:marked_for_destruction?).any?

    errors.add(:contexts, 'deve ter ao menos um selecionado')
  end
end
