# frozen_string_literal: true

module Demo
  module Writers
    # As **mensagens administrativas** (tickets) e a thread de cada uma.
    #
    # Chave natural: `public_token`. O model gera os dois tokens com
    # `SecureRandom` quando chegam em branco — deixá-lo gerar faria cada execução
    # criar vinte e oito mensagens novas, porque não haveria por onde reencontrar
    # as anteriores. O razão emite um **UUID v5 determinístico**; `legacy_id`
    # não serve para isso (DEC-12 reserva a coluna para proveniência do banco
    # legado, e carimbá-la aqui plantaria uma origem que não existe).
    #
    # ## A primeira nota é escrita aqui, e o callback do model concorda
    #
    # `AdminMessage` cria a fala inicial num `after_create_commit`, que só roda
    # **depois** do commit — ou seja, depois da transação inteira do seed. Sem
    # ela dentro da transação, as respostas seriam gravadas antes da pergunta e a
    # thread abriria fora de ordem. Escrevendo a primeira nota aqui, o callback
    # encontra `notes.exists?` e não faz nada: um caminho, um resultado.
    #
    # ## `updated_at` NÃO é escrito, e a razão é a máquina de estados
    #
    # `MessageNote` tem um `after_create` que move a mensagem de "Lido" para
    # "Respondido" na primeira fala do administrador, e de volta para "Aberto"
    # quando o remetente responde depois dele — por `update_columns`, que carimba
    # `updated_at`. Escrever `updated_at` aqui faria o escritor propor, em toda
    # execução, um carimbo que o model acabou de reescrever: "2 atualizados" para
    # sempre, sem nada ter mudado. `created_at` continua sendo escrito, porque é
    # ele que ordena a lista.
    #
    # ## `user_id` nulo numa nota é semântica, não descuido
    #
    # É assim que o legado distingue os dois lados da conversa: nota com
    # `user_id` é do administrador, nota sem é do remetente. Uma thread com um
    # lado só não demonstra a tela.
    class AdminMessages < Base
      def self.requires = %w[AdminMessage MessageNote]
      def self.owner_slice = 'S2'

      def call
        admin = demo_author

        ledger.admin_messages.each do |message|
          record = upsert!(::AdminMessage,
                           find_by: { public_token: message.public_token },
                           attributes: attributes_for(message, admin))

          write_notes!(record, message, admin)
        end
      end

      private

      def attributes_for(message, admin)
        {
          private_token: message.private_token,
          sender_name: message.sender_name,
          sender_email: message.sender_email,
          message: message.message,
          state: message.state,
          context: message.context,
          is_read: message.is_read,
          is_favorite: message.is_favorite,
          is_internal: message.is_internal,
          user_id: message.handled_by ? admin&.id : nil,
          read_at: message.read_at,
          created_at: message.created_at
        }
      end

      # Chave natural da nota: `(admin_message_id, description)`. Não há coluna
      # melhor — e o razão garante que dois textos nunca se repetem dentro da
      # mesma thread.
      def write_notes!(record, message, admin)
        message.notes.each do |note|
          upsert!(::MessageNote,
                  find_by: { admin_message_id: record.id, description: note.description },
                  attributes: {
                    author_name: note.author_name,
                    author_email: note.author_email,
                    user_id: note.from_admin ? admin&.id : nil,
                    unread: note.unread,
                    created_at: note.created_at
                  })
        end
      end
    end
  end
end
