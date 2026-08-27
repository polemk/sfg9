# frozen_string_literal: true

module Structured
  # S8 / **BE-280**…**BE-287**, **BE-291**, **DB-297** — as **operações
  # estruturadas** de um projeto.
  #
  # ## Os três `INNER JOIN` continuam INNER, e agora isso é seguro
  #
  # `structured_operations_controller.rb:22` junta empresa, portador e tipo com
  # `joins`, que é INNER. No legado isso tinha uma consequência silenciosa:
  # apagar um portador fazia a operação **sumir da lista** sem apagar nada — o
  # registro continuava lá, invisível. Com as FKs reais de `DB-282`
  # (`ON DELETE RESTRICT`) o portador apagado deixa de ser um estado possível,
  # então o INNER pode ficar sem esconder linha.
  #
  # ## BE-291 — trocar a empresa MOVE a operação de projeto
  #
  # `project_id` é derivado de `company.project_id` em **todo** save
  # (`structured_operation.rb:36`). O mecanismo é replicado; o que o ai9
  # acrescenta é que a mudança deixa de ser **efeito colateral**: trocar para
  # uma empresa de outro projeto exige `confirm_project_change: true`, porque a
  # operação leva junto o vínculo com uma remuneração e um recibo que ficam em
  # outro tenant. No legado bastava trocar um select.
  class OperationService < ProjectScopedService
    PROJECT_CHANGE_WARNING =
      'Esta empresa pertence a outro projeto. Salvar move a operação para lá, ' \
      'e a remuneração e o recibo deste projeto deixam de valer. ' \
      'Reenvie com `confirm_project_change: true` para confirmar.'

    COMPANY_OUT_OF_SCOPE = 'Empresa não encontrada neste projeto.'

    class << self
      def model = ::StructuredOperation
      def resource_label = 'Operação estruturada'
      def resource_genero = :feminino

      # **`:id` fica de fora** (BE-285): aceitá-lo no create é a mesma família
      # de mass assignment do D-60/D-68. `project_id` e `user_id` também —
      # o projeto vem da empresa e o autor vem da sessão.
      def writable_attributes
        %i[title company_id carrier_id operation_type_id contract_number issue_date due_date
           operation_value original_balance agreed_rate observation is_on_variable is_ended]
      end

      # BE-280 — os três joins, mais o `includes` que os torna uma consulta só
      # na serialização. Sem ele a lista de 50 linhas faz 150 consultas.
      def base_scope(project)
        model.for_project(project)
             .joins(:company, :carrier, :operation_type)
             .includes(:company, :carrier, :operation_type)
      end

      # BE-282 / OPS-283 — período, filtros e o **filtro por id DENTRO do
      # escopo**. É a correção literal da IDOR: no legado
      # `structured_operation_id` **reatribuía** a relation
      # (`structured_operations_controller.rb:25`) e o escopo de projeto
      # desaparecia — qualquer autenticado lia operação de qualquer projeto.
      def filter(scope, params)
        scope = scope.where(id: params[:structured_operation_id]) if params[:structured_operation_id].present?
        scope = scope.where(company_id: params[:company_id]) if params[:company_id].present?
        scope = scope.where(carrier_id: params[:carrier_id]) if params[:carrier_id].present?
        scope = scope.where(operation_type_id: params[:operation_type_id]) if params[:operation_type_id].present?
        scope = scope.in_period(params[:from], params[:to])
        scope
      end

      # BE-285 / BE-291 — a criação.
      def create(project:, attrs:, actor: nil)
        guard = company_guard(project, attrs)
        return guard if guard

        resultado = super
        stamp_editor(resultado, actor)
      end

      # BE-286 — **um** save, e a busca **com** escopo.
      #
      # No legado o `update` chamava `save` **três vezes** seguidas
      # (`structured_operations_controller.rb:78-92`), reexecutando os
      # callbacks 3× — inclusive o reset do saldo. Aqui é um.
      def update(project:, id:, attrs:, actor: nil)
        guard = company_guard(project, attrs)
        return guard if guard

        resultado = super
        stamp_editor(resultado, actor)
      end

      private

      # A empresa tem de existir e, se for de outro projeto, a mudança precisa
      # ser confirmada — nunca acontecer em silêncio.
      def company_guard(project, attrs)
        company_id = attrs[:company_id]
        return nil if company_id.blank?

        company = ::Company.find_by(id: uuid?(company_id) ? company_id : nil)
        return { status: 422, error: COMPANY_OUT_OF_SCOPE } if company.nil?
        return nil if company.project_id == project.id
        return nil if truthy?(attrs[:confirm_project_change])

        { status: 422, error: PROJECT_CHANGE_WARNING, code: 'PROJECT_CHANGE_REQUIRES_CONFIRMATION' }
      end

      # **DB-297 — autor e último editor são colunas separadas.**
      #
      # No legado `current_user.id` era forçado no create **e** no update
      # (`structured_operations_controller.rb:71`): quem gravasse depois virava
      # o "autor", e o autor original se perdia no primeiro save de outra
      # pessoa. Aqui `user_id` (autor) é escrito uma vez pelo
      # `ProjectScopedService` e `updated_by_id` é reescrito em todo save.
      # Os dois vêm da SESSÃO; nenhum é aceito no corpo.
      def stamp_editor(resultado, actor)
        return resultado unless [200, 201].include?(resultado[:status])
        return resultado if actor.nil?

        resultado[:data].update_column(:updated_by_id, actor.id)
        resultado[:data].reload
        resultado
      end
    end
  end
end
