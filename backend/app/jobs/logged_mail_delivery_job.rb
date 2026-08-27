# frozen_string_literal: true

# S13 / DB-481, DB-596 — o log de e-mail registra **status de entrega**, não só a
# intenção de enviar.
#
# **O buraco que este arquivo fecha.** O `EmailDeliveryLogger` é um
# `register_observer`, e o `Mail` só chama observador **depois de a entrega dar
# certo**. Ou seja: e-mail entregue vira linha; e-mail que estourou no SMTP vira
# **ausência de linha** — indistinguível de "nunca ninguém tentou mandar". Era
# exatamente o defeito do legado, que gravava `livetat_mailer_contacts` ANTES de
# enfileirar: lá a linha significa "eu quis mandar", e nada no sistema sabe dizer se
# a pessoa recebeu.
#
# Como funciona: o ActionMailer entrega todo `deliver_later` através de um job, e
# qual job é configurável. `ApplicationMailer.delivery_job` aponta para este, que
# envolve a entrega, grava a falha e **relança**.
#
# **O `raise` no fim não é opcional** (contrato D-C). Sem ele o Sidekiq marcaria o
# job como concluído, não haveria retentativa e o e-mail se perderia em silêncio —
# que é o D-79 do legado (`rescue => e` sem relançar em todos os 7 jobs, e um
# `rescue` literalmente vazio em `insert_projects_on_default_user_job.rb:11-12`).
# É a mesma decisão registrada em `design.md` §D1: em job do Safegold, `rescue` só
# existe para enriquecer o log e SEMPRE termina em `raise` — inclusive contra o
# exemplo de `ai9-conventions.md` §3.7, que traz um `rescue` sem `raise` como
# padrão canônico.
class LoggedMailDeliveryJob < ActionMailer::MailDeliveryJob
  rescue_from StandardError do |error|
    record_failure(error)
    raise error
  end

  private

  # Reconstrói o suficiente para a linha de log SEM materializar a mensagem: chamar
  # o mailer de novo aqui poderia disparar consultas — ou outro efeito colateral —
  # justamente no caminho de erro.
  def record_failure(error)
    mailer_class, action, = arguments
    params = arguments.last.is_a?(Hash) ? arguments.last : {}
    recipients = extract_recipients(params)

    EmailLog.record!(
      mailer: "#{mailer_class}##{action}",
      from_email: ENV.fetch('MAILER_FROM', 'no-reply@safegold.com.br'),
      to_email: recipients.presence || 'desconhecido',
      subject: nil,
      status: 'failed',
      error_message: "#{error.class}: #{error.message}"
    )
  rescue StandardError => e
    # O log da falha não pode virar uma segunda falha que engole a primeira.
    Rails.logger.warn("[LoggedMailDeliveryJob] falha ao registrar falha: #{e.class}: #{e.message}")
  end

  # `deliver_later` embala os argumentos do mailer; o destinatário pode estar num
  # `params:` (mailer com `with`) ou nos argumentos posicionais. Tenta os dois e
  # cai para vazio — evidência parcial é melhor que evidência nenhuma.
  def extract_recipients(params)
    candidates = []
    candidates << params[:params] if params.is_a?(Hash)
    candidates << params[:args] if params.is_a?(Hash)
    candidates << arguments

    emails = candidates.flatten.filter_map do |value|
      case value
      when String then value if value.include?('@')
      when Hash then value.values.find { |v| v.is_a?(String) && v.include?('@') }
      when User then value.email
      end
    end

    emails.first.to_s
  end
end
