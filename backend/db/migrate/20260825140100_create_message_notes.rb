# frozen_string_literal: true

# S2 / DB-395, DB-513, BE-528 — a **thread** da mensagem administrativa.
#
# Ex-`livetat_feedback_notes`. A primeira nota é criada junto com a mensagem e
# repete o corpo dela (`message.rb:83-96`) — é o que faz a conversa começar já
# com a fala do remetente.
#
# **A citação aninhada É portada** — `quoted_note_id` e `top_parent_quote_id`,
# com a associação e a regra de `ensure_top_parent` (`note.rb:16-27`). O
# `tasks.md` desta fatia dizia o contrário ("não é portada"); a **DEC-58 / P-088
# vence**, e a decisão é explícita: a coluna, a associação e a lógica entram, e a
# **UI continua sem preencher**, exatamente como no legado, onde não há campo,
# hidden input nem parâmetro AJAX que escreva a coluna. O QA do Phase 4 **não
# deve abrir defeito** por isto nascer sem consumidor.
class CreateMessageNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :message_notes, comment: 'Resposta na thread de uma mensagem administrativa. Ex-`livetat_feedback_notes`.' do |t|
      t.bigint :admin_message_id, null: false, comment: 'Ticket ao qual a nota pertence. Era `feedback_id`.'
      t.text :description, null: false, comment: 'Corpo da resposta. Limite de 500 aplicado no banco e no model.'

      t.string :author_name, null: false, comment: 'Era `user_formal`.'
      t.string :author_email, null: false, comment: 'Era `user_email`.'
      t.uuid :user_id, comment: 'Autor administrador. NULO significa "veio do remetente" — é assim que o legado distingue os dois lados da conversa.'

      t.boolean :unread, null: false, default: true, comment: 'Era integer com default 1.'

      # DEC-58 / P-088: portadas sem consumidor de UI, de propósito.
      t.bigint :quoted_note_id, comment: 'Nota citada. DEC-58: portada sem UI que preencha.'
      t.bigint :top_parent_quote_id, comment: 'Raiz da árvore de citação, resolvida em `before_save`. DEC-58.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :message_notes, %i[admin_message_id created_at]
    add_index :message_notes, :quoted_note_id
    add_index :message_notes, :top_parent_quote_id
    add_index :message_notes, :legacy_id, unique: true

    add_foreign_key :message_notes, :admin_messages, column: :admin_message_id, on_delete: :cascade
    add_foreign_key :message_notes, :users, column: :user_id, on_delete: :nullify
    add_foreign_key :message_notes, :message_notes, column: :quoted_note_id, on_delete: :nullify
    add_foreign_key :message_notes, :message_notes, column: :top_parent_quote_id, on_delete: :nullify

    add_check_constraint :message_notes, 'char_length(description) <= 500',
                         name: 'message_notes_description_length'
  end
end
