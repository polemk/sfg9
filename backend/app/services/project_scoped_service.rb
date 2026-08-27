# frozen_string_literal: true

# S4 — **o molde de serviço dos recursos escopados por projeto**.
#
# É o irmão do `CatalogService` (S3) e o **oposto** dele de propósito: lá o
# recurso é catálogo global e **nenhum** método chama `current_project!`; aqui
# **todo** método recebe o `project` já resolvido pelo endpoint. As duas regras
# convivem porque as duas estão certas — ver `app/models/concerns/global_catalog.rb`.
#
# O que este molde garante, igual nos quatro recursos da fatia
# (`Company`, `Provider`, `ProjectGuarantee`, `ProjectToCarrierConnection`):
#
# - **O escopo é a primeira linha de toda consulta.** `scope_for(project)` é
#   `model.for_project(project)`, e o filtro por id do cliente é aplicado
#   **dentro** dele. É a correção literal do `pub/project_guarantees_controller.rb:22`,
#   onde o legado **reatribuía** a relação e o filtro de projeto desaparecia
#   (família D-01 / D-16 / D-29 / D-76 / D-100).
# - **`project_id` do corpo é sempre ignorado** — no `create` **e** no `update`
#   (DC-04: mover empresa entre projetos arrastaria limites, recebíveis e
#   renegociações para outro tenant). `:id` também nunca entra.
# - **Id de outro projeto responde 404, igual a id inexistente.** Distinguir
#   403 de 404 transforma o endpoint num oráculo de existência de ids.
# - **Exclusão bloqueada responde 422 REAL** (D-24). O legado respondia `:ok` e
#   a tela dizia "removido com sucesso" sem ter removido.
# - **A paginação é aplicada pelo endpoint** (`paginate`, Kaminari + envelope em
#   cabeçalho — DEC-62). O serviço devolve a RELAÇÃO: materializar antes do
#   limite carrega o universo inteiro para contar (D-20).
class ProjectScopedService
  # Os ids desta base são **uuid**. Um id malformado tem de virar **404**, não o
  # `PG::InvalidTextRepresentation` que o Postgres levanta ao comparar `uuid`
  # com texto qualquer — 500 numa URL digitada errada é ruído que esconde erro
  # de verdade.
  #
  # Fica no corpo da classe (e não dentro de `class << self`) porque os serviços
  # e endpoints da fatia o leem como `ProjectScopedService::UUID_FORMAT`: um
  # lugar só define o que é um id aceitável.
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  class << self
    include ApiResponseHandler

    # --- Configuração das instâncias -------------------------------------
    def model
      raise NotImplementedError, "#{name} precisa declarar `model`"
    end

    def resource_label
      'Registro'
    end

    def ordering
      model::ORDERING
    end

    # Atributos que o serviço aceita gravar. `project_id`, `user_id` e `id`
    # NUNCA entram aqui — os três vêm do servidor.
    def writable_attributes
      []
    end

    # Relação base já com os `includes`/`joins` que a listagem precisa.
    def base_scope(project)
      model.for_project(project)
    end

    # Gancho de filtro específico de cada recurso.
    def filter(scope, _params)
      scope
    end

    # --- Leitura ----------------------------------------------------------
    def index(project:, params: {})
      scope = base_scope(project)
      scope = scope.search(params[:q]) if params[:q].present? && model.respond_to?(:search)
      scope = filter(scope, params)
      scope = ordering.apply(scope, keys: params[:ordering_keys], styles: params[:ordering_style])

      { status: 200, data: scope }
    end

    def show(project:, id:)
      record = find(project, id)
      return not_found if record.nil?

      { status: 200, data: record }
    end

    # --- Escrita ----------------------------------------------------------
    def create(project:, attrs:, actor: nil)
      record = model.new
      # O projeto vem do servidor. Um `project_id` no corpo nem é lido.
      record.project = project
      assign(record, attrs)
      record.user_id = actor&.id if record.respond_to?(:user_id=)

      return unprocessable(record) unless save_safely(record)

      { status: 201, data: record }
    end

    def update(project:, id:, attrs:, actor: nil)
      record = find(project, id)
      return not_found if record.nil?

      assign(record, attrs)
      after_assign_on_update(record, actor)
      # Reafirmado depois do `assign`: nem `assign` nem um gancho podem mover o
      # registro de tenant. É a metade que o legado esquecia (BE-062, D-23).
      record.project_id = project.id

      return unprocessable(record) unless save_safely(record)

      { status: 200, data: record.reload }
    end

    def destroy(project:, id:)
      record = find(project, id)
      return not_found if record.nil?

      unless record.destroy
        return { status: 422, error: record.errors.full_messages.to_sentence,
                 details: record.errors.messages }
      end

      { status: 200, data: { deleted: true, id: id.to_s } }
    rescue ActiveRecord::InvalidForeignKey
      { status: 422,
        error: "Não é possível excluir: há registros vinculados a #{este_com_genero} #{resource_label.downcase}." }
    end

    # --- Peças reusáveis --------------------------------------------------
    def uuid?(value)
      value.to_s.match?(UUID_FORMAT)
    end

    # **A forma canônica do contrato C1.** O filtro por id é aplicado DENTRO do
    # escopo; id de outro projeto simplesmente não é encontrado.
    def find(project, id)
      return nil unless uuid?(id)

      model.for_project(project).find_by(id: id)
    end

    private

    def assign(record, attrs)
      writable_attributes.each do |attribute|
        next unless attrs.key?(attribute)

        record.public_send(:"#{attribute}=", attrs[attribute])
      end
    end

    def after_assign_on_update(_record, _actor); end

    def save_safely(record)
      record.save
    rescue ActiveRecord::RecordNotUnique => e
      # Índice único do banco batendo antes da validação (corrida entre duas
      # abas). Vira 422 com texto de humano, não 500.
      Rails.logger.info("[#{name}] índice único do banco recusou: #{e.message}")
      record.errors.add(:base, 'Já existe um registro com estes dados neste projeto.')
      false
    end

    # **Concordância de gênero.** As frases de "não encontrado" e de "vinculados
    # a este" saíam com o remendo `(a)` — "Renegociação não encontrado(a).",
    # "vinculados a este(a) empresa". Dez dos vinte e quatro rótulos são
    # femininos, e o parêntese existia para não escolher.
    #
    # Achado renderizando `/renegotiations/:id` de um projeto que não é o
    # corrente (o 404 de escopo, que é comportamento correto — ver
    # `ProjectScopeState`). Nenhum portão pega concordância, e essa frase é lida
    # pelo cliente.
    #
    # O padrão é masculino porque a maioria dos rótulos é; quem é feminino
    # sobrescreve com uma linha.
    def resource_genero = :masculino

    def encontrado_com_genero = resource_genero == :feminino ? 'encontrada' : 'encontrado'
    def este_com_genero = resource_genero == :feminino ? 'esta' : 'este'

    def not_found
      { status: 404, error: "#{resource_label} não #{encontrado_com_genero}." }
    end

    def unprocessable(record)
      { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end
  end
end
