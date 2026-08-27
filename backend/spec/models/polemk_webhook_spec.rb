# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolemkWebhook, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:polemk_instance) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_presence_of(:polemk_instance_id) }
    it { is_expected.to validate_presence_of(:event) }
    it { is_expected.to validate_presence_of(:raw_response) }

    # **Os três booleanos aceitam `false`, e isso é o ponto.**
    #
    # Eram `validate_presence_of` — e `false.present?` é `false`, então gravar um
    # webhook DESLIGADO era impossível: o `update` devolvia `false` em silêncio e
    # a linha ficava com o valor antigo. O registro só sabia dizer "está tudo
    # ligado".
    #
    # Custou caro em 26/08/2026: a Evolution tinha o webhook da instância
    # `AI9_VINAO` com `enabled: false` e `events: []` havia meses, e a nossa
    # tabela dizia `enabled: true` nas três linhas. Quem foi procurar por que a
    # tela de pareamento não atualizava olhou o nosso registro primeiro e viu
    # tudo certo. Um registro que não consegue guardar o estado ruim esconde o
    # defeito de quem for procurar.
    it { is_expected.to validate_inclusion_of(:enabled).in_array([true, false]) }
    it { is_expected.to validate_inclusion_of(:webhook_by_events).in_array([true, false]) }
    it { is_expected.to validate_inclusion_of(:webhook_base_64).in_array([true, false]) }

    it 'grava um webhook DESLIGADO — que era o que a validação antiga impedia' do
      # `polemk_instance` PERSISTIDA: o model valida `polemk_instance_id`, que
      # em `build` ainda é nulo — a associação existe como objeto, o id não.
      webhook = build(:polemk_webhook, polemk_instance: create(:polemk_instance),
                                       enabled: false, webhook_by_events: false, webhook_base_64: false)

      expect(webhook).to be_valid
      expect(webhook.save).to be(true)
      expect(webhook.reload.enabled).to be(false)
    end
  end

  describe '#display_name' do
    let(:webhook) { build(:polemk_webhook, event: 'SEND_MESSAGE') }

    before do
       # Factory extracted to spec/factories/polemk_webhooks.rb
    end

    it 'returns human readable name for known events' do
      expect(webhook.display_name).to eq('Envio de mensagens')
    end

    it 'returns humanized string for unknown events' do
      webhook.event = 'unknown_event'
      expect(webhook.display_name).to eq('Unknown event')
    end
  end

  describe '#extract_base_url' do
    let(:webhook) { build(:polemk_webhook) }

    it 'extracts base url correctly when suffix is present' do
      webhook.url = 'https://api.example.com/webhook/send-message'
      expect(webhook.extract_base_url).to eq('https://api.example.com/webhook')
    end

    it 'returns clean url if no suffix matches' do
      webhook.url = 'https://api.example.com/webhook'
      expect(webhook.extract_base_url).to eq('https://api.example.com/webhook')
    end
    
  end
end
