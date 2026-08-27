# frozen_string_literal: true

# S13 / OPS-491 — destrava o motor de anexos para os models do domínio Safegold.
#
# **O defeito, medido:** `active_storage_attachments.record_id` nasceu `uuid NOT NULL`
# na base ai9, porque todos os models que a base anexava (`Medium`, `User`) têm chave
# primária `uuid`. Só que as tabelas do domínio Safegold são **bigint** — `projects`,
# `carriers`, `providers`, `app_themes` e, quando chegar, `renegotiations`. Resultado:
#
#     project.avatar.attach(...)
#     # => PG::NotNullViolation: null value in column "record_id"
#
# O Postgres não converte o bigint `5` para uuid, então o `record_id` chega `NULL` e a
# gravação estoura. **Nenhum model do Safegold com PK bigint conseguia ter anexo** —
# o que inclui os 4 anexos de documento da renegociação (S9), o logo do portador que a
# DEC-47 acabou de religar e o logo do fornecedor.
#
# Isto não aparece em `zeitwerk:check`, não aparece em `tsc` e não aparece numa
# revisão de código: aparece na primeira vez que alguém anexa um arquivo de verdade.
#
# **A correção é a que o próprio Rails documenta** para bases com chaves primárias
# mistas: `record_id` vira `string`. A associação polimórfica continua funcionando
# (o ActiveRecord converte o valor da chave para texto na consulta), e passa a
# aceitar as duas famílias de PK ao mesmo tempo.
#
# **Por que continua `string` mesmo depois da padronização em uuid** (o orquestrador
# está convertendo `projects.id` e as FKs de projeto para uuid, porque o padrão do
# ai9 é uuid): `record_id` **não é FK de uma tabela** — é o lado solto de uma
# associação polimórfica que aponta para qualquer model do sistema. Tipá-lo como o
# uuid de hoje é reintroduzir a mesma armadilha na primeira tabela que fugir do
# padrão, e hoje ainda há tabelas de cadastro global com PK bigint (`carriers`, que
# precisa de logo por OPS-498/DEC-47). `string` aceita as duas formas e o valor
# gravado para um registro uuid é o MESMO literal de antes.
#
# **Dado existente é preservado**: `uuid::text` mantém o mesmo literal
# (`"a1b2c3d4-…"`), que é exatamente o que `Medium#id.to_s` produz. Nenhuma linha de
# anexo é perdida, e nenhuma passa a apontar para o registro errado.
#
# Por que `execute` em vez de `change_column`: a conversão `uuid → varchar` exige
# `USING record_id::text` explícito no Postgres, e o `change_column` do Rails não
# emite a cláusula.
class AllowMixedPrimaryKeysOnAttachments < ActiveRecord::Migration[8.0]
  UNIQUENESS_INDEX = 'index_active_storage_attachments_uniqueness'

  def up
    remove_index :active_storage_attachments, name: UNIQUENESS_INDEX
    execute <<~SQL.squish
      ALTER TABLE active_storage_attachments
        ALTER COLUMN record_id TYPE character varying USING record_id::text
    SQL
    change_column_null :active_storage_attachments, :record_id, false
    add_index :active_storage_attachments,
              %i[record_type record_id name blob_id],
              name: UNIQUENESS_INDEX, unique: true
  end

  def down
    # A volta só é possível se TODO `record_id` ainda for um uuid válido. Se algum
    # model bigint já tiver anexo, o `::uuid` estoura — e estourar é o certo: a
    # alternativa seria apagar o anexo em silêncio.
    remove_index :active_storage_attachments, name: UNIQUENESS_INDEX
    execute <<~SQL.squish
      ALTER TABLE active_storage_attachments
        ALTER COLUMN record_id TYPE uuid USING record_id::uuid
    SQL
    change_column_null :active_storage_attachments, :record_id, false
    add_index :active_storage_attachments,
              %i[record_type record_id name blob_id],
              name: UNIQUENESS_INDEX, unique: true
  end
end
