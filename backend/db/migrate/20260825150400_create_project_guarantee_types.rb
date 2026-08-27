# frozen_string_literal: true

# S3 / DB-084, DB-558 — **tipos de garantia**, o catálogo que respondia para
# anônimo.
#
# Único catálogo desta fatia com defeito de AUTORIZAÇÃO, não de usabilidade: no
# legado o controller declarava `requires_current_user? == false` e o endpoint
# respondia sem sessão (D-23). No ai9 ele nasce dentro de `api/v1/base.rb`, que
# já exige sessão — 401 sem credencial é o comportamento padrão da base.
#
# **DEC-86 — o conteúdo é NOVO, e nasce marcado como provisório.** A tabela
# existe no legado desde 2022 e nenhum seed a popula: o select de garantias sobe
# vazio até alguém cadastrar à mão. Não há nada a migrar. Por isso a coluna
# `is_provisional`: os tipos semeados são suposição do orquestrador, a lista
# definitiva é do cliente, e a tela precisa poder dizer isso ao usuário.
# Substituir é trocar linhas de seed — sem migration e sem deploy de código.
#
# `title` e `integration_key` são únicos **no banco**, e a chave é **congelada**
# na criação (DC-22): renomear o título não a recalcula.
class CreateProjectGuaranteeTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :project_guarantee_types, id: :uuid, default: -> { 'gen_random_uuid()' }, comment: 'Tipo de garantia de projeto. Catálogo GLOBAL (C1, regra 4). Semeado como PROVISÓRIO — DEC-86.' do |t|
      t.string :title, null: false, comment: 'Nome do tipo. Único no banco (DB-084).'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração. Única no banco e CONGELADA na criação (DC-22).'
      t.boolean :is_active, null: false, default: true, comment: 'Tipo ativo. Era integer nullable no legado.'
      t.boolean :is_provisional, null: false, default: false,
                                 comment: 'DEC-86 — tipo semeado como suposição; a lista definitiva é do cliente. A tela avisa.'
      t.integer :sort_order, null: false, default: 0, comment: 'Ordem de exibição no select de garantias.'
      t.text :description, comment: 'Descrição do tipo, exibida no formulário de garantia.'
      t.text :observation, comment: 'Observação interna. É onde a nota de provisoriedade do seed fica legível.'
      t.uuid :user_id, comment: 'Autor do cadastro, vindo da SESSÃO (BE-703). O `user_id` do CORPO é ignorado.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência na base do legado.'

      t.timestamps
    end

    add_index :project_guarantee_types, :title, unique: true
    add_index :project_guarantee_types, :integration_key, unique: true
    add_index :project_guarantee_types, :is_active
    add_index :project_guarantee_types, :sort_order
    add_index :project_guarantee_types, :legacy_id, unique: true
    add_index :project_guarantee_types, :user_id

    add_foreign_key :project_guarantee_types, :users, column: :user_id, on_delete: :nullify
  end
end
