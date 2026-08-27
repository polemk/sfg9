# frozen_string_literal: true

module Api
  module V1
    # Autopreenchimento por CNPJ — DEC-46 (opção c: religado, **com teto por
    # usuário/dia**, porque a consulta é paga).
    #
    # Fica num recurso próprio, e não dentro de `providers`, porque quem consome é
    # qualquer formulário que peça CNPJ: fornecedor (S3/S4), empresa (S4) e portador.
    # Um endpoint por tela seria a mesma integração escrita três vezes.
    class CnpjLookup < Grape::API
      helpers Api::V1::ControllerHelpers

      resource :cnpj do
        desc 'Consulta cadastral de CNPJ (ReceitaWS). O retorno NÃO é persistido.' do
          detail 'Preenche o formulário. Indisponibilidade não impede o cadastro manual.'
        end
        params do
          requires :cnpj, type: String, desc: 'CNPJ com ou sem máscara'
        end
        get ':cnpj', requirements: { cnpj: %r{[0-9./-]+} }, http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [404, 'CNPJ não encontrado'],
          [422, 'CNPJ inválido'],
          [429, 'Limite diário de consultas atingido'],
          [503, 'Integração indisponível']
        ] do
          authenticate_user!
          result = Sfg::ReceitaWs::LookupService.call(cnpj: params[:cnpj], user: acting_user)

          if result[:success]
            status 200
            {
              data: result[:data],
              remaining_quota: Sfg::ReceitaWs::LookupService.remaining_quota(acting_user)
            }
          else
            error!({ error: result[:error], message: result[:error], code: 'CNPJ_LOOKUP_FAILED' },
                   result[:status])
          end
        end

        desc 'Quantas consultas de CNPJ ainda restam hoje para este usuário.'
        get do
          authenticate_user!
          status 200
          {
            enabled: Sfg::ReceitaWs::LookupService.api_key.present?,
            daily_limit: Sfg::ReceitaWs::LookupService.daily_limit,
            remaining_quota: Sfg::ReceitaWs::LookupService.remaining_quota(acting_user)
          }
        end
      end
    end
  end
end
