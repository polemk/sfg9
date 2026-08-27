# frozen_string_literal: true

# Modelo para códigos de login únicos (magic codes)
# Suporta códigos para email e WhatsApp com expiração de 5 minutos
class LoginCode < ApplicationRecord
  # Associations
  belongs_to :user, optional: true
  # DEC-108 — quem emitiu o convite. Só o caminho de convite
  # (`Auth::InviteService`) preenche; o login normal deixa nulo, e é essa
  # diferença que permite CONTAR convites em aberto para aplicar
  # `max_invitations_amount`.
  belongs_to :invited_by, class_name: 'User', optional: true

  # Validations
  validates :destination, presence: true
  validates :code, presence: true, length: { is: 6 }
  validates :method, inclusion: { in: %w[email whatsapp] }
  validates :expires_at, presence: true

  # Validate destination format based on method
  validate :valid_destination_format
  validate :valid_code_format

  # Callbacks
  before_validation :generate_code, on: :create
  before_validation :set_expires_at, on: :create
  before_save :normalize_destination

  # Scopes
  scope :active, -> { where('expires_at > ?', Time.current).where(used_at: nil) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  scope :used, -> { where.not(used_at: nil) }
  scope :by_destination, ->(dest) { where(destination: normalize_destination_value(dest)) }
  scope :by_method, ->(method) { where(method: method) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_link_token, ->(token) { where(link_token: token) }
  # Convites que ainda contam para o teto: emitidos por alguém, não usados e não
  # expirados. Convite usado ou vencido libera a vaga — o teto é de convites EM
  # ABERTO, não de convites já emitidos na vida.
  scope :pending_invitations, -> { where.not(invited_by_id: nil).active }

  # Métodos de classe
  def self.generate_for(destination, method, user = nil)
    # Limpar códigos antigos não utilizados para este destino
    by_destination(destination).by_method(method).used.destroy_all

    # Criar novo código
    create!(
      destination: destination,
      method: method,
      user: user
    )
  end

  def self.verify_code(destination, method, code)
    active_code = active
                  .by_destination(destination)
                  .by_method(method)
                  .recent
                  .first

    return nil if active_code.nil?

    # Verificar se código corresponde
    return nil unless active_code.matches?(code)

    # Verificar limite de tentativas
    return nil if active_code.attempts >= MAX_ATTEMPTS

    active_code
  end

  def self.cleanup_expired!
    expired.destroy_all
  end

  def self.cleanup_old_used!
    used.where('used_at < ?', 24.hours.ago).destroy_all
  end

  # Teto de tentativas por código. **Um número, um lugar** — estava 3 aqui e 5 no
  # `CodeValidationService`, e o caminho mais permissivo era o que valia na prática.
  MAX_ATTEMPTS = 3

  # Métodos de instância

  # Comparação em **tempo constante**. `==` em String retorna no primeiro byte
  # diferente, e essa diferença é medível pela rede. Num produto sem senha (DEC-14) o
  # código de 6 dígitos é a credencial inteira, então a comparação certa aqui custa uma
  # linha e fecha o canal lateral.
  def matches?(input_code)
    ActiveSupport::SecurityUtils.secure_compare(code.to_s, input_code.to_s.strip)
  end

  def valid_code?
    !expired? && !used? && attempts < MAX_ATTEMPTS
  end

  def expired?
    expires_at <= Time.current
  end

  def used?
    used_at.present?
  end

  def use!
    update!(
      used_at: Time.current,
      attempts: attempts + 1
    )
  end

  def increment_attempts!
    update!(attempts: attempts + 1)
  end

  def time_remaining
    return 0 if expired?

    [(expires_at - Time.current).to_i, 0].max
  end

  def formatted_time_remaining
    minutes = time_remaining / 60
    seconds = time_remaining % 60

    if minutes.positive?
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  def can_resend?
    created_at < 30.seconds.ago
  end

  def time_until_resend
    return 0 if can_resend?

    remaining = 30 - (Time.current - created_at).to_i
    remaining.negative? ? 0 : remaining
  end

  def masked_destination
    self.class.mask_destination(destination, method)
  end

  # Regra de mascaramento de destino, como método de CLASSE.
  #
  # Precisa ser de classe porque o rate limit de `SecurityHelpers#check_rate_limit!`
  # loga o destino bloqueado **antes** de existir um `LoginCode` — não há instância
  # para chamar. Sem isto, bater o teto de envios respondia **500**
  # (`NoMethodError`) em vez de 429, ou seja, a proteção derrubava justamente o
  # caminho que ela deveria proteger com uma resposta limpa.
  #
  # A de instância delega para cá: máscara que diverge é vazamento parcial — basta
  # comparar a resposta de dois endpoints para recuperar mais do endereço do que
  # qualquer um deles pretendia mostrar. Uma regra, um lugar.
  def self.mask_destination(value, method)
    value = value.to_s
    return value if value.blank?

    if method.to_s == 'email'
      username, domain, extra = value.split('@')
      return value if domain.blank? || extra.present?

      prefix = username.length <= 3 ? username[0] : username[0..2]
      "#{prefix}***@#{domain}"
    else # whatsapp
      phone = value.gsub(/[^0-9]/, '')
      return value if phone.length < 4

      "***#{phone[-4..]}"
    end
  end

  def to_log_data
    {
      id: id,
      method: method,
      destination: masked_destination,
      expires_at: expires_at,
      used: used?,
      attempts: attempts
    }
  end

  private

  def generate_code
    self.code ||= rand(100_000..999_999).to_s
  end

  def set_expires_at
    self.expires_at ||= 5.minutes.from_now
  end

  def normalize_destination
    self.destination = self.class.normalize_destination_value(destination)
  end

  def valid_destination_format
    return if destination.blank?

    if method == 'email'
      errors.add(:destination, 'deve ser um email válido') unless destination.match?(URI::MailTo::EMAIL_REGEXP)
    elsif method == 'whatsapp'
      normalized_phone = destination.gsub(/[^0-9]/, '')
      unless normalized_phone.length >= 10 && normalized_phone.length <= 15
        errors.add(:destination, 'deve ser um número de telefone válido (10-15 dígitos)')
      end
    end
  end

  def valid_code_format
    return if code.blank?

    return if code.match?(/\A\d{6}\z/)

    errors.add(:code, 'deve ter 6 dígitos numéricos')
  end

  def self.normalize_destination_value(value)
    return value if value.blank?

    # Para emails, lowercase e trim
    if value.match?(URI::MailTo::EMAIL_REGEXP)
      value.downcase.strip
    else
      # Para telefones, remove caracteres especiais
      value.gsub(/[^0-9]/, '')

    end
  end
end
