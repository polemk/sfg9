# frozen_string_literal: true

module Sfg
  module ReceitaWs
    # Consulta de CNPJ na ReceitaWS — OPS-480 / BE-457 / OPS-622, religada pela DEC-46.
    #
    # **O que estava morto e volta.** No legado o backend inteiro existia e funcionava
    # (gem, token, cache de 365 dias, timeout de 10 s, service em `helpers/cnpj_api.rb`,
    # endpoint em `pub/providers_controller.rb:121-133`) — **a UI é que estava morta em
    # duas pontas** (D-27): o botão comentado e a URL do JS com ERB escapado (`<%%=`).
    # Ninguém nunca clicou.
    #
    # **Três decisões que mudam em relação ao legado:**
    #
    #  1. **Teto de chamadas por usuário por dia (DEC-46).** A integração é **paga por
    #     consulta** e o custo é do cliente. Sem teto, um laço acidental na tela vira
    #     fatura. O legado não tinha teto nenhum.
    #  2. **A chave vem do `Credential`, não de ENV (DEC-61).** No legado o token estava
    #     **versionado no repositório** (`config/application.arch.yml:12`) — ou seja, já
    #     vazou por definição e será rotacionado no cutover. Aqui ele fica encriptado no
    #     banco e o cliente troca a própria chave por tela, sem deploy.
    #  3. **Ausência de chave NÃO derruba o app.** A integração responde *indisponível*
    #     e a tela continua aceitando o preenchimento manual. Integração externa que
    #     impede o cadastro é pior que integração ausente.
    #
    # **O retorno não é persistido**, de propósito: é o comportamento atual (o
    # preenchimento de `cnaes`/`atividades` está comentado no legado). O dado alimenta o
    # formulário e o usuário decide o que salvar.
    class LookupService
      extend ApiResponseHandler

      BASE_URL = ENV.fetch('RECEITAWS_URL', 'https://www.receitaws.com.br/v1/cnpj')

      # 10 s — o mesmo do legado (`initializers/receitaws.rb:14`). Curto de propósito:
      # a consulta acontece com o usuário esperando no formulário.
      TIMEOUT_SECONDS = 10

      # 365 dias — o mesmo do legado (`config.days = 365`). Dado cadastral de CNPJ
      # muda em anos, e cada consulta repetida é dinheiro.
      CACHE_TTL = 365.days

      # Teto diário POR USUÁRIO (DEC-46). Generoso para o uso real (cadastrar
      # fornecedor é operação de minutos) e apertado o suficiente para que um laço
      # acidental pare antes de virar conta.
      DEFAULT_DAILY_LIMIT = 30

      class << self
        # Devolve `success_response(data)` ou um `*_response` de erro. Nunca levanta:
        # o chamador é uma tela de cadastro, e falha de integração externa não pode
        # abortar o cadastro.
        def call(cnpj:, user: nil)
          digits = normalize(cnpj)
          return validation_error_response('CNPJ inválido. Informe os 14 dígitos.') unless valid_cnpj?(digits)

          token = api_key
          return unavailable_response if token.blank?

          cached = Rails.cache.read(cache_key(digits))
          # O cache NÃO conta contra o teto: o teto existe para proteger o custo, e
          # resposta em cache não custa consulta.
          return success_response(cached) if cached.present?

          return quota_response unless consume_quota!(user)

          fetch(digits, token)
        end

        # Quanto ainda resta hoje para este usuário. A tela usa para avisar antes de
        # o botão parar de funcionar — limite que só aparece quando estoura é limite
        # que o usuário lê como defeito.
        def remaining_quota(user)
          return daily_limit if user.blank?

          [daily_limit - used_today(user), 0].max
        end

        def daily_limit
          ENV.fetch('RECEITAWS_DAILY_LIMIT_PER_USER', DEFAULT_DAILY_LIMIT).to_i
        end

        # A chave vive encriptada em `credentials` (DEC-61). ENV continua funcionando
        # como escape para desenvolvimento, mas NÃO é a fonte.
        def api_key
          Credential.by_provider('receitaws').first&.api_key.presence ||
            ENV['RECEITAWS_TOKEN'].presence
        rescue StandardError => e
          # Banco indisponível ou chave de encriptação ausente não pode derrubar a
          # tela: a integração fica indisponível e o cadastro manual continua.
          Rails.logger.warn("[ReceitaWs] não foi possível ler a credencial: #{e.class}: #{e.message}")
          ENV['RECEITAWS_TOKEN'].presence
        end

        def normalize(cnpj)
          cnpj.to_s.gsub(/\D/, '')
        end

        private

        def fetch(digits, token)
          response = connection.get("#{BASE_URL}/#{digits}") do |req|
            req.headers['Authorization'] = "Bearer #{token}"
          end

          return upstream_response(response.status) unless response.status == 200

          body = parse(response.body)
          # A ReceitaWS devolve 200 com `status: "ERROR"` para CNPJ inexistente. Tratar
          # só o código HTTP faria "não encontrado" chegar à tela como sucesso vazio.
          if body['status'].to_s.casecmp('error').zero?
            return not_found_response(body['message'].presence || 'CNPJ')
          end

          data = present(body)
          Rails.cache.write(cache_key(digits), data, expires_in: CACHE_TTL)
          success_response(data)
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          Rails.logger.warn("[ReceitaWs] indisponível: #{e.class}: #{e.message}")
          unavailable_response
        rescue StandardError => e
          Rails.logger.error("[ReceitaWs] erro inesperado: #{e.class}: #{e.message}")
          unavailable_response
        end

        def connection
          @connection ||= Faraday.new do |f|
            f.options.timeout = TIMEOUT_SECONDS
            f.options.open_timeout = TIMEOUT_SECONDS
            f.adapter Faraday.default_adapter
          end
        end

        def parse(body)
          body.is_a?(Hash) ? body : JSON.parse(body.to_s)
        rescue JSON::ParserError
          {}
        end

        # Forma estável para o front. O corpo cru da ReceitaWS tem 30+ chaves e muda
        # sem aviso; expor tudo faria a tela depender do formato de um terceiro.
        def present(body)
          {
            cnpj: normalize(body['cnpj']),
            name: body['nome'],
            trade_name: body['fantasia'],
            status: body['situacao'],
            opened_at: body['abertura'],
            legal_nature: body['natureza_juridica'],
            email: body['email'],
            phone: body['telefone'],
            zip_code: body['cep'].to_s.gsub(/\D/, ''),
            street: body['logradouro'],
            number: body['numero'],
            complement: body['complemento'],
            district: body['bairro'],
            city: body['municipio'],
            state: body['uf'],
            main_activity: Array(body['atividade_principal']).first&.dig('text'),
            secondary_activities: Array(body['atividades_secundarias']).map { |a| a['text'] }.compact
          }
        end

        def cache_key(digits) = "receitaws:cnpj:#{digits}"

        def quota_key(user)
          "receitaws:quota:#{user.id}:#{Time.zone.today.iso8601}"
        end

        def used_today(user)
          Rails.cache.read(quota_key(user)).to_i
        end

        # Incrementa e devolve `false` quando o teto já foi atingido. Usuário ausente
        # (token de sistema) não tem teto — não há a quem cobrar o laço.
        def consume_quota!(user)
          return true if user.blank?

          used = used_today(user)
          return false if used >= daily_limit

          # `expires_in` de um dia inteiro: a chave já carrega a data, então ela morre
          # sozinha e não precisa de expurgo.
          Rails.cache.write(quota_key(user), used + 1, expires_in: 1.day)
          true
        end

        def unavailable_response
          error_response(
            'Consulta de CNPJ indisponível no momento. Preencha os dados manualmente.',
            503
          )
        end

        def quota_response
          error_response(
            "Você atingiu o limite de #{daily_limit} consultas de CNPJ por dia. " \
            'Preencha os dados manualmente ou tente amanhã.',
            429
          )
        end

        def upstream_response(status)
          return quota_response if status == 429

          Rails.logger.warn("[ReceitaWs] resposta inesperada: HTTP #{status}")
          unavailable_response
        end

        # Validação de dígito verificador. O legado mandava qualquer coisa para a API
        # — e cada CNPJ malformado era uma consulta paga desperdiçada.
        def valid_cnpj?(digits)
          return false unless digits.length == 14
          return false if digits.chars.uniq.size == 1

          [12, 13].all? { |position| digits[position].to_i == check_digit(digits, position) }
        end

        def check_digit(digits, position)
          weights = (2..9).cycle.first(position).reverse
          sum = digits[0, position].chars.each_with_index.sum { |d, i| d.to_i * weights[i] }
          remainder = sum % 11
          remainder < 2 ? 0 : 11 - remainder
        end
      end
    end
  end
end
