# frozen_string_literal: true

# Registro do webhook da Evolution — **o elo por onde o tempo real entra**.
#
# ## O que quebrou, e por quê isto está assim
#
# A tela de pareamento (`WhatsappPage`) escuta o `WhatsappInstanceChannel`, e
# quem publica nesse canal é o `WhatsAppWebhookService`, disparado por um POST da
# Evolution. Se a Evolution não tem webhook registrado, ninguém posta, ninguém
# transmite, e a tela fica parada para sempre **sem um único erro** — foi
# exatamente o sintoma relatado em 26/08/2026: o celular pareou, o
# `connectionState` da Evolution virou `open`, e a nossa linha ficou 18h em
# `connection_status: 'unknown'`.
#
# Medido naquele dia, direto na Evolution (`GET /webhook/find/AI9_VINAO`):
#
#     {"url":"https://tst","enabled":false,"events":[], ...}
#
# `https://tst` é placeholder, `enabled:false` e `events:[]`. Três defeitos
# empilhados levaram a isso:
#
# 1. **O endpoint que registra era inalcançável.** `/whats/v1/webhooks/config`
#    estava na allowlist de rotas públicas do `Api::Root`, então `@current_user`
#    nunca era preenchido e o `og?` do próprio endpoint respondia 401 a todos.
#    Ninguém conseguia registrar nada pelo app. Corrigido em `api/root.rb`.
# 2. **A URL não tinha fonte.** Só existia o que alguém digitasse no formulário.
#    Quem digitou uma vez digitou `https://tst` e ninguém voltou. Agora a URL vem
#    de configuração (`WHATS_WEBHOOK_URL`, com degrau para `API_HOST`), e o
#    formulário só a sobrescreve quando explicitamente informada.
# 3. **Nada reconciliava.** Registrado errado uma vez, ficava errado para sempre.
#    Agora `ensure_registered!` confere o estado real na Evolution e corrige.
#
# ## Por que existe `publicly_reachable?`
#
# A Evolution roda na nuvem e **não alcança `localhost`**. Registrar
# `http://localhost:3000` não é só inútil: esta máquina fala com a MESMA
# Evolution de produção, então um `set_webhook` de desenvolvimento
# **sobrescreveria o registro bom da produção** e derrubaria o tempo real de todo
# mundo. Por isso o registro é **recusado** quando a URL aponta para loopback ou
# rede privada — com motivo no log, nunca em silêncio. Em desenvolvimento, quem
# quiser tempo real de verdade abre um túnel e aponta `WHATS_WEBHOOK_URL` para
# ele; sem túnel, a tela continua funcionando pela carga inicial por HTTP.
class PolemkWebhookService
  class << self
    # Os eventos que a Evolution precisa nos mandar.
    #
    # Os três primeiros são o **ciclo de vida da instância** — são eles que a
    # tela de pareamento escuta, e eram justamente os que faltavam no registro
    # quebrado. Os três de mensagem vêm do legado e seguem registrados para não
    # perder recebimento/confirmação de leitura.
    LIFECYCLE_EVENTS = %w[CONNECTION_UPDATE QRCODE_UPDATED LOGOUT_INSTANCE].freeze
    MESSAGE_EVENTS   = %w[SEND_MESSAGE MESSAGES_UPSERT MESSAGES_UPDATE].freeze
    EVENTS = (LIFECYCLE_EVENTS + MESSAGE_EVENTS).freeze

    # Caminho onde `Api::Whats::V1::Webhooks` está montado. Com `byEvents: true`
    # a Evolution acrescenta o nome do evento em kebab-case a esta base —
    # `.../whats/v1/webhooks/connection-update` —, que é exatamente o `resource`
    # declarado lá. Deriva-lo aqui, e não escrevê-lo à mão em cada lugar, é o que
    # impede os dois lados de discordarem em silêncio.
    MOUNT_PATH = '/whats/v1/webhooks'

    # A URL que a Evolution vai chamar. **Vem de configuração, nunca de código.**
    #
    # `WHATS_WEBHOOK_URL` é a base completa (é o que se aponta para o túnel em
    # desenvolvimento, e o endereço público em produção). Sem ela, deriva de
    # `API_HOST` — que em dev é `localhost` e por isso cai no `publicly_reachable?`
    # abaixo.
    def callback_base_url
      configured = ENV['WHATS_WEBHOOK_URL'].presence
      return normalize_base(configured) if configured

      host = ENV['API_HOST'].presence
      return nil if host.blank?

      normalize_base("#{host.chomp('/')}#{MOUNT_PATH}")
    end

    # A Evolution só consegue POSTar em endereço que ela alcance da nuvem.
    # Loopback e faixa privada não são alcançáveis — e pior, registrá-los
    # SOBRESCREVE o registro bom, porque a instância é compartilhada.
    # Hosts que a Evolution nunca alcança da nuvem. `172.16.0.0/12` entra como
    # expressão porque a faixa privada só vai até `172.31`.
    HOSTS_LOCAIS = %w[localhost ::1 0.0.0.0].freeze
    SUFIXOS_LOCAIS = %w[.local .localhost].freeze
    PREFIXOS_PRIVADOS = %w[127. 10. 192.168. 169.254.].freeze
    FAIXA_172_PRIVADA = /\A172\.(1[6-9]|2\d|3[01])\./

    def publicly_reachable?(url)
      return false if url.blank?

      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      host = uri.host.to_s.downcase
      return false if host.blank?
      return false if HOSTS_LOCAIS.include?(host) || host.end_with?(*SUFIXOS_LOCAIS)
      return false if host.start_with?(*PREFIXOS_PRIVADOS) || host.match?(FAIXA_172_PRIVADA)

      true
    rescue URI::InvalidURIError
      false
    end

    # Confere o registro REAL na Evolution e corrige se estiver errado.
    #
    # Idempotente de propósito: pode ser chamada a cada abertura da tela de
    # pareamento sem custo além de um GET. Só escreve quando há divergência —
    # webhook desligado, URL diferente da configurada, ou faltando um dos eventos
    # de ciclo de vida.
    #
    # Nunca levanta: quem chama está no caminho de entregar um QR à pessoa, e um
    # problema de registro não pode virar tela de erro. O motivo vai para o log e
    # para o retorno.
    def ensure_registered!(base_url = nil)
      url = normalize_base(base_url.presence) || callback_base_url

      if url.blank?
        return skipped('WHATS_WEBHOOK_URL e API_HOST ausentes — sem URL para registrar')
      end

      unless publicly_reachable?(url)
        return skipped(
          "URL #{url} não é alcançável pela Evolution (loopback/rede privada). " \
          'Em desenvolvimento, abra um túnel e aponte WHATS_WEBHOOK_URL para ele.'
        )
      end

      remote = begin
        EvolutionConnection.list_webhooks[:response] || {}
      rescue StandardError => e
        Rails.logger.warn("[PolemkWebhookService] não deu para ler o webhook atual: #{e.message}")
        {}
      end

      if registered_correctly?(remote, url)
        Rails.logger.info("[PolemkWebhookService] webhook já registrado corretamente em #{url}")
        return { status: 'success', message: 'Webhook já estava registrado', data: remote, changed: false }
      end

      Rails.logger.info(
        "[PolemkWebhookService] registro divergente (url=#{remote['url'].inspect} " \
        "enabled=#{remote['enabled'].inspect} events=#{Array(remote['events']).inspect}) — registrando #{url}"
      )

      create_webhook({ url: url }).merge(changed: true)
    rescue StandardError => e
      Rails.logger.error("[PolemkWebhookService] falha ao reconciliar webhook: #{e.message}")
      { status: 'error', message: e.message, changed: false }
    end

    # `true` quando o que está na Evolution serve: ligado, na URL que
    # configuramos, e com **todos** os eventos de ciclo de vida assinados.
    def registered_correctly?(remote, url)
      return false unless remote.is_a?(Hash)
      return false unless remote['enabled'] == true
      return false unless normalize_base(remote['url'].to_s) == normalize_base(url)

      events = Array(remote['events']).map { |e| e.to_s.upcase.tr('.', '_') }
      LIFECYCLE_EVENTS.all? { |e| events.include?(e) }
    end

    def create_webhook(params)
      instance = PolemkInstance.first
      return { status: 'error', message: 'Nenhuma instância cadastrada' } if instance.nil?

      url = normalize_base(params[:url].presence) || callback_base_url
      return { status: 'error', message: 'URL do webhook não configurada' } if url.blank?

      # Contrato do `/webhook/set` da Evolution 2.3.x: tudo aninhado em `webhook`.
      webhook_payload = {
        webhook: {
          enabled: true,
          url: url,
          events: EVENTS,
          base64: true,
          byEvents: true
        }
      }

      remote = EvolutionConnection.set_webhook(webhook_payload)
      # A Evolution devolve o registro como ela o gravou. É ISSO que vale guardar
      # — antes gravávamos o nosso próprio pedido em `raw_response`, então a
      # linha do banco dizia `enabled: true` mesmo quando a Evolution tinha
      # gravado `enabled: false`. Um registro que só sabe repetir o que pedimos
      # não serve para descobrir que o pedido não pegou.
      remote_state = (remote.is_a?(Hash) ? remote[:response] : nil) || {}

      EVENTS.each do |event|
        full_url = "#{url}/#{event.downcase.tr('_', '-')}"
        webhook = instance.polemk_webhooks.find_or_initialize_by(event: event)
        webhook.update(
          url: full_url,
          enabled: remote_state.key?('enabled') ? remote_state['enabled'] : true,
          webhook_by_events: remote_state.key?('webhookByEvents') ? remote_state['webhookByEvents'] : true,
          webhook_base_64: remote_state.key?('webhookBase64') ? remote_state['webhookBase64'] : true,
          raw_response: remote_state.presence || webhook_payload
        )
      end

      result = Api::Entities::PolemkWebhook.represent(instance.polemk_webhooks.reload).as_json

      format_response('Webhook configurado com sucesso', result)
    end

    def list(_params)
      response = EvolutionConnection.list_webhooks
      format_response('Webhooks listadas com sucesso', response)
    end

    def test_connection(url)
      uri = URI.parse(url)
      raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
        f.request :json
        f.adapter Faraday.default_adapter
      end

      path = uri.request_uri
      payload = { ping: 'ok', timestamp: Time.now.utc.iso8601 }
      resp = conn.post(path, payload, { 'Content-Type' => 'application/json' })

      {
        status: 'success',
        message: 'Webhook respondeu',
        data: { code: resp.status, body: resp.body }
      }
    rescue URI::InvalidURIError
      {
        status: 422,
        error: 'invalid_url',
        message: 'URL inválida'
      }
    rescue StandardError => e
      {
        status: 502,
        error: 'connection_error',
        message: e.message
      }
    end

    private

    # Tira a barra final para que comparação de URL não falhe por cosmética —
    # `https://x/whats/v1/webhooks` e `https://x/whats/v1/webhooks/` são o mesmo
    # registro, e tratá-los como diferentes faria a reconciliação reescrever o
    # webhook a cada abertura da tela.
    def normalize_base(url)
      return nil if url.blank?

      url.to_s.strip.chomp('/')
    end

    def skipped(reason)
      Rails.logger.info("[PolemkWebhookService] registro de webhook não aplicado: #{reason}")
      { status: 'skipped', message: reason, changed: false }
    end

    def build_create_body(params)
      params.to_h.symbolize_keys.compact
    end

    def format_response(message, response)
      {
        status: 'success',
        message: message,
        data: response
      }
    end
  end
end
