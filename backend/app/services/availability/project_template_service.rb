# frozen_string_literal: true

module Availability
  # S11 / BE-110..116, BE-140..148 — **os padrões de disponibilidade de um projeto**.
  #
  # Escopado por projeto (contrato **C1**): todo método recebe o `project` já
  # resolvido pelo endpoint por `current_project!`, e o `project_id` que vier no
  # corpo da requisição **não é lido**. É o oposto do `GlobalTemplateService`, e
  # os dois estão certos.
  #
  # ## As guardas que passam a rodar no SERVIÇO, antes de enfileirar
  #
  # No legado (`pub/project_availabilities_controller.rb:78-100`) o controller
  # enfileirava o job **primeiro** e a guarda de obrigatoriedade morava dentro de
  # `deactive_and_reorder!` — método que **nenhum caminho real chamava**: o job
  # de desativação usava `background_deactivate`, que faz `template.is_active = 0`
  # direto. A guarda existia e nunca era executada (**D-04 / D-33**). Pior: a
  # consulta de dependentes filtrava `project_id: self.id` — o **id do padrão**
  # no lugar do id do projeto —, então nunca achava dependente nenhum.
  #
  # Aqui as três guardas rodam **antes de enfileirar** e a resposta é do
  # servidor: obrigatório não desativa, dependente obrigatório não desativa, e
  # padrão com lançamento não é removido (DC-20).
  class ProjectTemplateService < ProjectScopedService
    class << self
      def model = ProjectAvailabilityTemplate
      def resource_label = 'Padrão de disponibilidade'

      def writable_attributes
        %i[title operation_type deadline_type is_mandatory is_cumulative is_adjusted parent_template_id]
      end

      # Na edição só o título muda (DC-24). O legado tinha **toda** a
      # configuração dentro de um `if id.blank?` na view, sem nenhuma
      # explicação; a restrição fica, agora com a razão declarada — o
      # `immutable_fields_reason` viaja no entity e a tela a mostra.
      IMMUTABLE_ON_UPDATE = %i[operation_type deadline_type is_cumulative is_adjusted parent_template_id].freeze

      IMMUTABLE_REASON =
        'A natureza da operação, o prazo, a cumulatividade, a correção e o pai definem como os ' \
        'lançamentos já gravados foram calculados. Alterá-los mudaria valores do histórico, então ' \
        'só o título é editável. Para mudar a configuração, crie um padrão novo.'

      def base_scope(project)
        model.for_project(project).includes(:global_template)
      end

      # BE-110 / BE-140 — **a árvore, numa consulta**.
      #
      # O legado montava a ordem com `all_ids_by_position`, que faz **uma
      # consulta por nó de 1º e 2º nível**, e depois remontava a ordem com um
      # `joins("join (VALUES (1,0),(7,1),…)")` construído por interpolação de
      # string. Com o projeto zerado a lista de ids saía vazia e o `VALUES ()`
      # virava **SQL inválido** — o `#tree` respondia 500 em projeto novo.
      # Aqui é `ORDER BY sort_key`.
      def tree(project:, params: {})
        escopo = base_scope(project)
        escopo = escopo.search(params[:q]) if params[:q].present?
        escopo = escopo.where(is_active: truthy?(params[:is_active])) unless params[:is_active].nil?
        escopo = escopo.in_tree_order

        { status: 200, data: escopo }
      end

      # BE-111 / BE-141 — "Faz parte de" só oferece **pais válidos**, e só do
      # projeto corrente. É o servidor fechando o vazamento do `data-templates`
      # (FE-110/FE-139/FE-148).
      def available_parents(project:, level: nil)
        limite = level.present? ? level.to_i - 1 : AvailabilityTemplate::MAX_LEVEL - 1
        model.for_project(project)
             .where(level: 1..[limite, AvailabilityTemplate::MAX_LEVEL - 1].min)
             .in_tree_order
      end

      # --- Escrita ----------------------------------------------------------

      # BE-112 / BE-142. Projeto **do servidor**, `:id` fora do `permit`, nível
      # derivado do pai, título único no nível **incluindo o 3º**.
      def create(project:, attrs:, actor: nil)
        registro = model.new
        registro.project = project
        assign(registro, attrs)
        registro.user_id = actor&.id

        gravou = model.transaction do
          TreeService.assign_next_position!(registro)
          save_safely(registro) || raise(ActiveRecord::Rollback)
        end

        return unprocessable(registro) unless gravou

        { status: 201, data: registro }
      end

      # BE-143. Duas regras:
      #
      #  - **padrão bloqueado → 409.** Enquanto um job mexe nos lançamentos, o
      #    padrão não muda debaixo dele;
      #  - **renomear NÃO renumera** (DC-32). No legado o `before_validation` de
      #    posicionamento estava em `on: [:create]` no global mas rodava
      #    **também no update** do padrão de projeto: trocar o título
      #    recalculava a posição e embaralhava a árvore.
      def update(project:, id:, attrs:, actor: nil)
        registro = find(project, id)
        return not_found if registro.nil?
        return locked_conflict(registro) if registro.locked?

        recusados = attrs.keys.map(&:to_sym) & IMMUTABLE_ON_UPDATE
        if recusados.any?
          return { status: 422, error: IMMUTABLE_REASON,
                   details: { immutable_fields: recusados.map(&:to_s) } }
        end

        assign(registro, attrs.slice(*(writable_attributes - IMMUTABLE_ON_UPDATE)))
        registro.project_id = project.id

        return unprocessable(registro) unless save_safely(registro)

        { status: 200, data: registro.reload }
      end

      # BE-144 / BE-113 / DC-33 — **ativar**.
      #
      # Idempotente: a segunda ativação responde **409**, não um segundo job. No
      # legado `Delayed::Job.enqueue` era chamado sempre e o `unless job.nil?`
      # tratava a falha de enfileiramento como **sucesso** — a tela dizia
      # "ativado" e nada acontecia.
      def activate(project:, id:, actor: nil)
        registro = find(project, id)
        return not_found if registro.nil?
        return conflict('Este padrão já está ativo.') if registro.is_active? && !registro.locked?
        return locked_conflict(registro) if registro.locked?

        pai = registro.parent_template
        if pai.present? && !pai.is_active?
          return { status: 422,
                   error: "Ative antes o padrão \"#{pai.title}\", que está desativado — um padrão " \
                          'não pode ficar ativo debaixo de um pai inativo.' }
        end

        registro.lock!('Este padrão foi ativado e fica bloqueado até a atualização dos lançamentos terminar.',
                       actor: actor)
        ActivateProjectTemplateJob.perform_later(registro.id, actor&.id)

        { status: 202, data: registro.reload }
      end

      # BE-145 / BE-114 / D-04 / D-33 — **desativar**, com as guardas rodando
      # **aqui**, antes de qualquer job entrar na fila.
      def deactivate(project:, id:, actor: nil)
        registro = find(project, id)
        return not_found if registro.nil?
        return conflict('Este padrão já está desativado.') if !registro.is_active? && !registro.locked?
        return locked_conflict(registro) if registro.locked?

        if registro.is_mandatory?
          return { status: 422, error: 'Este padrão é obrigatório e não pode ser desativado.' }
        end

        dependentes = mandatory_dependents(registro)
        if dependentes.any?
          nomes = dependentes.map(&:title).to_sentence(locale: :'pt-BR')
          return { status: 422,
                   error: "Este padrão tem dependentes obrigatórios (#{nomes}) e não pode ser desativado." }
        end

        registro.lock!('Este padrão foi desativado e fica bloqueado até a atualização dos lançamentos terminar.',
                       actor: actor)
        DeactivateProjectTemplateJob.perform_later(registro.id, actor&.id)

        { status: 202, data: registro.reload }
      end

      # BE-146 / BE-115 / DC-20 — **remover**.
      #
      # Duas recusas que o legado não fazia:
      #
      #  - **padrão com lançamentos → 422**, e os lançamentos **permanecem**. O
      #    legado tinha `dependent: :restrict_with_error` na associação e o
      #    contornava com `self.entries.destroy_all` dentro de
      #    `background_remove_templates`: apagava dado financeiro sem avisar;
      #  - **padrão de origem global não é removível pela rota do projeto** — o
      #    vínculo se desfaz pelo catálogo, senão o projeto some com uma linha
      #    que o catálogo continua achando que existe.
      def destroy(project:, id:, actor: nil)
        registro = find(project, id)
        return not_found if registro.nil?
        return locked_conflict(registro) if registro.locked?

        if registro.is_global?
          return { status: 422,
                   error: 'Este padrão veio do catálogo global e não pode ser removido pela tela do ' \
                          'projeto. Desative-o aqui, ou remova o padrão no catálogo.' }
        end

        unless registro.deletable?
          quantidade = AvailabilityEntry.where(availability_template_id: registro.subtree_ids).count
          return { status: 422,
                   error: "Este padrão tem #{quantidade} lançamento(s) e não pode ser removido. " \
                          'Exclua os lançamentos antes, ou desative o padrão.' }
        end

        registro.lock!('Este padrão foi removido e fica bloqueado até a operação terminar.', actor: actor)
        RemoveProjectTemplateJob.perform_later(registro.id, actor&.id)

        { status: 202, data: { scheduled: true, id: registro.id } }
      end

      # BE-116 / BE-138 — mover dentro do grupo de irmãos.
      def move(project:, id:, position:)
        registro = find(project, id)
        return not_found if registro.nil?
        return locked_conflict(registro) if registro.locked?

        ok, mensagem = TreeService.move!(registro, position)
        return { status: 422, error: mensagem } unless ok

        { status: 200, data: registro.reload }
      end

      # Dependentes obrigatórios na subárvore. É a consulta que o legado escrevia
      # como `where(project_id: self.id, …)` — **id do padrão** no lugar do id
      # do projeto —, e que por isso nunca achava nada.
      def mandatory_dependents(registro)
        model.where(id: registro.subtree_ids - [registro.id], is_mandatory: true).to_a
      end

      private

      def conflict(mensagem)
        { status: 409, error: mensagem }
      end

      def locked_conflict(registro)
        conflict(registro.locked_message.presence ||
                 'Este padrão está bloqueado por uma operação em andamento. Tente de novo quando ela terminar.')
      end
    end
  end
end
