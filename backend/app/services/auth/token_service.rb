# frozen_string_literal: true

require 'jwt'

module Auth
  class TokenService
    # O default era 21600 minutos — 15 DIAS. O install.sh grava JWT_EXPIRATION_TIME
    # no .env, mas o código lê JWT_EXPIRATION_TIME_MINUTES, então a configuração
    # nunca chegava aqui e o default valia em produção: token de acesso de 15 dias
    # guardado em localStorage. Com o refresh silencioso via cookie, 15 minutos
    # passam despercebidos pelo usuário.
    ACCESS_TTL = ENV.fetch('JWT_EXPIRATION_TIME_MINUTES', '15').to_i.minutes
    REFRESH_TTL = ENV.fetch('JWT_REFRESH_EXPIRATION_DAYS', '30').to_i.days
    # Token exclusivo para o handshake do Action Cable. Só serve para abrir o
    # WebSocket (type 'cable') — não é aceito como Bearer na API nem no refresh.
    # Entregue em cookie HttpOnly (Path=/cable), nunca na URL, então não vaza em
    # log de proxy.
    CABLE_TTL = ENV.fetch('JWT_CABLE_EXPIRATION_HOURS', '12').to_i.hours
    # **A sessão personificada EXPIRA** (DEC-18.3 / tarefa 5.3).
    #
    # O refresh de impersonação usava o `REFRESH_TTL` normal — 30 dias. Na prática isso
    # é uma sessão que não expira: quem abriu um "ver como" para investigar um chamado
    # ficava com a identidade de outra pessoa renovável por um mês, e a trilha diria
    # que foi ela quem agiu o tempo todo. Uma hora cobre um atendimento inteiro; passar
    # disso é abrir de novo, que é barato e deixa rastro novo.
    IMPERSONATION_REFRESH_TTL = ENV.fetch('JWT_IMPERSONATION_TTL_MINUTES', '60').to_i.minutes

    def initialize(user)
      @user = user
      @algorithm = 'HS256'
      @secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] || Rails.application.credentials.secret_key_base || (Rails.application.respond_to?(:secret_key_base) ? Rails.application.secret_key_base : nil) || 'change-me-dev-secret'
    end

    def generate_tokens
      {
        token: generate_access_token,
        refresh_token: generate_refresh_token
      }
    end

    # Token de handshake do Action Cable (escopo mínimo). Aceita user_id direto
    # para ser gerado sem carregar o objeto User (ex.: a partir do sub do refresh).
    def cable_token_for(user_id)
      payload = {
        sub: user_id,
        type: 'cable',
        exp: CABLE_TTL.from_now.to_i,
        iat: Time.current.to_i,
        jti: SecureRandom.uuid
      }
      JWT.encode(payload, @secret, @algorithm)
    end

    def generate_impersonation_tokens(true_user_id)
      {
        token: generate_impersonation_access_token(true_user_id),
        refresh_token: generate_impersonation_refresh_token(true_user_id)
      }
    end

    # Checagem de revogação compartilhada. Um token revogado no logout continua
    # valendo em TODO ponto de autenticação que decodifica por fora daqui — o
    # Warden::JWTAuth::TokenDecoder, por exemplo, não consulta a jwt_denylist.
    # Chame este método sempre que decodificar sem passar pelo decode_token.
    def self.revoked?(payload)
      jti = payload.is_a?(Hash) ? (payload['jti'] || payload[:jti]) : nil
      return false if jti.blank?
      return false unless ActiveRecord::Base.connection.table_exists?('jwt_denylist')

      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.send(:sanitize_sql_array,
                                ['SELECT COUNT(*) FROM jwt_denylist WHERE jti = ?', jti])
      ).to_i.positive?
    rescue StandardError => e
      Rails.logger.warn("[TokenService] Falha ao consultar denylist: #{e.class} - #{e.message}")
      false
    end

    def decode_token(token, verify_exp: true)
      options = { algorithm: @algorithm }
      options[:verify_expiration] = verify_exp
      payload, = JWT.decode(token, @secret, true, options)
      raise JWT::DecodeError if self.class.revoked?(payload)

      payload
    rescue JWT::ExpiredSignature
      raise JWT::ExpiredSignature
    rescue JWT::DecodeError
      raise JWT::DecodeError
    end

    private

    def generate_access_token
      if defined?(Warden::JWTAuth::UserEncoder) && @user
        token, _payload = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil)
        return token
      end
      payload = {
        sub: @user.id,
        type: 'user',
        exp: ACCESS_TTL.from_now.to_i,
        iat: Time.current.to_i
      }
      JWT.encode(payload, @secret, @algorithm)
    end

    def generate_refresh_token
      payload = {
        sub: @user.id,
        type: 'refresh',
        exp: REFRESH_TTL.from_now.to_i,
        iat: Time.current.to_i,
        jti: SecureRandom.uuid
      }
      JWT.encode(payload, @secret, @algorithm)
    end

    def generate_impersonation_access_token(true_user_id)
      payload = {
        sub: @user.id,
        type: 'user',
        impersonated_by: true_user_id,
        exp: ACCESS_TTL.from_now.to_i,
        iat: Time.current.to_i,
        jti: SecureRandom.uuid
      }
      JWT.encode(payload, @secret, @algorithm)
    end

    def generate_impersonation_refresh_token(true_user_id)
      payload = {
        sub: @user.id,
        type: 'refresh',
        impersonated_by: true_user_id,
        exp: IMPERSONATION_REFRESH_TTL.from_now.to_i,
        iat: Time.current.to_i,
        jti: SecureRandom.uuid
      }
      JWT.encode(payload, @secret, @algorithm)
    end
  end
end
