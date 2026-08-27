# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # **Conexao sem usuario verificado e RECUSADA.**
    #
    # Antes era `self.current_user = user if user.present?` — sem `reject`. Ou
    # seja: token ausente, invalido ou revogado **abria o WebSocket assim
    # mesmo**, so que anonimo. A defesa ficava por conta de cada canal, e nem
    # todos defendiam: o `WhatsappInstanceChannel` so conferia se a instancia
    # existia, entao um anonimo podia assinar e **receber o QR de pareamento** —
    # que e credencial de acesso a conta de WhatsApp.
    #
    # O sintoma que denunciava isso estava a vista: o `unsubscribed` daquele
    # canal precisava de `connection.try(:current_user)` porque `current_user`
    # podia nao existir. Um `identified_by` que pode nao estar preenchido e um
    # `identified_by` que nao identifica.
    #
    # Nenhum canal do sistema serve anonimo: `ProjectProgress` e `Renegotiation`
    # ja faziam `reject if current_user.blank?`, e `Permissions` recusa quando o
    # id nao e o proprio. Recusar na conexao e o mesmo criterio, um degrau acima.
    def connect
      self.current_user = find_verified_user || reject_unauthorized_connection
    end

    private

    def find_verified_user
      token = connection_token
      return nil if token.blank?

      begin
        payload = nil
        payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
        payload ||= Auth::TokenService.new(nil).decode_token(token, verify_exp: true)

        # O decoder do Warden não consulta a jwt_denylist — sem isto um token
        # revogado no logout continuaria abrindo WebSocket até expirar.
        return nil if Auth::TokenService.revoked?(payload)
        # Refresh nunca autentica cable; aceitamos 'cable' (cookie) e 'user' (fallback)
        return nil if payload['type'] == 'refresh'

        uid = payload['sub'] || payload['user_id']
        User.find_by(id: uid)
      rescue StandardError
        nil
      end
    end

    # Preferência: cookie HttpOnly com escopo /cable — não trafega na URL, então
    # não vaza no log de acesso do proxy. O fallback ao query param mantém
    # clientes antigos funcionando durante a transição do frontend.
    def connection_token
      request.cookies['cable_token'].presence || request.params[:token].presence
    end

    def decode_user_id(token)
      payload = Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
      payload['sub'] || payload['user_id']
    end
  end
end
