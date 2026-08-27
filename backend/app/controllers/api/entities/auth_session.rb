# frozen_string_literal: true

module Api
  module Entities
    class AuthSession < Grape::Entity
      expose :success
      expose :message
      expose :user, using: Api::Entities::User, safe: true
      expose :access_token do |obj|
        obj.respond_to?(:[]) ? (obj[:access_token] || obj[:token]) : (obj.try(:access_token) || obj.try(:token))
      end
      expose :token
      # refresh_token NÃO é exposto: vai em cookie HttpOnly (ver AuthHelpers).
      # O valor cru continua acessível ao controller por entity.object.
      # `requires_completion` FOI REMOVIDO desta entity. Ele era o terceiro desfecho do
      # antigo `Auth::VerifyCodeService` e mandava o frontend para a tela "Completar
      # cadastro", que chamava `POST /auth/v1/complete_registration` — rota que a
      # DEC-49 apagou. Nenhum produtor sobrou, e chave de resposta sem produtor é a
      # metade de fronteira que ninguém vê: o cliente escreve o ramo, ele nunca
      # dispara, e a próxima pessoa acha que o fluxo existe.
      expose :is_new_user, if: ->(obj, _opts) { obj.respond_to?(:[]) && obj.key?(:is_new_user) }
    end
  end
end
