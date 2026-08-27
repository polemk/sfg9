# frozen_string_literal: true

require 'rails_helper'

# S1 / BE-040 — o canal que faz a mudança de permissão valer sem recarregar.
#
# Os dois primeiros exemplos travam a correção da flag de upstream **U2**: a versão
# da base assinava o fluxo do `user_id` que o CLIENTE mandasse.
RSpec.describe PermissionsChannel, type: :channel do
  let(:user)  { create(:user) }
  let(:outro) { create(:user) }

  before { stub_connection current_user: user }

  it 'streams the connected user own channel' do
    subscribe(user_id: user.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(described_class.stream_name_for(user.id))
  end

  it 'streams the connected user even when no user_id is given' do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(described_class.stream_name_for(user.id))
  end

  # U2 — o exemplo que separa o canal corrigido do da base.
  it 'rejects a subscription asking for someone else stream' do
    subscribe(user_id: outro.id)

    expect(subscription).to be_rejected
  end

  it 'rejects an anonymous connection' do
    stub_connection current_user: nil
    subscribe(user_id: user.id)

    expect(subscription).to be_rejected
  end

  describe '.publish_user_type_changed' do
    it 'notifies every user of that role, and nobody else' do
      UserType.seed_default_types!
      alvo  = create(:user, user_type: UserType.colaborador)
      fora  = create(:user, user_type: UserType.gerente)

      expect { described_class.publish_user_type_changed(UserType.colaborador.id, key: 'user_is_readonly') }
        .to have_broadcasted_to(described_class.stream_name_for(alvo.id))
        .with(hash_including('type' => 'permissions_changed', 'scope' => 'user_type'))

      expect { described_class.publish_user_type_changed(UserType.colaborador.id, key: 'user_is_readonly') }
        .not_to have_broadcasted_to(described_class.stream_name_for(fora.id))
    end
  end
end
