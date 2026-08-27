# frozen_string_literal: true

class AuthMailer < ApplicationMailer
  def magic_login_code
    @code = params[:code]
    user_id = params[:user_id]
    @user = User.find_by(id: user_id)
    return if @user.nil?

    mail(to: @user.email, subject: '🔐 Seu código de acesso')
  end

  def magic_link
    @magic_url = params[:magic_url]
    @user = User.find_by(id: params[:user_id])

    if @user.nil?
      Rails.logger.warn("[AuthMailer#magic_link] Usuário #{params[:user_id]} não encontrado — email ignorado")
      return
    end

    app_name = ENV.fetch('APP_NAME', 'Safegold')
    mail(to: @user.email, subject: "🔗 Seu link de acesso — #{app_name}")
  end

  # E-mail de **convite** — a única porta de entrada do sistema (DEC-18.7).
  #
  # **Não carrega senha, nem provisória, nem "sua senha inicial é…"** (D-38). O produto
  # não tem senha (DEC-14): o convite carrega um magic link de primeiro acesso, de uso
  # único, e a partir daí a pessoa entra por código como todo mundo.
  #
  # Os dois e-mails de senha do legado ("Perdeu a senha?" e "Nova senha configurada")
  # **não foram portados** (DEC-75) — perderam o objeto.
  def invite
    @user = User.find_by(id: params[:user_id])
    if @user.nil?
      Rails.logger.warn("[AuthMailer#invite] Usuário #{params[:user_id]} não encontrado — convite ignorado")
      return
    end

    @magic_url = params[:magic_url]
    @inviter_name = params[:inviter_name]
    @role_name = params[:role_name]
    app_name = ENV.fetch('APP_NAME', 'Safegold')

    mail(to: @user.email, subject: "Você foi convidado para o #{app_name}")
  end
end
