require 'rails_helper'

RSpec.describe Auth::OauthService, type: :service do
  let(:email) { 'oauth@example.com' }
  let(:provider) { 'google' }
  let(:uid) { '123456' }
  
  let(:service) do
    described_class.new(
      provider: provider,
      provider_uid: uid,
      email: email,
      name: 'OAuth User',
      avatar_url: 'http://image.com',
      ip_address: '127.0.0.1',
      user_agent: 'RSpec'
    )
  end

  before do
    UserType.seed_default_types!
  end

  # **DEC-44 — a tarefa crítica desta fatia.**
  #
  # O login social fica ligado e anunciado, mas **não é auto-cadastro**. Se ele criasse
  # conta, o D-39 (cadastro público criando Admin) voltaria por uma porta que a DEC-49
  # não fechou — e por uma porta pior, porque não passa pela allowlist de
  # `api/root.rb` e ninguém a revisaria de novo.
  describe '#execute!' do
    context 'when there is no account for the social login' do
      it 'NÃO cria usuário e responde 403 INVITE_ONLY' do
        expect {
          res = service.execute!
          expect(res[:status]).to eq(403)
          expect(res[:code]).to eq('INVITE_ONLY')
        }.not_to change(User, :count)
      end

      it 'não distingue "não tem conta" de "conta existe sem este provedor"' do
        sem_conta = service.execute!
        create(:user, email: 'outro@example.com')
        outro = described_class.new(
          provider: provider, provider_uid: 'zzz', email: 'inexistente@example.com',
          name: 'X', avatar_url: nil, ip_address: '127.0.0.1', user_agent: 'RSpec'
        ).execute!
        expect(sem_conta[:message]).to eq(outro[:message])
      end
    end

    context 'when user exists' do
      let!(:user) { create(:user, email: email) }

      it 'returns tokens for existing user' do
        expect {
          res = service.execute!
          expect(res[:success]).to be true
          data = res[:data].as_json
          expect(data[:user][:id]).to eq(user.id)
        }.not_to change(User, :count)
      end

      it 'recusa conta bloqueada com ACCOUNT_BLOCKED' do
        user.block!(reason: 'Desligado')
        res = service.execute!
        expect(res[:status]).to eq(403)
        expect(res[:code]).to eq('ACCOUNT_BLOCKED')
      end
    end
  end
end
