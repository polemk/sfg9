# frozen_string_literal: true

# S2 / DB-390, DB-508, BE-526 — as **mensagens administrativas** (o ticket).
#
# Substitui `livetat_feedback_messages` da engine `feedback19`, que deixa de ser
# engine e vira código do app (DC-12). Quatro correções de esquema entram aqui,
# todas com o defeito de origem nomeado:
#
#  1. **`message` era `string(255)` no banco** e a validação do model aceitava
#     500 (`feedback19/.../message.rb:16`). Toda mensagem entre 256 e 500
#     caracteres passava na validação e era **truncada em silêncio** pelo banco.
#     Aqui é `text`, e o limite de 500 é aplicado **nos dois lados**.
#  2. **Booleanos eram `integer 0/1`** (`is_read`, `is_favorite`, `is_intern`,
#     `uses_*`). Viram `boolean`.
#  3. **`state_id`/`context_id` eram FK para tabela de referência**, resolvida em
#     **variável de classe na carga da classe** (`state.rb:6-13`) — sem
#     sincronismo, e o processo que subisse antes do seed guardava `nil` para
#     sempre (OPS-507). Viram **enum string** com `CHECK` no banco.
#  4. **`hadouken_*`/`shoryuken_*`** — nomes de piada para dois campos extras
#     configuráveis. Viram `extra1_*`/`extra2_*` (FE-406).
class CreateAdminMessages < ActiveRecord::Migration[8.0]
  # As 8 situações do legado (`feedback19/.../state.rb:6-13`), na ordem em que
  # apareciam. **A inversão Concluído/Fechado é comportamento de aplicação**
  # (DEC-73), não de esquema: os dois estados existem aqui, distintos.
  STATES = %w[unread read open evaluated answered done closed rejected].freeze

  # Os 4 contextos (`feedback19/.../context.rb:9-12`).
  CONTEXTS = %w[other problem contact suggestion].freeze

  def change
    create_table :admin_messages, comment: 'Mensagem administrativa (ticket). Ex-`livetat_feedback_messages` — DC-12.' do |t|
      t.string :sender_name, null: false, comment: 'Nome de quem enviou. Era `formal`.'
      t.string :sender_email, null: false, comment: 'E-mail de quem enviou.'
      t.text :message, null: false,
                       comment: 'Corpo. Era string(255) com validação de 500: truncava em silêncio.'

      t.string :state, null: false, default: 'unread',
                       comment: 'Situação. Enum string — era FK para tabela resolvida em variável de classe (OPS-507).'
      t.string :context, null: false, default: 'other',
                         comment: 'Contexto. Enum string, mesma razão do `state`.'

      t.uuid :user_id, comment: 'Administrador que tocou a mensagem por último. Nulo enquanto ninguém tocou.'

      t.boolean :is_read, null: false, default: false, comment: 'Era integer 0/1.'
      t.boolean :is_favorite, null: false, default: false, comment: 'Era integer 0/1.'
      t.boolean :is_internal, null: false, default: false,
                              comment: 'Mensagem interna. Era `is_intern`, integer 0/1. Decide o envio a observador externo.'
      t.datetime :read_at, comment: 'Quando foi marcada como lida.'

      # Os dois tokens do legado. O público endereça a conversa por link; o
      # privado é a chave administrativa. Continuam **únicos** — no legado a
      # unicidade era um `loop` com `SELECT` (`message.rb:153-157`), sujeito a
      # corrida; aqui é índice.
      t.string :public_token, null: false, comment: 'Token público da conversa (link).'
      t.string :private_token, null: false, comment: 'Token privado (administrativo).'

      # Os dois campos extras configuráveis. Eram `hadouken_*`/`shoryuken_*`.
      t.boolean :extra1_enabled, null: false, default: false
      t.string :extra1_label
      t.string :extra1_value
      t.boolean :extra2_enabled, null: false, default: false
      t.string :extra2_label
      t.string :extra2_value

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :admin_messages, :public_token, unique: true
    add_index :admin_messages, :private_token, unique: true
    add_index :admin_messages, :state
    add_index :admin_messages, :context
    add_index :admin_messages, :created_at
    add_index :admin_messages, :legacy_id, unique: true

    add_foreign_key :admin_messages, :users, column: :user_id, on_delete: :nullify

    add_check_constraint :admin_messages,
                         "state IN (#{STATES.map { |s| "'#{s}'" }.join(', ')})",
                         name: 'admin_messages_state_enum'
    add_check_constraint :admin_messages,
                         "context IN (#{CONTEXTS.map { |c| "'#{c}'" }.join(', ')})",
                         name: 'admin_messages_context_enum'
    # O limite que o banco do legado tinha em 255 e a validação em 500. Agora os
    # dois dizem 500 — a validação do model deixa de ser uma promessa que o
    # banco não cumpre.
    add_check_constraint :admin_messages, 'char_length(message) <= 500',
                         name: 'admin_messages_message_length'
  end
end
