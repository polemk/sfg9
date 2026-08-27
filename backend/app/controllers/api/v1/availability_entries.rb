# frozen_string_literal: true

module Api
  module V1
    # S11 / BE-120..124, BE-131 — **a grade de lançamentos de disponibilidade**.
    #
    # Escopado por projeto: toda ação declara `project = current_project!`, e o
    # `project_id` do corpo não é declarado nos `params do` (contrato C1).
    #
    # ## A rota `index` do legado NÃO é portada (BE-121, DC-19 / DEC-09)
    #
    # `Pub::AvailabilityEntriesController#index` renderizava
    # `pub/availability_entries/index`, template que **não existe** no repositório
    # legado (`app/views/pub/availability_entries/` só tem os parciais de
    # `console/parts`). Qualquer requisição a ela respondia `MissingTemplate`.
    # É código vestigial, com evidência, e fica `dropped` no ledger.
    class AvailabilityEntries < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'availability_entries'

      namespace :availability_entries do
        before { authenticate_user! }

        desc 'A grade de lançamentos de um dia' do
          summary 'Grade de disponibilidade'
          detail 'BE-120 — montada em consultas AGREGADAS (duas), não uma por padrão como no legado. ' \
                 '`company_id` inválido responde **422**, em vez de cair calado na consolidação geral. ' \
                 '**Ler a grade não cria registro** (DC-30).'
          success [code: 200, model: Api::Entities::AvailabilityGridRow]
          is_array true
        end
        params do
          optional :date, type: String, desc: 'AAAA-MM-DD. Em branco devolve grade vazia'
          optional :company_id, type: String, desc: 'Em branco = consolidação geral'
          optional :q, type: String, desc: 'Filtra as linhas pelo título do padrão'
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          resultado = ::Availability::GridService.grid(project: project, date: params[:date],
                                                     company_id: params[:company_id], query: params[:q])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          {
            date: resultado[:data][:date]&.to_s,
            company_id: resultado[:data][:company]&.id,
            # DEC-26 — o rótulo do modo de leitura. Sem empresa escolhida a
            # grade é a **consolidação geral**, que soma bruto; com empresa, os
            # nós com filhos aplicam cumulatividade e sinal. Duas regras na
            # mesma tela, de propósito, e o usuário sabe qual está lendo.
            mode: resultado[:data][:company] ? 'company' : 'consolidation',
            mode_label: resultado[:data][:company] ? 'Empresa' : 'Consolidação geral — soma bruta',
            rows: Api::Entities::AvailabilityGridRow.represent(resultado[:data][:rows]).as_json
          }
        end

        desc 'Cria um lançamento' do
          detail 'BE-122 — duplicidade responde 422 pelo índice único do banco, e **nada é destruído ' \
                 'em caso de falha**: o legado chamava `destroy` sobre registro não persistido.'
        end
        params do
          requires :availability_template_id, type: String
          requires :company_id, type: String, desc: 'Obrigatório: consolidação geral não é lançável'
          requires :date, type: String
          requires :value, type: BigDecimal
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          resultado = ::Availability::EntryService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::AvailabilityEntry.represent(resultado[:data])
        end

        desc 'Atualiza o valor de um lançamento' do
          detail 'BE-123 — **uma única gravação** (o legado fazia `update` E `save`, e a segunda ' \
                 'gravação multiplicava o valor de novo num padrão corrigido). Consolidação geral ' \
                 'não é editável nem por envio direto. Padrão bloqueado → **409**.'
        end
        params do
          requires :id, type: String
          requires :value, type: BigDecimal
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          resultado = ::Availability::EntryService.update(project: project, id: params[:id],
                                                        attrs: attrs, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityEntry.represent(resultado[:data])
        end

        desc 'Exclui um lançamento' do
          detail 'BE-124 / DC-26 — **a exclusão não cria registro**. No legado `parent_entry` era ' \
                 'chamado ANTES do destroy e criava o pai (com um `TODO #7408` admitindo que o ' \
                 'cenário multiempresa não tinha sido fechado).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          resultado = ::Availability::EntryService.destroy(project: project, id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end
    end
  end
end
