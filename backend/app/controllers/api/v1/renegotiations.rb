# frozen_string_literal: true

module Api
  module V1
    # S9 / BE-190..BE-201, BE-202, BE-209..BE-212 — **renegociações**.
    #
    # O contrato **C1** é aplicado aqui, no endpoint, com `current_project!` —
    # nunca com `default_scope`. É a correção literal de
    # `pub/renegotiations_controller.rb:23-24`, onde a segunda linha reatribuía a
    # relação escopada e o filtro de projeto desaparecia: qualquer sessão lia a
    # renegociação de qualquer projeto passando `renegotiation_id` na query
    # string. **Este é o maior risco do bloco** — família D-01 / D-16 / D-29 /
    # D-76 / D-100.
    #
    # Quatro defeitos de listagem morrem de uma vez:
    #
    # - **D-20 / BE-194** — `l` e `o` eram lidos, guardados em variável de
    #   instância e **nunca aplicados**; e o `where!` do ramo com busca
    #   **descartava** a relação que o `limit`/`offset` tinha acabado de produzir.
    #   Aqui é Kaminari com envelope em cabeçalho (DEC-62).
    # - **D-49 / BE-191** — o `case params[:state]` não tinha `when "empty"`, caía
    #   no `else` com um `return` que abortava a action no meio e a tela dava 500.
    # - **BE-190** — a busca só casava `provider_name`, apesar de a primeira coluna
    #   da lista ser "Nome" (`title`). Agora casa os dois.
    # - **BE-193** — chave de ordenação desconhecida produzia `nil + " "` →
    #   `NoMethodError` → 500. `Sfg::Sortable` ignora o que não conhece.
    class Renegotiations < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'renegotiations'

      namespace :renegotiations do
        before { authenticate_user! }

        desc 'Lista as renegociações do projeto corrente' do
          summary 'Renegociações'
          success [code: 200, model: Api::Entities::Renegotiation]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca no NOME da renegociação OU no do fornecedor (BE-190)'
          optional :renegotiation_id, type: String, desc: 'Filtro por id — DENTRO do escopo do projeto'
          optional :state, type: String, values: %w[closed open inconsistent empty],
                           desc: 'Inclui `empty` — o legado abortava a action sem ele (D-49)'
          optional :kind, type: String, values: ::Renegotiation::KINDS
          optional :order_mode, type: String, values: %w[dash]
          optional :ordering_keys, type: Array[String],
                                   desc: 'title | provider | state | kind | renegotiation_date | ' \
                                         'total_debt | remaining_value | created_at'
          optional :ordering_style, type: Array[String]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = RenegotiationService.index(project: project, params: params)[:data]
          pagina = paginate(scope)

          # **Vencidas apuradas na consulta** (OPS-190), numa consulta só para a
          # página inteira. É o que substitui o cron diário sem virar N+1.
          representar(pagina.to_a)
        end

        desc 'Tipos e estados aceitos — a tela não tem lista escrita nela'
        get :options do
          authorize!(RESOURCE, :read)
          status 200
          {
            kinds: ::Renegotiation::KINDS,
            origins: ::Renegotiation::ORIGINS,
            states: ::Renegotiation::STATE_FILTERS.map { |chave, rotulo| { value: chave, label: rotulo } },
            delay_types: ::RenegotiationInstallment::DELAY_TYPES
          }
        end

        desc 'Detalhe de uma renegociação'
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          resultado = RenegotiationService.show(project: project, id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          representar(resultado[:data])
        end

        desc 'Painel de consistência do lançamento (BE-195)' do
          detail 'Corrige D-48: no legado o hash era montado e DESCARTADO — a resposta era o JSON cru do ' \
                 'registro, e o `to_json` sobrescrito ainda levantava ArgumentError.'
        end
        params { requires :id, type: String }
        get ':id/general_values' do
          authorize!(RESOURCE, :read)
          project = current_project!

          resultado = RenegotiationService.general_values(project: project, id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end

        desc 'Cria uma renegociação' do
          detail 'Recalcula os agregados NA CRIAÇÃO (BE-198): no legado o registro nascia zerado e ' \
                 '"Inconsistente" até alguém mexer numa parcela.'
        end
        params do
          requires :provider_id, type: String
          requires :company_id, type: String
          requires :kind, type: String, values: ::Renegotiation::KINDS
          requires :renegotiation_date, type: Date
          requires :operation_interest_rate, type: Float
          optional :title, type: String
          optional :observation, type: String
          optional :origin, type: String
          optional :monetary_correction, type: String
          optional :original_value, type: BigDecimal
          optional :original_pending_value, type: BigDecimal
          optional :additional_value, type: BigDecimal
          optional :total_debt, type: BigDecimal
          optional :desagio_value, type: BigDecimal
          optional :interest_rate_correction, type: Float
          optional :grace_period, type: Integer
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          resultado = RenegotiationService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::Renegotiation.represent(resultado[:data])
        end

        desc 'Atualiza uma renegociação'
        params do
          requires :id, type: String
          optional :provider_id, type: String
          optional :company_id, type: String
          optional :kind, type: String, values: ::Renegotiation::KINDS
          optional :renegotiation_date, type: Date
          optional :operation_interest_rate, type: Float
          optional :title, type: String
          optional :observation, type: String
          optional :origin, type: String
          optional :monetary_correction, type: String
          optional :original_value, type: BigDecimal
          optional :original_pending_value, type: BigDecimal
          optional :additional_value, type: BigDecimal
          optional :total_debt, type: BigDecimal
          optional :desagio_value, type: BigDecimal
          optional :interest_rate_correction, type: Float
          optional :grace_period, type: Integer
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          resultado = RenegotiationService.update(project: project, id: params[:id], attrs: attrs,
                                                  actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::Renegotiation.represent(resultado[:data])
        end

        desc 'Remove uma renegociação' do
          detail 'Só sem parcelas e sem pagamentos; os anexos vão junto. Corrige D-24 — o legado respondia ' \
                 '`errors.any? ? :ok : :ok` com template VAZIO: a tela dizia sucesso e o registro voltava.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          resultado = RenegotiationService.destroy(project: project, id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end

      helpers do
        # Uma forma só de representar renegociação, com os dois derivados que
        # vêm de CONSULTA e não de coluna. Duplicar isto entre a lista e o
        # detalhe seria o caminho para um dos dois mostrar o número velho.
        def representar(registros)
          lista = Array(registros)
          ids = lista.map(&:id)
          proximas = next_installments_for(lista)
          Api::Entities::Renegotiation.represent(
            registros,
            overdue_counts: ::Renegotiations::AggregateService.live_overdue_for(::Renegotiation.where(id: ids)),
            next_due_dates: proximas.transform_values(&:due_date),
            next_installment_values: proximas.transform_values(&:main_value_with_interest_cm)
          )
        end

        # A PRÓXIMA PARCELA de cada renegociação da página, numa consulta.
        #
        # Substitui as N+2 consultas por linha do legado
        # (`calculate_next_installment_value` + `_date`,
        # `renegotiation.rb:162-173`, cada uma repetindo o mesmo
        # `where … order … first`) **sem alterar o número**: o `upcoming` do
        # model é o mesmo filtro daquele `where` — não paga, vencimento a partir
        # de hoje — e a ordem por `due_date, number` desempata o dia em que caem
        # duas parcelas, coisa que o `order(due_date: :asc).first` do legado
        # resolvia por acaso da ordem física da tabela.
        #
        # **BE-211 — devolve a LINHA, não só a data.** Antes daqui só a data
        # viajava, e a coluna "Valor da próxima parcela" que o legado renderizava
        # (`list/_widget.html.erb:22`) tinha sumido da listagem: o cálculo não
        # existia em ponta nenhuma do ai9. Achado pela conferência de paridade da
        # Phase 4. Como as duas colunas saem da MESMA linha, buscá-la uma vez é
        # também menos trabalho do que as duas agregações separadas.
        #
        # `DISTINCT ON` e não `minimum`: agregação devolve um valor por grupo, e
        # aqui é preciso a linha inteira.
        def next_installments_for(renegotiations)
          ids = Array(renegotiations).map(&:id)
          return {} if ids.empty?

          ::RenegotiationInstallment
            .where(renegotiation_id: ids)
            .upcoming
            .select('DISTINCT ON (renegotiation_id) *')
            .order(:renegotiation_id, :due_date, :number)
            .index_by(&:renegotiation_id)
        end
      end
    end
  end
end
