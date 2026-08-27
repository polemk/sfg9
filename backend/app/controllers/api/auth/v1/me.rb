# frozen_string_literal: true

module Api
  module Auth
    module V1
      class Me < Grape::API
        helpers do
          def current_user
            env['api.current_user']
          end

          def process_service_response(response)
            status response[:status]
            if (200..299).include?(response[:status])
              response[:data]
            else
              error_payload = { error: response[:error] || response[:message] }
              error_payload[:details] = response[:details] if response[:details]
              error!(error_payload, response[:status])
            end
          end
        end

        namespace :me do
          get do
            service = ::Auth::MeService.new(current_user)
            process_service_response(service.show)
          end

          params do
            optional :email, type: String
            optional :phone, type: String
            optional :name, type: String
            optional :avatar_url, type: String
            optional :cpf_cnpj, type: String
            optional :cep, type: String
            optional :street, type: String
            optional :number, type: String
            optional :complement, type: String
            optional :district, type: String
            optional :city, type: String
            optional :state, type: String
            # DEC-74 — perfil estendido. O telefone acima é editável de propósito: a
            # trava do legado NÃO é replicada (ver `Auth::MeService#update`).
            optional :gender, type: String, values: %w[male female other undisclosed]
            optional :birthday, type: Date
            optional :cnpj, type: String
            optional :fiscal_document_number, type: String
            optional :fiscal_document_issued_at, type: Date
            optional :graduation, type: String
          end
          patch do
            csrf_header = headers['X-CSRF-Token'] || headers['HTTP_X_CSRF_TOKEN']
            error!({ error: 'csrf_required', message: 'CSRF token ausente' }, 403) unless csrf_header.present?

            # `declared(params, include_missing: false)` entrega ao serviço **só o que o
            # cliente mandou**, sem os parâmetros de rota. É a forma idiomática do Grape de
            # dizer "isto veio do corpo".
            #
            # **A correção do defeito, porém, foi tirar o `.compact` do serviço** — está
            # escrito lá, e o teste que a trava é o contexto "limpando campos do perfil
            # estendido" em `spec/requests/api/auth/v1/me_spec.rb`. Medido: recolocando o
            # `.compact`, três dos quatro exemplos voltam a responder 422.
            service = ::Auth::MeService.new(current_user)
            process_service_response(service.update(declared(params, include_missing: false), csrf_header))
          end
        end
      end
    end
  end
end
