# frozen_string_literal: true

module Auth
  # Login social (DEC-44 — Google e Facebook ligados e anunciados).
  #
  # **A tarefa crítica desta classe é o que ela NÃO faz: criar conta.**
  #
  # O D-39 do legado era o cadastro público criando usuário **Admin**
  # (`config/application.rb:84`, `minimal_type_to_sign_up_through_web = "Admin"`). A
  # DEC-49 fechou as 4 rotas de auto-cadastro. Se o callback OAuth criasse usuário, o
  # mesmo defeito voltaria por outra porta — e por uma porta pior, porque não passa pela
  # allowlist de `api/root.rb` e ninguém a revisaria de novo.
  #
  # Entrada é **só por convite** (DEC-18.7). Aqui o provedor social prova identidade;
  # quem admite é o convite.
  class OauthService
    include ApiResponseHandler

    def initialize(provider:, provider_uid:, email:, name:, avatar_url:, ip_address:, user_agent:)
      @provider = provider
      @provider_uid = provider_uid
      @email = email
      @name = name
      @avatar_url = avatar_url
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      user = ::User.find_for_oauth(@provider, @provider_uid, { email: @email, name: @name, image: @avatar_url })

      # Mesma resposta para "não existe conta" e para "existe conta sem este provedor
      # vinculado e sem e-mail casável": distinguir as duas transformaria o botão do
      # Google num oráculo de quem tem conta no Safegold.
      return invite_only_response unless user
      return blocked_response(user) if user.blocked?

      tokens = Auth::TokenService.new(user).generate_tokens
      user.update!(last_login_at: Time.current, login_count: user.login_count + 1)

      success_response(
        Api::Entities::AuthSession.represent(
          {
            user: user,
            token: tokens[:token],
            refresh_token: tokens[:refresh_token],
            # Sempre `false`: por desenho não há usuário novo saindo daqui.
            is_new_user: false
          }
        )
      )
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def invite_only_response
      {
        status: 403,
        error: 'invite_only',
        message: 'Não há conta para este login social. O acesso ao Safegold é somente por convite.',
        code: 'INVITE_ONLY'
      }
    end

    def blocked_response(user)
      {
        status: 403,
        error: 'account_blocked',
        message: user.blocked_reason.presence || 'Sua conta está bloqueada. Fale com o administrador do projeto.',
        code: 'ACCOUNT_BLOCKED'
      }
    end
  end
end
