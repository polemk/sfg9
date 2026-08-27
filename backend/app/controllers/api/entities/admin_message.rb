# frozen_string_literal: true

module Api
  module Entities
    # S2 / FE-526 — a mensagem administrativa como o console a lê.
    #
    # Os dois campos extras saem **nomeados** (`extra1_*`/`extra2_*`), não
    # `hadouken`/`shoryuken`.
    #
    # A cor do contexto **não é exposta**: no legado o model devolvia hex
    # (`context.rb:41-47`). Aqui o servidor manda a **chave** e o front escolhe
    # o token — cor em resposta de API é cor fora do tema, e o app tem dois modos.
    class AdminMessage < Grape::Entity
      expose :id
      expose :sender_name
      expose :sender_email
      expose :message
      expose :state
      expose :state_label
      expose :context
      expose :context_label
      expose :is_read
      expose :is_favorite
      expose :is_internal
      expose :read_at
      expose :public_token
      expose :extra1_enabled
      expose :extra1_label
      expose :extra1_value
      expose :extra2_enabled
      expose :extra2_label
      expose :extra2_value
      expose :notes_count do |m|
        m.notes.size
      end
      expose :unread_notes_count do |m|
        m.unread_notes_count
      end
      expose :created_at
      expose :updated_at

      expose :notes, using: Api::Entities::MessageNote, if: { full: true }
    end
  end
end
