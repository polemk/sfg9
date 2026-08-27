# frozen_string_literal: true

# S4 / BE-050..BE-056 — **empresas**.
#
# `project_id` do corpo é ignorado no create **e** no update (DC-04). Mover uma
# empresa entre projetos arrastaria `risk_controls`, recebíveis e renegociações
# para outro tenant — não é caso de uso, é vazamento.
class CompanyService < ProjectScopedService
  class << self
    def model = Company
    def resource_label = 'Empresa'
    def resource_genero = :feminino
    def writable_attributes = %i[title]

    # `order_mode=dash` — o resumo da tela inicial: título ascendente e `q`
    # **ignorado** (BE-051). É o comportamento do legado, preservado.
    def index(project:, params: {})
      return { status: 200, data: base_scope(project).order(title: :asc) } if params[:order_mode].to_s == 'dash'

      super
    end

    # BE-052 — resumo de limites de risco por empresa.
    #
    # ✅ **Preenchido pela S5** (BE-251, `Risk::AggregateService#total_limits_on`).
    # A forma decidida pela S4 foi mantida; o que mudou é que os números agora
    # são apurados em vez de zerados.
    #
    # **Contrato C2 em uma linha:** este endpoint chama o **mesmo** serviço que a
    # tela de risco e que a gravação. Não há uma segunda soma de exposição no
    # produto — nem aqui, nem no front.
    #
    # Sem `id`, o resumo é do **projeto inteiro**; com `id`, é da empresa. Id de
    # outro projeto responde 404, igual a id inexistente (C1).
    #
    # A guarda por model ausente continua: enquanto uma fatia não tiver
    # entregue `RiskControl` num ambiente qualquer, a resposta é o resumo vazio —
    # a mesma forma, com zeros —, nunca 500.
    def risk_summary(project:, id: nil, date: Date.current)
      company = id.present? ? find(project, id) : nil
      return not_found if id.present? && company.nil?

      klass = BlockingDependents.dependent_class_with_column('RiskControl', :company_id)
      return { status: 200, data: blank_risk_summary(date) } if klass.nil?

      { status: 200, data: Risk::AggregateService.total_limits_on(company || project, date) }
    end

    def blank_risk_summary(date)
      { date: date.to_s, has_risk_controls: false, pending_slice: 'S5', limits: [] }
    end
  end
end
