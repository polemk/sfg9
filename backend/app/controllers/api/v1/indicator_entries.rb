# frozen_string_literal: true

module Api
  module V1
    # S10 / BE-324, BE-326, BE-327, BE-328, BE-716, BE-717 — **a grade mensal**.
    #
    # É a tela que o usuário de verdade usa todo mês: 12 meses × indicador, com
    # gravação por célula. **Escopado por projeto** (contrato C1) — cada ação
    # declara `project = current_project!`, e o `project_id` do corpo (que no
    # legado estava no `permit` e num campo escondido do formulário) não existe.
    #
    # ## O contrato C2 em uma frase
    #
    # `GET grid` e `PUT ''` chamam o **mesmo** `::Indicators::EntryService`. No
    # legado a leitura era feita dentro da view e a escrita era um `$.ajax` por
    # campo: os dois lados não se conheciam, e é por isso que a célula podia
    # mostrar `0` para um mês nunca lançado e mostrar "salvo" para uma gravação
    # recusada.
    #
    # ## Autorização (BE-717)
    #
    # No legado **não há um único `before_action` de permissão** nos três
    # controllers do módulo: qualquer autenticado podia `POST /indicator_entries`
    # direto, inclusive quem tinha `user_is_readonly` (que só desabilitava o
    # campo no HTML). Aqui há `authorize!` em todo verbo, e o
    # `require_not_readonly!` global cobre o readonly (FE-718).
    class IndicatorEntries < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'indicator_entries'

      namespace :indicator_entries do
        before { authenticate_user! }

        desc 'A grade mensal do projeto' do
          summary 'Grade de lançamentos'
          detail 'BE-324 — UMA consulta. O legado buscava as entries DENTRO da view, uma por (indicador × ' \
                 'mês), e o mesmo método era chamado duas vezes por célula: 24 idas ao banco por indicador ' \
                 'no modo "todos os meses". `entry: null` = NÃO LANÇADO, distinguível de lançado como zero ' \
                 '(DEC-70). **Este é o endpoint que a S15 consome para o gráfico NEW-001** — nenhuma ' \
                 'agregação nova nasce no cliente (contrato C2).'
          success [code: 200, model: Api::Entities::IndicatorGridRow]
          is_array true
        end
        params do
          optional :year, type: Integer, desc: 'Ano. Default: o corrente'
          optional :month, type: Integer, values: 1..12, desc: 'Omitido = os 12 meses'
          optional :indicator_id, type: String, desc: 'Um indicador só'
        end
        get 'grid' do
          authorize!(RESOURCE, :read)
          projeto = current_project!

          linhas = ::Indicators::EntryService.grid(
            project: projeto,
            year: params[:year] || Date.current.year,
            month: params[:month],
            indicator_id: params[:indicator_id]
          )
          Api::Entities::IndicatorGridRow.represent(linhas)
        end

        desc 'Grava UMA célula da grade (upsert)' do
          detail 'BE-326 — três correções: (1) o autor vem da SESSÃO, e não do campo escondido do ' \
                 'formulário, que estava no `permit` e permitia lançar em nome de outro usuário; ' \
                 '(2) é upsert, então a segunda aba deixa de receber "já está em uso" em vez de atualizar; ' \
                 '(3) o projeto vem do escopo.'
        end
        params do
          requires :indicator_id, type: String
          requires :year, type: Integer
          requires :month, type: Integer, values: 1..12
          requires :value, type: BigDecimal, desc: 'Aceita negativos. Zero é um lançamento válido'
        end
        put '' do
          authorize!(RESOURCE, :update)
          projeto = current_project!

          resultado = ::Indicators::EntryService.upsert(
            project: projeto, indicator_id: params[:indicator_id], year: params[:year],
            month: params[:month], value: params[:value], actor: acting_user
          )
          error!(error_payload_for(resultado), resultado[:status]) unless [200, 201].include?(resultado[:status])

          status resultado[:status]
          Api::Entities::IndicatorEntry.represent(resultado[:data])
        end

        desc 'Atualiza um lançamento pelo id' do
          detail 'BE-327 — `indicator_id` nulo devolve 422, não 500 (no legado `self.indicator.title` ' \
                 'levantava NoMethodError no `before_validation`). Mover o lançamento de período deixa de ' \
                 'ser silencioso.'
        end
        params do
          requires :id, type: String
          optional :indicator_id, type: String
          optional :year, type: Integer
          optional :month, type: Integer, values: 1..12
          optional :value, type: BigDecimal
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          projeto = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          resultado = ::Indicators::EntryService.update(project: projeto, id: params[:id], attrs: attrs,
                                                       actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::IndicatorEntry.represent(resultado[:data])
        end

        desc 'Apaga um lançamento — endpoint SEM tela (DEC-71)' do
          detail 'A rota existe no legado (`routes.rb:84`) e NENHUMA view a chama: zero ocorrências de ' \
                 'excluir/remover/data-method na pasta de lançamentos. Na prática "zerar" é digitar 0. ' \
                 'A DEC-71 mandou portar o endpoint SEM botão — e, com a DEC-70, apagar passa a ter efeito ' \
                 'visível: a célula volta ao estado "não lançado", agora distinguível de zero. ' \
                 'Pela condição 1 do DEC-53, endpoint sem tela continua exigindo autorização e escopo.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          projeto = current_project!

          resultado = ::Indicators::EntryService.destroy(project: projeto, id: params[:id], actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end
    end
  end
end
