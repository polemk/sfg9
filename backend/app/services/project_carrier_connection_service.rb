# frozen_string_literal: true

# S4 / BE-102..BE-105 — **conexões projeto ↔ portador**.
#
# O legado resolvia isto com um endpoint genérico que fazia
# `params[:owner_type].constantize` e `params[:connection_type].constantize`:
# **qualquer classe da aplicação** podia ser instanciada e enumerada a partir da
# query string. Aqui não há `constantize` nenhum — o sentido da conexão vem de
# um **conjunto fechado**, e o único registro que o servidor aceita conectar é
# um portador do catálogo global a um projeto em que o usuário participa.
#
# Quatro defeitos do lote (`update_connections`) que **não** se replicam:
#
# 1. **`@connection.save` com retorno ignorado** — duplicata falhava calada e o
#    lote respondia `:ok`.
# 2. **Só o ÚLTIMO item era inspecionado** por erro (`@connection` era
#    reatribuído a cada volta do laço).
# 3. **Lote vazio derrubava a ação** (`@connection` ficava `nil` →
#    `NoMethodError`). Aqui lote vazio é **400**, explícito.
# 4. **Desconectar o que não está conectado** entrava no `select{}.first` e
#    dava `NoMethodError` no `nil`. Aqui vira resultado "não estava conectado",
#    por item.
class ProjectCarrierConnectionService
  # Conjunto FECHADO. Fica no corpo da classe (e não dentro de `class << self`)
  # porque o endpoint o lê como `ProjectCarrierConnectionService::ACTIONS` para
  # declarar os `values:` do Grape — um lugar só define o que é ação válida.
  ACTIONS = %w[connect disconnect].freeze

  class << self
    include ApiResponseHandler

    # BE-104 — **um** endpoint de candidatos. O legado tinha dois quase
    # idênticos (`search` com limite 25 e `connections` com limite 200), e o
    # segundo listava o catálogo inteiro sem filtro.
    def candidates(project:, params: {})
      conectados = ProjectToCarrierConnection.for_project(project).pluck(:carrier_id).to_set

      scope = Carrier.all
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.active if truthy?(params[:active])
      scope = scope.where(group_id: params[:group_id]) if uuid?(params[:group_id])
      scope = scope.order(:title)

      { status: 200, data: { scope: scope, connected_ids: conectados } }
    end

    def index(project:, params: {})
      scope = ProjectToCarrierConnection.for_project(project)
                                        .includes(carrier: :group)
                                        .joins(:carrier).order('carriers.title ASC')
      scope = scope.where(carriers: { id: params[:carrier_id] }) if uuid?(params[:carrier_id])

      { status: 200, data: scope }
    end

    # BE-103 — conectar/desconectar **em lote**, com resultado **por item**.
    #
    # O `action` é conjunto fechado. Um item de portador inexistente é recusado
    # e **os demais são aplicados** — o legado abortava ou mentia.
    def update_connections(project:, action:, carrier_ids:)
      return error_response('Ação inválida.', 400) unless ACTIONS.include?(action.to_s)

      ids = Array(carrier_ids).map(&:to_s).uniq.select { |i| uuid?(i) }
      return error_response('Selecione ao menos um portador.', 400) if ids.empty?

      existentes = Carrier.where(id: ids).pluck(:id).to_set

      resultados = ids.map do |carrier_id|
        next item(carrier_id, 'not_found', 'Portador inexistente.') unless existentes.include?(carrier_id)

        action.to_s == 'connect' ? connect_one(project, carrier_id) : disconnect_one(project, carrier_id)
      end

      success_response({
                         action: action.to_s,
                         results: resultados,
                         applied: resultados.count { |r| r[:status] == 'ok' },
                         failed: resultados.count { |r| r[:status] != 'ok' }
                       }, 200)
    end

    # BE-105 — remover **uma** conexão pelo id dela. No legado o `before_action`
    # preenchia `@connections` (plural) e a action lia `@connection` (singular):
    # `NoMethodError` garantido, a action nunca funcionou.
    def destroy(project:, id:)
      return not_found_response('Conexão', genero: :feminino) unless uuid?(id)

      connection = ProjectToCarrierConnection.for_project(project).find_by(id: id)
      return not_found_response('Conexão', genero: :feminino) if connection.nil?

      unless connection.destroy
        return error_response(connection.errors.full_messages.to_sentence, 422)
      end

      success_response({ deleted: true, id: id.to_s }, 200)
    end

    private

    def connect_one(project, carrier_id)
      connection = ProjectToCarrierConnection.new(project: project, carrier_id: carrier_id)
      return item(carrier_id, 'ok', 'Conectado.', connection.id) if connection.save

      # Já conectado não é falha do operador: o estado desejado é o estado
      # atual. O lote diz isso em vez de reprovar.
      if ProjectToCarrierConnection.exists?(project_id: project.id, carrier_id: carrier_id)
        return item(carrier_id, 'ok', 'Já estava conectado.')
      end

      item(carrier_id, 'error', connection.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      item(carrier_id, 'ok', 'Já estava conectado.')
    end

    def disconnect_one(project, carrier_id)
      connection = ProjectToCarrierConnection.for_project(project).find_by(carrier_id: carrier_id)
      return item(carrier_id, 'ok', 'Não estava conectado.') if connection.nil?

      # A garantia que aponta para este portador segura a desconexão: senão o
      # formulário de garantia passaria a oferecer um portador que o servidor
      # recusa, e a garantia existente ficaria órfã de critério.
      usadas = ProjectGuarantee.for_project(project).where(carrier_id: carrier_id).count
      if usadas.positive?
        return item(carrier_id, 'error',
                    "Não é possível desconectar: #{usadas} garantia(s) do projeto usam este portador.")
      end

      return item(carrier_id, 'ok', 'Desconectado.') if connection.destroy

      item(carrier_id, 'error', connection.errors.full_messages.to_sentence)
    end

    def item(carrier_id, status, message, id = nil)
      { carrier_id: carrier_id, status: status, message: message, id: id }.compact
    end

    def uuid?(value)
      value.to_s.match?(ProjectScopedService::UUID_FORMAT)
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end
  end
end
