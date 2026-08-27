# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      handle_oauth('google')
    end

    def facebook
      handle_oauth('facebook')
    end

    private

    def handle_oauth(provider)
      auth = request.env['omniauth.auth']
      info = auth.info || {}
      uid = auth.uid
      # DEC-44 — **casa, nunca cria.** Este callback é a segunda superfície de login
      # social (a primeira é `POST /auth/v1/oauth/callback`), e as duas precisam da
      # mesma regra: se aqui criasse conta, o D-39 voltaria por esta porta enquanto a
      # outra ficasse fechada.
      user = User.find_for_oauth(provider, uid, {
                                   email: info['email'],
                                   name: info['name'],
                                   image: info['image']
                                 })

      return redirect_to_frontend_error(provider, 'invite_only') if user.nil?
      return redirect_to_frontend_error(provider, 'account_blocked') if user.blocked?

      sign_in(user)
      token_service = Auth::TokenService.new(user)
      tokens = token_service.generate_tokens

      # Os tokens saíam na query string do redirect — e URL completa vai parar no
      # histórico do navegador, no header Referer de qualquer recurso externo da
      # página e no log de acesso do nginx. Agora vão em cookie HttpOnly e o
      # frontend troca o refresh por um access no callback.
      set_oauth_cookies(user, tokens)

      # allow_other_host é obrigatório: com load_defaults 8.0 o
      # raise_on_open_redirects vem ligado, e o FRONTEND_CALLBACK_URL aponta para
      # o domínio do front — outro host que o da API. Sem a flag este redirect
      # levanta ActionController::Redirect::UnsafeRedirectError.

      redirect_to (ENV['FRONTEND_CALLBACK_URL'] || ENV['OAUTH_REDIRECT_URI'] || '/auth/callback') +
                  "?provider=#{provider}&oauth=success", allow_other_host: true
    end

    # O front lê `?oauth=error&reason=...` e mostra a explicação na tela de login,
    # em vez do redirect mudo para "/" que não diz nada a quem tentou entrar.
    def redirect_to_frontend_error(provider, reason)
      base = ENV['FRONTEND_CALLBACK_URL'] || ENV['OAUTH_REDIRECT_URI'] || '/auth/callback'
      redirect_to "#{base}?provider=#{provider}&oauth=error&reason=#{reason}", allow_other_host: true
    end

    # Mesmos atributos do Api::Auth::V1::AuthHelpers — aqui é um controller do
    # Devise (Rails puro), fora do alcance dos helpers do Grape.
    def set_oauth_cookies(user, tokens)
      cookies['refresh_token'] = {
        value: tokens[:refresh_token],
        path: '/auth/v1',
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Auth::TokenService::REFRESH_TTL.from_now
      }
      cookies['cable_token'] = {
        value: Auth::TokenService.new(nil).cable_token_for(user.id),
        path: '/cable',
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Auth::TokenService::CABLE_TTL.from_now
      }
    end
  end
end
