# frozen_string_literal: true

module Risk
  # S5 / BE-230..BE-241, BE-252 — **limites de risco**.
  #
  # Herda o molde `ProjectScopedService` (contrato **C1**): o escopo é a primeira
  # linha de toda consulta, `project_id` do corpo é ignorado no create **e** no
  # update, id de outro projeto responde 404 igual a id inexistente, e a
  # exclusão bloqueada responde **422 real**.
  #
  # ### As três regras próprias desta fatia
  #
  # 1. **B-01 — empresa, portador e tipo são IMUTÁVEIS depois do create.**
  #    Mudar qualquer um dos três moveria a exposição de uma combinação para
  #    outra, arrastando junto as operações que já consomem o limite (elas se
  #    ligam por projeto+empresa+portador+tipo, não pelo id do limite). No legado
  #    os três estão no `permit` e a tela apenas os desabilitava — quem chamasse
  #    o endpoint direto trocava. Aqui é **422**, no servidor.
  # 2. **IMP-R3 — o `q` da busca passa a filtrar.** No legado ele era lido,
  #    recebia `""` por default e nunca era aplicado ao `where`. Registrado em
  #    `improvements-log.md`: a mensagem "Não encontramos nenhum resultado para a
  #    busca «x»" passa a ser alcançável.
  # 3. **Empresa e portador são validados DENTRO do projeto corrente.** O legado
  #    aceitava qualquer `company_id`/`carrier_id` do corpo (família
  #    D-01/D-16/D-29/D-76/D-100). Aqui, id de fora do projeto é 422 com a mesma
  #    mensagem de id inexistente — o endpoint não confirma existência alheia.
  class ControlService < ProjectScopedService
    # Colunas que definem a IDENTIDADE do limite. Depois do create, nenhuma muda.
    IMMUTABLE_ON_UPDATE = %i[company_id carrier_id risk_operation_type_id].freeze

    class << self
      def model = RiskControl
      def resource_label = 'Limite de risco'

      # `original_balance`/`original_balance_pre` só fazem sentido na criação:
      # é delas que o par estático nasce (BE-241), e o par já existe depois.
      # FE-245 espelha isso escondendo os campos na edição.
      def writable_attributes = %i[limite taxa]

      def creatable_attributes
        %i[company_id carrier_id risk_operation_type_id limite taxa original_balance original_balance_pre]
      end

      def base_scope(project)
        model.for_project(project).includes(:company, :risk_operation_type, carrier: :group)
      end

      def filter(scope, params)
        scope = scope.where(risk_operation_type_id: params[:risk_operation_type_id]) if params[:risk_operation_type_id].present?
        scope = scope.where(carrier_id: params[:carrier_id]) if params[:carrier_id].present?
        scope = scope.where(company_id: params[:company_id]) if params[:company_id].present?
        scope = scope.active if truthy?(params[:active])
        scope
      end

      # --- BE-234 — criação -------------------------------------------------
      def create(project:, attrs:, actor: nil)
        erro = validate_references(project, attrs)
        return erro if erro

        record = model.new
        record.project = project
        creatable_attributes.each do |atributo|
          record.public_send(:"#{atributo}=", attrs[atributo]) if attrs.key?(atributo)
        end
        record.user_id = actor&.id

        return unprocessable(record) unless save_safely(record)

        { status: 201, data: record }
      rescue StaticPairService::IncompleteSubtypes => e
        # A transação já voltou atrás: o limite NÃO foi gravado.
        { status: 422, error: e.message }
      end

      # --- BE-235 — atualização (B-01) --------------------------------------
      def update(project:, id:, attrs:, actor: nil)
        record = find(project, id)
        return not_found if record.nil?

        tentativa = IMMUTABLE_ON_UPDATE.select do |atributo|
          attrs.key?(atributo) && attrs[atributo].present? &&
            attrs[atributo].to_s != record.public_send(atributo).to_s
        end

        if tentativa.any?
          return {
            status: 422,
            error: 'Empresa, portador e tipo de limite não podem ser alterados. ' \
                   'Crie um limite novo para a outra combinação.',
            details: { immutable: tentativa }
          }
        end

        super(project: project, id: id, attrs: attrs.except(*IMMUTABLE_ON_UPDATE), actor: actor)
      end

      # --- BE-236 / BE-237 — ativar e desativar -----------------------------
      # `save!` e não `save`: no legado `activate!` fazia `save` e o controller
      # respondia 200 mesmo quando a validação recusava — o limite continuava
      # inativo e a tela dizia que tinha ativado.
      def activate(project:, id:)
        toggle(project: project, id: id, active: true)
      end

      # **Decisão B-02**: desativar tira o limite do resumo do console e
      # **mantém** as operações dele na tela de Operações de Risco. As duas
      # leituras divergem no legado e as duas ficam. Ver `RiskControl#operations`.
      def deactivate(project:, id:)
        toggle(project: project, id: id, active: false)
      end

      # --- BE-232 — combos auxiliares ---------------------------------------
      # Portadores conectados ao projeto **da empresa**. O legado fazia
      # `company.project.carriers` — aqui a empresa já vem de dentro do projeto
      # corrente, então o resultado é o mesmo com o escopo garantido.
      def carriers_for_company(project:, company_id:)
        company = Company.for_project(project).find_by(id: company_id) if uuid?(company_id)
        return not_found_company if company.nil?

        # **Um critério só** de "o projeto tem este portador": a conexão. É o
        # mesmo `where` que o `create` usa para aceitar o `carrier_id`, e o
        # mesmo que a S4 usa no formulário de garantia. Ter dois critérios foi o
        # que fez a tela do legado oferecer portador que o servidor recusava.
        # `Carrier` é catálogo GLOBAL e **não declara** a associação de
        # conexão — daí a subconsulta em vez de `joins`.
        { status: 200,
          data: Carrier.where(id: ProjectToCarrierConnection.for_project(project).select(:carrier_id))
                       .order(title: :asc) }
      end

      # Portadores que **têm limite ativo** — o filtro do console. `.uniq` como
      # no legado (`active_risk_controls_carriers.uniq`).
      def controls_filter(project:, company_id: nil)
        escopo = RiskControl.for_project(project).active
        if company_id.present?
          company = uuid?(company_id) ? Company.for_project(project).find_by(id: company_id) : nil
          return not_found_company if company.nil?

          escopo = escopo.where(company_id: company.id)
        end

        { status: 200, data: Carrier.where(id: escopo.select(:carrier_id)).distinct.order(title: :asc) }
      end

      # --- BE-252 — limites livres numa data --------------------------------
      def available_for_entry_on(project:, company_id: nil, date: Date.current)
        escopo = project
        if company_id.present?
          company = uuid?(company_id) ? Company.for_project(project).find_by(id: company_id) : nil
          return not_found_company if company.nil?

          escopo = company
        end

        { status: 200, data: AggregateService.available_for_entry_on(escopo, date) }
      end

      private

      def toggle(project:, id:, active:)
        record = find(project, id)
        return not_found if record.nil?

        record.is_active = active
        return unprocessable(record) unless record.save

        { status: 200, data: record.reload }
      end

      # C1 aplicado às referências do corpo: empresa e portador precisam existir
      # **dentro** do projeto corrente.
      def validate_references(project, attrs)
        company_id = attrs[:company_id]
        carrier_id = attrs[:carrier_id]
        type_id = attrs[:risk_operation_type_id]

        return { status: 422, error: 'Empresa é obrigatória.' } if company_id.blank?
        return { status: 422, error: 'Portador é obrigatório.' } if carrier_id.blank?
        return { status: 422, error: 'Tipo de limite é obrigatório.' } if type_id.blank?

        unless uuid?(company_id) && Company.for_project(project).exists?(id: company_id)
          return { status: 422, error: 'Empresa não encontrada neste projeto.' }
        end

        unless uuid?(carrier_id) &&
               ProjectToCarrierConnection.for_project(project).exists?(carrier_id: carrier_id)
          return { status: 422, error: 'Portador não está conectado a este projeto.' }
        end

        return { status: 422, error: 'Tipo de limite não encontrado.' } unless uuid?(type_id) &&
                                                                               RiskOperationType.exists?(id: type_id)

        nil
      end

      def not_found_company
        { status: 404, error: 'Empresa não encontrada.' }
      end
    end
  end
end
