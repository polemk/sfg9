# frozen_string_literal: true

module Rack
  class Attack
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
      url:       ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
      namespace: 'rack_attack',
      expires_in: 1.hour
    )

    ### ✅ 1️⃣ LIBERAR PREFLIGHT (CORS)
    safelist('allow-preflight') do |req|
      req.options?
    end

    ### ✅ 2️⃣ LIBERAR ENDPOINTS PÚBLICOS
    safelist('public-endpoints') do |req|
      req.path.start_with?('/public/')
    end

    ### (opcional) liberar healthcheck
    safelist('healthcheck') do |req|
      req.path == '/up'
    end

    ### Allow localhost
    safelist('allow-localhost') do |req|
      ['127.0.0.1', '::1'].include?(req.ip)
    end

    # **Requisicao autenticada e requisicao anonima nao sao a mesma coisa.**
    #
    # O teto generico existe para o que chega SEM identidade: raspador, forca
    # bruta, varredura. Quem esta logado e conhecido, auditado e revogavel — e o
    # abuso dele se trata cortando a sessao, nao contando pacote.
    #
    # `Bearer` no cabecalho basta como criterio: token invalido nao passa do gate
    # de autenticacao adiante, entao nada se ganha em recusa-lo aqui, e o custo de
    # decodificar JWT em TODA requisicao seria pago por todas.
    def self.autenticada?(req)
      req.get_header('HTTP_AUTHORIZATION').to_s.start_with?('Bearer ')
    end

    # Balde POR TOKEN, para o trafego autenticado.
    #
    # Nao e para conter gente: e teto contra automacao desgovernada — um `useEffect`
    # em laco, um script com o token de alguem. 1200/min sao 20 por SEGUNDO,
    # sustentados por um minuto inteiro. Nenhuma pessoa clicando chega la; um laco
    # chega em segundos.
    def self.chave_do_token(req)
      Digest::SHA256.hexdigest(req.get_header('HTTP_AUTHORIZATION').to_s)[0, 32]
    end

    ### ❗ Teto do trafego ANONIMO, por IP
    #
    # **Este teto valia para todo mundo, em 60/min, e punia o uso normal.**
    #
    # Em producao a pessoa logada perdia a tela: trocar de projeto refaz TODAS as
    # consultas de uma vez (`invalidateQueries()` sem filtro), cada navegacao
    # dispara `/flows/contextual`, e o orcamento acabava. Depois vinha o pior — o
    # token expira em 15 min, a proxima chamada leva 401, o cliente tenta RENOVAR,
    # a renovacao leva 429, e a sessao era destruida. F5 mandava para o login.
    #
    # **Subir o numero nao resolveria**, so adiaria: num sistema corporativo a
    # pessoa fica MAIS RAPIDA conforme domina a ferramenta, e um teto generico
    # acabaria punindo exatamente quem usa melhor. Produtividade nao pode custar a
    # sessao.
    #
    # Por isso o recorte mudou de LIMITE para CRITERIO: este balde passa a valer so
    # para quem chega sem identidade. Quem esta logado tem o balde proprio logo
    # abaixo, alto o bastante para nunca alcancar clicando.
    #
    # ⚠ Atras do proxy, `req.ip` so e o IP real se o `X-Forwarded-For` chegar (o
    # nginx do `install.sh` envia). Sem ele, TODOS os anonimos caem no mesmo balde.
    throttle('req/ip', limit: 300, period: 1.minute) do |req|
      req.ip unless req.options? || autenticada?(req)
    end

    ### Teto do trafego AUTENTICADO, por token
    #
    # Ver `chave_do_token`: teto contra automacao desgovernada, nao contra gente.
    throttle('req/token', limit: 1_200, period: 1.minute) do |req|
      chave_do_token(req) if autenticada?(req) && !req.options?
    end

    ### Login por IP
    throttle('logins/ip', limit: 5, period: 1.minute) do |req|
      req.ip if req.path == '/api/v1/auth/login' && req.post?
    end

    ### Login por email
    throttle('logins/email', limit: 5, period: 1.minute) do |req|
      if req.path == '/api/v1/auth/login' && req.post?
        req.params['email'].to_s.downcase.gsub(/\s+/, '')
      end
    end

    ### 🛡️ Public Chat Throttles
    throttle('public/chat/message', limit: 10, period: 1.minute) do |req|
      req.ip if req.path.include?('/chat/message') && req.post?
    end

    throttle('public/chat/session', limit: 30, period: 1.minute) do |req|
      req.ip if req.path.include?('/chat/session')
    end

    ### 🛡️ Visitor Signup Throttle
    throttle('auth/visitor_signup', limit: 5, period: 1.minute) do |req|
      req.ip if req.path.include?('/visitor_signup') && req.post?
    end

    ### 🛡️ Magic Link — envio por IP (3 links a cada 10 min)
    throttle('auth/magic_link_send/ip', limit: 3, period: 10.minutes) do |req|
      req.ip if req.path.include?('/visitor_signup_with_link') && req.post?
    end

    ### 🛡️ Magic Link — envio por email/phone (2 links por destinatário a cada 15 min)
    throttle('auth/magic_link_send/identifier', limit: 2, period: 15.minutes) do |req|
      if req.path.include?('/visitor_signup_with_link') && req.post?
        body = req.body.read
        req.body.rewind
        parsed = JSON.parse(body) rescue {}
        identifier = parsed['email'].presence || parsed['phone'].presence
        identifier&.downcase&.strip
      end
    end

    ### 🛡️ Magic Link — verificação por IP (20 tentativas por 5 min)
    throttle('auth/magic_link_verify/ip', limit: 20, period: 5.minutes) do |req|
      req.ip if req.path.include?('/magic_link/verify') && req.get?
    end

    # -------------------------------------------------------------------------
    # Limites do caminho de login por codigo.
    #
    # Origem: trazidos da branch `pika9` (commit 38475439) junto com o
    # `SecurityHelpers`, porque `check_rate_limit!` conta no MESMO store do
    # rack-attack e os dois lados precisam existir juntos. A quarta regra daquele
    # commit (busca de CEP) NAO veio: o endpoint `users/search_address` nao existe
    # nesta base.
    # -------------------------------------------------------------------------

    ### 🛡️ Login por código — pedido de código, por IP
    #
    # O teto por DESTINO não mora aqui: mora em
    # `Api::Auth::V1::SecurityHelpers#check_rate_limit!`. Do middleware só se enxerga a
    # string crua do corpo, então "Cliente@Exemplo.COM " e "cliente@exemplo.com"
    # cairiam em baldes diferentes e o limite seria contornável só mudando a grafia —
    # a normalização é da aplicação (`LoginCode.normalize_destination_value`). Os dois
    # contadores vivem no MESMO store Redis; não há um segundo mecanismo de limite.
    #
    # O que fica aqui é o eixo que o middleware faz melhor: volume por origem, cortado
    # antes de o Rails montar a requisição. É o caso de quem varre uma lista de e-mails
    # — cada destino é diferente, o balde por destino nunca enche, o balde por IP enche
    # na décima. 10 em 10 min é muito acima de um humano, que pede um código por login.
    throttle('auth/code_request/ip', limit: 10, period: 10.minutes) do |req|
      req.ip if req.path.include?('/magic_login/request_code') && req.post?
    end

    ### 🛡️ Login por código — validação, por IP
    #
    # Aqui o alvo é adivinhar o código de 6 dígitos de outra pessoa. O `LoginCode` já
    # destrói o código na 5ª tentativa errada, mas isso é POR CÓDIGO: quem pede um
    # código novo a cada 5 erros ganha 5 palpites por rodada e recomeça de graça.
    # 20 tentativas por 5 min por IP fecha a fresta e continua folgado para quem erra de
    # digitação. Cobre as duas portas do mesmo serviço: `magic_login/validate_code` e o
    # alias `code_validation`.
    throttle('auth/code_validation/ip', limit: 20, period: 5.minutes) do |req|
      if req.post? &&
         (req.path.include?('/magic_login/validate_code') || req.path.include?('/code_validation'))
        req.ip
      end
    end

    ### 🛡️ OAuth — callback, por IP
    #
    # Cada callback gasta duas chamadas de rede ao Google/Facebook com as NOSSAS
    # credenciais. Sem limite, repetir um código de autorização inválido em laço vira
    # consumo da nossa cota no provedor (e, no limite, bloqueio do nosso app para todo
    # mundo). Um usuário passa por aqui uma vez por login; 10 em 5 min é teto de sobra.
    throttle('auth/oauth_callback/ip', limit: 10, period: 5.minutes) do |req|
      req.ip if req.path.include?('/oauth/callback') && req.post?
    end

    

    ### Response customizada
    self.throttled_response = lambda do |env|
      now = Time.now
      match_data = env['rack.attack.match_data']

      headers = {
        'Content-Type' => 'application/json',
        'X-RateLimit-Limit' => match_data[:limit].to_s,
        'X-RateLimit-Remaining' => '0',
        'X-RateLimit-Reset' =>
          (now + (match_data[:period] - now.to_i % match_data[:period])).to_s
      }

      [429, headers, [{ error: 'Rate limit exceeded. Try again later.' }.to_json]]
    end
  end
end
