# frozen_string_literal: true

require 'rails_helper'

# O canal assinava DUAS chaves e o serviço transmitia para as DUAS: todo evento
# chegava em dobro no cliente. Achado gravando os quadros do WebSocket ao refazer
# a tela de pareamento — nenhum portão pegava, porque cada lado estava coerente
# sozinho e a tela era idempotente.
#
# Estes testes existem para impedir a volta. O caso que mais importa é o último:
# **um evento, uma entrega.**
RSpec.describe WhatsappInstanceChannel, type: :channel do
  before { UserType.seed_default_types! }

  # A conexao precisa estar IDENTIFICADA. Desde 26/08 (R-02) a
  # `ApplicationCable::Connection` recusa anonimo, e este canal confere
  # `current_user` de novo por defesa em profundidade — ele transmite o QR de
  # pareamento, que e credencial de acesso a conta de WhatsApp.
  let(:usuario) { create(:user, :gerente) }

  before { stub_connection current_user: usuario }

  let(:instance) do
    PolemkInstance.create!(
      display_name: 'AI9',
      instance_name: 'AI9_TESTE',
      instance_id: SecureRandom.uuid,
      api_key: 'chave-de-teste',
    )
  end

  describe 'assinatura' do
    it 'aceita o `instance_id` da Evolution' do
      subscribe(instance_id: instance.instance_id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(instance.cable_stream)
    end

    it 'aceita o `id` da linha' do
      subscribe(instance_id: instance.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(instance.cable_stream)
    end

    it 'assina UM stream só — as duas chaves levam ao mesmo nome' do
      subscribe(instance_id: instance.instance_id)

      # `streams` guarda tudo que a assinatura escuta. Mais de um aqui é o
      # defeito de volta: cada broadcast chegaria uma vez por stream.
      expect(subscription.streams.uniq.size).to eq(1)
    end

    it 'recusa conexão ANÔNIMA, mesmo com a instância existindo' do
      # Defesa em profundidade: a conexão já recusaria antes de chegar aqui.
      # Sem esta, bastaria um caminho que aceitasse anônimo para o QR vazar.
      stub_connection current_user: nil
      subscribe(instance_id: instance.instance_id)
      expect(subscription).to be_rejected
    end

    it 'recusa quando a instância não existe' do
      subscribe(instance_id: SecureRandom.uuid)
      expect(subscription).to be_rejected
    end

    it 'recusa quando a chave é vazia' do
      subscribe(instance_id: nil)
      expect(subscription).to be_rejected
    end

    it 'recusa chave que nem parece id, sem levantar exceção' do
      # `find_by(id: "nao-e-uuid")` faz o Postgres levantar. Se escapar, a
      # assinatura vira erro 500 no cabo em vez de recusa limpa.
      expect { subscribe(instance_id: 'nao-e-um-uuid') }.not_to raise_error
      expect(subscription).to be_rejected
    end
  end

  describe 'entrega' do
    it 'entrega o evento UMA vez, não duas' do
      subscribe(instance_id: instance.instance_id)

      expect do
        ActionCable.server.broadcast(instance.cable_stream, { type: 'qrcode_updated' })
      end.to have_broadcasted_to(instance.cable_stream).exactly(:once)
    end
  end
end
