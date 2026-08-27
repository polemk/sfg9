# frozen_string_literal: true

module Auth
  class EmailService
    include ActiveModel::Model
    include ApiResponseHandler

    attr_accessor :user, :code

    validates :user, presence: true
    # `code` só é exigido no caminho do código de acesso; o convite não tem código.
    validates :code, presence: true, on: :magic_login_code

    def initialize(attributes = {})
      super
    end

    def send_magic_login_code
      unless valid?(:magic_login_code)
        return validation_error_response('Dados inválidos', details: errors.full_messages)
      end

      AuthMailer.with(user_id: user.id, code: code).magic_login_code.deliver_later
      success_response({
                         message: 'Email enviado com sucesso',
                         email: user.email,
                         subject: "🔐 Seu código de acesso — #{ENV.fetch('APP_NAME', 'Safegold')}"
                       })
    rescue StandardError => e
      Rails.logger.error "[EmailService] Erro ao enviar email: #{e.message}"
      internal_error_response("Erro ao enviar email: #{e.message}")
    end

    # Convite (BE-012 / OPS-001). Emite um `LoginCode` com `link_token` de **uso
    # único** e manda o link por e-mail. Nenhuma senha sai daqui (D-38).
    def send_invite(inviter: nil, magic_url: nil)
      return validation_error_response('Usuário sem e-mail para convidar') if user&.email.blank?

      AuthMailer.with(
        user_id: user.id,
        magic_url: magic_url,
        inviter_name: inviter&.name,
        role_name: user.user_type&.display_name
      ).invite.deliver_later

      success_response({ message: 'Convite enviado', email: user.email })
    rescue StandardError => e
      Rails.logger.error "[EmailService] Erro ao enviar convite: #{e.message}"
      internal_error_response("Erro ao enviar convite: #{e.message}")
    end
  end
end
