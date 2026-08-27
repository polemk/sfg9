# frozen_string_literal: true

require 'rails_helper'

# Autenticação da conexão Action Cable (find_verified_user). Preferência: cookie
# HttpOnly `cable_token` (escopo /cable, fora da URL → não vaza em log). Fallback:
# query param `token` (compat com clientes antigos). Anônimo é permitido (chat
# público). O rspec-rails desta versão não expõe grupo :connection, então
# exercitamos o método diretamente com o `request` stubado — é ali que mora a
# decisão de segurança que foi alterada.
RSpec.describe ApplicationCable::Connection do
  let(:user) { create(:user) }
  let(:token_service) { Auth::TokenService.new(user) }

  # Instância sem boot do Action Cable; só o `request` importa para a auth.
  def verified_user(cookies: {}, params: {})
    conn = described_class.allocate
    req = instance_double(ActionDispatch::Request, cookies: cookies.transform_keys(&:to_s), params: params)
    allow(conn).to receive(:request).and_return(req)
    conn.send(:find_verified_user)
  end

  it 'autentica pelo cookie cable_token (tipo cable)' do
    expect(verified_user(cookies: { cable_token: token_service.cable_token_for(user.id) })).to eq(user)
  end

  it 'autentica pelo query param como fallback (access token)' do
    expect(verified_user(params: { token: token_service.generate_tokens[:token] })).to eq(user)
  end

  it 'prefere o cookie ao param quando ambos existem' do
    result = verified_user(
      cookies: { cable_token: token_service.cable_token_for(user.id) },
      params: { token: 'lixo-ignorado' }
    )
    expect(result).to eq(user)
  end

  it 'permite conexão anônima sem token (chat público)' do
    expect(verified_user).to be_nil
  end

  it 'não autentica com refresh token no cookie' do
    expect(verified_user(cookies: { cable_token: token_service.generate_tokens[:refresh_token] })).to be_nil
  end

  it 'não autentica com cable token de usuário inexistente' do
    expect(verified_user(cookies: { cable_token: token_service.cable_token_for(SecureRandom.uuid) })).to be_nil
  end
end
