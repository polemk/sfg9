# frozen_string_literal: true

# S3 / DB-057..DB-062, DB-552, OPS-052 — **portadores**, a contraparte
# financiadora (FIDC, securitizadora, factoring ou o próprio cliente).
#
# Catálogo GLOBAL (C1, regra 4). Cinco decisões de esquema, cada uma fechando um
# defeito medido no legado:
#
# 1. **`bank_code` é STRING** (DC-12). O legado guardava `integer` e o código
#    COMPE `001` virava `1`. Replicar o inteiro seria replicar corrupção de dado.
# 2. **`bank_name` NÃO existe.** No legado um `before_validation` fazia
#    `self.bank_name = self.title` — uma segunda cópia do título, que divergia
#    na primeira edição (o callback só rodava `on: :create`).
# 3. **`subordinated_accounts_percent` é `decimal`, não `float`** — e é
#    **derivado no servidor** (DC-09). No legado era calculado em JS a cada tecla
#    E persistido como coluna editável: duas fontes de verdade para o mesmo
#    número, e divisão por zero gravando `NaN`.
# 4. **`financial_agent` é conjunto fechado** (DB-059), validado por inclusão no
#    model (enum string, sintaxe Rails 8). Valor divergente é reportado no
#    dry-run do ETL, nunca inserido calado.
# 5. **`group_id` é FK real com índice** (DB-058). O legado tinha ZERO
#    `add_foreign_key` na base inteira, e apagar um grupo deixava `group_id`
#    órfão apontando para nada.
#
# O logo é `has_one_attached` no model (DEC-47/DEC-91) — ActiveStorage, **não**
# `Medium` (a tabela `media` não tem dono nem escopo) e **não** Paperclip. Por
# isso não há coluna `logo_*` aqui.
class CreateCarriers < ActiveRecord::Migration[8.0]
  def change
    create_table :carriers, id: :uuid, default: -> { 'gen_random_uuid()' }, comment: 'Portador — contraparte financiadora. Catálogo GLOBAL, sem escopo de projeto (C1, regra 4).' do |t|
      t.string :title, null: false,
                       comment: 'Razão social. Título DUPLICADO é permitido de propósito (BE-071, "Cloud #7036").'
      t.text :resume, comment: 'Descrição livre da contraparte.'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (DC-22).'
      t.string :bank_code,
               comment: 'Código COMPE. STRING (DC-12): o legado usava integer e `001` virava `1`.'
      t.integer :senior_accounts, null: false, default: 0, comment: 'Cotas sênior da estrutura de FIDC.'
      t.integer :subordinated_accounts, null: false, default: 0, comment: 'Cotas subordinadas da estrutura de FIDC.'
      t.decimal :net_worth, precision: 14, scale: 2, null: false, default: 0.0,
                            comment: 'Patrimônio líquido. decimal(14,2) — o padrão monetário desta migração.'
      t.decimal :subordinated_accounts_percent, precision: 9, scale: 4,
                                                comment: 'DERIVADO no servidor (DC-09) pela fórmula DO LEGADO (DEC-30): subordinadas ÷ SÊNIOR × 100, e 0 quando sênior é 0. Nunca NaN.'
      t.uuid :group_id, comment: 'Grupo de portadores. FK real com índice (DB-058). `uuid` — é o padrão de id do ai9.'
      t.string :financial_agent,
               comment: 'Agente financeiro. Conjunto FECHADO: FIDC / Securitizadora / Factoring / Cliente (DB-059).'
      t.string :city, comment: 'Cidade da sede. Dado de CADASTRO — não há geocodificação (OPS-057, L-11).'
      t.string :uf, limit: 2, comment: 'UF da sede, normalizada em 2 caracteres maiúsculos (DB-060).'
      t.boolean :is_active, null: false, default: true, comment: 'Portador ativo. Era integer nullable no legado.'
      t.uuid :user_id, comment: 'Autor do cadastro, vindo da SESSÃO. Informativo.'
      t.integer :legacy_id,
                comment: 'DEC-12 — única prova de proveniência dos borderôs de 2016-2021. O pipeline `Legacy::execute` NÃO é portado.'

      t.timestamps
    end

    add_index :carriers, :title
    add_index :carriers, :integration_key
    add_index :carriers, :bank_code
    add_index :carriers, :group_id
    add_index :carriers, :financial_agent
    add_index :carriers, :uf
    add_index :carriers, :is_active
    add_index :carriers, :legacy_id, unique: true
    add_index :carriers, :user_id

    add_foreign_key :carriers, :carrier_groups, column: :group_id
    add_foreign_key :carriers, :users, column: :user_id, on_delete: :nullify
  end
end
