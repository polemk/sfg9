# frozen_string_literal: true

# S0 / OPS-086 — a trilha de auditoria é o `paper_trail` (DEC-59).
#
# NÃO se cria `AuditEvent` e `permission_audit_logs` NÃO ganha produtor (fica
# como linha em `upstream-flags.md`). Esta tabela é a única trilha do sistema.
#
# Decisões do DEC-59 e do DEC-78 materializadas aqui:
#  - `object`/`object_changes` em **jsonb** (DEC-78 #4) — o payload é COMPLETO,
#    então precisa ser consultável, não texto opaco;
#  - `item_id` é **string** porque a base mistura PK uuid (`users`) e bigint
#    (`projects`, `permissions`) — coluna tipada quebraria em metade dos models;
#  - `whodunnit` guarda o **`true_user`** na impersonação (DEC-59 #3). Sem isso a
#    trilha diz que o impersonado fez o que o OG fez, que é o oposto do ponto de
#    ter trilha. `impersonated_id` guarda quem a sessão *aparentava* ser;
#  - retenção: ver `PurgeAuditVersionsJob` (DEC-59 #1 / DEC-60).
class CreateVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :versions, comment: 'Trilha de auditoria (paper_trail). Única trilha do sistema — DEC-59.' do |t|
      t.string :item_type, null: false, comment: 'Classe do registro versionado.'
      t.string :item_id, null: false,
                         comment: 'PK do registro versionado, como texto — a base mistura uuid e bigint.'
      t.string :event, null: false, comment: 'create / update / destroy.'
      t.string :whodunnit,
               comment: 'ID do usuário REAL do ato. Na impersonação é o `true_user`, nunca o impersonado (DEC-59 #3).'
      t.string :impersonated_id,
               comment: 'Preenchido só em sessão de impersonação: quem a sessão aparentava ser.'
      t.string :reason,
               comment: 'Motivo declarado do ato administrativo (concessão/revogação de permissão, impersonação).'
      t.string :ip_address, comment: 'Origem da requisição que produziu a versão.'
      t.jsonb :object, comment: 'Foto COMPLETA do registro antes da mudança (DEC-78).'
      t.jsonb :object_changes, comment: 'Diff da mudança, campo a campo (DEC-78).'
      t.datetime :created_at, null: false
    end

    add_index :versions, %i[item_type item_id]
    add_index :versions, :whodunnit
    add_index :versions, :created_at
    add_index :versions, :event
  end
end
