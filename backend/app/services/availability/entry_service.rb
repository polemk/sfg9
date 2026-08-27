# frozen_string_literal: true

module Availability
  # S11 / BE-122, BE-123, BE-124, BE-131 — **gravação de lançamento de
  # disponibilidade**.
  #
  # Escopado por projeto (contrato **C1**). O `project_id` que chega no corpo da
  # requisição **não é lido** — é o mesmo cuidado do `ProjectScopedService`, e
  # aqui ele importa mais: o legado aceitava `:project_id`, `:company_id`,
  # `:availability_template_id` **e** `:user_id` soltos no `permit`
  # (`availability_entries_controller.rb:82-92`).
  #
  # ## Os quatro defeitos que este serviço fecha
  #
  # | Defeito | No legado |
  # | ------- | --------- |
  # | **BE-122** | `create` inválido chamava `@availability_entry.destroy` — `destroy` sobre registro **não persistido**. Funciona por acaso; deixa de funcionar no dia em que houver `after_destroy` |
  # | **BE-123** | `update` fazia `@entry.update(params)` **e** `@entry.save` logo em seguida: **duas gravações**, e a segunda dispara toda a cascata de derivados de novo — que, num padrão corrigido, **multiplica o valor mais uma vez** (D-02) |
  # | **BE-123** | a **consolidação geral era editável por envio direto**: nada no servidor recusava `company_id` nulo vindo do cliente |
  # | **BE-124 / DC-26** | `destroy` chamava `parent_entry` **antes** do destroy, e `parent_entry` **cria** o pai quando ele não existe: apagar uma célula de 1º nível criava um registro |
  #
  # **O que NÃO muda:** as fórmulas. Ver `AvailabilityEntry` — DEC-24, DEC-26,
  # DEC-27 e DEC-28 mandaram replicar, e há golden test travando cada uma.
  class EntryService
    class << self
      UUID_FORMAT = ProjectScopedService::UUID_FORMAT

      # BE-122. Duplicidade responde **422** — o índice único do banco
      # (`index_availability_entries_unique_by_company`) é a garantia, e a
      # validação é a mensagem em pt-BR. E **nada é destruído em caso de
      # falha**: um registro que não foi gravado não precisa ser apagado.
      def create(project:, attrs:, actor: nil)
        padrao, erro = resolve_template(project, attrs[:availability_template_id])
        return erro if erro

        empresa, erro = resolve_company(project, attrs[:company_id])
        return erro if erro
        return consolidation_refused if empresa.nil?
        return locked_conflict(padrao) if padrao.locked?
        return derived_refused if padrao.has_children?

        registro = AvailabilityEntry.new(
          project: project, company: empresa, availability_template: padrao,
          date: attrs[:date], value: attrs[:value].presence || 0, user_id: actor&.id
        )

        return unprocessable(registro) unless salvar(registro)

        { status: 201, data: registro.reload }
      end

      # BE-123. **Uma única gravação.**
      def update(project:, id:, attrs:, actor: nil)
        registro = find(project, id)
        return not_found if registro.nil?

        padrao = registro.availability_template
        return consolidation_refused if registro.consolidation?
        return locked_conflict(padrao) if padrao&.locked?
        return derived_refused if padrao&.has_children?

        registro.value = attrs[:value] if attrs.key?(:value)
        registro.user_id = actor&.id if actor
        # Reafirmado depois da atribuição: nem o corpo nem um gancho movem o
        # lançamento de projeto.
        registro.project_id = project.id

        return unprocessable(registro) unless salvar(registro)

        { status: 200, data: registro.reload }
      end

      # BE-124 / DC-26. **A exclusão não cria registro.**
      #
      # O legado fazia `parent = @entry.parent_entry` (que **cria** o pai se ele
      # não existir), depois `@entry.destroy`, depois `parent.save`. Havia
      # inclusive um `TODO #7408` admitindo que o cenário multiempresa não tinha
      # sido fechado. Aqui o pai e a consolidação são recalculados **só se já
      # existirem**.
      def destroy(project:, id:)
        registro = find(project, id)
        return not_found if registro.nil?

        padrao = registro.availability_template
        return consolidation_refused if registro.consolidation?
        return locked_conflict(padrao) if padrao&.locked?

        contexto = { project_id: registro.project_id, company_id: registro.company_id,
                     date: registro.date, parent_template_id: padrao&.parent_template_id,
                     template_id: registro.availability_template_id }

        AvailabilityEntry.transaction do
          registro.destroy!
          recompute_existing_relatives(contexto)
        end

        { status: 200, data: { deleted: true, id: id.to_s } }
      end

      def find(project, id)
        return nil unless uuid?(id)

        AvailabilityEntry.for_project(project).find_by(id: id)
      end

      private

      def uuid?(value) = value.to_s.match?(UUID_FORMAT)

      def resolve_template(project, template_id)
        return [nil, not_found] unless uuid?(template_id)

        padrao = ProjectAvailabilityTemplate.for_project(project).find_by(id: template_id)
        return [nil, not_found] if padrao.nil?
        unless padrao.is_active?
          return [nil, { status: 422, error: 'Este padrão está desativado e não aceita lançamento.' }]
        end

        [padrao, nil]
      end

      def resolve_company(project, company_id)
        GridService.resolve_company(project, company_id)
      end

      # Recalcula pai e consolidação **sem criar nada**.
      def recompute_existing_relatives(contexto)
        if contexto[:parent_template_id].present?
          pai = AvailabilityEntry.find_by(project_id: contexto[:project_id], company_id: contexto[:company_id],
                                          availability_template_id: contexto[:parent_template_id],
                                          date: contexto[:date])
          pai&.recompute_and_save!
        end

        espelho = AvailabilityEntry.find_by(project_id: contexto[:project_id], company_id: nil,
                                            availability_template_id: contexto[:template_id],
                                            date: contexto[:date])
        espelho&.recompute_and_save!
      end

      def salvar(registro)
        registro.save
      rescue ActiveRecord::RecordNotUnique => e
        Rails.logger.info("[Availability::EntryService] índice único recusou: #{e.message}")
        registro.errors.add(:base, 'Já existe lançamento para este padrão, nesta data e nesta empresa. ' \
                                   'Recarregue a grade para editá-lo.')
        false
      end

      def not_found
        { status: 404, error: 'Lançamento não encontrado.' }
      end

      def consolidation_refused
        { status: 422,
          error: 'A consolidação geral é calculada a partir das empresas e não pode ser lançada ' \
                 'diretamente. Escolha uma empresa para lançar o valor.' }
      end

      def derived_refused
        { status: 422,
          error: 'Este padrão tem itens abaixo dele: o valor é a soma dos filhos e não pode ser ' \
                 'digitado. Lance nos itens de baixo.' }
      end

      def locked_conflict(padrao)
        { status: 409,
          error: padrao&.locked_message.presence ||
                 'Este padrão está bloqueado por uma operação em andamento. Tente de novo quando ela terminar.' }
      end

      def unprocessable(registro)
        { status: 422, error: registro.errors.full_messages.to_sentence, details: registro.errors.messages }
      end
    end
  end
end
