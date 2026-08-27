# frozen_string_literal: true

module Auth
  # Convite — **a única porta de entrada do sistema** (DEC-18.7 / BE-012 / OPS-001).
  #
  # O legado deixava qualquer pessoa na internet se cadastrar até a hierarquia 998
  # (`minimal_type_to_sign_up_through_web = "Admin"`, `config/application.rb:84`): é o
  # D-39. A DEC-49 removeu as 4 rotas de auto-cadastro; a DEC-44 fechou o login social
  # como porta alternativa. Sobra este caminho, e ele exige que **alguém com permissão
  # emita o convite** e que **o papel seja explícito**.
  #
  # Duas regras que não são detalhe:
  #
  #  - **papel explícito, nunca `Admin` fixo.** Era assim que o D-39 escalava: o
  #    cadastro nascia Admin porque o valor padrão dizia Admin;
  #  - **hierarquia inferior.** Quem convida não cria alguém com poder igual ou maior
  #    que o seu — senão o convite vira a autopromoção que a DEC-18.2 fechou na tela de
  #    permissões, só que por outra rota.
  class InviteService
    include ApiResponseHandler

    # 24 horas, igual ao que o e-mail de convite promete. Um número, dois lugares:
    # se mudar aqui, mude o texto do template junto.
    LINK_TTL = 24.hours

    def self.call(inviter:, user:)
      new(inviter: inviter, user: user).call
    end

    def initialize(inviter:, user:)
      @inviter = inviter
      @user = user
    end

    def call
      return validation_error_response('Usuário sem e-mail — o convite não tem para onde ir') if @user.email.blank?

      login_code = build_login_code
      Auth::EmailService.new(user: @user).send_invite(inviter: @inviter, magic_url: magic_url_for(login_code))

      success_response({ message: 'Convite enviado', email: @user.email, expires_at: login_code.expires_at }, 200)
    rescue StandardError => e
      Rails.logger.error("[InviteService] #{e.class}: #{e.message}")
      internal_error_response(e.message)
    end

    private

    # O `link_token` tem índice ÚNICO em `login_codes` e `MagicLinkVerifyService`
    # consome de forma atômica (`update_all(used_at:)` condicionado a `used_at IS
    # NULL`). Uso único de verdade, não "uso único se ninguém clicar duas vezes".
    def build_login_code
      LoginCode.create!(
        user: @user,
        # DEC-108 — marca quem convidou. É o que permite contar convites em
        # aberto e aplicar `max_invitations_amount`; sem isso o teto seria um
        # número na tela sem nada para comparar, que foi o defeito do legado.
        invited_by: @inviter,
        destination: @user.email,
        method: 'email',
        code: SecureRandom.random_number(1_000_000).to_s.rjust(6, '0'),
        link_token: SecureRandom.urlsafe_base64(32),
        expires_at: LINK_TTL.from_now,
        attempts: 0
      )
    end

    def magic_url_for(login_code)
      base = ENV['APP_HOST'].presence || 'http://localhost:5173'
      "#{base.chomp('/')}/magic-login?token=#{login_code.link_token}"
    end
  end
end
