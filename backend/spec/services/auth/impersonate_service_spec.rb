require 'rails_helper'

RSpec.describe Auth::ImpersonateService do
  before { UserType.seed_default_types! }

  # DEC-18.3 — motivo é OBRIGATÓRIO. Todos os `start` abaixo passam um motivo real;
  # o caminho sem motivo tem teste próprio no fim do arquivo.

  let(:og_user) { create(:user, user_type: UserType.og) }
  let(:client_user) { create(:user, user_type: UserType.colaborador) }
  let(:client_user2) { create(:user, user_type: UserType.colaborador) }

  describe '.start' do
    context 'when og user impersonates' do
      it 'succeeds impersonating a client' do
        result = described_class.start(og_user, client_user.id, reason: 'suporte ao chamado 1234')
        expect(result[:status]).to eq(200)
        expect(result[:data][:access_token]).to be_present
        expect(result[:data][:refresh_token]).to be_present
        expect(result[:data][:true_user][:id]).to eq(og_user.id)
      end

      it 'fails impersonating self' do
        result = described_class.start(og_user, og_user.id, reason: 'suporte ao chamado 1234')
        expect(result[:status]).to eq(422)
      end
    end

    context 'when client tries to impersonate' do
      it 'fails with permission error' do
        result = described_class.start(client_user, client_user2.id, reason: 'suporte ao chamado 1234')
        expect(result[:status]).to eq(403)
      end
    end

    context 'with invalid target' do
      it 'returns not found for nonexistent user' do
        result = described_class.start(og_user, 'nonexistent-id', reason: 'suporte ao chamado 1234')
        expect(result[:status]).to eq(404)
      end
    end

    it 'generates tokens with impersonated_by claim' do
      result = described_class.start(og_user, client_user.id, reason: 'suporte ao chamado 1234')
      token = result[:data][:access_token]

      token_service = Auth::TokenService.new(client_user)
      payload = token_service.decode_token(token, verify_exp: false)

      expect(payload['impersonated_by']).to eq(og_user.id)
      expect(payload['sub']).to eq(client_user.id)
    end
  end

  # O motivo é obrigatório e a trilha é persistida — DEC-18.3 / tarefa 5.2.
  describe 'motivo obrigatório e trilha' do
    it 'recusa impersonação sem motivo' do
      result = described_class.start(og_user, client_user.id, reason: '')
      expect(result[:status]).to eq(422)
      expect(result[:error]).to include('motivo')
    end

    it 'recusa motivo curto demais (nem "ok" nem "test")' do
      expect(described_class.start(og_user, client_user.id, reason: 'ok')[:status]).to eq(422)
    end

    it 'grava quem, quem foi personificado, quando e por quê' do
      expect {
        described_class.start(og_user, client_user.id, reason: 'investigar chamado 4711')
      }.to change(PaperTrail::Version.where(event: 'impersonate_start'), :count).by(1)

      version = PaperTrail::Version.where(event: 'impersonate_start').last
      expect(version.whodunnit).to eq(og_user.id.to_s)
      expect(version.impersonated_id).to eq(client_user.id.to_s)
      expect(version.reason).to eq('investigar chamado 4711')
      expect(version.created_at).to be_present
    end

    it 'fecha a trilha no stop' do
      expect {
        described_class.stop(og_user.id, impersonated_id: client_user.id)
      }.to change(PaperTrail::Version.where(event: 'impersonate_stop'), :count).by(1)
    end
  end

  # IMP-A28 — 403 vem ANTES de 404. Quem não pode personificar recebe o mesmo 403
  # para id que existe e para id que não existe: senão o endpoint enumera usuários.
  describe 'ordem das checagens' do
    it 'não distingue id existente de inexistente para quem não pode personificar' do
      inexistente = described_class.start(client_user, SecureRandom.uuid, reason: 'tentativa qualquer')
      existente   = described_class.start(client_user, client_user2.id, reason: 'tentativa qualquer')

      expect(inexistente[:status]).to eq(403)
      expect(existente[:status]).to eq(403)
      expect(inexistente[:error]).to eq(existente[:error])
    end
  end

  # A sessão personificada EXPIRA (tarefa 5.3): o refresh vive 1 hora, não 30 dias.
  describe 'expiração da sessão personificada' do
    it 'emite refresh com TTL de impersonação, não o de 30 dias' do
      result = described_class.start(og_user, client_user.id, reason: 'suporte ao chamado 1234')
      payload = Auth::TokenService.new(client_user).decode_token(result[:data][:refresh_token], verify_exp: false)

      expect(payload['exp']).to be <= (Time.current + Auth::TokenService::IMPERSONATION_REFRESH_TTL + 5.seconds).to_i
      expect(payload['exp']).to be < (Time.current + Auth::TokenService::REFRESH_TTL).to_i
    end
  end

  describe '.stop' do
    it 'generates fresh tokens for the true user' do
      result = described_class.stop(og_user.id)
      expect(result[:status]).to eq(200)
      expect(result[:data][:access_token]).to be_present
      expect(result[:data][:user]).to be_present
    end

    it 'returns not found for invalid user id' do
      result = described_class.stop('nonexistent-id')
      expect(result[:status]).to eq(404)
    end
  end
  # DEC-18.3 / C3 — a trava de hierarquia, nos DOIS lados.
  describe 'trava de hierarquia' do
    let(:admin_user)   { create(:user, user_type: UserType.admin) }
    let(:admin_user2)  { create(:user, user_type: UserType.admin) }
    let(:gerente_user) { create(:user, user_type: UserType.gerente) }

    it 'Admin NÃO personifica OG — e personifica Colaborador' do
      expect(described_class.start(admin_user, og_user.id, reason: 'suporte ao chamado 1234')[:status]).to eq(403)
      expect(described_class.start(admin_user, client_user.id, reason: 'suporte ao chamado 1234')[:status]).to eq(200)
    end

    it 'Admin NÃO personifica outro Admin (lateral) — e o OG personifica Admin' do
      expect(described_class.start(admin_user, admin_user2.id, reason: 'suporte ao chamado 1234')[:status]).to eq(403)
      expect(described_class.start(og_user, admin_user.id, reason: 'suporte ao chamado 1234')[:status]).to eq(200)
    end

    it 'Gerente não personifica ninguém — e o OG personifica o Gerente' do
      expect(described_class.start(gerente_user, client_user.id, reason: 'suporte ao chamado 1234')[:status]).to eq(403)
      expect(described_class.start(og_user, gerente_user.id, reason: 'suporte ao chamado 1234')[:status]).to eq(200)
    end
  end

end
