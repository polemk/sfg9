# frozen_string_literal: true

# S4 / DB-080 (parte de domínio), DB-091, DB-549, BE-093, BE-094, BE-095 —
# **as colunas de domínio do projeto**.
#
# A tabela `projects` em si nasceu na S0 (contrato C4: quem constrói a coisa é
# dono, quem consome referencia) com o mínimo do escopo: `name`, `slug`,
# `user_id`, `segment_id`, `sub_segment_id`, `is_active`. **Esta migration não
# recria a tabela** — ela só acrescenta. Recriar tabela por migration apaga em
# silêncio as colunas que migrations POSTERIORES acrescentaram, e foi assim que
# `job_state`/`job_progress` se perderam em 25/08/2026.
#
# O que muda em relação ao legado (`db/migrate/20210301170412_create_projects.rb`):
#
# 1. **`responsible_id` é referência de usuário de verdade.** No legado era
#    `string` — uma FK escrita como texto, sem índice e sem integridade.
# 2. **`city` e `address_city` viram UMA coluna** (`address_city`). O legado
#    tinha as duas, o formulário escrevia em `address_city`
#    (`projects/new/_body.html.erb:111`) e o endereço formatado lia `city`
#    (`project.rb:beauty_address`): **a cidade digitada nunca aparecia no
#    endereço**. É o **D-124**, achado nesta fatia. Duas colunas para o mesmo
#    dado é a causa, não o sintoma.
# 3. **As três marcas são `boolean`**, não `integer` com default `1`.
#    `has_safegold_management`, `has_bi` e `is_sandbox` eram inteiros nullable —
#    e todo filtro do legado caía em NULL.
# 4. **`job_id` não volta.** Era FK para `delayed_jobs`; o estado do job vive em
#    `job_state`/`job_progress` no próprio projeto (DB-460, S13). `job_report`
#    volta como texto, porque é a mensagem de falha que a tela mostra.
# 5. **`integration_key` ganha índice único.** No legado não tinha índice nenhum,
#    apesar de ser chave de integração.
#
# ⚠ `has_safegold_management` entra **só em `projects`**. A coluna nas 6 tabelas
# filhas (DB-051 em `companies`, DB-090 nas demais) depende da **Q-02**, que
# continua sem resposta do usuário: carimbo histórico × derivado do projeto. A
# decisão muda o significado de relatório em 6 tabelas e não se toma por
# conveniência de migration.
class AddProjectDomainColumns < ActiveRecord::Migration[8.0]
  def change
    change_table :projects, bulk: true do |t|
      t.string :integration_key,
               comment: 'Chave de integração, derivada do nome na CRIAÇÃO e congelada depois (DC-22).'
      t.string :color,
               comment: 'Cor de identificação do projeto no console. Hex `#RRGGBB`, sorteada na criação.'

      # --- Endereço (uma coluna por dado; ver D-124 no cabeçalho) ---------
      t.string :address_type, comment: 'Tipo de logradouro (Rua, Avenida…).'
      t.string :address, comment: 'Logradouro.'
      t.string :address_number, comment: 'Número. STRING: existe "s/n" e "123-A".'
      t.string :address_complement, comment: 'Complemento.'
      t.string :neighborhood, comment: 'Bairro.'
      t.string :cep, limit: 9, comment: 'CEP, normalizado em 8 dígitos com hífen.'
      t.string :address_state, limit: 2,
                               comment: 'UF. Catálogo em GET /api/v1/br_states — `geocoder` não foi portado (DEC-92).'
      t.string :address_city,
               comment: 'Cidade. Coluna ÚNICA: o legado tinha `city` e `address_city` e escrevia numa e lia da outra (D-124).'

      t.date :closing_date, comment: 'Data de baixa do projeto. Informativa.'

      # --- Responsável ----------------------------------------------------
      t.uuid :responsible_id,
             comment: 'Responsável pelo projeto. FK REAL para `users` — no legado era `string` sem índice.'
      t.string :responsible_name,
               comment: 'Nome do responsável quando ele NÃO tem conta (o legado chamava `responsible_formal`).'
      t.string :responsible_email,
               comment: 'E-mail do responsável quando ele não tem conta. NUNCA guarda credencial (D-38).'

      # --- Marcas ---------------------------------------------------------
      t.boolean :has_safegold_management, null: false, default: true,
                                          comment: 'Projeto gerido pela Safegold. BOOLEAN (era integer default 1). A cópia nas 6 filhas depende da Q-02 e NÃO foi criada.'
      t.boolean :has_bi, null: false, default: false,
                         comment: 'BI contratado. Marca comercial (DC-16) — pode haver consumidor externo, por isso é preservada.'
      t.boolean :is_sandbox, null: false, default: false,
                             comment: 'Projeto de treinamento. NÃO pode ser removido, só limpo (BE-092).'

      # --- Operação -------------------------------------------------------
      t.text :job_report,
             comment: 'Última mensagem do job de criação. `job_id` NÃO volta: o estado vive em job_state/job_progress (DB-460).'
      t.integer :importing_id,
                comment: 'DEC-12 — lote de importação do legado. Nunca escrito pela aplicação; existe porque a busca filtra por ele (BE-082).'
    end

    add_index :projects, :integration_key, unique: true
    add_index :projects, :responsible_id
    add_index :projects, :importing_id
    add_index :projects, :is_sandbox, where: 'is_sandbox'
    # `name` é único no legado (`validates :formal, uniqueness: true`) e não
    # tinha índice: duas abas criavam dois projetos com o mesmo nome.
    add_index :projects, :name, unique: true

    add_foreign_key :projects, :users, column: :responsible_id, on_delete: :nullify
  end
end
