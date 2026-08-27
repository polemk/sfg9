# frozen_string_literal: true

module Auth
  class MagicLinkVerifyService
    include ApiResponseHandler

    def self.call(token)
      new(token).call
    end

    def initialize(token)
      @token = token.to_s.strip
    end

    def call
      return validation_error_response('Token inválido') if @token.blank?

      # Busca primeiro para dar mensagens de erro específicas
      login_code = LoginCode.by_link_token(@token).first
      return invalid_response unless login_code
      return invalid_response if login_code.expired? || login_code.used?

      # Marca como usado atomicamente — protege contra race condition em múltiplos workers
      user = login_code.user
      return not_found_response unless user

      tokens = nil
      ActiveRecord::Base.transaction do
        rows = LoginCode.where(id: login_code.id, used_at: nil).update_all(used_at: Time.current)
        raise ActiveRecord::Rollback if rows == 0

        user.update_login_stats!
        tokens = Auth::TokenService.new(user).generate_tokens
      end

      return not_found_response if tokens.nil?

      success_response(
        {
          token:         tokens[:token],
          refresh_token: tokens[:refresh_token],
          user:          Api::Entities::User.represent(user)
        },
        200
      )
    rescue StandardError => e
      Rails.logger.error("[MagicLinkVerifyService] #{e.class}: #{e.message}")
      internal_error_response
    end

    private

    def invalid_response
      { status: 404, error: 'link_invalid', message: 'Link inválido, expirado ou já utilizado' }
    end

    def not_found_response
      { status: 404, error: 'link_invalid', message: 'Link inválido ou já utilizado' }
    end
  end
end
