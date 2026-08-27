# frozen_string_literal: true

require 'rails_helper'

# S13 / DB-481, DB-596 — o log de e-mail distingue **entregue** de **perdido**.
RSpec.describe LoggedMailDeliveryJob do
  let(:user) { create(:user, email: 'destino@example.com') }

  it 'registra a entrega bem-sucedida com status `sent`' do
    expect { AuthMailer.with(user_id: user.id, code: '123456').magic_login_code.deliver_now }
      .to change(EmailLog, :count).by(1)

    log = EmailLog.last
    expect(log.status).to eq('sent')
    expect(log.to_email).to eq('destino@example.com')
    # DEC-90: metadados, nunca corpo. O código de acesso É a credencial.
    expect(EmailLog.column_names).not_to include('body', 'message')
  end

  it 'registra a FALHA de entrega — ausência de linha seria indistinguível de "ninguém tentou"' do
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
      .and_raise(Net::SMTPServerBusy, 'servidor recusou')

    entrega = lambda do
      described_class.perform_now('AuthMailer', 'magic_login_code', 'deliver_now',
                                  params: { user_id: user.id, code: '123456' }, args: [])
    end

    expect { expect(&entrega).to raise_error(Net::SMTPServerBusy) }
      .to change(EmailLog.failures, :count).by(1)

    log = EmailLog.failures.last
    expect(log.mailer).to eq('AuthMailer#magic_login_code')
    expect(log.error_message).to include('servidor recusou')
  end

  it 'RELANÇA a exceção para o Sidekiq retentar (contrato D-C)' do
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
      .and_raise(Net::SMTPServerBusy, 'servidor recusou')

    # Engolir aqui marcaria o job como concluído: sem retentativa, sem dead set e
    # sem ninguém sabendo — o D-79 do legado, de volta pela porta do e-mail.
    expect do
      described_class.perform_now('AuthMailer', 'magic_login_code', 'deliver_now',
                                  params: { user_id: user.id, code: '123456' }, args: [])
    end.to raise_error(Net::SMTPServerBusy)
  end

  it 'é o job de entrega que o ApplicationMailer usa — senão nada disto roda' do
    expect(ApplicationMailer.delivery_job).to eq(described_class)
    expect(AuthMailer.delivery_job).to eq(described_class)
  end
end
