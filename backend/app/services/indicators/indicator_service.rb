# frozen_string_literal: true

module Indicators
  # S10 / BE-311, BE-312, BE-314..BE-319 — **o catálogo de indicadores**.
  #
  # **Nenhum método daqui chama `current_project!`** quando o assunto é o
  # catálogo GLOBAL (contrato C1, regra 4 — DEC-18.4: o menu esconde a tela de
  # administração do catálogo, não o dado do catálogo). O projeto entra pelo
  # parâmetro `project:`, e só quando a operação é sobre um indicador
  # **específico** — e vem sempre do servidor, nunca do corpo da requisição.
  #
  # ## O que muda em relação ao legado
  #
  # | Legado | Aqui |
  # | ------ | ---- |
  # | `search` sem total: o front manda `l=50, o=0` fixos e **nunca incrementa o offset** — a lista trunca em 50 indicadores **sem aviso nenhum** | Kaminari + `X-Total-Count` (DEC-62). Paginação de verdade |
  # | `create` chama `ProjectIndicatorConnection.create` **fora de transação** e, se o indicador falhou, ainda tenta criar a conexão com `indicator_id: nil` — que falha em silêncio | Uma transação. Ou nasce o par, ou não nasce nada |
  # | `create` faz `@indicator.destroy` num objeto **não persistido** no ramo de erro | Não há o que destruir: nada foi gravado |
  # | `update` chama `update` **e** `save` — o `after_save` de propagação roda **duas vezes** | Um save |
  # | trocar `project_id` de um indicador existente **não** mexe na conexão: ele vira "específico" sem conexão e **some da tela do projeto** | A conexão é sincronizada |
  # | `activated` faz `nil.is_active=` quando o id não existe → **500** | 404 estruturado |
  # | `destroy` apaga o indicador **e toda a série histórica** (`dependent: :delete_all`) e responde `:ok` nos dois ramos | Exclusão LÓGICA (D-66) e 422 de verdade |
  class IndicatorService
    class << self
      include ApiResponseHandler

      RESOURCE_LABEL = 'Indicador'

      # --- Leitura ---------------------------------------------------------

      # **Só os globais** (`project_id IS NULL`) — os específicos aparecem na
      # tela de conexões do projeto, nunca no catálogo. Devolve a RELAÇÃO: quem
      # materializa antes do `limit` carrega o universo inteiro para contar.
      def index(params: {})
        scope = Indicator.kept.global
        scope = scope.search(params[:q]) if params[:q].present?
        scope = scope.active if truthy?(params[:active])
        scope = Indicator::ORDERING.apply(scope, keys: params[:ordering_keys], styles: params[:ordering_style])

        { status: 200, data: scope }
      end

      # Contagem de lançamentos por indicador, em UMA consulta para a página
      # inteira. Sem isto, mostrar "quantos lançamentos" numa lista de 20 linhas
      # são 20 consultas — e é justamente esse número que a confirmação de
      # exclusão precisa (FE-315).
      def entry_counts(ids)
        ids = Array(ids).compact
        return {} if ids.empty?

        IndicatorEntry.where(indicator_id: ids).group(:indicator_id).count
      end

      # Idem para projetos conectados.
      def connection_counts(ids)
        ids = Array(ids).compact
        return {} if ids.empty?

        ProjectIndicatorConnection.where(indicator_id: ids).group(:indicator_id).count
      end

      def show(id:)
        record = find(id)
        return not_found if record.nil?

        { status: 200, data: record }
      end

      # O que uma exclusão afeta — calculado **antes** de qualquer escrita.
      # É o conteúdo da confirmação que fecha o D-66 na copy.
      def deletion_impact(id:)
        record = find(id)
        return not_found if record.nil?

        { status: 200, data: record.deletion_impact.merge(id: record.id, title: record.title) }
      end

      # --- Escrita ---------------------------------------------------------

      # `project:` **nulo** cria um indicador global; preenchido cria um
      # específico **e** a conexão, na mesma transação. O projeto vem sempre do
      # servidor (`current_project!`); o `project_id` do corpo nem é declarado
      # no endpoint.
      def create(attrs:, project: nil, actor: nil)
        record = Indicator.new
        assign(record, attrs)
        record.project = project

        Indicator.transaction do
          raise ActiveRecord::Rollback unless save_safely(record)

          if project
            conexao = ProjectIndicatorConnection.new(project: project, indicator: record)
            unless conexao.save
              record.errors.add(:base, conexao.errors.full_messages.to_sentence)
              raise ActiveRecord::Rollback
            end
          end
        end

        return unprocessable(record) unless record.persisted? && record.errors.empty?

        Rails.logger.info("[Indicators] #{actor&.id} criou o indicador #{record.id} (#{record.title})")
        { status: 201, data: record }
      end

      # `scope_change` diz o que fazer com o alcance do indicador:
      #   `nil`        → não mexe (o padrão; editar título não muda alcance)
      #   `:global`    → vira global e a conexão do projeto sai
      #   `:project`   → vira específico do `project:` e a conexão entra
      #
      # No legado trocar `project_id` **não** criava nem removia a conexão: o
      # indicador virava específico sem conexão e sumia da tela do projeto.
      def update(id:, attrs:, project: nil, scope_change: nil, actor: nil)
        record = find(id)
        return not_found if record.nil?

        assign(record, attrs)
        apply_scope_change(record, project, scope_change)

        ok = false
        Indicator.transaction do
          unless save_safely(record)
            raise ActiveRecord::Rollback
          end

          ok = sync_connection(record, project, scope_change)
          raise ActiveRecord::Rollback unless ok
        end

        return unprocessable(record) unless ok

        Rails.logger.info("[Indicators] #{actor&.id} editou o indicador #{record.id}")
        { status: 200, data: record.reload }
      end

      # `BE-319`. `is_active` é boolean; id inexistente é 404, não
      # `nil.is_active=` → 500.
      def activate(id:, is_active:, actor: nil)
        record = find(id)
        return not_found if record.nil?

        record.is_active = ActiveModel::Type::Boolean.new.cast(is_active)
        return unprocessable(record) unless save_safely(record)

        Rails.logger.info("[Indicators] #{actor&.id} #{record.is_active ? 'ativou' : 'desativou'} #{record.id}")
        { status: 200, data: record }
      end

      # **`BE-318` — a exclusão LÓGICA que fecha o D-66.**
      #
      # No legado o `destroy` levava junto **toda a série histórica**
      # (`dependent: :delete_all`, sem callbacks e sem backup) e o ramo de erro
      # respondia `:ok` do mesmo jeito — a tela dizia "removido" e o registro
      # continuava lá.
      #
      # Aqui: marca `discarded_at`, os lançamentos ficam, e o indicador some das
      # listas (`Indicator.kept`). Reverter é `undiscard!`.
      def destroy(id:, actor: nil)
        record = find(id)
        return not_found if record.nil?

        impacto = record.deletion_impact
        unless record.discard!
          return { status: 422, error: record.errors.full_messages.to_sentence,
                   details: record.errors.messages }
        end

        Rails.logger.info(
          "[Indicators] #{actor&.id} descartou o indicador #{record.id} (#{record.title}); " \
          "#{impacto[:entries_count]} lançamento(s) PRESERVADO(s)"
        )
        { status: 200, data: { deleted: true, id: record.id, discarded_at: record.discarded_at,
                               entries_preserved: impacto[:entries_count] } }
      end

      # --- Peças ------------------------------------------------------------

      def find(id)
        return nil unless id.to_s.match?(ProjectScopedService::UUID_FORMAT)

        Indicator.kept.find_by(id: id)
      end

      # `key` **não** está aqui: ela é derivada na criação e congelada (DEC-85).
      # `is_active` está no permit sem campo no formulário — replicado (Q-R24).
      def writable_attributes
        %i[title key is_active description]
      end

      private

      def assign(record, attrs)
        writable_attributes.each do |attribute|
          next unless attrs.key?(attribute)
          # A chave só é aceita na criação: depois disso ela é congelada
          # (DEC-85 — o campo se chama "Chave de Integração").
          next if attribute == :key && record.persisted?

          record.public_send(:"#{attribute}=", attrs[attribute])
        end
      end

      def apply_scope_change(record, project, scope_change)
        case scope_change
        when :global then record.project = nil
        when :project then record.project = project
        end
      end

      # Mantém a `ProjectIndicatorConnection` coerente com o alcance.
      def sync_connection(record, project, scope_change)
        return true if scope_change.nil?

        if scope_change == :global
          ProjectIndicatorConnection.where(indicator_id: record.id).destroy_all
          return true
        end

        return true if project.nil?

        conexao = ProjectIndicatorConnection.find_or_initialize_by(project_id: project.id, indicator_id: record.id)
        return true if conexao.persisted? || conexao.save

        record.errors.add(:base, conexao.errors.full_messages.to_sentence)
        false
      end

      def save_safely(record)
        record.save
      rescue ActiveRecord::RecordNotUnique => e
        Rails.logger.info("[Indicators] índice único do banco recusou: #{e.message}")
        record.errors.add(:title, 'Já utilizado')
        false
      end

      def not_found
        { status: 404, error: "#{RESOURCE_LABEL} não encontrado." }
      end

      def unprocessable(record)
        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value) == true
      end
    end
  end
end
