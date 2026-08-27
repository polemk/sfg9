# frozen_string_literal: true

# S8 — **operações estruturadas e remuneração**. As três tabelas que faltavam:
# `structured_operation_types`, `structured_operations` e `remunerations`.
#
# Fecha **DB-280**, **DB-281**, **DB-282**, **DB-283**, **DB-284**, **DB-285**,
# **DB-295**, **DB-296**, **DB-297**, **DB-580**, **DB-581** e **DB-582**.
#
# ### ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220701123654_create_structured_operation_types`,
# `20220701125757_create_structured_operations`,
# `20220629123512_create_remunerations` e `20220802165837_add_title_to_remuneration`
# são quatro das **24 migrations que nunca subiram** (`analise-dump-producao.md`
# §1). A última migration aplicada em produção é de **25/05/2022** e o sistema
# rodou em uso até **31/05/2025** — estas tabelas **não existem** no dump.
#
# Por **DEC-103b**, confirmada pela **DEC-105**, o esquema vem espelhado do
# código de 2022, **sem corrigir o que parecer errado**. O que muda aqui em
# relação ao legado é **forma de armazenamento e integridade**, nunca a
# sequência de cálculo: `int → uuid`, `integer 0/1 → boolean`, `float → decimal`,
# FK real onde não havia nenhuma. É exatamente a licença que a **DEC-02** dá
# ("o tipo de coluna no ai9 pode ser `decimal`, mas a sequência de operações
# replica a do legado").
#
# ### Por que `decimal(14,2)` e `decimal(7,4)`, e não o que a tarefa 1.1 dizia
#
# A tarefa 1.1 pedia `agreed_rate` em `decimal(9,4)`; a 1.10, que é a passada de
# padronização e vem depois, pede **valores em `decimal(14,2)` e taxas em
# `decimal(7,4)`**. Vale a 1.10, e por uma razão medida: `risk_operations`
# (S5/S7) — a tabela irmã, que entra na **mesma** fórmula polimórfica de recibo —
# já está em `decimal(14,2)` / `decimal(7,4)`. Duas escalas diferentes nos dois
# lados de `Receipt#fetch` seriam duas verdades no mesmo faturamento.
#
# O legado usa `decimal(15,2)` para valor e **`float`** para taxa. O estreitamento
# de 15 para 14 casas inteiras (de 10 trilhões para 1 trilhão) é o mesmo que a S5
# aplicou em `risk_operations` e está registrado ali.
#
# ### `remunerations.value` é `decimal(7,4)`, não `decimal(15,2)`
#
# A tarefa F.5 pede `decimal(15,2)` dizendo "preservar a precisão do legado".
# **A premissa está errada nas duas pontas** e por isso a tarefa fica riscada com
# motivo, não cumprida ao pé da letra:
#
# 1. o legado **não** é `decimal(15,2)` — é `t.float :value, default: 0`
#    (`20220629123512_create_remunerations.rb:6`);
# 2. `receipts.fee`, que **copia** esta coluna (`receipt.rb:61`), já nasceu
#    `decimal(7,4)` na S6. Guardar a taxa com 2 casas e copiá-la para uma coluna
#    de 4 perderia a terceira e a quarta casa **na origem** — uma taxa de
#    `1,7550%` viraria `1,75%` e o valor faturado mudaria. `decimal(7,4)`
#    preserva **mais** que `decimal(15,2)` para uma taxa.
#
# ### `resource_kinds` NÃO nasce — e isso é decisão medida, não omissão
#
# O portão **T-D7** abria com um número: `SELECT count(*) FROM receivable_entries
# WHERE resource_kind_id IS NOT NULL`. O dump respondeu **zero**, e a tabela
# `resource_kinds` tem **0 linhas** (`analise-dump-producao.md` §2, consulta 2).
# Os 10 IDs já estão `dropped` **com a evidência** no `parity-ledger.md`
# (BE-307, BE-720…BE-724, FE-307, DB-286, DB-289, DB-294). A S6 já havia deixado
# a tabela e a coluna fora de `20260826220000_catalogos_de_recebivel.rb`.
# **Não há tabela a remover**: ela nunca foi criada no ai9. Fica escrito aqui
# para que ninguém a crie por engano depois.
class OperacoesEstruturadasERemuneracao < ActiveRecord::Migration[8.0]
  def change
    # ------------------------------------------------------------------
    # DB-283 / DB-580 — tipos de operação estruturada. Catálogo GLOBAL.
    # ------------------------------------------------------------------
    # No legado a tabela não tem **um** índice, apesar de `integration_key` se
    # chamar chave. Aqui título e chave são únicos no banco: a unicidade da
    # chave é o que impede dois títulos diferentes de colidirem na mesma
    # chave derivada (BE-297).
    create_table :structured_operation_types, id: :uuid, default: -> { 'gen_random_uuid()' },
                                              comment: 'Tipo de operação estruturada (Fomento, Comissária, Intercompany, Auto Liquidável). Catálogo GLOBAL — sem escopo de projeto (C1, regra 4). NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b, espelho de `20220701123654_create_structured_operation_types.rb`.' do |t|
      t.string :title, null: false, comment: 'Nome do tipo. Único — é o que a tela mostra e o que `Remuneration#title` copia.'
      t.string :integration_key, null: false,
                                 comment: 'Chave estável derivada do título na CRIAÇÃO e congelada depois (BE-298). É CONTRATO: fomento/comissaria/intercompany/auto_liquidavel.'
      t.boolean :is_active, null: false, default: true, comment: 'Ativo. `is_active = 1` no legado (integer), aqui boolean — DB-295.'
      t.boolean :is_default, null: false, default: false,
                             comment: 'Linha semeada pelo sistema. BLOQUEIA a exclusão (`structured_operation_type.rb:10-15`). Os 4 tipos semeados são TODOS `is_default`: na prática nenhum é removível.'
      t.boolean :allow_manual_operations, null: false, default: true,
                                          comment: 'No `permit` do legado (`structured_operation_types_controller.rb:133`) sem formulário e SEM CONSUMIDOR. Migrada como coluna, sem ganhar consumidor (Q-R15).'
      t.boolean :allow_receivable_entries, null: false, default: false,
                                           comment: 'Idem. Semeada `false` nos 4 tipos.'
      t.boolean :has_pre_faturamento, null: false, default: false,
                                      comment: 'Idem. Semeada `false` nos 4 tipos. Diferente do homônimo de `risk_operation_types`, aqui NÃO gera subtipo nem muda bucket — não há subtipo de operação estruturada.'
      t.uuid :user_id, comment: 'Autor do cadastro. Vem da SESSÃO; o do corpo é ignorado. No legado vinha de `hidden_field` e nunca era conferido.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência. Sem uso prático: a tabela não existe em produção.'

      t.timestamps
    end
    add_index :structured_operation_types, :title, unique: true
    add_index :structured_operation_types, :integration_key, unique: true
    add_index :structured_operation_types, :is_active
    add_index :structured_operation_types, :legacy_id, unique: true
    add_foreign_key :structured_operation_types, :users, on_delete: :restrict

    # ------------------------------------------------------------------
    # DB-280 / DB-281 / DB-282 / DB-297 / DB-581 — a operação estruturada
    # ------------------------------------------------------------------
    create_table :structured_operations, id: :uuid, default: -> { 'gen_random_uuid()' },
                                         comment: 'Operação estruturada. Escopada por projeto (C1). NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b, espelho de `20220701125757_create_structured_operations.rb`.' do |t|
      t.string :title, comment: 'Em branco na CRIAÇÃO recebe `carrier.title` (`structured_operation.rb:31-33`). Só no create — renomear o portador depois não mexe aqui.'
      t.uuid :user_id, comment: 'AUTOR. Vem da SESSÃO. No legado `current_user.id` era forçado no create E no update, então o "autor" virava o último editor (DB-297); aqui os dois são colunas separadas.'
      t.uuid :updated_by_id, comment: 'ÚLTIMO EDITOR. Vem da SESSÃO em todo save. É a metade que o legado sobrescrevia por cima do autor.'
      t.uuid :operation_type_id, null: false
      t.uuid :project_id, null: false, comment: 'Projeto dono (C1). DERIVADO de `company.project_id` em TODO save (`structured_operation.rb:36`) — o do corpo é ignorado.'
      t.uuid :company_id, null: false
      t.uuid :carrier_id, null: false
      t.string :contract_number, comment: 'Sem unicidade — o legado não a tem, e replicar a ausência é a decisão (Q-R7, BE-293).'
      t.date :issue_date, comment: 'Emissão. Obrigatória pela validação do model.'
      t.date :due_date, comment: 'Vencimento. Obrigatório. SEM validação de `due_date >= issue_date` — ausência REPLICADA (BE-293).'

      t.decimal :operation_value, precision: 14, scale: 2, null: false, default: 0,
                                  comment: 'Capital da operação. SEM validação de `> 0` — ausência REPLICADA. É o multiplicando da fórmula de remuneração.'
      t.decimal :original_balance, precision: 14, scale: 2, null: false, default: 0,
                                   comment: 'Saldo inicial, gravado NEGATIVO: `(-1) * abs` (`structured_operation.rb:37`). Convenção de sinal do legado REPLICADA (DEC-01).'
      t.decimal :balance, precision: 14, scale: 2, null: false, default: 0,
                          comment: 'Saldo corrente. RESETADO para `original_balance` em TODO save, inclusive editando só a observação (`structured_operation.rb:38`, sem `on:`). Nada no legado inteiro dá baixa nele — a coluna é DECORATIVA (T-D6/BE-292). Golden E6 trava isso.'
      t.decimal :agreed_rate, precision: 7, scale: 4, null: false, default: 0,
                              comment: 'Taxa acordada, em %. **NÃO é a taxa que remunera** — quem remunera é `remunerations.value`. Persistida e exibida, sem consumidor de cálculo (BE-295, Q-R14).'

      t.text :observation, comment: 'No legado `varchar(255)`; aqui `text` — o campo da tela é um textarea e 255 caracteres cortavam observação de operação (DB-280).'
      t.boolean :is_on_variable, null: false, default: false,
                                 comment: 'Considerar no variável. Integer 0/1 no legado (DB-295). Sem consumidor de cálculo, relatório, filtro ou job — varredura em BE-295.'
      t.boolean :is_ended, null: false, default: false,
                           comment: 'Encerrada. Sem consumidor: operação encerrada CONTINUA candidata a recibo (Q-R18, golden E7).'

      t.uuid :receipt_id, comment: 'Recibo que faturou a operação. É a coluna de `scope :available_for_receipt` (`structured_operation.rb:10`), consultada em TODO cálculo de candidatos — por isso o índice é obrigatório (DB-281).'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência. Sem uso prático: a tabela não existe em produção.'

      t.timestamps
    end
    add_index :structured_operations, :project_id
    add_index :structured_operations, :company_id
    add_index :structured_operations, :carrier_id
    add_index :structured_operations, :operation_type_id
    # DB-281 — obrigatório: `available_for_receipt` é `where(receipt_id: nil)`.
    add_index :structured_operations, :receipt_id
    # DB-280 — a busca faz sempre 3 INNER JOINs + range de datas
    # (`structured_operations_controller.rb:22,31`).
    add_index :structured_operations, %i[project_id issue_date due_date]
    add_index :structured_operations, :legacy_id, unique: true

    # DB-282 — **nenhuma das migrations legadas declara `foreign_key: true`**.
    # Com FK real somem dois estados ilegíveis: operação com carrier apagado
    # sumindo da lista pelo INNER JOIN, e recibo órfão.
    add_foreign_key :structured_operations, :projects, on_delete: :restrict
    add_foreign_key :structured_operations, :companies, on_delete: :restrict
    add_foreign_key :structured_operations, :carriers, on_delete: :restrict
    add_foreign_key :structured_operations, :structured_operation_types,
                    column: :operation_type_id, on_delete: :restrict
    add_foreign_key :structured_operations, :users, column: :user_id, on_delete: :restrict
    add_foreign_key :structured_operations, :users, column: :updated_by_id, on_delete: :restrict
    # A metade de DB-165 que a S6 deixou nomeada para cá
    # (`s6/tasks.md` 1.15): `risk_operations.receipt_id` ganhou FK lá; a de
    # `structured_operations` só podia nascer com a tabela.
    add_foreign_key :structured_operations, :receipts, column: :receipt_id, on_delete: :restrict

    # ------------------------------------------------------------------
    # DB-284 / DB-285 / DB-582 — a remuneração
    # ------------------------------------------------------------------
    create_table :remunerations, id: :uuid, default: -> { 'gen_random_uuid()' },
                                 comment: 'A taxa que o projeto cobra por tipo de operação. Escopada por projeto (C1). NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b, espelho de `20220629123512_create_remunerations.rb` + `20220802165837_add_title_to_remuneration.rb`.' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto dono (C1). FORÇADO ao projeto corrente — no legado vinha de `hidden_field` e não era conferido (BE-301, falha de escopo).'
      t.string :operation_type_type, null: false,
                                     comment: 'Classe do tipo: `RiskOperationType` (LIQ) ou `StructuredOperationType` (EST). Domínio fechado no banco — o legado aceitava valor arbitrário e depois quebrava em `operation_class` nil e `beauty_type` "???" (`remuneration.rb:35,44`).'
      t.uuid :operation_type_id, null: false, comment: 'O tipo. Polimórfico: aponta para `risk_operation_types` OU `structured_operation_types`, por isso não há FK.'
      t.decimal :value, precision: 7, scale: 4, null: false, default: 0,
                        comment: 'A taxa, em %. **SEM validação de faixa** — DEC-37/T-D9: 250% passa hoje e continua passando. É ela que multiplica TODO o faturamento do tipo. Legado: `t.float :value`; aqui decimal(7,4), a mesma escala de `receipts.fee`, que a copia.'
      t.string :title, null: false,
                       comment: 'DESNORMALIZADO de propósito (decisão B-06, DB-285): é a coluna que a busca textual usa (`remunerations_controller.rb:14`). Reescrito a partir de `operation_type.title` em TODO save (`remuneration.rb:17-19`).'
      t.uuid :user_id, comment: 'Autor do cadastro. Vem da SESSÃO. No legado não havia coluna: `user_id` sequer estava no `permit`.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência. Sem uso prático: a tabela não existe em produção.'

      t.timestamps
    end
    # DB-284 — o índice único composto é o que garante que `Receipt#fetch`
    # (`receipt.rb:47-51`, `.first`) ache **UMA** taxa. No legado a unicidade só
    # existia em `validates_uniqueness_of` (`remuneration.rb:11`), sujeita a
    # corrida entre duas abas.
    add_index :remunerations, %i[project_id operation_type_type operation_type_id],
              unique: true, name: 'index_remunerations_on_project_and_type'
    add_index :remunerations, %i[operation_type_type operation_type_id]
    add_index :remunerations, :project_id
    add_index :remunerations, :legacy_id, unique: true
    add_check_constraint :remunerations,
                         "operation_type_type IN ('RiskOperationType', 'StructuredOperationType')",
                         name: 'remunerations_operation_type_type_check'
    add_foreign_key :remunerations, :projects, on_delete: :restrict
    add_foreign_key :remunerations, :users, on_delete: :restrict

    # DB-284, segunda metade — a FK que a S6 deixou pendente nomeando esta
    # fatia. `has_many :receipts` do legado (`remuneration.rb:4`) não tem
    # `dependent:`: apagar a remuneração deixava **recibo órfão**, e como
    # `Receipt belongs_to :remuneration` é obrigatório, qualquer save posterior
    # daquele recibo falhava (BE-303).
    add_foreign_key :receipts, :remunerations, column: :remuneration_id, on_delete: :restrict
  end
end
