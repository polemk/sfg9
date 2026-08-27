# frozen_string_literal: true

module Contracts
  # S12 / BE-330, FE-334 — **a allowlist de destino de retorno** da página
  # pública de contrato.
  #
  # É o fecho do **D-69**, que eram *duas* vulnerabilidades no mesmo parâmetro:
  # o `redirect_url` do legado (`pub/contracts_controller.rb:3`) era interpolado
  # na view e usado como destino — **XSS refletido** e **open redirect** na
  # mesma variável.
  #
  # O desenho aqui não valida o parâmetro: ele **não usa** o parâmetro como URL.
  # O cliente manda uma **chave** (`login`, `profile`, `console`), e o servidor
  # responde o caminho correspondente. Um valor fora da lista cai no destino
  # padrão. Não existe caminho em que texto do usuário vire href.
  module ReturnDestinations
    DEFAULT = 'login'

    PATHS = {
      'login' => '/login',
      'console' => '/dashboard',
      'profile' => '/profile',
      'faq' => '/faq'
    }.freeze

    module_function

    def keys
      PATHS.keys
    end

    def allowed?(key)
      PATHS.key?(key.to_s)
    end

    # Nunca levanta e nunca devolve o que veio do cliente: ou é uma das chaves,
    # ou é o padrão.
    def resolve(key)
      PATHS.fetch(key.to_s, PATHS.fetch(DEFAULT))
    end
  end
end
