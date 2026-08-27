# frozen_string_literal: true

# S11 / DB-123, DB-125, DB-126, DB-127, DB-130, DB-133, DB-567
#
# **Lançamentos de disponibilidade** — a célula da grade: um valor, para um
# padrão, numa data, de uma empresa (ou da consolidação do projeto).
#
# ## É a maior tabela do módulo e no legado não tinha NENHUM índice
#
# `20210420180813_create_availability_entries.rb` cria sete colunas e nada mais:
# sem FK, sem índice, sem unicidade. A unicidade existia **só** no model
# (`validates_uniqueness_of :date, scope: [...]`), que é exatamente o tipo de
# garantia que duas abas abertas contornam.
#
# ## `original_value` — o que ele guarda, e por que NÃO é o valor digitado
#
# O desenho original desta fatia dizia "o valor digitado, preservado, nunca
# sobrescrito". **A DEC-24 revogou isso**: o usuário escolheu, conscientemente,
# replicar o decaimento composto do legado (defeito **D-02**).
#
# Na prática: `availability_entry.rb:20` regrava `original_value = value`
# **toda vez** que `value` chega alterado num padrão corrigido, e a correção por
# dias úteis (`:193`) multiplica de novo. Salvar a mesma célula duas vezes
# produz números diferentes — e continua produzindo, de propósito, porque
# paridade numérica está acima de correção (DEC-30). O golden test
# `spec/models/availability_entry_spec.rb` trava esse comportamento e **reprova
# quem "consertar" a fórmula** sem passar por uma DEC nova.
#
# ## A marca de consolidação é EXPLÍCITA (DB-126)
#
# No legado "é consolidação" era inferido de `company_id IS NULL`
# (`availability_entry.rb#mirror?`). O problema é que a rotina `fix__7412`
# **reatribuiu empresa nula à primeira empresa do projeto**, então o ETL não
# consegue distinguir consolidação legítima de dado sujo olhando só a coluna.
# Aqui existe `is_consolidation`, e ela é a verdade.
class CreateAvailabilityEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :availability_entries, id: :uuid, comment: 'Lançamento de disponibilidade — a célula da grade (padrão × data × empresa).' do |t|
      t.references :project, type: :uuid, null: false, foreign_key: true, index: false,
                   comment: 'Projeto dono (contrato C1). Nunca aceito no corpo da requisição.'
      t.references :company, type: :uuid, null: true, foreign_key: true, index: true,
                   comment: 'Empresa do lançamento. NULO na linha de consolidação geral.'
      t.uuid :availability_template_id, null: false,
             comment: 'Padrão a que o lançamento pertence.'

      t.boolean :is_consolidation, null: false, default: false,
                comment: 'DB-126 — marca EXPLÍCITA de consolidação geral. O legado inferia por company_id nulo, e a rotina fix__7412 reatribuiu empresa nula à primeira empresa.'

      t.string :title, comment: 'Título derivado do padrão, copiado na gravação (paridade com o legado).'

      # Precisão **15,2**, a do legado (`create_availability_entries.rb`,
      # `add_original_value_column…`, `add_virtual_value_…`). A fila desta fatia
      # pedia 14,2; reduzir a precisão de uma coluna financeira já carregada é
      # risco de truncamento no ETL, e DEC-30 manda replicar o dado.
      t.decimal :value, precision: 15, scale: 2, null: false, default: 0,
                comment: 'Valor efetivo da célula. Em padrão corrigido é original_value × multiplicador de dias úteis.'
      t.decimal :original_value, precision: 15, scale: 2, null: false, default: 0,
                comment: 'Base da correção por dias úteis. **É regravado a cada alteração de value** — decaimento composto do legado, replicado por decisão do usuário (DEC-24 / D-02).'
      t.decimal :virtual_value, precision: 15, scale: 2, null: false, default: 0,
                comment: 'Saldo acumulado do 1º nível (soma corrigida dos níveis anteriores). Derivado persistido — DB-127 traz a rotina de reconciliação.'

      t.date :date, null: false, comment: 'Data do lançamento.'
      t.uuid :user_id, comment: 'Autor da gravação.'

      t.timestamps
    end

    add_foreign_key :availability_entries, :availability_templates,
                    column: :availability_template_id
    add_foreign_key :availability_entries, :users, column: :user_id, on_delete: :nullify

    # --- Índices (DB-123) ------------------------------------------------
    add_index :availability_entries, %i[project_id date]
    add_index :availability_entries, %i[availability_template_id date]
    add_index :availability_entries, %i[project_id company_id date],
              name: 'index_availability_entries_on_grid'

    # **A unicidade que o legado só tinha no model.** Em duas variantes porque o
    # Postgres trata cada `NULL` como distinto num índice único comum — sem a
    # segunda, duas linhas de consolidação geral para o mesmo (projeto, padrão,
    # data) passariam.
    add_index :availability_entries, %i[project_id company_id availability_template_id date],
              unique: true, where: 'company_id IS NOT NULL',
              name: 'index_availability_entries_unique_by_company'
    add_index :availability_entries, %i[project_id availability_template_id date],
              unique: true, where: 'company_id IS NULL',
              name: 'index_availability_entries_unique_consolidation'
  end
end
