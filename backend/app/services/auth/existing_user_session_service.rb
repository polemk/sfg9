# frozen_string_literal: true

module Auth
  # Abre sessão para um usuário que **já existe**, a partir de e-mail ou telefone
  # capturados no contexto de uma conversa (nó `redirect` do assistente).
  #
  # ### Por que trocou de nome, e o que mudou junto
  #
  # Chamava-se `VisitorAuthService` e fazia `find_or_create`. Os dois pedaços do nome
  # mentiam depois das decisões desta migração:
  #
  #  - **`Visitor`** — o tipo `visitor` não existe mais (DEC-41). O nome sugeria um
  #    papel que o produto não tem;
  #  - **`find_or_create`** — era a **quinta** porta de auto-cadastro do sistema, e a
  #    única que a DEC-49 não fechou porque não estava em `api/root.rb`: bastava um
  #    e-mail qualquer no contexto da conversa para nascer um usuário **com JWT
  #    emitido**. Exatamente o D-39, por outro caminho. Entrada é só por convite
  #    (DEC-18.7).
  #
  # Agora **só casa**. Contexto sem usuário correspondente devolve 404 e o nó de
  # redirect segue sem sessão — que é o comportamento correto: não se conhece a pessoa.
  class ExistingUserSessionService
    include ApiResponseHandler

    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = params
    end

    def call
      return validation_error_response('Email or Phone is required') if @params[:email].blank? && @params[:phone].blank?

      user = find_existing_user
      return not_found_response('Usuário') unless user
      return forbidden_response('Conta bloqueada') if user.blocked?

      user.update_login_stats!
      tokens = Auth::TokenService.new(user).generate_tokens

      success_response(
        {
          user: Api::Entities::User.represent(user),
          token: tokens[:token],
          refresh_token: tokens[:refresh_token]
        },
        200
      )
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def find_existing_user
      user = nil
      user = User.by_email(@params[:email]).first if @params[:email].present?
      user ||= User.by_phone(@params[:phone]).first if @params[:phone].present?
      user
    end
  end
end
