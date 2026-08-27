# frozen_string_literal: true

module Api
  module V1
    # S7 / **BE-253..BE-277, OPS-235, OPS-237** — **operações de risco**, com
    # movimentos, prorrogações e renovação aninhados.
    #
    # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
    #
    # As seis migrations desta família (`create_risk_operation_types`,
    # `create_risk_movement_types`, `create_risk_operations`,
    # `create_risk_movements`, `create_risk_operation_extensions`,
    # `create_risk_operation_subtypes`) estão entre as **24 que nunca subiram**
    # (`analise-dump-producao.md` §1). A última migration aplicada em produção é
    # de **25/05/2022** e o sistema rodou em uso até **31/05/2025**.
    #
    # Tudo o que este arquivo replica vem do **fonte de 2022**, com arquivo e
    # linha citados — não de comportamento observado. É a diferença entre esta
    # fatia e a S6, que pôde usar o dump como oráculo (28.099 linhas × 33
    # colunas, zero divergência). **Aqui não há oráculo**, e os goldens dizem
    # isso na própria marca.
    #
    # ## Contrato C1 — o escopo é a primeira linha de toda ação
    #
    # `project = current_project!`, sempre visível. **Duas IDORs da família
    # D-01/D-16/D-29/D-76/D-100 morrem aqui:**
    #
    # - `risk_operations#search` (`:23`) fazia
    #   `RiskOperation.where(id: params[:risk_operation_id])`, **substituindo a
    #   relation inteira** e perdendo o `where(project_id:)` da linha anterior;
    # - `risk_movements#search` (`:15`) **não tinha escopo nenhum**: qualquer
    #   `risk_operation_id` era aceito.
    #
    # Isso é **EXCEÇÃO-2 do DEC-30** (segurança e autorização não se replicam).
    #
    # ## A ordem das rotas importa
    #
    # `get 'filters'` vem **antes** de `get ':id'`. Invertido, `:id` casaria com
    # a palavra e o combo do formulário viraria a busca de uma operação chamada
    # "filters".
    class RiskOperations < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'risk_operations'
      MOVEMENTS_RESOURCE = 'risk_movements'
      EXTENSIONS_RESOURCE = 'risk_operation_extensions'

      helpers do
        def scoped_operation!(project, id)
          operation = Risk::OperationService.find(project, id)
          if operation.nil?
            error!({ error: 'not_found', message: 'Operação de risco não encontrada.' }, 404)
          end
          operation
        end

        # Contagens da LISTA em duas consultas agregadas, não uma por linha.
        # Sem isso a lista de 50 operações faz 150 consultas — e é a tela que o
        # gerente abre primeiro.
        def operation_counts(registros)
          ids = Array(registros).map(&:id)
          return {} if ids.empty?

          raizes = Array(registros).map { |o| o.original_id.presence || o.id }.uniq
          {
            extension_counts: RiskOperationExtension.where(risk_operation_id: ids).group(:risk_operation_id).count,
            movement_counts: RiskMovement.where(risk_operation_id: ids).group(:risk_operation_id).count,
            renewal_counts: RiskOperation.where(original_id: raizes).group(:original_id).count
          }
        end
      end

      namespace :risk_operations do
        before { authenticate_user! }

        # ------------------------------------------------------------------
        # BE-254 — os combos em cascata do formulário
        # ------------------------------------------------------------------
        desc 'Cascata empresa → portador → tipo do formulário de operação' do
          detail '`search_type=company` devolve os PORTADORES com limite ativo de tipo manual para a empresa. ' \
                 '`search_type=carrier` devolve os TIPOS manuais com limite ativo para (projeto, empresa, portador). ' \
                 'No legado, `search_type` desconhecido devolvia `{}` com 200 (select vazio, sem explicação) e ' \
                 '`Company.find` de id inexistente dava 500. Aqui é **400** e **404**.'
        end
        params do
          requires :search_type, type: String, desc: 'company | carrier'
          requires :company_id, type: String
          optional :carrier_id, type: String, desc: 'Obrigatório quando `search_type=carrier`'
        end
        get 'filters' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::OperationService.filter_options(
            project: project, search_type: params[:search_type],
            company_id: params[:company_id], carrier_id: params[:carrier_id]
          )
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          if params[:search_type].to_s == 'company'
            Api::Entities::Carrier.represent(result[:data])
          else
            Api::Entities::RiskOperationType.represent(result[:data])
          end
        end

        # ------------------------------------------------------------------
        # FE-257 — as duas guardas do botão "Cadastrar"
        # ------------------------------------------------------------------
        desc 'Pré-condições para abrir uma operação neste projeto' do
          detail 'No legado os dois predicados eram calculados NA VIEW e despejados em `data-` para o ' \
                 'JavaScript decidir (`_body.html.erb:19`, `_body.js.erb:440-453`) — regra que mora só ' \
                 'na tela é regra que a API não tem. Aqui eles vêm do servidor, e a mensagem da tela é ' \
                 'a mesma que o operador já conhece.'
        end
        get 'availability' do
          authorize!(RESOURCE, :read)
          project = current_project!

          Risk::OperationService.availability(project: project)[:data]
        end

        # ------------------------------------------------------------------
        # BE-253 — listagem
        # ------------------------------------------------------------------
        desc 'Lista as operações de risco do projeto corrente' do
          summary 'Operações de risco'
          detail '**Corrige o D-100**: `risk_operation_id` filtra DENTRO do escopo de projeto, nunca ' \
                 'substitui a relation. `X-Total-Count` é calculado ANTES do recorte — no legado o total ' \
                 'era contado depois do `limit!/offset!`, então a paginação nunca passava de uma página. ' \
                 'Chave de ordenação desconhecida devolve **400** (no legado, `nil + " "` → 500). ' \
                 '`order_mode=dash` força emissão decrescente e ignora as chaves, como no legado.'
          success [code: 200, model: Api::Entities::RiskOperation]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca em título do PORTADOR ou da OPERAÇÃO'
          optional :company_id, type: String
          optional :carrier_id, type: String
          optional :operation_type_id, type: String
          optional :risk_operation_id, type: String, desc: 'Filtra DENTRO do escopo (D-100)'
          optional :from, type: Date, desc: 'Janela fechada nos dois lados, igual a BE-242'
          optional :to, type: Date
          optional :order_mode, type: String, values: %w[dash], desc: 'dash = emissão desc, ignorando as chaves'
          optional :ordering_keys, type: Array[String]
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 50, desc: 'FE-250: a lista nasce com 50'
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::OperationService.index(project: project, params: params)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          registros = paginate(result[:data]).to_a
          Api::Entities::RiskOperation.represent(registros, **operation_counts(registros))
        end

        desc 'Detalhe de uma operação' do
          detail 'Id de OUTRO projeto responde 404, igual a id inexistente (C1). O par estático do ' \
                 'limite é alcançável aqui (o extrato dele é legítimo) e NÃO aparece na lista.'
        end
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          operation = scoped_operation!(project, params[:id])
          Api::Entities::RiskOperation.represent(operation, **operation_counts([operation]))
        end

        # ------------------------------------------------------------------
        # BE-255 — o cartão "última movimentação"
        # ------------------------------------------------------------------
        desc 'Última movimentação da operação' do
          detail 'Por **`sequence` asc**, não por data. **Operação sem movimento devolve payload vazio** — ' \
                 'no legado `@last_movement.date` em `nil` dava **500 na abertura do detalhe**, e o par ' \
                 'estático recém-criado é exatamente esse caso.'
        end
        params { requires :id, type: String }
        get ':id/last_movement' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::OperationService.last_movement(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        # ------------------------------------------------------------------
        # BE-256 — criação
        # ------------------------------------------------------------------
        desc 'Cria uma operação de risco' do
          detail 'A cascata inteira em UMA transação: BE-261 (limite pela quádrupla, **sem filtrar ' \
                 '`is_active`**) → BE-262 (tipo↔subtipo, com o subtipo padrão da DEC-67) → BE-263 (sinal ' \
                 'negativo, DEC-01) → BE-264 (movimento "Liberação do Recurso", só para tipo SEM ' \
                 'pré-faturamento) → BE-265 (recálculo). Qualquer elo que falhe desfaz tudo. ' \
                 '`user_id` vem da SESSÃO; `balance` NÃO entra no permit (é cache derivado). ' \
                 '**Replicado de propósito**: não há `due_date >= issue_date` nem `operation_value > 0` (Q-R7).'
        end
        params do
          requires :company_id, type: String
          requires :carrier_id, type: String
          requires :operation_type_id, type: String
          optional :operation_subtype_id, type: String, desc: 'Ausente = subtipo padrão do tipo (DEC-67)'
          optional :title, type: String, desc: 'Vazio cai para o título do portador'
          optional :contract_number, type: String
          requires :issue_date, type: Date
          requires :due_date, type: Date
          requires :operation_value, type: BigDecimal, desc: 'Zero é aceito — replicado (Q-R7)'
          optional :original_balance, type: BigDecimal, default: 0, desc: 'Gravado NEGATIVO (DEC-01)'
          optional :agreed_rate, type: BigDecimal, default: 0
          optional :observation, type: String
          optional :is_on_variable, type: Boolean, default: false
          optional :is_ended, type: Boolean, default: false, desc: 'Rótulo, sem consequência (DEC-35)'
          optional :receivable_id, type: String
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          result = Risk::OperationService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::RiskOperation.represent(result[:data])
        end

        # ------------------------------------------------------------------
        # BE-257 — edição
        # ------------------------------------------------------------------
        desc 'Atualiza uma operação' do
          detail '**T-D5 / FE-260** — `issue_date` e `due_date` NÃO são editáveis: a tela do legado já as ' \
                 'travava e a API aceitava, e a spec irmã de estruturadas (FE-297) resolve como regra de ' \
                 'servidor. As duas chegam declaradas para o contrato ficar explícito e são **ignoradas**. ' \
                 'Esticar prazo é PRORROGAÇÃO (`POST :id/extensions`). ' \
                 'Editar `operation_value` **não** regenera o movimento de liberação — replicado.'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :contract_number, type: String
          optional :operation_value, type: BigDecimal
          optional :original_balance, type: BigDecimal
          optional :agreed_rate, type: BigDecimal
          optional :observation, type: String
          optional :is_on_variable, type: Boolean
          optional :is_ended, type: Boolean
          optional :issue_date, type: Date, desc: 'Ignorado — a data não é editável (T-D5)'
          optional :due_date, type: Date, desc: 'Ignorado — use a prorrogação'
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = Risk::OperationService.update(project: project, id: params[:id], attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::RiskOperation.represent(result[:data])
        end

        # ------------------------------------------------------------------
        # BE-258 — exclusão
        # ------------------------------------------------------------------
        desc 'Remove uma operação' do
          detail 'Movimentos vão junto (`dependent: :destroy`) e prorrogações também (FK em cascata, DB-237). ' \
                 '**Operação com recibo responde 422 DE VERDADE** — no legado a resposta era literalmente ' \
                 '`errors.any? ? :ok : :ok` e a tela dizia "Operação foi removida com sucesso!" mesmo ' \
                 'quando o `restrict_with_error` tinha barrado (D-98).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = Risk::OperationService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        # ==================================================================
        # BE-259 / BE-260 — RENOVAÇÃO
        # ==================================================================
        desc 'Prévia da renovação (nada é gravado)' do
          detail 'BE-259 — `issue_date = hoje` e `due_date = due_date_original + (hoje − issue_date_original)`: ' \
                 '**preserva o prazo em dias**. Golden `M3`: 01/03→30/06 renovada em 20/05 sugere 18/09/2026. ' \
                 'Id inexistente → 404 (no legado, `.first` seguido de `.id` → 500).'
        end
        params do
          requires :id, type: String
          optional :issue_date, type: Date, desc: 'Default hoje'
        end
        get ':id/renewal' do
          authorize!(RESOURCE, :create)
          project = current_project!

          result = Risk::RenewalService.prepare(project: project, operation_id: params[:id],
                                                issue_date: params[:issue_date])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        desc 'Renova a operação' do
          detail 'BE-260 — copia os 13 campos, força `is_ended = false` na nova e **encadeia sempre na raiz** ' \
                 '(`original.original_id || original.id`). ' \
                 '**A original NÃO é encerrada — DEC-35.** O `tasks.md` (Phase 2) pedia o contrário (IMP-R1, ' \
                 'D-94); o usuário decidiu DEPOIS que o ciclo de vida do legado é replicado, e a DEC diz com ' \
                 'todas as letras que "um teste que exija encerramento automático está errado contra esta DEC". ' \
                 'Consequência: as duas operações consomem limite enquanto as janelas se sobrepõem.'
        end
        params do
          requires :id, type: String
          optional :issue_date, type: Date
          optional :due_date, type: Date
        end
        post ':id/renewal' do
          authorize!(RESOURCE, :create)
          project = current_project!

          result = Risk::RenewalService.create(project: project, operation_id: params[:id],
                                               issue_date: params[:issue_date], due_date: params[:due_date],
                                               actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::RiskOperation.represent(result[:data])
        end

        desc 'A cadeia de renovações (FE-267)' do
          detail 'Todos os elos com o mesmo `original_id`, mais a raiz. Mostra o estado de cada um — ' \
                 'com a DEC-35 os elos anteriores continuam abertos, e é isso que o cartão exibe.'
        end
        params { requires :id, type: String }
        get ':id/renewals' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Risk::RenewalService.chain(project: project, operation_id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          registros = result[:data].to_a
          Api::Entities::RiskOperation.represent(registros, **operation_counts(registros))
        end

        # ==================================================================
        # BE-270..BE-276 — MOVIMENTOS
        # ==================================================================
        desc 'Extrato da operação' do
          detail 'BE-270 — ordenado por `sequence` asc, **paginado** e **escopado por projeto**. ' \
                 'No legado não havia nem uma coisa nem outra: `l`/`o`/`q` eram lidos e ignorados, e ' \
                 'qualquer `risk_operation_id` era aceito sem olhar o projeto (IDOR).'
          success [code: 200, model: Api::Entities::RiskMovement]
          is_array true
        end
        params do
          requires :id, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get ':id/movements' do
          authorize!(MOVEMENTS_RESOURCE, :read)
          project = current_project!

          result = Risk::MovementService.index(project: project, operation_id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::RiskMovement.represent(paginate(result[:data]))
        end

        desc 'Opções do drawer de movimento' do
          detail 'BE-271 — `mode=new` devolve os tipos manuais; `mode=transfer` devolve o tipo ' \
                 '"Valor Transferido" **fixado** e só existe em operação de subtipo pré-faturamento (FE-272). ' \
                 'Id inexistente → 404 (no legado, `NoMethodError` em `nil` → 500).'
        end
        params do
          requires :id, type: String
          optional :mode, type: String, values: %w[new transfer], default: 'new'
        end
        get ':id/movements/options' do
          authorize!(MOVEMENTS_RESOURCE, :read)
          project = current_project!

          result = Risk::MovementService.form_options(project: project, operation_id: params[:id],
                                                      mode: params[:mode])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          dados = result[:data]
          {
            mode: dados[:mode],
            movement_type_id: dados[:movement_type_id],
            movement_type_locked: dados[:movement_type_locked],
            movement_types: Api::Entities::RiskMovementType.represent(dados[:movement_types]).as_json,
            min_date: dados[:operation].issue_date,
            max_date: dados[:operation].due_date
          }
        end

        desc 'Lança um movimento' do
          detail 'BE-272 — `user_id` da SESSÃO; `project_id`/`company_id`/`carrier_id` **copiados da ' \
                 'operação** e o que vier no payload é descartado (replicado). ' \
                 '**`movement_value > 0` passa a valer no servidor** (decisão B-05): valor negativo INVERTE ' \
                 'o sinal do movimento, o que é registro corrompido e não convenção de sinal — não cai no DEC-01. ' \
                 'Tipo de **transferência** entra pelo `Risk::TransferService`, que grava o par **antes** de ' \
                 'gravar qualquer coisa (BE-275): sem par de antecipação, nada é gravado. No legado ficava ' \
                 'meia transferência.'
        end
        params do
          requires :id, type: String
          requires :movement_type_id, type: String
          requires :date, type: Date, desc: 'Tem de cair entre emissão e vencimento (BE-274)'
          requires :movement_value, type: BigDecimal
          optional :observation, type: String
        end
        post ':id/movements' do
          authorize!(MOVEMENTS_RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = Risk::MovementService.create(project: project, operation_id: params[:id],
                                                attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::RiskMovement.represent(result[:data])
        end

        desc 'Edita um movimento' do
          detail 'BE-273/BE-276 — salvar refaz a cadeia inteira e renumera o `sequence`. ' \
                 'Movimento com par espelha **data e valor** no espelho: **corrige o D-97**, em que ' \
                 '`on_duplicate_key_update: [:date, movement_value]` (sem os dois-pontos) levanta ' \
                 '`NameError` em produção. O tipo é readonly em movimento de transferência.'
        end
        params do
          requires :id, type: String
          requires :movement_id, type: String
          optional :movement_type_id, type: String
          optional :date, type: Date
          optional :movement_value, type: BigDecimal
          optional :observation, type: String
        end
        put ':id/movements/:movement_id' do
          authorize!(MOVEMENTS_RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id, :movement_id)
          result = Risk::MovementService.update(project: project, operation_id: params[:id],
                                                id: params[:movement_id], attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::RiskMovement.represent(result[:data])
        end

        desc 'Exclui um movimento' do
          detail 'BE-273 — o `after_destroy` refaz a cadeia e renumera o `sequence` dos restantes. ' \
                 '**O movimento automático de "Liberação do Recurso" PODE ser excluído e NÃO é recriado** ' \
                 '— replicado. Movimento de transferência leva o par junto.'
        end
        params do
          requires :id, type: String
          requires :movement_id, type: String
        end
        delete ':id/movements/:movement_id' do
          authorize!(MOVEMENTS_RESOURCE, :destroy)
          project = current_project!

          result = Risk::MovementService.destroy(project: project, operation_id: params[:id],
                                                 id: params[:movement_id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        # ==================================================================
        # BE-277 — PRORROGAÇÕES
        # ==================================================================
        desc 'Prorrogações da operação' do
          detail 'Log **imutável**, por `created_at asc`. Não há update nem destroy expostos — nem no legado.'
          success [code: 200, model: Api::Entities::RiskOperationExtension]
          is_array true
        end
        params do
          requires :id, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get ':id/extensions' do
          authorize!(EXTENSIONS_RESOURCE, :read)
          project = current_project!

          result = Risk::ExtensionService.index(project: project, operation_id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::RiskOperationExtension.represent(paginate(result[:data]))
        end

        desc 'Prévia da prorrogação' do
          detail 'Devolve `min_due_date = due_date + 1` — o `minDate` do datepicker do legado, agora ' \
                 'vindo do servidor para que os dois lados não divirjam.'
        end
        params { requires :id, type: String }
        get ':id/extensions/new' do
          authorize!(EXTENSIONS_RESOURCE, :create)
          project = current_project!

          result = Risk::ExtensionService.prepare(project: project, operation_id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        desc 'Prorroga o vencimento' do
          detail 'BE-277 — `original_due_date` é carimbado **da operação** (o valor do formulário é ' \
                 'ignorado); o `after_create` sobrescreve `operation.due_date` e reexecuta o recálculo. ' \
                 '**`new_due_date > original_due_date` passa a valer no SERVIDOR**: no legado só o ' \
                 '`minDate` do datepicker impedia, e por requisição direta dava para **encurtar** o ' \
                 'vencimento, deixando movimentos legítimos fora da janela.'
        end
        params do
          requires :id, type: String
          requires :new_due_date, type: Date
          optional :observation, type: String
          optional :original_due_date, type: Date, desc: 'Declarado só para o contrato — é IGNORADO'
        end
        post ':id/extensions' do
          authorize!(EXTENSIONS_RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id, :original_due_date)
          result = Risk::ExtensionService.create(project: project, operation_id: params[:id],
                                                 attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::RiskOperationExtension.represent(result[:data])
        end
      end
    end
  end
end
