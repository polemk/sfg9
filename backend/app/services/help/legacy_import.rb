# frozen_string_literal: true

module Help
  # S12 / DB-369, BE-362, tarefas 6.1 e 6.2 — **a carga em dois passos do item
  # de ajuda**, e a desambiguação do slug de categoria.
  #
  # O item de ajuda do legado tem **dois acervos**:
  #
  #  - `help_items.description`, a **coluna**, escrita até 04/2019;
  #  - `action_text_rich_texts`, usada depois, quando `has_rich_text` entrou.
  #
  # `has_rich_text` **sobrescreveu o leitor da coluna**: a partir de 04/2019 o
  # conteúdo novo ficou invisível para todo `WHERE description ILIKE …`. É o
  # D-58, e ele não aparece na tela — o item abre normalmente; só a busca mente.
  #
  # A carga é em **dois passos, nesta ordem**:
  #
  #   1. o acervo **ActionText** (o mais recente vence);
  #   2. a **coluna**, só para os itens que não têm registro rico.
  #
  # Inverter a ordem faria o conteúdo de 2018 sobrescrever o de 2024 nos itens
  # que têm os dois.
  #
  # **`dry_run: true` não grava nada** e devolve de onde cada item viria. É o que
  # a tarefa 6.1 exige: *"o dry-run lista quantos vieram de cada origem"*.
  #
  # ⚠️ **Risco alto (dado):** imagem embutida no conteúdo do editor depende de
  # `DB-482` (motor único de anexos, fatia S-08). Se os anexos não migrarem, o
  # texto vem e a imagem some. O relatório abaixo conta quantos corpos contêm
  # `<action-text-attachment>` justamente para que isso não seja descoberto
  # depois.
  module LegacyImport
    # Uma linha de origem, agnóstica de onde veio (dump, CSV, conexão direta):
    # `{ legacy_id:, title:, category_legacy_id:, user_legacy_id:,
    #    rich_text_body:, column_description: }`
    Report = Struct.new(:from_rich_text, :from_column, :without_body, :with_attachments,
                        :created, :updated, :skipped, :errors, keyword_init: true) do
      def to_h
        {
          from_rich_text: from_rich_text, from_column: from_column,
          without_body: without_body, with_attachments: with_attachments,
          created: created, updated: updated, skipped: skipped, errors: errors
        }
      end
    end

    module_function

    def call(rows, dry_run: true)
      relatorio = Report.new(from_rich_text: 0, from_column: 0, without_body: 0,
                             with_attachments: 0, created: 0, updated: 0,
                             skipped: 0, errors: [])

      Array(rows).each do |row|
        r = row.respond_to?(:symbolize_keys) ? row.symbolize_keys : row
        corpo, origem = resolve_body(r)

        case origem
        when :rich_text then relatorio.from_rich_text += 1
        when :column then relatorio.from_column += 1
        else relatorio.without_body += 1
        end

        relatorio.with_attachments += 1 if corpo.to_s.include?('<action-text-attachment')

        next if dry_run

        aplicar!(r, corpo, relatorio)
      end

      relatorio
    end

    # Passo 1 antes do passo 2 — é a ordem que decide qual acervo vence.
    def resolve_body(row)
      rico = row[:rich_text_body].to_s
      return [rico, :rich_text] if rico.strip.present?

      coluna = row[:column_description].to_s
      return [coluna, :column] if coluna.strip.present?

      [nil, :none]
    end

    def aplicar!(row, corpo, relatorio)
      categoria = HelpCategory.find_by(legacy_id: row[:category_legacy_id])
      if categoria.nil?
        relatorio.skipped += 1
        relatorio.errors << "item legado #{row[:legacy_id]}: categoria #{row[:category_legacy_id]} não encontrada"
        return
      end

      item = HelpItem.find_or_initialize_by(legacy_id: row[:legacy_id])
      novo = item.new_record?
      item.help_category_id = categoria.id
      item.title = row[:title]
      item.description = corpo if corpo.present?
      item.user_id ||= User.find_by(legacy_id: row[:user_legacy_id])&.id

      if item.save
        novo ? relatorio.created += 1 : relatorio.updated += 1
      else
        relatorio.skipped += 1
        relatorio.errors << "item legado #{row[:legacy_id]}: #{item.errors.full_messages.to_sentence}"
      end
    end
  end
end
