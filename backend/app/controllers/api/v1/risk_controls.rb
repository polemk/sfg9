# frozen_string_literal: true

module Api
  module V1
    # S5 / BE-230..BE-241, BE-252, BE-231 — **limites de risco** e o **console de
    # exposição**.
    #
    # **Toda ação declara o escopo numa linha visível**: `project = current_project!`
    # (contrato C1). O `project_id` que vier no corpo é sempre ignorado — ele nem
    # é declarado nos `params do`.
    #
    # ### BE-233 — `new` e `edit` deixam de ser rotas
    #
    # No legado `new`, `edit` e `show` eram actions que renderizavam parciais de
    # formulário via `format: :js`. No ai9 abrir o formulário é **estado de tela**
    # (o drawer), não uma ida ao servidor: o `GET :id` devolve o registro e a tela
    # decide o que fazer com ele. As três actions vão para `dropped` com
    # evidência — a do `show` renderizava `pub/console/parts/risk_controls/detail/body`,
    # que **não existe** no repositório legado, ou seja, dava 500 em toda chamada.
    #
    # ### A ordem das rotas importa
    #
    # `get 'summary'`, `get 'filters'` e `get 'available'` vêm **antes** de
    # `get ':id'`. Invertido, `:id` casaria com a palavra e o console viraria uma
    # busca por um limite chamado "summary".
    class RiskControls < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'risk_controls'
      # O console é outro item de menu e outra linha da matriz.
      CONSOLE_RESOURCE = 'risk'

      helpers do
        # Contagem de uso da PÁGINA, em uma consulta por dependente. É o mesmo
        # número que o servidor usa para responder 422 na exclusão.
        def risk_control_usage(registros)
          ids = Array(registros).map(&:id)
          return {} if ids.empty?

          RiskControl.blocking_dependents.each_with_object(Hash.new(0)) do |(class_name, config), acc|
            coluna = config.fetch(:foreign_key)
            klass = BlockingDependents.dependent_class_with_column(class_name, coluna)
            next if klass.nil?

            klass.where(coluna => ids).group(coluna).count.each { |id, total| acc[id] += total }
          end
        end

        # Resolve empresa e portador **dentro** do projeto corrente. Id de fora
        # responde 404, igual a id inexistente — o endpoint não confirma a
        # existência de registro alheio.
        def scoped_company!(project, id)
          return nil if id.blank?

          company = Risk::ControlService.uuid?(id) ? Company.for_project(project).find_by(id: id) : nil
          error!({ error: 'not_found', message: 'Empresa não encontrada.' }, 404) if company.nil?
          company
        end

        def scoped_carrier!(project, id)
          return nil if id.blank?

          # Mesmo critério único da S4: a conexão. `Carrier` é catálogo global
          # e não declara a associação, então é subconsulta, não `joins`.
          carrier =
            if Risk::ControlService.uuid?(id)
              Carrier.where(id: ProjectToCarrierConnection.for_project(project).select(:carrier_id))
                     .find_by(id: id)
            end
          error!({ error: 'not_found', message: 'Portador não encontrado neste projeto.' }, 404) if carrier.nil?
          carrier
        end
      end

      namespace :risk_controls do
        before { authenticate_user! }

        # ------------------------------------------------------------------
        # BE-231 — o payload do console "Controle de Risco"
        # ------------------------------------------------------------------
        desc 'Resumo de exposição por limite (console de risco)' do
          summary 'Console de risco'
          detail 'Sem `company_id`, agrega o PROJETO inteiro (a opção "Grupo econômico" da tela); ' \
                 'com `company_id`, agrega a empresa. `is_single` (presença de `carrier_id`) troca o layout. ' \
                 '**Os dois ramos NÃO produzem os mesmos rótulos** — ver `Risk::AggregateService`: os dois ' \
                 'erros do D-95 existem só no caminho da empresa, e a DEC-01 manda replicar os dois. ' \
                 '`carrier_id` inexistente → 404 (no legado, `Carrier.find` → 500). ' \
                 '`date` malformada → 400, validada pelo Grape.'
        end
        params do
          optional :company_id, type: String, desc: 'Vazio = grupo econômico (projeto inteiro)'
          optional :carrier_id, type: String, desc: 'Preenchido = layout de portador único'
          optional :date, type: Date, default: -> { Date.current },
                          desc: 'Posição do dia. A tela não permite data futura (FE-233).'
        end
        get 'summary' do
          authorize!(CONSOLE_RESOURCE, :read)
          project = current_project!

          company = scoped_company!(project, params[:company_id])
          carrier = scoped_carrier!(project, params[:carrier_id])

          Risk::AggregateService.summary_on(
            project: project, company: company, carrier: carrier, date: params[:date]
          )
        end

        # ------------------------------------------------------------------
        # BE-232 — combos auxiliares
        # ------------------------------------------------------------------
        desc 'Portadores com limite ATIVO (filtro do console)' do
          detail 'FE-232 — a lista vem dos limites ativos do projeto (ou da empresa), com `.uniq`. ' \
                 'No legado a tela de Limites populava o mesmo select com `Carrier.all` (FE-241).'
        end
        params { optional :company_id, type: String }
        get 'filters' do
          authorize!(CONSOLE_RESOURCE, :read)
          project = current_project!

          result = Risk::ControlService.controls_filter(project: project, company_id: params[:company_id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Carrier.represent(result[:data])
        end

        desc 'Portadores conectados ao projeto da empresa (cascata do formulário)' do
          detail 'BE-232 — a cascata empresa → portador do formulário de limite. `company_id` inválido → 404, não 500.'
        end
        params { requires :company_id, type: String }
        get 'carriers' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::ControlService.carriers_for_company(project: project, company_id: params[:company_id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Carrier.represent(result[:data])
        end

        desc 'Limites ainda livres para lançar posição numa data' do
          detail 'BE-252 — limites ATIVOS sem nenhuma operação vigente na data. ' \
                 '**Consequência a preservar:** limite de tipo COM pré-faturamento nunca aparece aqui, ' \
                 'porque o par estático está sempre na janela. É o contrato que a S6 consome (OPS-238).'
        end
        params do
          optional :company_id, type: String
          optional :date, type: Date, default: -> { Date.current }
        end
        get 'available' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::ControlService.available_for_entry_on(
            project: project, company_id: params[:company_id], date: params[:date]
          )
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::RiskControl.represent(result[:data])
        end

        # ------------------------------------------------------------------
        # BE-230 — lista
        # ------------------------------------------------------------------
        desc 'Lista os limites de risco do projeto corrente' do
          summary 'Limites'
          detail '**IMP-R3**: o parâmetro `q` passa a FILTRAR. No legado ele era lido, recebia `""` por ' \
                 'default e nunca era aplicado ao `where` — a caixa de busca não fazia nada e a mensagem ' \
                 'de "nenhum resultado" era inalcançável.'
          success [code: 200, model: Api::Entities::RiskControl]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por portador, empresa ou título do limite'
          optional :company_id, type: String
          optional :carrier_id, type: String
          optional :risk_operation_type_id, type: String
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | limite | taxa | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::ControlService.index(project: project, params: params)
          registros = paginate(result[:data]).to_a
          Api::Entities::RiskControl.represent(registros, usage: risk_control_usage(registros))
        end

        desc 'Detalhe de um limite' do
          detail 'Id de OUTRO projeto responde 404, igual a id inexistente (C1).'
        end
        params { requires :id, type: String, desc: 'UUID do limite' }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::ControlService.show(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::RiskControl.represent(result[:data], usage: risk_control_usage([result[:data]]))
        end

        # ------------------------------------------------------------------
        # BE-234 — criação
        # ------------------------------------------------------------------
        desc 'Cria um limite de risco' do
          detail 'Transacional: se o tipo usa pré-faturamento, o par estático nasce junto (BE-241) — e se o ' \
                 'tipo não tiver os dois subtipos, o limite **não é gravado** e a resposta é 422. ' \
                 '`user_id` vem da SESSÃO. Empresa e portador são validados DENTRO do projeto corrente.'
        end
        params do
          requires :company_id, type: String
          requires :carrier_id, type: String
          requires :risk_operation_type_id, type: String
          requires :limite, type: BigDecimal, desc: 'Zero é válido — mantém vivo o ramo de divisão protegida'
          requires :taxa, type: BigDecimal
          optional :original_balance, type: BigDecimal, default: 0,
                                      desc: 'Saldo inicial liquidável. Vira a operação estática de antecipação.'
          optional :original_balance_pre, type: BigDecimal, default: 0,
                                          desc: 'Saldo inicial pré. Vira a operação estática de pré-faturamento.'
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          result = Risk::ControlService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::RiskControl.represent(result[:data])
        end

        # ------------------------------------------------------------------
        # BE-235 — atualização (decisão B-01)
        # ------------------------------------------------------------------
        desc 'Atualiza um limite' do
          detail '**Empresa, portador e tipo são imutáveis** (B-01): mudá-los moveria a exposição de uma ' \
                 'combinação para outra arrastando as operações que já consomem o limite. Tentar → 422. ' \
                 'No legado os três estavam no `permit` e só a tela os desabilitava. ' \
                 'Os saldos iniciais também não mudam: o par estático já nasceu deles.'
        end
        params do
          requires :id, type: String
          optional :limite, type: BigDecimal
          optional :taxa, type: BigDecimal
          optional :company_id, type: String, desc: 'Recusado — existe no contrato só para responder 422 explícito'
          optional :carrier_id, type: String, desc: 'Recusado — idem'
          optional :risk_operation_type_id, type: String, desc: 'Recusado — idem'
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = Risk::ControlService.update(project: project, id: params[:id], attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::RiskControl.represent(result[:data])
        end

        # ------------------------------------------------------------------
        # BE-236 / BE-237 — ativar e desativar
        # ------------------------------------------------------------------
        desc 'Ativa um limite' do
          detail 'BE-236 — `save!`. No legado era `save`, e o controller respondia 200 mesmo quando a ' \
                 'validação recusava: a tela dizia "ativado" e o limite continuava inativo. ' \
                 'Reentra imediatamente em todos os agregados.'
        end
        params { requires :id, type: String }
        put ':id/activate' do
          authorize!(RESOURCE, :update)
          project = current_project!

          result = Risk::ControlService.activate(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::RiskControl.represent(result[:data])
        end

        desc 'Desativa um limite' do
          detail '**Decisão B-02 — as duas leituras divergentes são PRESERVADAS**: o limite some do resumo ' \
                 'do console E suas operações continuam na lista de Operações de Risco. Não unificar: ' \
                 'unificar muda exposição financeira. Golden `L4` trava as duas.'
        end
        params { requires :id, type: String }
        put ':id/deactivate' do
          authorize!(RESOURCE, :update)
          project = current_project!

          result = Risk::ControlService.deactivate(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::RiskControl.represent(result[:data])
        end

        # ------------------------------------------------------------------
        # BE-238 — exclusão
        # ------------------------------------------------------------------
        desc 'Remove um limite' do
          detail 'Bloqueio por dependente (posição diária ou operação de risco) responde **422 real** com a ' \
                 'dependência nomeada — o legado respondia **202** e a tela dizia "excluído" (família D-24/D-98). ' \
                 'Consequência conhecida e fiel ao legado: limite de tipo COM pré-faturamento tem sempre o par ' \
                 'estático pendurado, logo não é excluível enquanto o par existir.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = Risk::ControlService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
