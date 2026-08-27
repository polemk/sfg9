require 'rails_helper'

RSpec.describe Auth::EmailService, type: :service do
  let!(:user) { create(:user, email: 'test@example.com') }
  let(:code) { '123456' }
  let(:service) { described_class.new(user: user, code: code) }

  describe '#send_magic_login_code' do
    it 'sends the email via AuthMailer' do
      # Expect mailer call
      mailer = instance_double('ActionMailer::MessageDelivery')
      
      expect(AuthMailer).to receive(:with).with(user_id: user.id, code: code).and_return(double(magic_login_code: mailer))
      expect(mailer).to receive(:deliver_later)
      
      res = service.send_magic_login_code
      expect(res[:success]).to be true
    end

    it 'returns validation error if user missing' do
      invalid_service = described_class.new(code: '123')
      res = invalid_service.send_magic_login_code
      expect(res[:success]).to be false
      expect(res[:error]).to include('Dados inválidos')
    end
  end

  # Tarefa 6.3 — os e-mails vivos são **templates ERB**, nunca concatenação de string
  # dentro do Ruby. `build_magic_login_email_body` e `build_welcome_email_body`
  # montavam HTML em heredoc aqui dentro; foram removidos, e com eles o
  # `send_welcome_email`, que só escrevia no log e nunca enviou nada.
  describe 'corpo do e-mail' do
    it 'não monta HTML dentro do Ruby' do
      expect(described_class.private_instance_methods).not_to include(:build_magic_login_email_body)
      expect(described_class.private_instance_methods).not_to include(:build_welcome_email_body)
      expect(described_class.instance_methods).not_to include(:send_welcome_email)
    end

    it 'tem versão .text.erb ao lado de cada .html.erb' do
      %w[magic_login_code magic_link invite].each do |template|
        expect(File).to exist(Rails.root.join("app/views/auth_mailer/#{template}.html.erb"))
        expect(File).to exist(Rails.root.join("app/views/auth_mailer/#{template}.text.erb"))
      end
    end
  end

  # BE-012 / OPS-001 / D-38 — o convite carrega magic link, nunca senha.
  describe '#send_invite' do
    it 'envia o convite com o magic link' do
      mailer = instance_double('ActionMailer::MessageDelivery')
      expect(AuthMailer).to receive(:with).and_return(double(invite: mailer))
      expect(mailer).to receive(:deliver_later)

      res = described_class.new(user: user).send_invite(magic_url: 'https://app.test/magic-login?token=abc')
      expect(res[:success]).to be true
    end

    it 'recusa convidar quem não tem e-mail' do
      phone_only = create(:user, email: nil, phone: '5511977776666')
      res = described_class.new(user: phone_only).send_invite(magic_url: 'https://app.test/x')
      expect(res[:success]).to be false
    end
  end
end
