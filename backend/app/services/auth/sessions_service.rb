# frozen_string_literal: true

module Auth
  class SessionsService
    include ApiResponseHandler

    def self.status(params)
      new.status(params)
    end

    def self.refresh(params)
      new.refresh(params)
    end

    def self.logout(params)
      new.logout(params)
    end



    def status(params)
      token = params[:token] || extract_token_from_header(params)
      return success_response({ valid: false }) if token.blank?

      begin
        payload = Auth::TokenService.new(nil).decode_token(token)
        # Só o access autentica sessão. O refresh e o token do cable também têm
        # `sub`, então a checagem antiga (`type == 'user' || sub.present?`) os
        # aceitava — bastava um deles chegar como Bearer para o /sessions/status
        # dizer que a sessão é válida.
        #
        # A guarda é por EXCLUSÃO, não por lista branca: o access emitido pelo
        # Warden não traz o claim `type` (medido: nil), então exigir
        # `type == 'user'` derrubaria a sessão real.
        return success_response({ valid: false }) if %w[refresh cable].include?(payload['type'].to_s)

        user = User.find_by(id: payload['sub'])
        return success_response({ valid: false }) unless user

        success_response({
                           valid: true,
                           user: Api::Entities::User.represent(user),
                           expires_at: Time.at(payload['exp'])
                         })
      rescue JWT::ExpiredSignature
        success_response({ valid: false })
      rescue JWT::DecodeError
        success_response({ valid: false })
      end
    end

    def refresh(params)
      refresh_token = params[:refresh_token]
      return unauthorized_response('Refresh token não fornecido') if refresh_token.blank?

      begin
        payload = Auth::TokenService.new(nil).decode_token(refresh_token)
        return unauthorized_response('Tipo de token inválido') unless payload['type'].to_s == 'refresh'

        user = User.find_by(id: payload['sub'])
        return unauthorized_response('Usuário não encontrado') unless user

        # Preserva o claim de impersonação através das rotações de refresh —
        # sem isso, o primeiro refresh (15min) derrubaria a sessão impersonada.
        tokens = if payload['impersonated_by'].present?
                   Auth::TokenService.new(user).generate_impersonation_tokens(payload['impersonated_by'])
                 else
                   Auth::TokenService.new(user).generate_tokens
                 end
        session_payload = {
          user: user,
          token: tokens[:token],
          refresh_token: tokens[:refresh_token]
        }
        success_response(Api::Entities::AuthSession.represent(session_payload))
      rescue JWT::ExpiredSignature
        unauthorized_response('Refresh token expirado')
      rescue JWT::DecodeError
        unauthorized_response('Refresh token inválido')
      end
    end

    def logout(params)
      # Revoga access (Bearer), refresh (cookie) e cable (cookie). Antes só o
      # access ia para a denylist: o refresh sobrevivente reemitia a sessão
      # inteira, e o do cable continuava abrindo WebSocket até expirar.
      tokens = [
        params[:token] || extract_token_from_header(params),
        params[:refresh_token],
        params[:cable_token]
      ].compact_blank

      # **Logout de quem já está deslogado não é erro** (BE-005). Devolvia 422, e o
      # front tratava esse 422 como "falhou" — então o usuário via mensagem de erro ao
      # sair de uma sessão que já tinha expirado, exatamente no momento em que ele
      # menos precisa de um susto. Sem token para revogar, o estado desejado já é o
      # atual: responde 200.
      return success_response({ message: 'Nenhuma sessão ativa para encerrar' }) if tokens.empty?

      tokens.each { |t| revoke_token(t) }

      success_response({ message: 'Logout realizado com sucesso' })
    end

    # Grava o jti na denylist. Best-effort: token ilegível ou já expirado não
    # impede o logout de concluir — o objetivo é derrubar o que ainda vale.
    def revoke_token(token)
      return if token.blank?

      payload = Auth::TokenService.new(nil).decode_token(token, verify_exp: false)
      return unless ActiveRecord::Base.connection.table_exists?('jwt_denylist')

      exp = Time.at(payload['exp'] || Time.current.to_i + 60)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.send(:sanitize_sql_array, [
                                  'INSERT INTO jwt_denylist (jti, exp, created_at, updated_at) VALUES (?, ?, NOW(), NOW())',
                                  payload['jti'] || SecureRandom.uuid,
                                  exp
                                ])
      )
    rescue StandardError => e
      Rails.logger.warn("[SessionsService] Falha ao revogar token: #{e.class} - #{e.message}")
    end

    private

    def extract_token_from_header(params)
      # Extrair token do header Authorization
      auth_header = params[:authorization] || params[:http_authorization]
      return nil if auth_header.blank?

      auth_header.split(' ').last
    end
  end
end
