# frozen_string_literal: true

# Impede que o ActiveJob logue argumentos sensíveis nos jobs de email.
# Sem isso, códigos de login (magic codes) aparecem em plain text nos logs.
Rails.application.config.after_initialize do
  if defined?(ActionMailer::MailDeliveryJob)
    ActionMailer::MailDeliveryJob.log_arguments = false
  end
end
