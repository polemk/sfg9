require 'rails_helper'

RSpec.describe Auth::MagicLoginService, type: :service do
  let(:email) { 'test@example.com' }
  let(:phone) { '5511999999999' }
  let(:ip) { '127.0.0.1' }
  let(:user_agent) { 'Test' }
  let(:user) { create(:user, email: email, phone: phone) }

  describe '#execute!' do
    context 'via email' do
      let(:service) { described_class.new(identifier: email, method: 'email', ip_address: ip, user_agent: user_agent) }

      before { user } # ensure user exists

      it 'sends code via email' do
        expect_any_instance_of(Auth::EmailService).to receive(:send_magic_login_code)
        res = service.execute!
        expect(res[:success]).to be true
        expect(res[:data][:message]).to include('email')
      end
    end

    context 'via whatsapp' do
      let(:service) { described_class.new(identifier: phone, method: 'whatsapp', ip_address: ip, user_agent: user_agent) }

      before { user }

      it 'sends code via whatsapp' do
        expect(EvolutionConnection).to receive(:send_message)
        res = service.execute!
        expect(res[:success]).to be true
        expect(res[:data][:message]).to include('WhatsApp')
      end
    end

    # **Não enumeramos contas.** Destino desconhecido recebe a MESMA resposta de
    # destino conhecido, e nada é enviado. Antes o serviço respondia "Usuário não
    # encontrado", e a tela de login virava um verificador de "esta pessoa é cliente do
    # Safegold?" — num produto de crédito isso é informação de negócio, não só de
    # segurança.
    context 'destino desconhecido' do
      let(:service) { described_class.new(identifier: 'ninguem@example.com', method: 'email', ip_address: ip, user_agent: user_agent) }

      it 'responde como sucesso e não envia nada' do
        expect(Auth::EmailService).not_to receive(:new)
        res = service.execute!
        expect(res[:success]).to be true
        expect(res[:data][:destination]).to eq(LoginCode.mask_destination('ninguem@example.com', 'email'))
      end

      it 'não cria código nenhum' do
        expect { service.execute! }.not_to change(LoginCode, :count)
      end
    end

    context 'conta bloqueada' do
      let!(:blocked) { create(:user, email: 'blocked@example.com').tap { |u| u.block!(reason: 'desligado') } }
      let(:service) { described_class.new(identifier: 'blocked@example.com', method: 'email', ip_address: ip, user_agent: user_agent) }

      it 'não envia código e não vaza o bloqueio no pedido' do
        expect { service.execute! }.not_to change(LoginCode, :count)
        res = service.execute!
        expect(res[:success]).to be true
        expect(res[:data].to_s).not_to include('bloque')
      end
    end

    # DEC-45 — `username` IDENTIFICA, e o código sai pelo e-mail do cadastro.
    context 'identificador é um username' do
      let!(:user) { create(:user, email: 'maria@example.com', username: 'maria.souza') }
      let(:service) { described_class.new(identifier: 'maria.souza', method: 'email', ip_address: ip, user_agent: user_agent) }

      it 'emite o código para o e-mail do cadastro, não para o username' do
        allow_any_instance_of(Auth::EmailService).to receive(:send_magic_login_code).and_return({ success: true })
        res = service.execute!
        expect(res[:success]).to be true
        expect(LoginCode.last.destination).to eq('maria@example.com')
        expect(LoginCode.last.user_id).to eq(user.id)
      end
    end

    # O caso que o dry-run do P-049 tem de contar: `username` sem e-mail nem telefone.
    context 'usuário com username e sem canal de envio' do
      let!(:user) do
        u = create(:user, email: 'semcanal@example.com', username: 'sem.canal')
        # Contorna a validação de presença: é exatamente o estado que o ETL pode trazer.
        u.update_column(:email, nil)
        u
      end
      let(:service) { described_class.new(identifier: 'sem.canal', method: 'email', ip_address: ip, user_agent: user_agent) }

      it 'explica que não há destino, em vez de fingir que enviou' do
        res = service.execute!
        expect(res[:success]).to be false
        expect(res[:error]).to include('não tem e-mail cadastrado')
      end
    end

    # `SecureRandom`, não `Kernel#rand`: o código é a credencial inteira num produto
    # sem senha, e o Mersenne Twister é previsível a partir de algumas amostras.
    context 'geração do código' do
      let!(:user) { create(:user, email: 'rng@example.com') }
      let(:service) { described_class.new(identifier: 'rng@example.com', method: 'email', ip_address: ip, user_agent: user_agent) }

      it 'usa SecureRandom' do
        allow_any_instance_of(Auth::EmailService).to receive(:send_magic_login_code).and_return({ success: true })
        expect(SecureRandom).to receive(:random_number).with(1_000_000).and_return(42)
        service.execute!
        expect(LoginCode.last.code).to eq('000042')
      end
    end
  end
end
