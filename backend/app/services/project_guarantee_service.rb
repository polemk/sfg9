# frozen_string_literal: true

# S4 / BE-118, BE-119 — **garantias do projeto**.
#
# É o serviço do defeito que dá nome ao contrato C1: `project_guarantee_id`
# chegando por parâmetro é aplicado **dentro** de `for_project`, nunca no lugar
# dele (`pub/project_guarantees_controller.rb:22`).
class ProjectGuaranteeService < ProjectScopedService
  class << self
    def model = ProjectGuarantee
    def resource_label = 'Garantia'
    def resource_genero = :feminino
    def writable_attributes = %i[title value observation carrier_id guarantee_type_id]

    def base_scope(project)
      model.for_project(project).with_ordering_joins.includes(:carrier, :guarantee_type)
    end

    # Os três filtros da tela. **Todos aplicados DENTRO do escopo** — é a linha
    # que o legado reatribuía.
    def filter(scope, params)
      scope = scope.where(id: params[:project_guarantee_id]) if uuid?(params[:project_guarantee_id])
      # Id malformado ou de outro projeto: conjunto vazio, nunca a lista inteira.
      scope = scope.none if params[:project_guarantee_id].present? && !uuid?(params[:project_guarantee_id])
      scope = scope.where(carrier_id: params[:carrier_id]) if uuid?(params[:carrier_id])
      scope = scope.where(guarantee_type_id: params[:guarantee_type_id]) if uuid?(params[:guarantee_type_id])
      scope
    end

    # `order_mode=dash` — criação descendente, `q` ignorado (comportamento do
    # legado, preservado).
    def index(project:, params: {})
      if params[:order_mode].to_s == 'dash'
        return { status: 200, data: base_scope(project).order(created_at: :desc) }
      end

      super
    end

    # Os portadores oferecidos no formulário: **um único critério**, a conexão
    # do projeto (BE-119). O legado usava `active_risk_controls_carriers` no
    # botão e `project.carriers` no formulário — dois critérios para a mesma
    # pergunta, e a tela oferecia portador que o servidor recusava.
    def available_carriers(project)
      # Subconsulta em vez de `joins`: `Carrier` é catálogo GLOBAL e não ganha
      # associação para a ponte só por causa desta tela. A regra da S3 vale por
      # inteiro — o portador não é escopado; a CONEXÃO é.
      Carrier.where(id: ProjectToCarrierConnection.for_project(project).select(:carrier_id)).order(:title)
    end
  end
end
