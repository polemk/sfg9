# frozen_string_literal: true

module Api
  module Auth
    module V1
      # Helpers de segurança do caminho de entrada — login por código e callback OAuth.
      #
      # Até 19/08/2026 estes quatro métodos eram **chamados e nunca definidos**
      # (`magic_login.rb:33,35,40,79,85`, `code_validation.rb:42`, `oauth.rb:119`), e os
      # quatro endpoints respondiam 500. Os dois request specs que os cobriam stubavam
      # exatamente os quatro símbolos ausentes em `Grape::Endpoint`, com o comentário
      # "direct helper injection didn't work" — a suíte ficava verde sobre código morto.
      #
      # A injeção de helper sempre funcionou: `Api::Auth::V1::Base` declara
      # `helpers` ANTES dos `mount`, e a API montada herda. Medido em 19/08/2026 com
      # `can_resend`, que usa `process_service_response` vindo do `AuthHelpers` do Base
      # sem redefinir nada. Por isso este módulo entra no Base, uma vez, e não copiado
      # dentro de cada API montada.
      #
      # ── Onde cada limite mora, e por quê ────────────────────────────────────────
      #
      # O `rack-attack` já está no projeto e ganhou aqui os limites POR IP dos quatro
      # caminhos (`config/initializers/rack_attack.rb`). Não criamos um segundo
      # mecanismo de limite por IP: o middleware corta antes de o Rails montar a
      # requisição, é onde volume por origem deve morrer.
      #
      # O que ficou no endpoint é o que o middleware não consegue fazer:
      #
      #   * `check_rate_limit!` conta por DESTINO NORMALIZADO. Do middleware só se
      #     enxerga a string crua do corpo, então "Cliente@Exemplo.COM " e
      #     "cliente@exemplo.com" cairiam em baldes diferentes — o limite que protege a
      #     caixa de entrada de uma pessoa seria contornável só mudando a grafia. A
      #     normalização é `LoginCode.normalize_destination_value`, a mesma que o
      #     serviço usa para gravar. Contador: o próprio store do rack-attack (Redis),
      #     para haver UM contador no sistema e não dois.
      #
      #   * `check_brute_force!` conta TENTATIVAS QUE FALHARAM, e só a aplicação sabe se
      #     uma tentativa falhou. O contador é a própria trilha de auditoria
      #     (`LoginAttempt`, em Postgres) — a mesma evidência que um incidente vai
      #     querer ler depois, e que não some num flush de Redis.
      #
      # ── Falha aberta × falha fechada ────────────────────────────────────────────
      #
      # `check_rate_limit!` falha ABERTO se o Redis estiver fora: é limite de conforto
      # e de custo de envio; derrubar o login inteiro do produto porque um contador
      # piscou é um estrago maior do que o que ele evita. `check_brute_force!` não tem
      # esse escape — se o Postgres estiver fora, não há login para proteger de todo
      # jeito, porque não há como validar código nenhum.
      #
      # ── Não enumeramos contas ───────────────────────────────────────────────────
      #
      # Os dois limites são avaliados ANTES de qualquer busca por usuário e não
      # dependem de a conta existir. Um 429 daqui diz "houve volume nesta chave", nunca
      # "esta conta existe" — a mesma linha que o `MagicLoginService` segura no
      # `silent_response`.
      module SecurityHelpers
        # Teto de PEDIDOS DE CÓDIGO por destino+método.
        #
        # 5 em 15 minutos. O código vive 5 minutos (`LoginCode::TTL_BY_PURPOSE`), então
        # 5 pedidos cobrem três ciclos inteiros de expiração — folga de sobra para quem
        # digitou o e-mail errado, não recebeu, pediu de novo. Acima disso não é mais
        # alguém tentando entrar: é o nosso SMTP (ou a nossa conta de WhatsApp, que é
        # paga por mensagem) apontado para a caixa de entrada de um terceiro.
        #
        # Deliberadamente mais folgado que o magic link (`auth/magic_link_send/identifier`,
        # 2 por 15 min): o link de primeiro acesso é enviado uma vez por venda, o código
        # de login é digitado à mão e erra mais.
        CODE_REQUEST_LIMIT = 5
        CODE_REQUEST_PERIOD = 15.minutes.to_i

        # Prefixo da chave no store do rack-attack. Fica fora do espaço de nomes dos
        # throttles do middleware de propósito: são contadores distintos e ninguém deve
        # zerar um mexendo no outro.
        CODE_REQUEST_KEY_PREFIX = 'auth/code_request'

        # `LoginAttempt` valida presença de `ip_address`; um nil aqui derrubaria a
        # gravação da trilha de auditoria — ou seja, a falta de IP apagaria o registro
        # justamente da tentativa mais estranha. Preferimos gravar com IP desconhecido.
        UNKNOWN_IP = '0.0.0.0'

        # IP do cliente. `Rack::Request#ip` já resolve `X-Forwarded-For` respeitando os
        # proxies confiáveis, e é exatamente a mesma leitura que o `rack-attack` faz —
        # os dois limites precisam concordar sobre quem é o chamador.
        #
        # Sim, `X-Forwarded-For` é forjável por quem fala direto com a aplicação. É por
        # isso que a trava principal de `check_brute_force!` é o IDENTIFICADOR, que o
        # atacante não pode variar sem mudar de alvo; o IP é o eixo secundário.
        def current_ip
          request.ip.presence || env['REMOTE_ADDR'].presence || UNKNOWN_IP
        end

        # User-Agent do cliente. Vai para a trilha de auditoria, nunca para decisão de
        # acesso — é um campo que o chamador escolhe.
        def current_user_agent
          request.user_agent.presence || env['HTTP_USER_AGENT'].presence
        end

        # Barra o identificador (e o IP) que já acumulou falhas suficientes para não ser
        # mais um erro de digitação. A política em si vive no `LoginAttempt`
        # (`suspicious_activity?` e `brute_force_detected?`), que já era a regra do
        # projeto — este helper não inventa uma segunda:
        #
        #   * 5 falhas do mesmo identificador em 15 min;
        #   * 10 falhas do mesmo IP em 15 min;
        #   * 5 identificadores distintos falhando do mesmo IP em 15 min (varredura);
        #   * 10 tentativas do mesmo identificador em 5 min;
        #   * 5 tentativas em 1 min com menos de 2 s entre duas delas (cadência de robô).
        #
        # 429 e não 403: o acesso não foi negado, foi adiado. E a mensagem é a mesma
        # para conta que existe e para conta que não existe.
        def check_brute_force!(identifier, ip_address = nil)
          ip_address = ip_address.presence || current_ip

          return true unless LoginAttempt.suspicious_activity?(identifier, ip_address) ||
                             LoginAttempt.brute_force_detected?(identifier, ip_address)

          Rails.logger.warn(
            "[SecurityHelpers] força bruta barrada — identificador=#{identifier.to_s[0, 3]}*** ip=#{ip_address}"
          )
          too_many_requests!('Muitas tentativas. Aguarde alguns minutos antes de tentar novamente')
        end

        # Teto de envio por destino normalizado. Ver o cabeçalho do módulo para o porquê
        # de este limite não morar no `rack-attack` junto com os demais.
        def check_rate_limit!(identifier, delivery_method)
          destination = LoginCode.normalize_destination_value(identifier)
          count = code_request_count(delivery_method, destination)
          return true if count.nil? || count <= CODE_REQUEST_LIMIT

          Rails.logger.warn(
            '[SecurityHelpers] teto de envio atingido para ' \
            "#{LoginCode.mask_destination(destination, delivery_method)} " \
            "(#{count}/#{CODE_REQUEST_LIMIT} em #{CODE_REQUEST_PERIOD}s)"
          )
          too_many_requests!('Muitas solicitações de código. Aguarde alguns minutos antes de tentar novamente')
        end

        private

        # Devolve a contagem da janela corrente, ou `nil` quando o contador está
        # indisponível — `nil` é lido como "libera" por `check_rate_limit!`.
        #
        # Os dois caminhos de indisponibilidade são registrados, e o segundo é o que
        # importa: `ActiveSupport::Cache::RedisCacheStore` tem `failsafe` interno e
        # devolve `nil` em erro de conexão SEM levantar exceção. Sem esta linha, o
        # limite de envio deixaria de existir em silêncio absoluto — nenhum erro,
        # nenhum log, só um endpoint que parou de limitar.
        def code_request_count(delivery_method, destination)
          key = "#{CODE_REQUEST_KEY_PREFIX}:#{delivery_method}:#{destination}"
          count = Rack::Attack.cache.count(key, CODE_REQUEST_PERIOD)
          counter_unavailable('store devolveu nil') if count.nil?
          count
        rescue StandardError => e
          counter_unavailable("#{e.class}: #{e.message}")
          nil
        end

        def counter_unavailable(reason)
          Rails.logger.warn("[SecurityHelpers] contador de envio indisponível (#{reason}) — pedido liberado")
        end

        def too_many_requests!(message)
          error!({ error: 'too_many_requests', message: message }, 429)
        end
      end
    end
  end
end
