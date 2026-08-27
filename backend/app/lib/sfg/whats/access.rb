# frozen_string_literal: true

module Sfg
  module Whats
    # **Quem pode operar a instância do WhatsApp — DEC-83.**
    #
    # ## O defeito que este arquivo fecha
    #
    # A tela `/platform/whatsapp` é oferecida no menu a **OG e Admin**
    # (`consoleNavigation.tsx`, `roles: ['og', 'admin']`), e a API respondia
    # `401 Acesso negado` para o Admin: as quatro guardas do engine perguntavam
    # `@current_user&.og?`. Medido abrindo o app como Helena (Admin), nos três
    # modos: a tela sobe, o menu leva até ela, e ela diz "Acesso negado".
    #
    # ## Por que a API é que estava errada, e não o menu
    #
    # A **DEC-83** não é conveniência de navegação — ela diz por que o Admin
    # precisa entrar:
    #
    # > *"com o DEC-14, WhatsApp é uma das portas de entrada. Sem a tela, quando
    # > a sessão da instância expirar o canal cai e ninguém consegue reparear
    # > pela interface — o cliente fica dependendo da Livetat para voltar a
    # > entrar."*
    #
    # Estreitar o menu para OG resolveria o sintoma e **criaria** exatamente a
    # dependência que a decisão existe para evitar.
    #
    # ## Uma política, um lugar
    #
    # A mesma expressão estava copiada em **quatro** guardas (uma em
    # `instances.rb`, três em `webhooks.rb`). Quatro cópias de uma regra de
    # autorização é a forma de três delas continuarem erradas depois que alguém
    # conserta a primeira.
    #
    # `ClientApplication` (integração máquina-a-máquina) continua passando: é o
    # caminho que o webhook usa, e ele não tem papel.
    module Access
      ROLES = %w[og admin].freeze

      module_function

      # `client` é `@current_client` (integração) e `user` é `@current_user`.
      def allowed?(client, user)
        return true if client.present?
        return false if user.nil?

        ROLES.include?(user.user_type&.name.to_s.downcase)
      end
    end
  end
end
