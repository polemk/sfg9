# frozen_string_literal: true

# S4 / DB-052..DB-056, DB-556 — **fornecedores**, escopados por projeto.
#
# O fornecedor é a contraparte das renegociações (S9). Cinco decisões:
#
# 1. **O documento é o par `(document_type, document)`** (DC-11), e continua
#    **opcional**. O legado tinha duas colunas (`cnpj` e `cpf`) com duas
#    unicidades separadas, e a regra "ao menos um" estava **comentada**
#    (`provider.rb:36-38`) — a base quase certamente tem fornecedor sem
#    documento. Duas colunas para "o documento" é o mesmo erro do D-124.
# 2. **`cnaes` e `atividades` viram UM `jsonb`: `activities`** (D-25). O legado
#    guardava `cnaes` como **YAML** (`serialize :cnaes`) e `atividades` como
#    **JSON dentro de uma coluna de texto**, na mesma tabela. Dois formatos para
#    a mesma coisa, e o YAML ainda é superfície de desserialização.
# 3. **Os campos da ReceitaWS usam os nomes que o serviço já normaliza**
#    (`Sfg::ReceitaWs::LookupService#present`): `legal_name`, `trade_name`,
#    `opened_at`, `zip_code`… O legado guardava as chaves cruas em português do
#    provedor, e uma mudança de contrato do terceiro virava mudança de coluna.
# 4. **`opened_at` e `status_changed_at` são `date` de verdade** — já eram, e
#    ficam. `cnpj_fetched_at` é novo: sem ele não há como saber se o dado
#    cadastral é de ontem ou de 2021.
# 5. **`is_active` é boolean.** Era `integer default 1`, e `is_active?` comparava
#    com `== 1`: qualquer outro inteiro (ou NULL) significava "inativo" sem que
#    ninguém tivesse dito isso.
#
# O logo é `has_one_attached` pelo motor único (`Attachable` + `attachments.yml`,
# chave `provider.logo`, 1 MB — DEC-91). As 4 colunas do Paperclip **não** são
# recriadas: o ETL da S14 copia o binário e reanexa.
class CreateProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :providers, id: :uuid, default: -> { 'gen_random_uuid()' },
                             comment: 'Fornecedor de um projeto — contraparte das renegociações. Escopado por projeto (C1).' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto dono. Obrigatório (C1).'
      t.string :title, null: false, comment: 'Nome do fornecedor. Derivado do nome fantasia/razão social quando vem da ReceitaWS.'
      t.text :resume, comment: 'Descrição livre.'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (DC-22). Única POR PROJETO.'
      t.boolean :is_active, null: false, default: true, comment: 'Fornecedor ativo. Era integer nullable no legado.'
      t.uuid :user_id, comment: 'Autor do cadastro, vindo da SESSÃO. O `user_id` do corpo é ignorado.'

      # --- Documento (par explícito, opcional — DC-11) ---------------------
      t.string :document_type, limit: 4,
                               comment: 'CPF ou CNPJ. Conjunto FECHADO. NULL quando não há documento — que é caso legítimo.'
      t.string :document, limit: 14,
                          comment: 'Somente dígitos. Validado (dígito verificador) no servidor. Único por (projeto, tipo).'

      # --- Cadastro da ReceitaWS (DB-054) ----------------------------------
      t.datetime :cnpj_fetched_at,
                 comment: 'Quando o cadastro foi consultado na ReceitaWS. NULL = preenchido à mão. O legado não tinha isto.'
      t.string :legal_name, comment: 'Razão social (`nome` na ReceitaWS).'
      t.string :trade_name, comment: 'Nome fantasia (`fantasia`).'
      t.string :status, comment: 'Situação cadastral (`situacao`).'
      t.date :opened_at, comment: 'Data de abertura (`abertura`).'
      t.date :status_changed_at, comment: 'Data da situação cadastral (`data_situacao`).'
      t.string :email, comment: 'E-mail do cadastro.'
      t.string :phone, comment: 'Telefone do cadastro.'
      t.string :zip_code, limit: 9, comment: 'CEP.'
      t.string :street, comment: 'Logradouro.'
      t.string :number, comment: 'Número.'
      t.string :complement, comment: 'Complemento.'
      t.string :district, comment: 'Bairro.'
      t.string :city, comment: 'Município.'
      t.string :state, limit: 2, comment: 'UF.'
      t.jsonb :activities, null: false, default: {},
                           comment: 'CNAEs e atividades num ÚNICO jsonb (D-25): o legado tinha YAML numa coluna e JSON noutra.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :providers, :project_id
    add_index :providers, %i[project_id integration_key], unique: true
    add_index :providers, %i[project_id document_type document], unique: true,
                                                                 where: 'document IS NOT NULL'
    add_index :providers, :document
    add_index :providers, :is_active
    add_index :providers, :user_id
    add_index :providers, :legacy_id, unique: true

    add_foreign_key :providers, :projects, column: :project_id
    add_foreign_key :providers, :users, column: :user_id, on_delete: :nullify
  end
end
