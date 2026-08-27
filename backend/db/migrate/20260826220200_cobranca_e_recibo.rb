# frozen_string_literal: true

# S6 — **cobrança e recibo**. `charges` e `receipts`.
#
# Fecha **DB-162**, **DB-163**, **DB-164** e a metade de **DB-165** que cabe
# hoje. A dona é a S6 por **DEC-63** (P-098).
#
# ### ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220707164909_create_charges`, `20220802225011_create_receipts` e
# `20220804195335_add_date_and_operation_title_to_receipts` são três das **24
# migrations que nunca subiram** (`analise-dump-producao.md` §1). Conferido no
# dump: não há `COPY public.charges` nem `COPY public.receipts` — as tabelas não
# existem em produção, e `remunerations` também não.
#
# Por **DEC-103b** o esquema e a regra vêm **espelhados do código de 2022**, sem
# corrigir o que parecer errado. Todo golden desta família leva a marca
# `NUNCA EXECUTADO EM PRODUÇÃO`, com arquivo e linha do legado: o teste trava a
# **leitura do código de 2022**, não um comportamento observado.
#
# ### A restrição arquitetural do legado é PRESERVADA
#
# O comentário de `20220707164909_create_charges.rb:2-3` diz, no original:
#
# > *jamais relacionar cobranças e ops diretamente, deve-se usar o receipt como
# > referência para evitar problemas de escalabilidade nas tabelas de operações*
#
# É D-B11. `charges` **não** tem coluna de operação e nunca terá; o caminho é
# sempre `charge → receipts → operation`.
#
# ### O que fica pendente de S7/S8, e por quê
#
# `receipts.operation` é polimórfica entre `RiskOperation` (existe, criada pela
# S5) e `StructuredOperation` (**S8**, não existe). `receipts.remuneration_id`
# aponta para `remunerations` (**S8**, não existe). Não é possível declarar FK
# para tabela ausente:
#
# - `risk_operations.receipt_id` **ganha FK aqui** (a coluna já existe, criada
#   pela S5);
# - `structured_operations.receipt_id` e `receipts.remuneration_id` ficam como
#   **tarefa nominal da S8** — está escrito em `tasks.md` 1.15 e no relatório.
#
# ### `state` com domínio fechado no BANCO (D-B9)
#
# No legado o estado é texto pt-BR livre (`"Edição"`, `"Disponível"`,
# `"Faturado"`, `charge.rb:19-21`) comparado por igualdade de string. Aqui vira
# enum estável (`editing`/`available`/`done`) com `check_constraint`, e o rótulo
# pt-BR vive na apresentação — mesmo tratamento de `BE-445`.
class CobrancaERecibo < ActiveRecord::Migration[8.0]
  def change
    create_table :charges, id: :uuid, default: -> { 'gen_random_uuid()' },
                           comment: 'Pacote de cobrança: um conjunto de recibos faturados juntos. Escopado por projeto (C1). NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b, espelho de `20220707164909_create_charges.rb`.' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto dono (C1).'
      t.uuid :user_id, comment: 'Autor. Vem da SESSÃO.'
      t.date :date, null: false, comment: 'Data da cobrança. Na criação, o padrão da tela é hoje + 30 dias (FE-186).'
      t.string :state, null: false, default: 'editing',
                       comment: 'Situação: `editing` | `available` | `done`. `done` (Faturado) BLOQUEIA alteração no SERVIDOR, não só na tela (D-18).'

      # Totais denormalizados. São recalculados por `Charge#calc!` no legado
      # (`charge.rb:44-58`) a cada mudança de recibo — mesma semântica aqui.
      t.decimal :value, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma do valor dos recibos (LIQ + EST).'
      t.decimal :structured_operations_value, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma de `operation_value` dos recibos EST.'
      t.decimal :risk_operations_value, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma de `operation_value` dos recibos LIQ.'
      t.decimal :total_operations_value, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: risco + estruturadas.'

      t.integer :receipts_count, null: false, default: 0, comment: 'DERIVADO: quantidade de recibos.'
      t.integer :risk_operations_count, null: false, default: 0, comment: 'DERIVADO.'
      t.integer :structured_operations_count, null: false, default: 0, comment: 'DERIVADO.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência. Sem uso prático: a tabela não existe em produção.'

      t.timestamps
    end
    add_index :charges, %i[project_id date]
    add_index :charges, :state
    add_index :charges, :legacy_id, unique: true
    add_check_constraint :charges,
                         "state IN ('editing', 'available', 'done')",
                         name: 'charges_state_check'
    add_foreign_key :charges, :projects
    add_foreign_key :charges, :users

    create_table :receipts, id: :uuid, default: -> { 'gen_random_uuid()' },
                            comment: 'Recibo: a remuneração devida sobre UMA operação. É a única ponte entre cobrança e operação (D-B11). NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b.' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto dono (C1). Derivado da operação, nunca do corpo.'
      t.uuid :charge_id, comment: 'Pacote de cobrança. NULO enquanto o recibo é só candidato.'
      t.uuid :user_id, comment: 'Quem gerou o recibo. Vem da SESSÃO.'

      t.uuid :operation_id, comment: 'Operação faturada. Polimórfica.'
      t.string :operation_type, comment: '`RiskOperation` ou `StructuredOperation`. Tipo desconhecido FALHA — o legado devolvia a string `"???"` (`remuneration.rb:41`).'
      t.uuid :remuneration_id, comment: 'Remuneração que deu a taxa. FK pendente da S8, dona de `remunerations`.'

      t.string :temp_id, comment: 'Identidade estável do candidato ANTES de existir: `RCP-<projeto>-<kind>-<remuneração>-<operação>`. É por ela que a tela casa marcado × persistido.'
      t.string :kind, comment: 'Sigla do tipo, delegada da remuneração: `LIQ` (risco) ou `EST` (estruturada).'
      t.string :title, null: false, comment: 'Título delegado da remuneração, que por sua vez delega do tipo de operação.'
      t.decimal :fee, precision: 7, scale: 4, null: false, comment: 'Taxa em %, 0–100. Sem validação de faixa — DEC-37.'
      t.decimal :operation_value, precision: 15, scale: 2, null: false, comment: 'FOTOGRAFIA do valor da operação no dia do recibo.'
      t.decimal :value, precision: 15, scale: 2, null: false,
                        comment: 'A receita faturada: `operation_value × (fee / 100)`. Multiplicação `decimal × float` e truncamento em 2 casas REPLICADOS (D-B14).'

      t.date :date, comment: 'FOTOGRAFIA da data de emissão da operação. Nula quando a operação é estática (issue_date nula) — a tela não pode quebrar por isso (FE-184).'
      t.string :operation_title, comment: 'FOTOGRAFIA do título da operação no dia do recibo.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência. Sem uso prático: a tabela não existe em produção.'

      t.timestamps
    end
    add_index :receipts, :charge_id
    add_index :receipts, :project_id
    add_index :receipts, :remuneration_id
    add_index :receipts, %i[operation_type operation_id]
    add_index :receipts, :legacy_id, unique: true
    # `validates_uniqueness_of :operation_id, scope: [:project_id, :operation_type]`
    # (`receipt.rb:11`) fechado no BANCO: uma operação não pode ser faturada duas vezes.
    add_index :receipts, %i[operation_id project_id operation_type],
              unique: true, name: 'index_receipts_on_operation_unique'
    add_check_constraint :receipts,
                         "operation_type IS NULL OR operation_type IN ('RiskOperation', 'StructuredOperation')",
                         name: 'receipts_operation_type_check'
    add_check_constraint :receipts,
                         "kind IS NULL OR kind IN ('LIQ', 'EST')",
                         name: 'receipts_kind_check'
    add_foreign_key :receipts, :charges
    add_foreign_key :receipts, :projects
    add_foreign_key :receipts, :users

    # DB-165, a metade possível hoje. `risk_operations.receipt_id` já existe
    # (criada pela S5); aqui ela ganha a constraint real. A metade de
    # `structured_operations` fica com a S8, dona da tabela.
    add_foreign_key :risk_operations, :receipts, column: :receipt_id
  end
end
