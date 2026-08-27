# frozen_string_literal: true

# S2 / DB-391, DB-392, DB-511, DB-512 — **observadores** e os contextos que cada
# um observa.
#
# Ex-`livetat_feedback_observers` e `livetat_feedback_observer_contexts`.
#
# Duas correções:
#
#  1. **`is_extern` não entra.** Campo morto: defaultado em `set_defaults`
#     (`observer.rb:17`) e **não exposto** nem na UI nem no `permit`
#     (`observers_controller.rb:110-118`). O único predicado que o legado
#     realmente avalia é `is_intern` (`notification.rb:38`).
#  2. **A prevenção de duplicata vira índice único.** No legado era um
#     `SELECT COUNT` a cada save (`observer_context.rb:9`) — duas requisições
#     concorrentes passavam as duas pela contagem e gravavam as duas.
class CreateObservers < ActiveRecord::Migration[8.0]
  CONTEXTS = %w[other problem contact suggestion].freeze

  def change
    create_table :observers, comment: 'Quem é notificado por e-mail quando chega mensagem administrativa.' do |t|
      t.string :name, null: false, comment: 'Nome do observador. Era `title`.'
      t.string :email, null: false, comment: 'E-mail notificado. Único.'
      t.boolean :is_internal, null: false, default: true,
                              comment: 'Era `is_intern`, integer. Observador não interno não recebe mensagem interna.'

      t.uuid :user_id, null: false, comment: 'Administrador que cadastrou.'
      t.uuid :last_updated_user_id, comment: 'Administrador que alterou por último.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :observers, 'lower(email)', unique: true, name: 'index_observers_on_lower_email'
    add_index :observers, :legacy_id, unique: true
    add_foreign_key :observers, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :observers, :users, column: :last_updated_user_id, on_delete: :nullify

    create_table :observer_contexts, comment: 'Contextos que um observador acompanha. Junção observador × contexto.' do |t|
      t.bigint :observer_id, null: false
      t.string :context, null: false, comment: 'Enum string — o contexto deixou de ser tabela (OPS-507).'

      t.timestamps
    end

    # A correção do `SELECT COUNT` sujeito a corrida.
    add_index :observer_contexts, %i[observer_id context], unique: true
    add_foreign_key :observer_contexts, :observers, column: :observer_id, on_delete: :cascade

    add_check_constraint :observer_contexts,
                         "context IN (#{CONTEXTS.map { |c| "'#{c}'" }.join(', ')})",
                         name: 'observer_contexts_context_enum'
  end
end
