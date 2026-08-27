# frozen_string_literal: true

# S10 / DB-310, DB-585 — **catálogo de indicadores**.
#
# O indicador é o cadastro que descreve *o que* o cliente lança mês a mês. Ele é
# **global** (`project_id IS NULL`, catálogo compartilhado — contrato C1 regra 4)
# ou **específico de um projeto**.
#
# O legado (`../sfg/db/migrate/20211026165448_create_indicators.rb` + as quatro
# migrations que foram remendando a tabela depois) chegou a isto:
#
#     t.string :title      # sem índice
#     t.string :key        # sem índice, sem unicidade
#     t.string :value_type # acrescentada em 27/10/2021
#     t.integer :project_id # acrescentada em 29/10/2021, SEM FK e SEM índice
#     t.integer :is_active, default: 1 # acrescentada em 23/02/2022
#
# **Nenhum índice além da PK**, apesar de a tela ordenar por título e por chave e
# de a grade mensal filtrar por projeto. O que muda aqui:
#
# 1. **Índices reais** em `project_id`, `title` e `key`, mais o parcial de
#    descartados.
# 2. **FK real** para `projects`. No legado `project_id` era `integer` solto:
#    apagar um projeto deixava indicadores específicos órfãos, e o
#    `nil.indicators` da grade virava 500.
# 3. **`is_active` vira boolean.** No legado é `integer default 1` e o leitor é
#    `is_active?` → `self.is_active == 1` (`indicator.rb:83-85`), enquanto a
#    grade filtra `where(is_active: 1)`
#    (`indicator_entries_controller.rb:23`). Ou seja: **o legado lê `= 1`, não
#    `≠ 0`** — um `is_active = 2` conta como INATIVO nas duas leituras.
#    **Regra para o ETL da S14: `1 → true`, qualquer outro valor (inclusive NULL
#    e 2) → `false`.** O `tasks.md` desta fatia dizia `≠ 0 → true`; medi as duas
#    leituras do legado e a regra correta é `= 1`. Fica registrado aqui porque é
#    o único lugar que o ETL vai ler.
# 4. **`discarded_at`** — exclusão LÓGICA (D-66). No legado
#    `has_many :entries, dependent: :delete_all` apagava **a série histórica
#    inteira**, sem callback, sem backup e com uma confirmação que nem
#    mencionava os lançamentos. Ver `Indicator#discard!`.
#
# **A `key` NÃO ganha unicidade** (DEC-85, T-D13): ela se chama "Chave de
# Integração", nada dentro do repositório a lê, e não há como confirmar de dentro
# do código se há BI ou planilha lendo do lado de fora. Impor unicidade quebraria
# um consumidor externo **em silêncio**, que é o pior modo de falha de
# integração. O índice abaixo é de LEITURA (ordenação por chave), não `unique`.
class CreateIndicators < ActiveRecord::Migration[8.0]
  def change
    create_table :indicators, id: :uuid, default: -> { 'gen_random_uuid()' },
                              comment: 'Indicador mensal. Global (project_id NULL) ou específico de um projeto.' do |t|
      t.uuid :project_id,
             comment: 'NULL = indicador GLOBAL (catálogo sem escopo, C1 regra 4). Preenchido = específico do projeto.'
      t.string :title, null: false,
                       comment: 'Título. Gravado em CAIXA ALTA e SEM ACENTO (DEC-89 — I18n.transliterate(...).upcase em todo save).'
      t.string :key, null: false,
                     comment: 'Chave de Integração. Derivada do título na criação e congelada. SEM unicidade, por decisão (DEC-85).'
      t.string :value_type, null: false, default: 'Dinheiro',
                            comment: 'Tipo do valor. Conjunto de UM elemento hoje ("Dinheiro"), extensível sem migração de dados (Q-R32).'
      t.boolean :is_active, null: false, default: true,
                            comment: 'Indicador ativo. Era integer default 1; o legado lê `= 1` (não `≠ 0`) nas duas leituras.'
      t.datetime :discarded_at,
                 comment: 'Exclusão LÓGICA (D-66). NULL = vivo. Excluir NUNCA apaga os lançamentos históricos.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :indicators, :project_id
    add_index :indicators, :title
    add_index :indicators, :key
    add_index :indicators, :legacy_id, unique: true
    # Índice parcial: quase toda consulta do módulo é "os que não foram
    # descartados". Parcial porque descartado é a minoria e o índice fica menor.
    add_index :indicators, :discarded_at, where: 'discarded_at IS NULL',
                                          name: 'index_indicators_on_kept'

    add_foreign_key :indicators, :projects, column: :project_id, on_delete: :cascade
  end
end
