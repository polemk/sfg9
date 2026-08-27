# frozen_string_literal: true

# S2 / BE-424, BE-527, BE-531 — regra de negócio das mensagens administrativas.
class AdminMessagesService
  class << self
    # BE-424. **O total respeita os filtros.** No legado o `@total_count` era
    # `Message.all.count` — o total GLOBAL, calculado antes de qualquer filtro:
    # filtrar por "Problema" mostrava 12 linhas e dizia "de 380".
    def index(params:)
      scope = AdminMessage.all
      scope = scope.with_state(params[:state]) if params[:state].present?
      scope = scope.with_context(params[:context]) if params[:context].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = scope.where(is_favorite: true) if truthy?(params[:favorite])
      scope = scope.where(is_read: false) if truthy?(params[:unread])

      { status: 200, data: scope.recent_first }
    end

    def show(id:, admin:)
      message = find(id)
      return not_found unless message

      # Abrir a mensagem é o que a move de "Não lido" para "Lido", e é também o
      # que marca como lidas as falas do outro lado da conversa.
      message.mark_opened_by(admin)
      message.mark_notes_read_for(admin)

      { status: 200, data: message.reload }
    end

    def create(attrs:, sender: nil)
      message = AdminMessage.new(attrs)
      # DEC-40 / P-056: o envio é **autenticado**. Com o cadastro público
      # desligado (DEC-18.7) não sobra visitante legítimo para o canal anônimo,
      # e no legado o `create` era isento de autenticação de propósito
      # (`messages_controller.rb:6`) — com o filtro restante fazendo bypass
      # total quando o formato era JS, que é justamente o que o console usava.
      if sender
        message.sender_name = message.sender_name.presence || sender.name
        message.sender_email = message.sender_email.presence || sender.email
      end

      return unprocessable(message) unless message.save

      notify_safely { MessageMailer.received(message).deliver_later }
      notify_observers(message)

      { status: 201, data: message }
    end

    # BE-527 — a máquina de estados.
    #
    # **DEC-73: a inversão Concluído/Fechado é REPLICADA.** No legado os dois
    # estados existem e estão trocados entre si: no `update`, escolher
    # "Concluído" grava **Fechado** (`messages_controller.rb:118-119`); a action
    # `close` grava **Concluído** (`:156-159`). Inversão dupla, nos dois
    # sentidos — não é typo de um lado.
    #
    # O `tasks.md` desta fatia (3.3 e 6.4.2) dizia "pedir Concluído grava
    # Concluído", seguindo a DC-16. Ele foi escrito **antes** da DEC-73, que
    # respondeu o contrário: vale o DEC-30, replicar. **A DEC vence o tasks.**
    # Quem "consertar" isto sem passar por uma DEC nova é reprovado pelo golden
    # test `admin_messages_state_spec`, que trava os DOIS sentidos.
    def update(id:, attrs:, admin:)
      message = find(id)
      return not_found unless message

      message.is_favorite = truthy?(attrs[:is_favorite]) unless attrs[:is_favorite].nil?
      unless attrs[:is_read].nil?
        message.is_read = truthy?(attrs[:is_read])
        message.read_at = Time.current if message.is_read?
      end

      if attrs[:state].present?
        pedido = attrs[:state].to_s
        return invalid_state unless AdminMessage::STATES.key?(pedido)

        message.state = (pedido == 'done' ? 'closed' : pedido)
      end

      message.user_id = admin&.id || message.user_id

      return unprocessable(message) unless message.save

      { status: 200, data: message }
    end

    # O outro lado da inversão do DEC-73: a ação "encerrar" grava **Concluído**.
    def close(id:, admin:)
      message = find(id)
      return not_found unless message

      message.state = 'done'
      message.user_id = admin&.id || message.user_id
      return unprocessable(message) unless message.save

      { status: 200, data: message }
    end

    def destroy(id:)
      message = find(id)
      return not_found unless message

      message.destroy
      { status: 200, data: { deleted: true } }
    end

    # Resposta na thread. Quem responde define o lado: administrador presente =
    # fala do administrador; ausente = fala do remetente.
    def add_note(id:, description:, admin:)
      message = find(id)
      return not_found unless message

      note = message.notes.new(
        description: description,
        author_name: admin&.name || message.sender_name,
        author_email: admin&.email || message.sender_email,
        user_id: admin&.id,
        unread: true
      )
      return unprocessable(note) unless note.save

      notify_safely { MessageMailer.note_added(note).deliver_later }
      { status: 201, data: note }
    end

    private

    # `messages_controller.rb:179-184` aceitava id, token público ou token
    # privado no mesmo parâmetro, com um `OR` de três ramos em SQL cru. Aqui a
    # busca por token continua existindo (o link do e-mail depende dela), mas em
    # consultas separadas e sem interpolação.
    def find(identifier)
      id = identifier.to_s
      AdminMessage.find_by(id: (id if id.match?(/\A\d+\z/))) ||
        AdminMessage.find_by(public_token: id) ||
        AdminMessage.find_by(private_token: id)
    end

    def notify_observers(message)
      Observer.for_message(message).find_each do |observer|
        notify_safely { ObserverMailer.message_received(observer, message).deliver_later }
      end
    end

    # Mesma razão do `ObserversService`: e-mail é notificação, não transação.
    # SMTP fora não pode transformar uma mensagem gravada num 500.
    def notify_safely
      yield
    rescue StandardError => e
      Rails.logger.error "[AdminMessagesService] falha ao enfileirar e-mail: #{e.message}"
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def not_found
      { status: 404, error: 'Mensagem não encontrada.' }
    end

    def invalid_state
      { status: 400, error: 'Situação inválida.' }
    end

    def unprocessable(record)
      { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
    end
  end
end
