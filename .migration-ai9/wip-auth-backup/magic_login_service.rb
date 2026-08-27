# frozen_string_literal: true

module Auth
  # Pedido de código de acesso — o primeiro passo do único caminho de entrada do
  # produto (DEC-14: não existe senha em lugar nenhum).
  #
  # ### As três chaves de identidade (DEC-45)
  #
  # `identifier` aceita **e-mail**, **telefone** ou **`username`**. O ramo de `username`
  # foi ACRESCENTADO; os de e-mail e telefone não mudaram uma linha. Isso é deliberado:
  # `username` atende o caso de cutover (quem só sabe o próprio usuário e perderia
  # acesso no dia 1), e não vale arriscar o caminho que todo mundo usa para servi-lo.
  #
  # **`username` identifica, não recebe.** Quem tem `username` mas não tem e-mail nem
  # telefone não consegue entrar — não há para onde mandar o código. O dry-run do ETL
  # conta e lista esses casos antes do cutover; aqui a resposta é explícita, porque o
  # usuário existe e a falha é nossa, não dele.
  class MagicLoginService
    include ApiResponseHandler

    # 6 dígitos. Mantido em constante porque o front valida o mesmo comprimento e o
    # `LoginCode` valida o formato — três lugares, um número.
    CODE_DIGITS = 6
    CODE_TTL = 5.minutes

    def initialize(identifier:, method:, ip_address:, user_agent:)
      @identifier = identifier
      @method = method
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      normalized_identifier = LoginCode.normalize_destination_value(@identifier)

      user = User.find_for_identifier(@identifier)

      # **Não enumeramos contas.** Destino desconhecido recebe a MESMA resposta de
      # destino conhecido — só não sai mensagem nenhuma. Distinguir os dois transforma
      # a tela de login num verificador de "esta pessoa é cliente do Safegold?", que num
      # produto de crédito é informação de negócio, não só de segurança.
      return silent_response(normalized_identifier) if user.nil?

      # Conta bloqueada (DEC-39) também responde silenciosamente: dizer "sua conta está
      # bloqueada" antes de provar a identidade entrega o mesmo oráculo. A explicação
      # existe, e chega no momento certo — quando a sessão é recusada com o motivo
      # (`ACCOUNT_BLOCKED`, IMP-A17).
      return silent_response(normalized_identifier) if user.blocked?

      destination = delivery_destination(user)
      return no_delivery_channel_response if destination.blank?
      return validation_error_response('Identificador inválido') unless valid_destination?(destination)

      # O teto de envio, a trava de força bruta e o cooldown de 30 s NÃO são mais
      # avaliados aqui. Eles subiram para `Api::Auth::V1::SecurityHelpers`, que é o
      # único ponto capaz de cobrá-los SEM saber se a conta existe.
      #
      # Enquanto o cooldown ficava neste ponto do método — depois do
      # `User.find_for_identifier` e depois do `silent_response` — ele só alcançava
      # conta real: dois pedidos seguidos devolviam 422 para cliente do Safegold e 200
      # para desconhecido (D-QA-01). O `silent_response` logo acima prometia por
      # escrito o contrário do que o método executava.

      Rails.logger.info("[MagicLoginService] Solicitação de código para #{masked(destination)} via #{@method}")
      create_login_attempt(success: false, user: user)

      code = generate_login_code

      LoginCode.create!(
        destination: destination,
        method: @method,
        code: code,
        expires_at: CODE_TTL.from_now,
        attempts: 0,
        user: user
      )

      send_code(user, destination, code)
      Rails.logger.info("[MagicLoginService] Código enviado com sucesso para #{masked(destination)} via #{@method}")

      update_last_attempt(success: true)

      success_response(sent_payload(destination))
    rescue EvolutionConnection::InvalidResponseError => e
      update_last_attempt(success: false)
      internal_error_response("Erro na Evolution API: #{e.error}")
    rescue EvolutionConnection::TimeoutError, EvolutionConnection::ConnectionError => e
      update_last_attempt(success: false)
      internal_error_response(e.message)
    rescue ActiveRecord::RecordInvalid => e
      update_last_attempt(success: false)
      validation_error_response(e.message)
    rescue StandardError => e
      update_last_attempt(success: false)
      internal_error_response(e.message)
    end

    private

    # Para onde o código vai, dado o canal escolhido. **Nunca o `username`**: ele
    # identifica, não recebe. Quando o usuário digitou o próprio e-mail/telefone, o
    # destino é o mesmo valor — mas quem manda é o cadastro, não o que foi digitado,
    # para que o `username` também funcione.
    def delivery_destination(user)
      @method == 'email' ? user.email.presence : user.phone.presence
    end

    def no_delivery_channel_response
      channel = @method == 'email' ? 'e-mail' : 'telefone'
      validation_error_response(
        "Sua conta não tem #{channel} cadastrado, e o código de acesso precisa de um destino. " \
        'Peça ao administrador do projeto para cadastrar um.'
      )
    end

    # A resposta que o chamador recebe quando o código realmente saiu.
    def sent_payload(destination)
      payload = {
        message: "Código enviado para #{@method == 'email' ? 'email' : 'WhatsApp'}",
        destination: LoginCode.mask_destination(destination, @method),
        method: @method
      }
      # Só em desenvolvimento: sem isto não há como testar o fluxo sem SMTP nem
      # instância de WhatsApp pareada. Em produção o corpo NUNCA carrega o código —
      # ele é a credencial (DEC-90).
      payload[:code] = LoginCode.by_destination(destination).by_method(@method).active.recent.first&.code if Rails.env.development?
      payload
    end

    # Resposta indistinguível da de sucesso, sem envio nenhum.
    def silent_response(normalized_identifier)
      Rails.logger.info(
        "[MagicLoginService] pedido para destino sem conta ativa (#{masked(normalized_identifier)}) — resposta silenciosa"
      )
      payload = {
        message: "Código enviado para #{@method == 'email' ? 'email' : 'WhatsApp'}",
        destination: LoginCode.mask_destination(normalized_identifier, @method),
        method: @method
      }
      # O eco de desenvolvimento do `sent_payload` também precisa existir aqui, senão
      # ele sozinho denuncia a conta: em `development` o corpo de sucesso carrega
      # `code` e o silencioso não carregava — bastava olhar a presença da CHAVE para
      # saber quem é cliente. E a demonstração roda em `development` (`backend/.env`),
      # que é exatamente onde o oráculo apareceria.
      #
      # O valor é gerado e NÃO é gravado em lugar nenhum: não existe conta, então não
      # existe código: digitá-lo falha, como tem de falhar. Em produção nenhum dos dois
      # ramos carrega `code` (DEC-90).
      payload[:code] = generate_login_code if Rails.env.development?
      success_response(payload)
    end

    # `SecureRandom`, não `rand`. `Kernel#rand` usa o Mersenne Twister, que não é
    # criptográfico: observando alguns códigos dá para prever os próximos, e o código
    # de acesso é a credencial inteira num produto sem senha.
    def generate_login_code
      SecureRandom.random_number(10**CODE_DIGITS).to_s.rjust(CODE_DIGITS, '0')
    end

    def create_login_attempt(success:, user: nil)
      LoginAttempt.create!(
        identifier: @identifier,
        method: @method,
        ip_address: @ip_address,
        user_agent: @user_agent,
        success: success,
        user: user
      )
    end

    def update_last_attempt(success:)
      last_attempt = LoginAttempt.where(
        identifier: @identifier,
        method: @method,
        ip_address: @ip_address
      ).last

      last_attempt&.update!(success: success)
    end

    def send_code(user, destination, code)
      if @method == 'email'
        Auth::EmailService.new(user: user, code: code).send_magic_login_code
      else
        number = destination.gsub(/[^0-9]/, '')
        message_text = "🔒 *#{app_name}* — seu código de acesso: *#{code}*\n\n⏰ Expira em 5 minutos.\n⚠️ Não compartilhe este código com ninguém."
        EvolutionConnection.send_message({ number: number, text: message_text })
      end
    end

    def valid_destination?(destination)
      if @method == 'email'
        destination.match?(URI::MailTo::EMAIL_REGEXP)
      else
        destination.gsub(/[^0-9]/, '').length.between?(10, 15)
      end
    end

    def masked(value)
      LoginCode.mask_destination(value, @method)
    end

    def app_name
      ENV.fetch('APP_NAME', 'Safegold')
    end
  end
end
