# frozen_string_literal: true

require 'rails_helper'

# Achado da varredura de resíduos do trim (R-02, 26/08/2026).
#
# `connect` fazia `self.current_user = user if user.present?` — **sem `reject`**.
# Token ausente, inválido ou revogado abria o WebSocket assim mesmo, só que
# anônimo. A defesa ficava por conta de cada canal, e o `WhatsappInstanceChannel`
# não defendia: conferia só se a instância existia. Um anônimo podia assinar e
# receber o **QR de pareamento**, que é credencial de acesso à conta.
RSpec.describe ApplicationCable::Connection, type: :channel do
  before { UserType.seed_default_types! }

  let(:usuario) { create(:user, :gerente) }
  let(:token) { Auth::TokenService.new(usuario).generate_tokens[:token] }

  it 'aceita e identifica quem tem token válido' do
    connect '/cable', params: { token: token }
    expect(connection.current_user).to eq(usuario)
  end

  it 'RECUSA conexão sem token nenhum' do
    expect { connect '/cable' }.to have_rejected_connection
  end

  it 'RECUSA token que não decodifica' do
    expect { connect '/cable', params: { token: 'nao-e-um-token' } }.to have_rejected_connection
  end

  it 'RECUSA token de refresh — refresh nunca autentica cabo' do
    refresh = Auth::TokenService.new(usuario).generate_tokens[:refresh_token]
    expect { connect '/cable', params: { token: refresh } }.to have_rejected_connection
  end

  it 'RECUSA token revogado — o logout precisa valer no cabo também' do
    payload = Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
    Auth::TokenService.revoke!(payload) if Auth::TokenService.respond_to?(:revoke!)
    skip 'revogação não exposta neste ponto' unless Auth::TokenService.revoked?(payload)

    expect { connect '/cable', params: { token: token } }.to have_rejected_connection
  end

  it 'o canal órfão `PublicEventsChannel` não existe mais' do
    # Ele transmitia de `"public_events"` SEM autorização nenhuma, e sobrou de
    # uma feature ai9 removida no trim. Com a conexão aceitando anônimo, era
    # transmissão aberta a quem abrisse um socket.
    expect(defined?(PublicEventsChannel)).to be_nil
    expect(File).not_to exist(Rails.root.join('app/channels/public_events_channel.rb'))
  end
end
