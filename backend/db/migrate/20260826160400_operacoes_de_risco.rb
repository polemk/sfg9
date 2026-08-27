# frozen_string_literal: true

# **DB-235 é da S7 — esta migration nasce na S5 por dependência de chave
# estrangeira, e o ID de inventário NÃO é reivindicado aqui.**
#
# Por quê: a S5 roda antes da S7 na corrente (S3 → S4 → S5 → S6 → S7) e entrega
# o motor de exposição (`Risk::Calculator`), o par estático do limite (BE-241) e
# as tabelas `risk_movements` (DB-236) e `risk_operation_extensions` (DB-237) —
# **as três dependem de `risk_operations` existir**. Sem esta tabela nada do
# núcleo da S5 pode ser construído nem testado. O `proposal.md` da S5 já dizia
# que "as 7 tabelas de risco são criadas juntas"; ele só não listou esta.
#
# ### ATENÇÃO, S7: a tabela JÁ EXISTE. Não crie outra, não a recrie.
#
# O conjunto de colunas abaixo é exatamente o que `s7-operacoes-risco/tasks.md`
# item 1.1 pede. A tarefa 1.1 da S7 se fecha **conferindo** este arquivo, não
# escrevendo um `create_table` novo. Recriar tabela por migration **apaga em
# silêncio as colunas que migrations posteriores acrescentaram**, e as
# migrations posteriores continuam marcadas como executadas — foi o que a S13 já
# perdeu uma vez (`checkpoint.md`, armadilha 2). Coluna que faltar se acrescenta
# com `add_column`.
#
# ### O que é da S5 nesta tabela (e está implementado)
#
# - `is_static` — decisão **B-08**: substitui as sentinelas `DateTime.dinosaurs`
#   (ano −2000) e `DateTime.mars` (ano +2000) que o legado usava para manter a
#   operação estática dentro de toda janela de data. A sentinela é um bug
#   esperando o calendário: qualquer consulta por intervalo a inclui, e qualquer
#   soma de prazo produz absurdo. Aqui as datas do par estático são **nulas** e
#   o predicado da janela é `is_static OR (issue_date <= d AND due_date >= d)`.
# - `original_balance` **gravado negativo** (`(-1) * value.abs`,
#   `risk_operation.rb:34`) — convenção de sinal REPLICADA por DEC-01.
# - `balance` é **cache derivada** do último movimento, não coluna gerada: o
#   recálculo é da S7 (BE-265) e a leitura por data é `Risk::Calculator#balance_on`,
#   que **não** lê esta coluna.
#
# ### O que é da S7
#
# CRUD, prorrogação, renovação, encerramento, recálculo da cadeia de movimentos,
# integração com recebível e recibo, e as telas. Nada disso está aqui.
class OperacoesDeRisco < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_operations, id: :uuid, default: -> { 'gen_random_uuid()' },
                                   comment: 'Operação de risco. Tabela criada em S5 por dependência de FK; o COMPORTAMENTO (DB-235, CRUD, renovação, recálculo) é da S7.' do |t|
      t.string :title
      t.uuid :user_id
      t.uuid :operation_type_id, null: false
      t.uuid :operation_subtype_id
      t.uuid :project_id, null: false
      t.uuid :company_id, null: false
      t.uuid :carrier_id, null: false
      t.uuid :risk_control_id, null: false, comment: 'O limite consumido. Obrigatório: operação sem limite é exposição sem teto.'

      t.string :contract_number

      t.date :issue_date, comment: 'Nula APENAS no par estático (is_static). Ver B-08.'
      t.date :due_date, comment: 'Nula APENAS no par estático (is_static). Ver B-08.'
      t.date :original_due_date, comment: 'Vencimento antes da primeira prorrogação (S7).'

      t.decimal :operation_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :original_balance, precision: 14, scale: 2, null: false, default: 0,
                                   comment: 'Gravado NEGATIVO ((-1)*abs), convenção de sinal do legado REPLICADA (DEC-01).'
      t.decimal :balance, precision: 14, scale: 2, null: false, default: 0,
                          comment: 'Cache do saldo após o último movimento. A leitura POR DATA é Risk::Calculator#balance_on, que não lê esta coluna.'
      t.decimal :agreed_rate, precision: 7, scale: 4, null: false, default: 0

      t.string :observation

      t.boolean :is_on_variable, null: false, default: false
      t.boolean :is_ended, null: false, default: false,
                           comment: 'Encerrada. NÃO tira a operação da exposição — DEC-35 (o ciclo de vida do legado é replicado).'
      t.boolean :is_static, null: false, default: false,
                            comment: 'B-08 — par pré/antecipação aberto pelo limite. Entra em TODA janela de data e tem issue_date/due_date nulas.'

      t.uuid :original_id, comment: 'Operação de origem, quando esta é uma renovação (S7).'
      t.uuid :pair_id, comment: 'A outra metade do par estático pré/antecipação.'
      t.uuid :receivable_id, comment: 'Recebível que originou a operação (S6).'
      t.uuid :receipt_id, comment: 'Recibo que faturou a operação (S6). Legado: add_column em 20220802225011_create_receipts.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_operations, %i[project_id issue_date due_date]
    add_index :risk_operations, :risk_control_id
    add_index :risk_operations, :operation_type_id
    add_index :risk_operations, :operation_subtype_id
    add_index :risk_operations, :company_id
    add_index :risk_operations, :carrier_id
    add_index :risk_operations, :original_id
    add_index :risk_operations, :pair_id
    add_index :risk_operations, :receivable_id
    add_index :risk_operations, :receipt_id
    add_index :risk_operations, :legacy_id, unique: true
    # O predicado da janela do motor de exposição começa por aqui: as estáticas
    # entram em qualquer data e são poucas por limite.
    add_index :risk_operations, %i[risk_control_id is_static],
              name: 'index_risk_operations_on_control_and_static'

    add_foreign_key :risk_operations, :projects, column: :project_id
    add_foreign_key :risk_operations, :companies, column: :company_id
    add_foreign_key :risk_operations, :carriers, column: :carrier_id
    add_foreign_key :risk_operations, :risk_controls, column: :risk_control_id
    add_foreign_key :risk_operations, :risk_operation_types, column: :operation_type_id
    add_foreign_key :risk_operations, :risk_operation_subtypes, column: :operation_subtype_id
    add_foreign_key :risk_operations, :risk_operations, column: :original_id, on_delete: :nullify
    add_foreign_key :risk_operations, :risk_operations, column: :pair_id, on_delete: :nullify
    add_foreign_key :risk_operations, :users, column: :user_id

    # A janela é fechada nos dois lados OU a operação é estática. Um par estático
    # com data preenchida voltaria a ser a sentinela de ±2000 anos que a B-08
    # veio eliminar; uma operação normal sem data sairia de todos os agregados.
    add_check_constraint :risk_operations,
                         '(is_static AND issue_date IS NULL AND due_date IS NULL) OR ' \
                         '(NOT is_static AND issue_date IS NOT NULL AND due_date IS NOT NULL)',
                         name: 'risk_operations_static_dates_check'
  end
end
