# frozen_string_literal: true

# S3 — **o molde de serviço dos cinco catálogos globais**.
#
# Os cinco recursos desta fatia são o mesmo objeto com colunas diferentes: lista
# paginada e ordenável, busca por texto, criação/edição por painel lateral,
# exclusão bloqueável e detalhe. Cinco serviços escritos à mão terminam com
# cinco semânticas de paginação e cinco formatos de erro — foi assim que o
# legado chegou a `prepare_ordering` copiado **idêntico em 18 models**.
#
# O que este molde garante, igual nos cinco:
#
# - **Busca simétrica** (BE-067): o `where` da busca é aplicado ANTES da
#   ordenação e não depende dela. No legado o ramo com `ordering_keys` e o sem
#   montavam consultas diferentes — e o com ordenação ainda fazia `.upcase` no
#   termo só num dos dois, de modo que o mesmo `q` devolvia conjuntos
#   diferentes conforme a coluna clicada.
# - **A paginação é aplicada pelo endpoint** (`paginate` do `ControllerHelpers`,
#   Kaminari + envelope em cabeçalho — DEC-62). O serviço devolve a RELAÇÃO, não
#   um array: quem materializa a lista antes do `limit` carrega o universo
#   inteiro para contar (foi o D-20/D-88).
# - **`user_id` vem da SESSÃO** e o do corpo é ignorado (BE-076, BE-703).
# - **Exclusão bloqueia com 422 real** (D-24). O legado respondia `:ok` mesmo
#   quando não excluía — a tela dizia "excluído" e o registro continuava lá.
#
# **Nenhum método daqui chama `current_project!`**: catálogo global não é
# escopado (C1, regra 4). A regra oposta — `Model.for_project(current_project!)`
# — vale nas fatias S4 e S11, e as duas estão escritas de propósito.
class CatalogService
  class << self
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

    # Atributos que o serviço aceita gravar. `user_id` NUNCA entra aqui.
    def writable_attributes
      %i[title integration_key is_active]
    end

    # Ganchos de filtro específicos de cada catálogo (ex.: `group_id` do
    # portador). Recebe e devolve a relação.
    def filter(scope, _params)
      scope
    end

    # --- Leitura ----------------------------------------------------------
    def index(params:)
      scope = model.all
      # Busca primeiro, ordenação depois: é isto que torna o conjunto o MESMO
      # com e sem `ordering_keys` (BE-067, segunda metade).
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.active if truthy?(params[:active])
      scope = filter(scope, params)
      scope = ordering.apply(scope, keys: params[:ordering_keys], styles: params[:ordering_style])

      { status: 200, data: scope }
    end

    # **Contagem de USO por registro, em UMA consulta por dependente.**
    #
    # Existe para que a coluna "# Projetos" da listagem não vire N+1: com 20
    # linhas na página, calcular a contagem dentro do serializer são 20
    # consultas — e é exatamente o tipo de coisa que só aparece com dado real.
    # O endpoint chama isto uma vez com os ids da PÁGINA e passa o resultado
    # como opção do entity.
    #
    # Dependente cuja tabela ainda não nasceu (S4..S6) simplesmente não conta.
    def usage_counts(ids)
      ids = Array(ids).compact
      return {} if ids.empty?

      usage_dependents.each_with_object(Hash.new(0)) do |(class_name, config), acc|
        coluna = config.fetch(:foreign_key)
        klass = GlobalCatalog.dependent_class_with_column(class_name, coluna)
        next if klass.nil?

        klass.where(coluna => ids).group(coluna).count.each { |id, total| acc[id] += total }
      end
    end

    # Quais dependentes contam como "uso" na listagem. Por padrão são os mesmos
    # que bloqueiam a exclusão — a tela mostra o número que explica o 422.
    def usage_dependents
      model.blocking_dependents
    end

    def show(id:)
      record = find(id)
      return not_found if record.nil?

      { status: 200, data: record }
    end

    # --- Escrita ----------------------------------------------------------
    def create(attrs:, actor: nil)
      record = model.new
      assign(record, attrs)
      # O autor é o da SESSÃO. Um `user_id` no corpo é ignorado — no legado o
      # `ProjectGuaranteeTypesController` era o único que NÃO o sobrescrevia
      # (D-23), e o `SegmentsController` o deixava fora do `permit` e a criação
      # falhava sempre (D-21). As duas pontas se resolvem com a mesma regra.
      record.user_id = actor&.id if record.respond_to?(:user_id=)

      return unprocessable(record) unless save_safely(record)

      { status: 201, data: record }
    end

    def update(id:, attrs:, actor: nil)
      record = find(id)
      return not_found if record.nil?

      assign(record, attrs)
      after_assign_on_update(record, actor)

      return unprocessable(record) unless save_safely(record)

      { status: 200, data: record.reload }
    end

    # Exclusão bloqueada responde **422 de verdade** (D-24), com a frase
    # nomeando o vínculo. Duas camadas: o `before_destroy` do `GlobalCatalog` e
    # a própria FK do Postgres, para o caso de alguém contornar o model.
    def destroy(id:)
      record = find(id)
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

    private

    # Os ids desta fatia são **uuid** (o padrão de id do ai9). Um id malformado
    # tem de virar **404**, não o `PG::InvalidTextRepresentation` que o Postgres
    # levanta ao comparar `uuid` com texto qualquer — 500 numa URL digitada
    # errada é ruído que esconde erro de verdade.
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def find(id)
      return nil unless id.to_s.match?(UUID_FORMAT)

      model.find_by(id: id)
    end

    def assign(record, attrs)
      writable_attributes.each do |attribute|
        next unless attrs.key?(attribute)

        record.public_send(:"#{attribute}=", attrs[attribute])
      end
    end

    # Gancho para quem precisa reagir à edição (nenhum catálogo precisa hoje;
    # existe para que a instância não sobrescreva `update` inteiro por causa de
    # uma linha).
    def after_assign_on_update(_record, _actor); end

    def save_safely(record)
      record.save
    rescue ActiveRecord::RecordNotUnique => e
      # Índice único do banco batendo antes da validação (corrida entre duas
      # abas). Vira 422 com texto de humano, não 500.
      Rails.logger.info("[#{name}] índice único do banco recusou: #{e.message}")
      record.errors.add(:title, 'já está em uso')
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
