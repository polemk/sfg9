# frozen_string_literal: true

class PolemkInstance < ApplicationRecord
  has_many :polemk_webhooks, dependent: :destroy

  validates :display_name, presence: true
  validates :instance_name, presence: true
  validates :instance_id, presence: true, uniqueness: true
  validates :api_key, presence: true

  # Status de conexão válidos
  CONNECTION_STATUSES = %w[
    unknown
    connecting
    connected
    disconnected
    waiting_qr
  ].freeze

  validates :connection_status, inclusion: { in: CONNECTION_STATUSES }

  # Scopes para facilitar consultas
  scope :connected, -> { where(connection_status: 'connected') }
  scope :disconnected, -> { where(connection_status: 'disconnected') }
  scope :waiting_qr, -> { where(connection_status: 'waiting_qr') }

  # O nome do stream de Action Cable desta instância — **uma fonte só**.
  #
  # O canal e o serviço derivavam o nome cada um por conta própria, e cada um
  # usava DUAS chaves (`instance_id` da Evolution e o `id` da linha): o canal
  # assinava as duas e o serviço transmitia para as duas, então **todo evento
  # chegava em dobro**. Era inofensivo enquanto a tela fosse idempotente — e
  # deixa de ser no dia em que alguém contar eventos, animar uma transição ou
  # incrementar algo no `received`.
  #
  # A chave é o `id` da linha: `uuid`, estável, e nosso. O `instance_id` vem da
  # Evolution e muda se a instância for recriada lá.
  def cable_stream
    self.class.cable_stream_for(id)
  end

  def self.cable_stream_for(record_id)
    "whatsapp_instance_#{record_id}"
  end

  # Aceita o `id` da linha OU o `instance_id` da Evolution — a tela manda um dos
  # dois conforme de onde veio. Resolver aqui é o que permite o stream ser único.
  def self.find_for_cable(key)
    return nil if key.blank?

    find_by(instance_id: key) || find_by(id: key)
  rescue ActiveRecord::StatementInvalid
    # `key` que não é uuid válido faz o Postgres levantar no `find_by(id:)`.
    nil
  end

  def self.normalize_instance_name(display_name)
    return unless display_name.present?

    I18n.transliterate(display_name)
                             .gsub(/[^\w\s-]/, '')
                             .gsub(/[\s-]+/, '_')
                             .upcase
  end

  # Verifica se a instância está conectada
  def connected?
    connection_status == 'connected'
  end

  # Verifica se está aguardando QR Code
  def waiting_qr?
    connection_status == 'waiting_qr'
  end

  # Verifica se o QR Code está expirado
  def qr_code_expired?
    return true if qr_expires_at.nil?

    Time.current > qr_expires_at
  end

  # Retorna o tempo restante do QR Code em segundos
  def qr_code_time_remaining
    return 0 if qr_expires_at.nil?

    remaining = (qr_expires_at - Time.current).to_i
    [remaining, 0].max
  end

  # Limpa dados sensíveis após logout
  def clear_connection_data
    update_columns(
      qr_code: nil,
      qr_expires_at: nil,
      qr_session: nil,
      last_qr_generated_at: nil,
      connection_data: nil
    )
  end

  def restart_instance
    EvolutionConnection.restart_instance
  end
end
