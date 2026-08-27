# frozen_string_literal: true

module Availability
  # S11 / BE-132..139 — **o catálogo global de padrões** ("Tipos de disponibilidade").
  #
  # **Não é escopado por projeto**, e isso é a regra (contrato C1, regra 4).
  # Nenhum método aqui recebe `project`. O oposto de `ProjectTemplateService`,
  # de propósito.
  #
  # ## Os quatro defeitos que este serviço fecha
  #
  # | Defeito | No legado |
  # | ------- | --------- |
  # | **D-06** | a busca montava `where!("title #{Dev.ilike} ", "#{@query}%")` — fragmento **sem placeholder**, com o padrão passado como segundo argumento. Qualquer texto digitado derrubava a requisição, e a lista só parava de atualizar, sem mensagem |
  # | **D-07 / D-20** | `l` e `o` eram lidos e **nunca aplicados**: a lista vinha inteira, sempre |
  # | **BE-134** | `is_mandatory |= 1` no `before_validation`: **todo global nascia obrigatório**, ignorando o formulário. E `should_insert_on_existing_projects` tinha default `1` e não era exposto — **toda criação** enfileirava job em **todos** os projetos |
  # | **D-24** | o `after_destroy` fazia `update_all` sem transação; quando falhava no meio sobravam padrões de projeto apontando para um global inexistente, e existia uma rotina manual (`fix_after_global_remove`) para limpar depois |
  class GlobalTemplateService
    class << self
      include ApiResponseHandler

      UUID_FORMAT = ProjectScopedService::UUID_FORMAT

      def model = GlobalAvailabilityTemplate

      def writable_attributes
        %i[title operation_type deadline_type is_mandatory is_cumulative is_adjusted
           should_insert_on_existing_projects default_position parent_template_id]
      end

      # --- Leitura ---------------------------------------------------------

      # BE-132. Busca por **substring** (não só prefixo, como o `"#{@query}%"`
      # do legado tentava), ordenação real e paginação real. Catálogo vazio
      # devolve lista vazia — nunca SQL inválido.
      def index(params: {})
        escopo = model.all
        escopo = escopo.search(params[:q]) if params[:q].present?
        escopo = escopo.where(parent_template_id: params[:parent_id]) if uuid?(params[:parent_id])
        escopo = escopo.where(is_active: truthy?(params[:is_active])) unless params[:is_active].nil?
        escopo = AvailabilityTemplate::ORDERING.apply(escopo, keys: params[:ordering_keys],
                                                              styles: params[:ordering_style])

        { status: 200, data: escopo }
      end

      # BE-133 — o detalhe funciona **também** para padrão de projeto. No legado
      # a view do detalhe chamava `@availability_template.projects`, associação
      # que **não existe** em nenhuma das duas classes: `NoMethodError` na hora.
      # Aqui a busca é na tabela, não na classe, e o serializer sabe distinguir.
      def show(id:)
        registro = AvailabilityTemplate.find_by(id: id) if uuid?(id)
        return not_found if registro.nil?

        { status: 200, data: registro }
      end

      # BE-111 / BE-141 — os pais **válidos** para o nível pretendido. Um padrão
      # de 3º nível não pode ser pai de ninguém.
      def available_parents(level: nil)
        limite = level.present? ? level.to_i - 1 : AvailabilityTemplate::MAX_LEVEL - 1
        model.where(level: 1..[limite, AvailabilityTemplate::MAX_LEVEL - 1].min).in_tree_order
      end

      # --- Escrita ---------------------------------------------------------

      # BE-134 / BE-137. A obrigatoriedade escolhida **é gravada**, e a
      # propagação para projetos existentes é **opção do usuário**.
      def create(attrs:, actor: nil)
        registro = model.new
        atribuir(registro, attrs)
        registro.user_id = actor&.id

        propagar = truthy?(registro.should_insert_on_existing_projects)

        # **Sem `return` dentro do bloco de transação**: a partir do Rails 7.1
        # `return`/`break` dentro de `transaction do` deixaram de dar rollback e
        # passaram a **commitar**. O resultado sai numa variável.
        gravou = model.transaction do
          TreeService.assign_next_position!(registro)
          salvar(registro) || raise(ActiveRecord::Rollback)
        end

        return unprocessable(registro) unless gravou

        enqueue_propagation(registro, actor: actor) if propagar

        { status: 201, data: registro, propagated: propagar }
      end

      # BE-135. Duas coisas acontecem aqui e não aconteciam no legado:
      #
      #  - a **posição é recalculada** quando o pai muda (o legado tinha o
      #    `before_validation` de posicionamento em `on: [:create]`, então
      #    reparentar deixava a `sort_key` mentindo);
      #  - alterar `is_adjusted`/`is_cumulative` **propaga** aos padrões de
      #    projeto derivados, em segundo plano (DC-31). Hoje não propaga, e o
      #    catálogo mente sobre os padrões que gerou.
      def update(id:, attrs:, actor: nil)
        registro = model.find_by(id: id) if uuid?(id)
        return not_found if registro.nil?

        pai_anterior = registro.parent_template_id
        atribuir(registro, attrs)
        propagaveis = registro.changes.slice('is_adjusted', 'is_cumulative')

        gravou = model.transaction do
          TreeService.assign_next_position!(registro) if registro.parent_template_id != pai_anterior
          salvar(registro) || raise(ActiveRecord::Rollback)
          TreeService.rebuild_subtree_sort_keys!(registro) if registro.saved_change_to_attribute?(:sort_key)
          true
        end

        return unprocessable(registro) unless gravou

        enqueue_attribute_propagation(registro, propagaveis, actor: actor) if propagaveis.any?

        { status: 200, data: registro.reload, propagated_attributes: propagaveis.keys }
      end

      # BE-136 / D-24 — **desvínculo em cascata, transacional**.
      #
      # O legado tinha `has_many :child_templates, dependent: :destroy` (que
      # apaga a subárvore global) e um `after_destroy` que rodava
      # `project_templates.update_all(...)` **fora de qualquer transação**.
      # Falha no meio deixava padrões de projeto órfãos apontando para um global
      # que não existe mais, e alguém precisava rodar `fix_after_global_remove`
      # à mão. Aqui as duas coisas acontecem na mesma transação, ou nenhuma.
      def destroy(id:)
        registro = model.find_by(id: id) if uuid?(id)
        return not_found if registro.nil?

        ids = registro.subtree_ids

        model.transaction do
          ProjectAvailabilityTemplate.where(global_availability_template_id: ids)
                                     .update_all(global_availability_template_id: nil, is_global: false,
                                                 updated_at: Time.current)
          # Do mais fundo para a raiz: o `restrict_with_error` do pai só não
          # dispara porque os filhos já saíram. `destroy!` em vez de
          # `destroy_all` porque `destroy_all` engole a recusa e devolve uma
          # lista — exclusão parcial em silêncio é o D-24 outra vez.
          AvailabilityTemplate.where(id: ids).order(level: :desc).each(&:destroy!)
        end

        TreeService.reorder_global!
        { status: 200, data: { deleted: true, id: id.to_s, removed_count: ids.size } }
      rescue ActiveRecord::InvalidForeignKey => e
        Rails.logger.info("[Availability::GlobalTemplateService] exclusão recusada pelo banco: #{e.message}")
        { status: 422, error: 'Não é possível excluir: há registros vinculados a este padrão.' }
      end

      # BE-138 — reordenar. Recusado no servidor quando inválido.
      def move(id:, position:)
        registro = model.find_by(id: id) if uuid?(id)
        return not_found if registro.nil?

        ok, mensagem = TreeService.move!(registro, position)
        return { status: 422, error: mensagem } unless ok

        { status: 200, data: registro.reload }
      end

      # --- Peças internas ---------------------------------------------------

      def uuid?(value) = value.to_s.match?(UUID_FORMAT)

      def truthy?(value) = ActiveModel::Type::Boolean.new.cast(value) == true

      private

      def atribuir(registro, attrs)
        writable_attributes.each do |atributo|
          next unless attrs.key?(atributo)

          registro.public_send(:"#{atributo}=", attrs[atributo])
        end
      end

      def salvar(registro)
        registro.save
      rescue ActiveRecord::RecordNotUnique => e
        Rails.logger.info("[Availability::GlobalTemplateService] índice único recusou: #{e.message}")
        registro.errors.add(:base, 'Já existe um padrão com este título neste nível.')
        false
      end

      # OPS-121 — a propagação vira **job**, nunca um laço `Project.all.each`
      # dentro de um `after_create` de model, que é o que o legado fazia
      # (`global_availability_template.rb:26-38`).
      def enqueue_propagation(registro, actor: nil)
        PropagateGlobalTemplateJob.perform_later(registro.id, actor&.id, 'insert')
      end

      def enqueue_attribute_propagation(registro, _mudancas, actor: nil)
        PropagateGlobalTemplateJob.perform_later(registro.id, actor&.id, 'sync_attributes')
      end

      def not_found
        { status: 404, error: 'Padrão de disponibilidade não encontrado.' }
      end

      def unprocessable(registro)
        { status: 422, error: registro.errors.full_messages.to_sentence, details: registro.errors.messages }
      end
    end
  end
end
