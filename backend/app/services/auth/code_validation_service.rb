# frozen_string_literal: true

module Auth
  # Validação do código de acesso — o segundo e último passo da entrada (DEC-14).
  #
  # ### Três coisas que este serviço faz de propósito
  #
  # 1. **Resolve o usuário ANTES do código.** O identificador digitado pode ser um
  #    `username` (DEC-45), e nesse caso ele não é o `destination` gravado no
  #    `LoginCode` — o destino é o e-mail ou o telefone do cadastro. Procurar o código
  #    só pelo texto digitado faria o login por `username` falhar sempre, com o código
  #    correto na mão.
  #
  # 2. **Compara em tempo constante.** `==` em string sai no primeiro byte diferente, e
  #    a diferença de tempo é medível pela rede. Com 3 tentativas por código isso não é
  #    o vetor mais provável, mas o código de acesso é a credencial inteira do produto
  #    e a comparação certa custa uma linha.
  #
  # 3. **Nunca cria conta.** Havia aqui um `find_or_create_user` privado — código morto
  #    que, se algum dia fosse chamado, seria a sexta porta do D-39. Removido junto com
  #    as rotas de auto-cadastro da DEC-49: serviço órfão é convite a remontar a rota.
  class CodeValidationService
    include ApiResponseHandler

    # 3 tentativas, não 5. O código tem 6 dígitos e vive 5 minutos; 3 chances cobrem
    # erro de digitação e nada mais. Estava 5 aqui e 3 no `LoginCode` — dois números
    # para a mesma regra, e o caminho mais permissivo é o que valia.
    MAX_ATTEMPTS = 3

    def initialize(identifier:, code:, method:, ip_address:, user_agent:)
      @identifier = identifier
      @code = code.to_s.strip
      @method = method
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      user = User.find_for_identifier(@identifier)
      return invalid_code_response if user.nil?
      return blocked_response(user) if user.blocked?

      login_code = active_code_for(user)
      return invalid_code_response unless login_code

      if login_code.attempts >= MAX_ATTEMPTS
        login_code.update!(used_at: Time.current)
        create_login_attempt(success: false)
        return unauthorized_response('Código bloqueado por muitas tentativas. Peça um novo código')
      end

      login_code.increment!(:attempts)

      unless login_code.matches?(@code)
        create_login_attempt(success: false)
        return invalid_code_response
      end

      tokens = Auth::TokenService.new(user).generate_tokens
      user.update!(last_login_at: Time.current, login_count: user.login_count + 1)
      login_code.update!(used_at: Time.current)
      create_login_attempt(success: true)

      success_response(
        Api::Entities::AuthSession.represent(
          {
            success: true,
            message: 'Login realizado com sucesso',
            user: user,
            access_token: tokens[:token],
            token: tokens[:token],
            refresh_token: tokens[:refresh_token]
          }
        )
      )
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    # Pelo USUÁRIO, não pelo texto digitado — ver o item 1 do cabeçalho. O
    # `destination` continua entrando na busca como segundo eixo para que um código
    # emitido para o e-mail não seja consumido pelo canal WhatsApp e vice-versa.
    def active_code_for(user)
      LoginCode.where(user_id: user.id, method: @method)
               .where('expires_at > ?', Time.current)
               .where(used_at: nil)
               .order(created_at: :desc)
               .first
    end

    def invalid_code_response
      unauthorized_response('Código inválido ou expirado')
    end

    def blocked_response(user)
      {
        status: 403,
        error: 'account_blocked',
        message: user.blocked_reason.presence || 'Sua conta está bloqueada. Fale com o administrador do projeto.',
        code: 'ACCOUNT_BLOCKED'
      }
    end

    def create_login_attempt(success:)
      LoginAttempt.create!(
        identifier: @identifier,
        method: @method,
        ip_address: @ip_address,
        user_agent: @user_agent,
        success: success
      )
    end
  end
end
