# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class Base < Grape::API
        format :json
        prefix :auth
        version 'v1', using: :path

        helpers Api::Auth::V1::AuthHelpers
        # Helpers de segurança do caminho de entrada (current_ip, current_user_agent,
        # check_brute_force!, check_rate_limit!). Declarados ANTES dos `mount` de
        # propósito: é assim que a API montada os herda — ver o cabeçalho de
        # `security_helpers.rb`.
        helpers Api::Auth::V1::SecurityHelpers

        # Monta os endpoints de autenticação
        mount Api::Auth::V1::MagicLogin
        mount Api::Auth::V1::CodeValidation
        mount Api::Auth::V1::Oauth
        mount Api::Auth::V1::Sessions
        mount Api::Auth::V1::Me
        mount Api::Auth::V1::Registration
        mount Api::Auth::V1::Impersonate
        mount Api::Auth::V1::MagicLink

        # Tratamento de erros específico seguindo padrão do Api::V1::Base
        rescue_from :all do |e|
          unless (e.is_a? Grape::Exceptions::ValidationErrors) ||
                 (e.is_a? Grape::Exceptions::MethodNotAllowed) ||
                 e.message.include?('Mysql2::Error') ||
                 (e.is_a? PG::Error)

            env = {}
            env['exception_notifier.exception_data'] = {
              api: 'API AUTH - POLEMK WHATS',
              message: e.message,
              user: 'No User.',
              environment: Rails.env
            }
          end

          # Log de erro
          error_backtrace = "ERROR - API AUTH POLEMK: #{e.message} <br/> \n BACKTRACE: #{e.backtrace.join "\n"}"
          Rails.logger.warn error_backtrace

          if e.is_a?(Grape::Exceptions::ValidationErrors)
            error!({
                     error: 'validation_error',
                     message: 'Dados inválidos',
                     details: e.errors
                   }, 400)
          else
            error!({
                     error: 'internal_error',
                     message: 'Erro interno no servidor'
                   }, 500)
          end
        end
      end
    end
  end
end
