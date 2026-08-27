# frozen_string_literal: true

require 'rails_helper'

# **A cadeia do tempo real da tela de pareamento, inteira, de ponta a ponta.**
#
# Achado por uso, em 26/08/2026: o usuário pareou o celular de verdade, a
# Evolution passou a `state: "open"`, e a `WhatsappPage` não reagiu. A nossa
# linha ficou 18 horas em `connection_status: 'unknown'`.
#
# O que os testes que já existiam provavam, e por que não bastou: o
# `whats_app_webhook_service_spec` **estuba o broadcast**
# (`allow(described_class).to receive(:broadcast_connection_update)`), então ele
# nunca chegou a mostrar um evento saindo pelo Action Cable; e o
# `whatsapp_instance_channel_spec` prova a assinatura, mas nada exercitava o elo
# de CIMA — quem faz a Evolution nos chamar. Cada lado estava coerente sozinho e
# a corrente não existia.
#
# A causa raiz estava em dois elos empilhados, ambos ACIMA do Action Cable:
#
#   1. `api/root.rb` listava `/whats/v1/webhooks/config` como rota pública. O
#      gate central fazia `next` e nunca preenchia `@current_user`; o endpoint
#      então conferia `@current_user&.og?`, achava `nil`, e respondia **401 para
#      todo mundo**. Registrar o webhook pelo app era impossível.
#   2. A URL do webhook não tinha fonte de configuração — só o que alguém
#      digitasse no formulário. O que ficou gravado foi `https://tst`, e do lado
#      da Evolution o registro estava `enabled: false, events: []`.
#
# Sem `CONNECTION_UPDATE` registrado, o pareamento acontecia e a tela nunca
# ficava sabendo — sem erro, sem log, sem nada na tela.
RSpec.describe 'WhatsApp — cadeia do tempo real', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }
  let!(:instance) { create(:polemk_instance, instance_name: 'AI9_TESTE') }

  # A URL precisa ser PÚBLICA: `PolemkWebhookService` recusa loopback de
  # propósito (ver o teste correspondente mais abaixo).
  let(:base_publica) { 'https://exemplo-tunel.ngrok-free.app/whats/v1/webhooks' }

  # Payload real de `CONNECTION_UPDATE` da Evolution 2.3.x, como ela o envia
  # quando o celular termina de parear.
  let(:payload_conexao) do
    {
      event: 'connection.update',
      instance: 'AI9_TESTE',
      data: { instance: 'AI9_TESTE', state: 'open', statusReason: 200 },
      date_time: '2026-08-26T20:19:06.000Z',
      sender: '5511999999999@s.whatsapp.net',
      server_url: 'https://whats.polemk.com'
    }
  end

  describe 'elo 1 — registrar o webhook na Evolution' do
    # ESTE É O TESTE QUE FALHA ANTES DO CONSERTO.
    #
    # Com `config` na allowlist de rotas públicas, esta requisição respondia 401
    # mesmo com um token OG válido — medido contra o servidor de pé antes de
    # mexer em nada. Sem passar por aqui, nada mais da cadeia chega a acontecer.
    it 'aceita um OG autenticado — não responde 401' do
      allow(EvolutionConnection).to receive(:set_webhook).and_return(
        { status: 'success', response: { 'enabled' => true, 'url' => base_publica } }
      )

      post '/whats/v1/webhooks/config', params: { url: base_publica }.to_json,
                                        headers: auth_headers(og).merge('CONTENT_TYPE' => 'application/json')

      expect(response.status).not_to eq(401),
                                     'o endpoint que registra o webhook voltou a ser inalcançável — ' \
                                     'confira se `config` reentrou na allowlist de `api/root.rb`'
      expect(response).to have_http_status(:created)
    end

    it 'continua recusando quem não está autenticado' do
      post '/whats/v1/webhooks/config', params: { url: base_publica }.to_json,
                                        headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end

    # Sem estes dois eventos a tela não tem como saber de nada. Eram justamente
    # os que faltavam no registro real: `events: []`.
    it 'assina CONNECTION_UPDATE e QRCODE_UPDATED' do
      enviado = nil
      allow(EvolutionConnection).to receive(:set_webhook) do |body|
        enviado = body
        { status: 'success', response: { 'enabled' => true, 'url' => base_publica } }
      end

      post '/whats/v1/webhooks/config', params: { url: base_publica }.to_json,
                                        headers: auth_headers(og).merge('CONTENT_TYPE' => 'application/json')

      expect(enviado.dig(:webhook, :events)).to include('CONNECTION_UPDATE', 'QRCODE_UPDATED', 'LOGOUT_INSTANCE')
      expect(enviado.dig(:webhook, :enabled)).to be(true)
    end
  end

  describe 'elo 2 — reconciliação (PolemkWebhookService.ensure_registered!)' do
    # O estado REAL medido na Evolution em 26/08/2026, palavra por palavra.
    let(:registro_quebrado) do
      { 'id' => 'cmiq4u80j0162qr4b96i7xlvc', 'url' => 'https://tst', 'enabled' => false, 'events' => [],
        'webhookByEvents' => false }
    end

    it 'reescreve um registro desligado, com URL placeholder e sem eventos' do
      allow(EvolutionConnection).to receive(:list_webhooks).and_return({ status: 'success',
                                                                        response: registro_quebrado })
      expect(EvolutionConnection).to receive(:set_webhook).and_return(
        { status: 'success', response: { 'enabled' => true, 'url' => base_publica } }
      )

      resultado = described_class_service.ensure_registered!(base_publica)

      expect(resultado[:changed]).to be(true)
    end

    it 'não reescreve quando o registro já está correto — é idempotente' do
      ja_certo = { 'url' => base_publica, 'enabled' => true,
                   'events' => %w[CONNECTION_UPDATE QRCODE_UPDATED LOGOUT_INSTANCE] }
      allow(EvolutionConnection).to receive(:list_webhooks).and_return({ status: 'success', response: ja_certo })
      expect(EvolutionConnection).not_to receive(:set_webhook)

      resultado = described_class_service.ensure_registered!(base_publica)

      expect(resultado[:changed]).to be(false)
    end

    # Esta máquina de desenvolvimento fala com a MESMA Evolution de produção.
    # Registrar `localhost` não seria só inútil (a Evolution não alcança) — ela
    # SOBRESCREVERIA o registro bom e derrubaria o tempo real de todo mundo.
    it 'recusa URL de loopback em vez de sobrescrever o registro de produção' do
      expect(EvolutionConnection).not_to receive(:set_webhook)

      resultado = described_class_service.ensure_registered!('http://localhost:3000/whats/v1/webhooks')

      expect(resultado[:status]).to eq('skipped')
      expect(resultado[:message]).to match(/alcançável/)
    end

    # Pedir o QR é o único momento em que sabemos que alguém está prestes a
    # parear. Sem este gancho, o registro dependia de alguém abrir um formulário.
    it 'é disparada quando a tela pede o QR (connect_instance)' do
      allow(EvolutionConnection).to receive(:connect_instance).and_return({ status: 'success', response: {} })
      expect(described_class_service).to receive(:ensure_registered!)

      PolemkInstanceService.connect_instance({})
    end
  end

  describe 'elo 3 — o evento vira broadcast (A PROVA DO TEMPO REAL)' do
    # Nada de estubar o broadcast aqui: o ponto do teste é justamente que ele
    # ACONTECE, no stream que a `WhatsappPage` assina. Um POST no webhook real,
    # pela rota real, e um quadro saindo pelo Action Cable.
    it 'um CONNECTION_UPDATE da Evolution chega ao stream que a tela escuta' do
      expect do
        post '/whats/v1/webhooks/connection-update', params: payload_conexao.to_json,
                                                     headers: { 'CONTENT_TYPE' => 'application/json' }
      end.to have_broadcasted_to(instance.cable_stream)
        .with(hash_including(type: 'connection_update', status: 'open'))

      expect(response).to have_http_status(:created)
    end

    it 'e a instância fica marcada como conectada no banco' do
      post '/whats/v1/webhooks/connection-update', params: payload_conexao.to_json,
                                                   headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(instance.reload.connection_status).to eq('connected')
      expect(instance.last_connection_at).to be_present
    end

    it 'um QRCODE_UPDATED também chega ao mesmo stream' do
      payload_qr = {
        event: 'qrcode.updated',
        instance: 'AI9_TESTE',
        data: { qrcode: { instance: 'AI9_TESTE', base64: 'data:image/png;base64,AAAA', pairingCode: 'ABCD-1234' } }
      }

      expect do
        post '/whats/v1/webhooks/qrcode-updated', params: payload_qr.to_json,
                                                  headers: { 'CONTENT_TYPE' => 'application/json' }
      end.to have_broadcasted_to(instance.cable_stream).with(hash_including(type: 'qrcode_updated'))
    end

    # O nome do stream é a costura entre os dois lados. Se ele divergir, tudo
    # acima continua verde e a tela para de receber — em silêncio.
    it 'o stream do broadcast é o mesmo que o canal assina' do
      expect(instance.cable_stream).to eq(PolemkInstance.cable_stream_for(instance.id))
      expect(PolemkInstance.find_for_cable(instance.instance_id)&.cable_stream).to eq(instance.cable_stream)
    end
  end

  # A allowlist de rotas públicas só pode conter RECEPTORES. `config` não é: ele
  # diz à Evolution para onde mandar evento, e ficar público significava, na
  # prática, ficar 401 para todos — ver o comentário em `api/root.rb`.
  describe 'allowlist pública' do
    it 'não expõe o endpoint de configuração do webhook' do
      fonte = File.read(Rails.root.join('app/controllers/api/root.rb'))
      liberados = fonte.scan(%r{\^/whats/v1/webhooks/([a-z-]+)/\?\$}).flatten

      expect(liberados).to match_array(%w[connection-update qrcode-updated logout-instance])
      expect(liberados).not_to include('config'),
                               'rota que REGISTRA webhook não pode pular o gate: sem `@current_user`, ' \
                               'o `og?` do endpoint responde 401 a todos e o registro fica impossível'
    end
  end

  def described_class_service
    PolemkWebhookService
  end
end
