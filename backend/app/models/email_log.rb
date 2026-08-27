# frozen_string_literal: true

# DEC-90 — registro de entrega de e-mail com **metadados apenas**.
#
# Não existe atributo de corpo, e isso é a proteção: no legado
# (`livetat_mailer_contacts`) a coluna `message` guardava o corpo de todo envio,
# **inclusive os de credencial**, sem expurgo nenhum. Como no ai9 os 3 e-mails vivos são
# de identidade e o código de acesso **é** a credencial, um log com corpo seria um
# depósito de senhas em texto puro.
#
# Se algum dia alguém precisar "só para depurar", o caminho é o log da aplicação com
# retenção curta — não esta tabela, que por desenho tem retenção de 180 dias
# (`PurgeEmailLogsJob`) e é longa demais para credencial.
class EmailLog < ApplicationRecord
  STATUSES = %w[sent failed].freeze

  belongs_to :user, optional: true

  validates :mailer, :from_email, :to_email, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :failures, -> { where(status: 'failed') }

  # Ponto único de gravação. Nunca recebe corpo — a assinatura não tem onde pôr.
  def self.record!(mailer:, from_email:, to_email:, subject: nil, status: 'sent', error_message: nil, user_id: nil)
    create!(
      mailer: mailer.to_s,
      from_email: from_email.to_s,
      to_email: to_email.to_s,
      subject: subject.to_s.presence,
      status: status.to_s,
      error_message: error_message.to_s.presence,
      user_id: user_id
    )
  rescue StandardError => e
    # O log de entrega nunca derruba a entrega. Se ele falhar, o e-mail já saiu.
    Rails.logger.warn("[EmailLog] falha ao registrar entrega: #{e.class}: #{e.message}")
    nil
  end
end
