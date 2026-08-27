require 'rails_helper'

RSpec.describe Auth::CodeValidationService do
  let(:identifier) { 'test@example.com' }
  let(:code) { '123456' }
  let(:method) { 'email' }
  let(:ip) { '127.0.0.1' }
  let(:user_agent) { 'TestAgent' }
  
  let(:service) do
    described_class.new(
      identifier: identifier,
      code: code,
      method: method,
      ip_address: ip,
      user_agent: user_agent
    )
  end

  before do
    allow_any_instance_of(Auth::TokenService).to receive(:generate_tokens).and_return({ token: 'jwt', refresh_token: 'refresh' })
  end

  describe '#execute!' do
    context 'when code is valid' do
      let!(:user) { create(:user, email: identifier) }
      let!(:login_code) do
        create(:login_code, 
          destination: identifier, 
          code: code, 
          method: method, 
          expires_at: 10.minutes.from_now,
          user: user
        )
      end

      it 'returns success session' do
        result = service.execute!
        expect(result[:data].as_json[:access_token]).to eq('jwt')
      end

      it 'marks code as used' do
        expect { service.execute! }.to change { login_code.reload.used_at }.from(nil)
      end

      it 'logs success attempt' do
        expect { service.execute! }.to change(LoginAttempt, :count).by(1)
        expect(LoginAttempt.last.success).to be_truthy
      end
    end

    context 'when code is invalid' do
      let!(:user) { create(:user, email: identifier) }
      let!(:login_code) do
        create(:login_code,
          destination: identifier,
          code: '999999',
          method: method,
          expires_at: 10.minutes.from_now,
          user: user
        )
      end

      it 'returns unauthorized' do
        result = service.execute!
        expect(result[:status]).to eq(401)
      end

      it 'logs failed attempt' do
        expect { service.execute! }.to change(LoginAttempt, :count).by(1)
        expect(LoginAttempt.last.success).to be_falsey
      end
    end

    # Código órfão (sem usuário) e destino sem conta recebem a MESMA resposta de
    # código errado. Antes o serviço dizia "Usuário não encontrado", que é um
    # verificador de conta: bastava pedir um código e mandar qualquer coisa para
    # descobrir se o e-mail está cadastrado no Safegold.
    context 'when there is no user for the identifier' do
      it 'responds like a wrong code, without naming the account' do
        result = service.execute!
        expect(result[:status]).to eq(401)
        expect(result[:error]).to include('Código inválido ou expirado')
        expect(result[:error]).not_to include('Usuário')
      end
    end

    # 3 tentativas, não 5 (o `LoginCode` já dizia 3; este serviço dizia 5, e o
    # caminho mais permissivo era o que valia).
    context 'when max attempts exceeded' do
       let!(:user) { create(:user, email: identifier) }
       let!(:login_code) do
        create(:login_code, 
          destination: identifier, 
          code: code, 
          method: method, 
          expires_at: 10.minutes.from_now,
          user: user,
          attempts: Auth::CodeValidationService::MAX_ATTEMPTS
        )
      end
      
      it 'burns the code and returns error' do
        result = service.execute!
        expect(result[:error]).to include('bloqueado')
        # O código não é APAGADO: fica gravado como usado. Apagar tira do banco a
        # evidência de que houve uma sequência de tentativas contra esta conta —
        # exatamente o que uma investigação de acesso indevido vai procurar.
        expect(login_code.reload.used_at).to be_present
      end

      it 'a terceira tentativa errada ainda responde 401, a quarta bloqueia' do
        login_code.update!(attempts: Auth::CodeValidationService::MAX_ATTEMPTS - 1, code: '999999')
        expect(service.execute![:error]).to include('Código inválido')
        expect(service.execute![:error]).to include('bloqueado')
      end
    end

    # Conta bloqueada não entra, e o motivo chega estruturado (DEC-39 / IMP-A17).
    context 'when the account is blocked' do
      let!(:user) { create(:user, email: identifier) }
      let!(:login_code) do
        create(:login_code, destination: identifier, code: code, method: method,
                            expires_at: 10.minutes.from_now, user: user)
      end

      it 'returns 403 with ACCOUNT_BLOCKED and the reason' do
        user.block!(reason: 'Desligado em 01/2026')
        result = service.execute!
        expect(result[:status]).to eq(403)
        expect(result[:code]).to eq('ACCOUNT_BLOCKED')
        expect(result[:message]).to include('Desligado')
      end
    end

    # DEC-45 — a terceira chave de identidade entra pelo MESMO campo.
    context 'when the identifier is a username' do
      let!(:user) { create(:user, email: 'jose@example.com', username: 'jose.silva') }
      let!(:login_code) do
        create(:login_code, destination: 'jose@example.com', code: code, method: method,
                            expires_at: 10.minutes.from_now, user: user)
      end
      let(:service) do
        described_class.new(identifier: 'jose.silva', code: code, method: method,
                            ip_address: ip, user_agent: user_agent)
      end

      it 'valida o código emitido para o e-mail do cadastro' do
        result = service.execute!
        expect(result[:status]).to eq(200)
      end
    end
  end
end
