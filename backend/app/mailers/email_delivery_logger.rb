# frozen_string_literal: true

# DEC-90 — observador de entrega. Grava **metadados, nunca o corpo**.
#
# É um `ActionMailer::Base.register_observer`, e não uma chamada dentro de cada mailer,
# por um motivo específico: mailer novo não precisa lembrar de registrar. O legado
# gravava o log dentro de cada método (`grind_mailer.rb:5-13,27,47,67,85` mais 4 pontos
# no decorator), e cada novo ponto era uma chance de esquecer — ou de gravar demais.
#
# **O que este arquivo NÃO faz, e é o ponto dele:** não toca em `message.body`,
# `message.html_part` nem `message.text_part`. `EmailLog` sequer tem coluna para isso.
# Os 3 e-mails vivos do produto são de identidade e o código de acesso É a credencial
# (DEC-14) — um log com corpo seria um depósito de credenciais em texto puro com
# retenção de 180 dias.
class EmailDeliveryLogger
  def self.delivered_email(message)
    EmailLog.record!(
      mailer: mailer_name(message),
      from_email: Array(message.from).first.to_s,
      to_email: Array(message.to).first.to_s,
      subject: message.subject,
      status: 'sent',
      user_id: recipient_user_id(message)
    )
  rescue StandardError => e
    # Observador nunca derruba a entrega: quando este método roda, o e-mail já saiu.
    Rails.logger.warn("[EmailDeliveryLogger] #{e.class}: #{e.message}")
  end

  # O cabeçalho que o ActionMailer põe em toda mensagem. Cai para 'unknown' em vez de
  # levantar: o log é evidência, e evidência parcial é melhor que evidência ausente.
  def self.mailer_name(message)
    [message['X-Mailer-Class']&.value, message['X-Mailer-Action']&.value].compact.join('#').presence ||
      message['X-Mailer']&.value.presence ||
      'unknown'
  end

  def self.recipient_user_id(message)
    to = Array(message.to).first.to_s
    return nil if to.blank?

    User.where(email: to.downcase).pick(:id)
  rescue StandardError
    nil
  end
end
