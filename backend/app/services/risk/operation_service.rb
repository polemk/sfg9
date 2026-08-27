# frozen_string_literal: true

module Risk
  # S7 / **BE-253..BE-258** — o CRUD da **operação de risco**.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `create_risk_operations`, `create_risk_operation_types`,
  # `create_risk_operation_subtypes` e `create_risk_movements` estão entre as
  # **24 migrations que nunca subiram** (`analise-dump-producao.md` §1). Em três
  # anos de uso real **nenhuma operação de risco tipada existiu em produção**.
  # O que este serviço replica é o **fonte de 2022**, com arquivo e linha citados
  # — não um comportamento observado. Onde o código de 2022 é ambíguo, a escolha
  # está escrita no comentário, e não inventada em silêncio.
  #
  # ## O que muda em relação ao legado, e por quê
  #
  # | O legado | Aqui | Motivo |
  # | -------- | ---- | ------ |
  # | `risk_operation_id` **substitui a relation inteira** (`risk_operations_controller.rb:23`), perdendo o escopo de projeto | filtra **dentro** de `for_project` | **D-100**, a IDOR. EXCEÇÃO-2 do DEC-30: segurança não se replica |
  # | `@total_count` calculado **depois** do `limit!/offset!` (`:34,40,44`) | `X-Total-Count` vem da relação **antes** do recorte (Kaminari) | o total do legado é o tamanho da página, então a paginação nunca passava de uma |
  # | chave de ordenação desconhecida → `nil + " "` → **500** | **400** nomeando a chave | um `?ordering_keys[]=x` na barra de endereço derrubava a lista |
  # | `destroy` responde `errors.any? ? :ok : :ok` (`:139`) | **422 de verdade** | **D-98**: a tela dizia "Operação foi removida com sucesso!" sem ter removido |
  # | `update` faz **três** passagens pelo `before_validation` (`:117-123`) | **um** save, **um** recálculo | o resultado é o mesmo e a cadeia é reescrita uma vez |
  #
  # ## O que **não** muda, e é decisão registrada
  #
  # - o limite é resolvido pela quádrupla **sem filtrar `is_active`** (BE-261) —
  #   é possível abrir operação em limite desativado, e a **DEC-105** acabou de
  #   confirmar o critério do espelho mesmo com consequência visível;
  # - **não há** `due_date >= issue_date` nem `operation_value > 0` (BE-267,
  #   Q-R7): operação de capital zero continua entrando;
  # - editar `operation_value` **não** regenera o movimento de "Liberação do
  #   Recurso" já criado (BE-257 / spec). O movimento existente permanece como
  #   está, e o saldo passa a divergir do capital — replicado.
  class OperationService < ProjectScopedService
    class << self
      def model = RiskOperation

      def resource_label = 'Operação de risco'
      def resource_genero = :feminino

      # `balance` **fora** do permit: é cache derivado, reescrito pelo
      # recálculo. No legado ele estava no `permit` (`:229`) e um payload podia
      # gravar um saldo que a próxima gravação apagaria.
      # `project_id`, `user_id` e `id` também nunca entram (regra do molde).
      def writable_attributes
        %i[title operation_type_id operation_subtype_id company_id carrier_id
           contract_number issue_date due_date operation_value original_balance
           agreed_rate observation is_on_variable is_ended receivable_id]
      end

      # Só o par estático fica de fora da lista: ele não é operação do
      # operador, é a moldura do limite (B-08 da S5). Ele continua entrando em
      # `operations_on` — o que muda é que ninguém o edita pela tela de
      # operações.
      def base_scope(project)
        RiskOperation.for_project(project)
                     .where(is_static: false)
                     .joins(:carrier, :company, :operation_type)
                     .includes(:carrier, :company, :operation_type, :operation_subtype)
      end

      # ------------------------------------------------------------------
      # BE-253 — listagem
      # ------------------------------------------------------------------
      def index(project:, params: {})
        chaves_invalidas = RiskOperation::ORDERING.rejected(params[:ordering_keys])
        if chaves_invalidas.any?
          return { status: 400,
                   error: "Ordenação desconhecida: #{chaves_invalidas.to_sentence}. " \
                          "Chaves aceitas: #{RiskOperation::ORDERING.allowed.keys.to_sentence}." }
        end

        scope = filter(base_scope(project), params)
        scope = scope.search(params[:q]) if params[:q].present?

        scope =
          if params[:order_mode].to_s == 'dash'
            # `:33-34` — o painel pede sempre emissão decrescente e ignora as
            # chaves do cliente. Replicado.
            scope.order(Arel.sql('risk_operations.issue_date DESC'))
          else
            RiskOperation::ORDERING.apply(scope, keys: params[:ordering_keys], styles: params[:ordering_style])
          end

        { status: 200, data: scope }
      end

      def filter(scope, params)
        scope = scope.where(company_id: params[:company_id]) if params[:company_id].present?
        scope = scope.where(carrier_id: params[:carrier_id]) if params[:carrier_id].present?
        scope = scope.where(operation_type_id: params[:operation_type_id]) if params[:operation_type_id].present?
        # **A correção do D-100.** O legado fazia
        # `@risk_operations = RiskOperation.where(id: params[:risk_operation_id])`,
        # jogando fora o `where(project_id:)` da linha anterior. Aqui o id
        # filtra DENTRO do escopo — id de outro projeto simplesmente não é
        # encontrado.
        scope = scope.where(id: params[:risk_operation_id]) if params[:risk_operation_id].present?
        scope = janela(scope, params[:from], params[:to])
        scope
      end

      # `:31` — a mesma janela fechada nos dois lados de `BE-242`. Sem `from`
      # nem `to` o legado usava as sentinelas de ±2000 anos; aqui a ausência de
      # limite simplesmente não filtra, que é o mesmo conjunto sem data falsa.
      def janela(scope, from, to)
        scope = scope.where('DATE(risk_operations.due_date) >= DATE(?)', from.to_date) if from.present?
        scope = scope.where('DATE(risk_operations.issue_date) <= DATE(?)', to.to_date) if to.present?
        scope
      end

      # O `find` do molde não serve aqui: o detalhe precisa alcançar também o
      # par estático (o extrato dele é legítimo), enquanto a LISTA não o mostra.
      def find(project, id)
        return nil unless uuid?(id)

        RiskOperation.for_project(project).find_by(id: id)
      end

      # ------------------------------------------------------------------
      # BE-254 — os combos em cascata do formulário
      # ------------------------------------------------------------------
      # `new_filters_for_new` (`:144-161`). Duas correções de robustez, nenhuma
      # de regra:
      #
      # - `search_type` desconhecido devolvia `{}` com 200 e a tela ficava com
      #   o select vazio sem saber por quê → **400**;
      # - `Company.find` levantava `RecordNotFound` → 500 → **404**.
      def filter_options(project:, search_type:, company_id: nil, carrier_id: nil)
        case search_type.to_s
        when 'company'  then carriers_with_manual_control(project, company_id)
        when 'carrier'  then manual_types_for(project, company_id, carrier_id)
        else
          { status: 400,
            error: "search_type desconhecido: «#{search_type}». Use «company» ou «carrier»." }
        end
      end

      # `:147-151` — portadores da empresa que têm limite ATIVO de tipo manual.
      def carriers_with_manual_control(project, company_id)
        company = Company.for_project(project).find_by(id: company_id) if uuid?(company_id)
        return not_found_company if company.nil?

        ids = RiskControl.where(project_id: project.id, company_id: company.id, is_active: true)
                         .where(risk_operation_type_id: RiskOperationType.manual.select(:id))
                         .select(:carrier_id)

        { status: 200, data: Carrier.where(id: ids).order(title: :asc) }
      end

      # `:152-156` — tipos manuais com limite ativo para (projeto, empresa, portador).
      def manual_types_for(project, company_id, carrier_id)
        company = Company.for_project(project).find_by(id: company_id) if uuid?(company_id)
        return not_found_company if company.nil?

        ids = RiskControl.where(project_id: project.id, company_id: company.id,
                                carrier_id: carrier_id, is_active: true)
                         .where(risk_operation_type_id: RiskOperationType.manual.select(:id))
                         .distinct.select(:risk_operation_type_id)

        { status: 200, data: RiskOperationType.manual.where(id: ids).order(title: :asc) }
      end

      # ------------------------------------------------------------------
      # FE-257 — as duas guardas do botão "Cadastrar", agora NO SERVIDOR
      # ------------------------------------------------------------------
      # `../sfg/app/views/pub/console/parts/risk_operations/_body.html.erb:19`
      # calcula os dois predicados **na view** e os despeja em `data-` para o
      # JavaScript decidir (`_body.js.erb:440-453`):
      #
      # ```erb
      # data-carrier_available="<%= !current_user.default_project.active_risk_controls_carriers.blank? %>"
      # data-manual_control="<%= !current_user.default_project.active_risk_controls
      #                            .where(risk_operation_type_id: RiskOperationType.manual.pluck(:id)).blank? %>"
      # ```
      #
      # Regra que mora só na tela é regra que a API não tem. Aqui os dois
      # predicados são calculados **onde o dado está** e a tela apenas os
      # exibe — a mensagem continua a mesma, e é a que o operador já conhece.
      def availability(project:)
        ativos = RiskControl.for_project(project).where(is_active: true)
        {
          status: 200,
          data: {
            carrier_available: ativos.where.not(carrier_id: nil).exists?,
            manual_control: ativos.where(risk_operation_type_id: RiskOperationType.manual.select(:id)).exists?
          }
        }
      end

      # ------------------------------------------------------------------
      # BE-255 — o cartão "última movimentação"
      # ------------------------------------------------------------------
      def last_movement(project:, id:)
        operation = find(project, id)
        return not_found if operation.nil?

        { status: 200, data: Risk::Calculator.last_movement(operation) }
      end

      # ------------------------------------------------------------------
      # BE-256 — criação, a cascata inteira em UMA transação
      # ------------------------------------------------------------------
      # `BE-261` (limite) → `BE-262` (tipo↔subtipo) → `BE-263` (sinal) →
      # `BE-264` (movimento de liberação) → `BE-265` (recálculo).
      #
      # No legado a cascata é um `save` solto (`:70-75`): uma falha no meio
      # deixava a operação gravada sem movimento, ou o movimento com o tipo
      # funcional faltando levantava `NoMethodError` **depois** do INSERT. Aqui
      # qualquer elo que falhe desfaz tudo.
      def create(project:, attrs:, actor: nil)
        fora = escopo_violado(project, attrs)
        return fora if fora

        record = RiskOperation.new
        record.project = project
        assign(record, attrs)
        record.user_id = actor&.id

        RiskOperation.transaction do
          raise ActiveRecord::Rollback unless save_safely(record)
        end

        return unprocessable(record) if record.errors.any? || !record.persisted?

        { status: 201, data: record.reload }
      rescue RiskMovementType::MissingFunctionalType => e
        # B-09 — erro de NEGÓCIO, nomeando a chave de integração que falta, e
        # levantado ANTES de a operação ficar gravada (a transação volta).
        { status: 422, error: e.message }
      rescue ActiveRecord::RecordInvalid => e
        # O `after_create` do movimento de liberação recusado: a transação já
        # voltou, e o operador precisa da mensagem, não de um 500.
        { status: 422, error: e.record&.errors&.full_messages&.to_sentence.presence || e.message }
      end

      # ------------------------------------------------------------------
      # BE-257 — edição
      # ------------------------------------------------------------------
      # Duas regras de servidor, e as duas espelham a tela:
      #
      # 1. **T-D5 / FE-260** — as datas de uma operação existente **não** são
      #    editáveis. A tela do legado já as travava e a API aceitava; a spec
      #    irmã de estruturadas (`FE-297`) resolve como regra de servidor, e os
      #    dois módulos adotam a mesma semântica. Datas no payload de `update`
      #    são **ignoradas em silêncio** (não é erro: a tela não as manda).
      # 2. **B-03** — encolher a janela deixando movimento de fora é recusado
      #    **com a lista dos movimentos conflitantes**. Como as datas não são
      #    editáveis por aqui, essa regra vale para o caminho que **pode**
      #    encurtar: a prorrogação (`ExtensionService`) e o ETL. Fica escrita
      #    aqui, e o teste a exercita pelo caminho de prorrogação.
      def update(project:, id:, attrs:, actor: nil)
        record = find(project, id)
        return not_found if record.nil?
        return { status: 422, error: 'O par estático do limite não é editável pela tela de operações.' } if record.is_static?

        fora = escopo_violado(project, attrs)
        return fora if fora

        assign(record, attrs.except(:issue_date, :due_date))
        record.project_id = project.id

        return unprocessable(record) unless save_safely(record)

        { status: 200, data: record.reload }
      end

      # ------------------------------------------------------------------
      # BE-258 — exclusão
      # ------------------------------------------------------------------
      # `dependent: :destroy` nos movimentos, `restrict_with_error` no recibo, e
      # **422 de verdade**. A FK em cascata da S5 garante que a prorrogação não
      # fica órfã (DB-237).
      def destroy(project:, id:)
        record = find(project, id)
        return not_found if record.nil?
        return { status: 422, error: 'O par estático do limite é removido junto com o limite, não aqui.' } if record.is_static?

        super
      end

      private

      # **A trava que o `inherit_project_from_company` obriga.**
      #
      # O legado faz `self.project_id = self.company.project_id` em todo save
      # (`risk_operation.rb:28`) e isso é replicado — é o que mantém coerente o
      # dado histórico. Mas replicado **sozinho** ele vira um vazamento de
      # tenant: bastaria mandar `company_id` de outro projeto para a operação
      # nascer lá, contornando o `record.project = project` do molde. O teste de
      # C1 pegou exatamente isso.
      #
      # Por **EXCEÇÃO-2 do DEC-30** (segurança e autorização não se replicam), a
      # empresa e o portador são resolvidos **dentro** do projeto corrente antes
      # de qualquer atribuição. Id de fora responde **404**, igual a id
      # inexistente: o endpoint não confirma a existência de registro alheio.
      def escopo_violado(project, attrs)
        if attrs[:company_id].present? &&
           !Company.for_project(project).exists?(id: valid_uuid(attrs[:company_id]))
          return not_found_company
        end

        if attrs[:carrier_id].present? &&
           !ProjectToCarrierConnection.for_project(project).exists?(carrier_id: valid_uuid(attrs[:carrier_id]))
          return { status: 404, error: 'Portador não encontrado neste projeto.' }
        end

        nil
      end

      # `nil` para id malformado: comparar `uuid` com texto qualquer levanta
      # `PG::InvalidTextRepresentation`, e 500 numa URL digitada errada é ruído.
      def valid_uuid(value)
        uuid?(value) ? value : nil
      end

      def not_found_company
        { status: 404, error: 'Empresa não encontrada neste projeto.' }
      end
    end
  end
end
