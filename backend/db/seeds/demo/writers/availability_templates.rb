# frozen_string_literal: true

module Demo
  module Writers
    # A árvore de **padrões de disponibilidade**: o catálogo global e a cópia
    # derivada de cada projeto.
    #
    # ## A chave natural é o título NORMALIZADO dentro do pai
    #
    # O banco cobra duas unicidades — `(type, project_id, title)` na raiz e
    # `(project_id, parent_template_id, title)` no filho — e as duas são por
    # **texto exato**. Casar por texto exato aqui seria um bug esperando o
    # primeiro acento: o banco de demonstração já tinha treze padrões criados à
    # mão, sem acentuação (`Recebiveis a vencer`, `Exigivel de longo prazo`), e
    # gravar a versão acentuada por cima criaria uma **segunda** raiz com o
    # mesmo significado — ou estouraria o índice.
    #
    # Por isso o casamento é por `I18n.transliterate(title).downcase`: a linha
    # existente é **adotada** e recebe o título canônico. Na segunda execução ela
    # já está canônica e nada muda.
    #
    # ## `position` e `sort_key` vêm do razão, não do `TreeService`
    #
    # `TreeService.assign_next_position!` lê `max(position) + 1` sob advisory
    # lock — correto para a tela, e **não determinístico** para um seed: a
    # posição passaria a depender da ordem de gravação e de o que já existia. O
    # razão declara o caminho (`"1.2.3"`), e daí saem posição e `sort_key`
    # zero-padded. Rodar duas vezes dá a mesma árvore.
    class AvailabilityTemplates < Base
      def self.requires = %w[GlobalAvailabilityTemplate ProjectAvailabilityTemplate]
      def self.owner_slice = 'S11'

      def call
        globals = write_globals!
        ledger.clients.each { |client| write_project!(client, globals) }
      end

      # Os padrões de projeto gravados, por `(slug do projeto, caminho)`. É o
      # que o escritor de lançamentos consome.
      def self.resolve_for_project(project, ledger)
        existing = ::ProjectAvailabilityTemplate.where(project_id: project.id).to_a
        ledger.availability_templates.each_with_object({}) do |node, acc|
          record = existing.find { |t| Base.normalized_title(t.title) == Base.normalized_title(node.title) }
          acc[node.key] = record if record
        end
      end

      private

      def write_globals!
        existing = ::GlobalAvailabilityTemplate.all.to_a
        map = {}

        Ledger::Availability.global_templates.each do |node|
          parent = node.parent_path && map[node.parent_path]
          candidates = existing.select { |t| t.parent_template_id == parent&.id }
          record = find_by_title(candidates, node.title) || ::GlobalAvailabilityTemplate.new

          persist!(record, attributes_for(node, parent).merge(project_id: nil))
          map[node.path] = record
        end

        map
      end

      def write_project!(client, globals)
        project = project_for(client)
        return if project.nil?

        existing = ::ProjectAvailabilityTemplate.where(project_id: project.id).to_a
        map = {}

        ledger.availability_templates.each do |node|
          parent = node.parent_path && map[node.parent_path]
          candidates = existing.select { |t| t.parent_template_id == parent&.id }
          record = find_by_title(candidates, node.title) || ::ProjectAvailabilityTemplate.new

          persist!(record, attributes_for(node, parent).merge(
                             project_id: project.id,
                             # A origem global é o que liga o padrão do projeto ao
                             # catálogo — sem ela a propagação de atributo (DC-31)
                             # não encontra os derivados. O padrão específico do
                             # projeto não tem origem, e é por isso que a tela o
                             # rotula "Específico".
                             is_global: node.is_global,
                             global_availability_template_id: node.is_global ? globals[node.path]&.id : nil
                           ))
          map[node.path] = record
        end
      end

      def find_by_title(candidates, title)
        normalized = Base.normalized_title(title)
        candidates.find { |t| Base.normalized_title(t.title) == normalized }
      end

      def attributes_for(node, parent)
        {
          title: node.title,
          parent_template_id: parent&.id,
          position: node.position,
          sort_key: node.path.split('.').map { |segment| format('%04d', segment.to_i) }.join('.'),
          operation_type: node.operation_type,
          deadline_type: node.deadline_type,
          is_active: true,
          is_mandatory: node.is_mandatory,
          is_cumulative: node.is_cumulative,
          is_adjusted: node.is_adjusted,
          # **Padrão bloqueado NÃO nasce bloqueado** (D-05): o bloqueio é estado
          # transitório de job, e um seed que o grava entrega uma tela em que
          # nada é editável e ninguém sabe por quê.
          is_locked: false,
          user_id: demo_author&.id
        }
      end
    end
  end
end
