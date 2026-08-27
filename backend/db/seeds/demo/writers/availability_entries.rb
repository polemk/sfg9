# frozen_string_literal: true

module Demo
  module Writers
    # Os **lançamentos de disponibilidade** — a célula da grade
    # (padrão × empresa × data).
    #
    # ## O escritor grava só as FOLHAS, e isso é a decisão inteira
    #
    # Nó com filhos, padrão base e a linha de consolidação geral são derivados, e
    # quem os materializa é o `after_save` de `AvailabilityEntry` — o **mesmo**
    # caminho por onde a tela grava. Escrever aqui o valor de um nó pai seria
    # criar um segundo cálculo para o mesmo número; na primeira divergência, o
    # rodapé do painel deixaria de bater com a soma das linhas na frente do
    # cliente, e ninguém saberia qual dos dois está certo.
    #
    # Consequência prática: este módulo reporta ~1.700 criados na primeira
    # execução e o banco fica com ~2.700 lançamentos. A diferença **não é** linha
    # perdida — é o derivado que a cascata materializou.
    #
    # ## Padrão corrigido: o valor do razão é a BASE, não o exibido
    #
    # Num padrão `is_adjusted` (DEC-24 / D-02) o model regrava
    # `original_value = value` e depois faz `value = original_value ×
    # multiplicador de dias úteis`. O razão declara a **base**; o `value`
    # gravado é o corrigido. É por isso que a segunda execução não muda nada:
    # atribuir a base de novo produz exatamente o mesmo par.
    class AvailabilityEntries < Base
      def self.requires = %w[AvailabilityEntry ProjectAvailabilityTemplate Company]
      def self.owner_slice = 'S11'

      def call
        author_id = demo_author&.id

        ledger.availability_entries_by_client.each do |slug, entries|
          client = ledger.clients.find { |c| c.slug == slug }
          project = project_for(client)
          next if project.nil?

          templates = AvailabilityTemplates.resolve_for_project(project, ledger)

          entries.each do |entry|
            company = companies_by_key[entry.company.key]
            template = templates[entry.template_key]
            next if company.nil? || template.nil?

            record = ::AvailabilityEntry.find_or_initialize_by(
              project_id: project.id, company_id: company.id,
              availability_template_id: template.id, date: entry.date
            )

            if settled?(record, template, entry, author_id)
              @unchanged += 1
              next
            end

            persist!(record, { value: entry.value, user_id: author_id })
          end
        end
      end

      private

      # **A célula já está como o razão a quer?**
      #
      # A comparação normal de `upsert!` (atribuir e perguntar `changed?`) não
      # serve aqui, e o motivo é o D-02: num padrão corrigido o que fica em
      # `value` é o valor **já multiplicado** pelos dias úteis, e o que o razão
      # declara é a **base**. Atribuir a base marca `value` como alterado; a
      # validação recalcula e o valor volta ao que já estava — mas o contador já
      # tinha registrado "atualizado". Resultado: 312 atualizações fantasmas por
      # execução, para sempre, e o portão de idempotência nunca fecha.
      #
      # A saída **não** é validar antes de contar: rodar o `before_validation`
      # duas vezes num registro novo é exatamente o decaimento composto do
      # BE-123 — `original_value` receberia o valor já corrigido e a célula
      # encolheria a cada gravação. Aqui a pergunta é feita no campo certo: num
      # padrão corrigido, a entrada digitada mora em `original_value`.
      def settled?(record, template, entry, author_id)
        return false unless record.persisted?
        return false unless record.user_id == author_id

        stored = template.is_adjusted? ? record.original_value : record.value
        stored.to_d == entry.value.to_d
      end
    end
  end
end
