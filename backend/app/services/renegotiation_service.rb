# frozen_string_literal: true

# S9 / BE-190..BE-201 — **renegociações**, escopadas por projeto.
#
# Segue o molde `ProjectScopedService` (S4) por inteiro, e por isso herda de graça
# as quatro garantias do contrato **C1**: o escopo é a primeira linha de toda
# consulta, o filtro por id entra **dentro** dele, `project_id` do corpo é sempre
# ignorado, e id de outro projeto responde **404 igual a id inexistente**.
#
# É a mesma família de defeito do `pub/project_guarantees_controller.rb:22`, e o
# controller de renegociação do legado a repete com todas as letras
# (`pub/renegotiations_controller.rb:23-24`):
#
#     @renegotiations = Renegotiation.where(project_id: current_user.default_project_id)
#     @renegotiations = Renegotiation.where(id: params[:renegotiation_id]) if !params[:renegotiation_id].nil?
#
# A segunda linha **reatribui** a relação: o filtro de projeto desaparece e
# qualquer sessão lia a renegociação de qualquer projeto passando o id na query
# string. É o maior risco do bloco — família D-01 / D-16 / D-29 / D-76 / D-100.
#
# **O que este serviço NÃO deixa escrever:** os ~20 agregados. O `permit` do
# legado aceitava `paid_value`, `remaining_value`, `state`, `paid_percent`,
# `installments_count`… — quarenta colunas, todas derivadas, todas graváveis por
# campo escondido de formulário. Aqui `writable_attributes` são os **13 campos do
# cadastro**, e quem escreve agregado é o `Renegotiations::AggregateService`.
class RenegotiationService < ProjectScopedService
  class << self
    def model = Renegotiation
    def resource_label = 'Renegociação'
    def resource_genero = :feminino

    # Os 13 campos do formulário, e só eles.
    def writable_attributes
      %i[
        title provider_id company_id kind renegotiation_date observation origin
        monetary_correction original_value original_pending_value additional_value
        total_debt desagio_value interest_rate_correction grace_period
        operation_interest_rate
      ]
    end

    def base_scope(project)
      model.for_project(project).includes(:provider, :company)
    end

    # Os três filtros da tela, **todos dentro do escopo**.
    def filter(scope, params)
      if params[:renegotiation_id].present?
        scope = uuid?(params[:renegotiation_id]) ? scope.where(id: params[:renegotiation_id]) : scope.none
      end
      # `state` aceita `empty` (BE-191). No legado o `case` não tinha
      # `when "empty"`, caía no `else` com um `return` que abortava a action no
      # meio — a tela dava 500 e o filtro "Sem parcela cadastrada" nunca funcionou
      # (D-49).
      scope = scope.with_state(params[:state]) if params[:state].present?
      scope = scope.with_kind(params[:kind]) if params[:kind].present?
      scope
    end

    # **`order_mode=dash` — BE-194 / DEC-137.**
    #
    # Ordenação por atualização ascendente e busca ignorada, como no legado. O
    # que MUDOU aqui: o dash passa pelo `filter`, e não mais por `base_scope`
    # cru.
    #
    # No legado o `case params[:state]` roda **antes** do ramo do dash
    # (`renegotiations_controller.rb:22-36`): o modo troca a ordenação e pula a
    # busca por nome, e não descarta os filtros. O ai9 fazia early-return no
    # `base_scope` e devolvia o projeto inteiro — quem pedisse o resumo filtrado
    # por "Em aberto" recebia também os fechados, com o mesmo 200 e sem aviso.
    #
    # O `q` continua ignorado, e isso é do legado: o ramo do dash não aplica a
    # busca por `provider_name`.
    def index(project:, params: {})
      if params[:order_mode].to_s == 'dash'
        escopo = filter(base_scope(project), params.except(:q))
        return { status: 200, data: escopo.order(updated_at: :asc) }
      end

      super
    end

    # **Recalcula na CRIAÇÃO** (BE-198). No legado o registro nascia com tudo
    # zerado e `state = "Inconsistente"` — o `before_validation` forçava o estado
    # e nada recalculava até alguém mexer numa parcela.
    def create(project:, attrs:, actor: nil)
      resultado = super
      return resultado unless resultado[:status] == 201

      Renegotiations::AggregateService.recalculate!(resultado[:data], broadcast: false)
      { status: 201, data: resultado[:data].reload }
    end

    # **Edição inválida não muta agregado** (BE-200). No legado o controller
    # chamava `update` e, na linha seguinte, `update_values!` — mesmo quando o
    # `update` tinha falhado na validação. O agregado era regravado a partir de um
    # objeto sujo, com os valores rejeitados em memória.
    def update(project:, id:, attrs:, actor: nil)
      resultado = super
      return resultado unless resultado[:status] == 200

      Renegotiations::AggregateService.recalculate!(resultado[:data])
      { status: 200, data: resultado[:data].reload }
    end

    # **Exclusão honesta** (BE-201, corrige D-24). O legado respondia
    # `errors.any? ? :ok : :ok` — os dois ramos `:ok` — e o template de resposta
    # estava **vazio**: a tela dizia "removido com sucesso", a lista recarregava e
    # o registro voltava.
    #
    # Aqui: só sem parcelas e sem pagamentos; os **anexos vão junto** (são
    # documento DELA, não dado independente). Bloqueio responde **422 nomeando o
    # vínculo**.
    def destroy(project:, id:)
      record = find(project, id)
      return not_found if record.nil?

      mensagem = record.blocking_dependents_message
      return { status: 422, error: mensagem } if mensagem.present?

      super
    end

    # BE-195 / #general_values — os sete valores do painel de consistência.
    #
    # Corrige o **D-48**: no legado o hash `values` era montado com todos estes
    # campos e **descartado**; a resposta era `@renegotiation.to_json`, o JSON cru
    # do registro. Nenhum dos valores calculados chegava à tela — e o `to_json`
    # ainda estava sobrescrito com assinatura errada (`def to_json` sem `*args`),
    # o que levantava `ArgumentError` quando o Rails o chamava com opções.
    #
    # **Recalcula de verdade antes de responder**, para que o painel não mostre a
    # fotografia do último `update_values!`.
    def general_values(project:, id:)
      record = find(project, id)
      return not_found if record.nil?

      Renegotiations::AggregateService.recalculate!(record, broadcast: false)
      record.reload

      {
        status: 200,
        data: {
          renegotiation_id: record.id,
          paid_value: record.paid_value,
          remaining_value: record.remaining_value,
          total_debt: record.total_debt,
          installments_value: record.installments_main_value,
          unposted_value: record.unposted_value,
          installment_status: record.installment_status,
          # "Remover todas as parcelas" só aparece quando há parcela e **nenhum**
          # pagamento. O botão em si não é portado (DEC-53 #3); a flag continua
          # porque a tela a usa para explicar por que a ação em lote está limitada.
          show_remove_all_option: record.installments_count.positive? && !record.payments.exists?
        }
      }
    end
  end
end
