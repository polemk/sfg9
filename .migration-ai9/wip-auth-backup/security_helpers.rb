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

        # ── Cooldown de reenvio, 30 s por DESTINO NORMALIZADO ───────────────────
        #
        # Este intervalo já existia, mas morava no `MagicLoginService`, atrás de
        # `user.can_request_new_code?` — ou seja, era avaliado DEPOIS da busca por
        # usuário e DEPOIS do `silent_response`. O efeito medido (D-QA-01, alta) era
        # um oráculo de enumeração de carteira: dois "Entrar" seguidos com o mesmo
        # e-mail devolviam **422** para quem é cliente do Safegold e **200** para quem
        # não é. Num produto de crédito isso não é só informação de segurança — é a
        # lista de clientes, conferível da tela pública em 30 segundos.
        #
        # Subiu para cá porque este é o único lugar onde o limite pode ser cobrado
        # SEM saber se a conta existe: a chave é o destino que a pessoa digitou,
        # normalizado, não a conta para onde ele aponta (ou não aponta). Os dois casos
        # passam pelo mesmo `if`, então respondem igual por construção — não por
        # alguém lembrar de manter dois ramos em sincronia.
        #
        # 429 e não 422: é a mesma semântica do `check_rate_limit!` logo acima, e é o
        # que o próprio endpoint documenta (`magic_login.rb`, `failure [{ code: 429 }]`).
        # O 422 anterior era um terceiro código para a mesma coisa.
        #
        # 30 s é o número que já estava em `User#can_request_new_code?` e em
        # `LoginCode#can_resend?` — não mexemos na política, só em onde ela é cobrada.
        CODE_RESEND_COOLDOWN = 30
        CODE_COOLDOWN_KEY_PREFIX = 'auth/code_cooldown'

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

        # Barra o SEGUNDO pedido dentro da janela de 30 s. Ver o bloco de
        # `CODE_RESEND_COOLDOWN` para o porquê de isto viver aqui e não no serviço.
        #
        # Falha ABERTO se o contador estiver fora, pelo mesmo motivo do
        # `check_rate_limit!` — e, o que importa mais aqui: falha aberto IGUAL para
        # conta que existe e conta que não existe, então nem a indisponibilidade do
        # Redis vira oráculo.
        def check_code_cooldown!(identifier, delivery_method)
          return true if code_cooldown_remaining(identifier, delivery_method).zero?

          Rails.logger.info(
            '[SecurityHelpers] cooldown de reenvio ativo para ' \
            "#{LoginCode.mask_destination(LoginCode.normalize_destination_value(identifier), delivery_method)}"
          )
          too_many_requests!('Aguarde alguns segundos antes de pedir um novo código')
        end

        # Arma o cooldown. Chamado no endpoint ANTES de o serviço rodar, para que o
        # relógio comece igual nos dois casos — inclusive quando nenhum código sai.
        def start_code_cooldown!(identifier, delivery_method)
          Rack::Attack.cache.write(
            cooldown_key(identifier, delivery_method),
            Time.current.to_i.to_s,
            CODE_RESEND_COOLDOWN
          )
          true
        rescue StandardError => e
          counter_unavailable("#{e.class}: #{e.message}")
          false
        end

        # Segundos que faltam para poder pedir de novo; 0 quando pode.
        # É também a fonte do `can_resend` — se ele lesse o `LoginCode`, como lia antes,
        # devolveria a mesma diferença que o D-QA-01 descreve, só por outra porta:
        # `can_resend: false` só existiria para quem tem conta.
        def code_cooldown_remaining(identifier, delivery_method)
          started_at = Rack::Attack.cache.read(cooldown_key(identifier, delivery_method))
          return 0 if started_at.blank?

          remaining = CODE_RESEND_COOLDOWN - (Time.current.to_i - started_at.to_i)
          remaining.positive? ? remaining : 0
        rescue StandardError => e
          counter_unavailable("#{e.class}: #{e.message}")
          0
        end

        private

        def cooldown_key(identifier, delivery_method)
          destination = LoginCode.normalize_destination_value(identifier)
          "#{CODE_COOLDOWN_KEY_PREFIX}:#{delivery_method}:#{destination}"
        end

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
