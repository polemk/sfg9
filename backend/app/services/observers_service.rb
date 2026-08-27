# frozen_string_literal: true

# S2 / BE-426..BE-429 — CRUD de observadores.
class ObserversService
  class << self
    # **D-88: `limit`/`offset` eram lidos e nunca aplicados.** A tela mandava,
    # o controller lia, e a consulta ignorava — a lista voltava inteira sempre.
    # Aqui a paginação é a do `paginate` do `ControllerHelpers` (Kaminari,
    # envelope em cabeçalho, teto de `per_page`), e o endpoint a aplica.
    def index(params:)
      scope = Observer.includes(:observer_contexts).order(:name)
      if params[:context].present?
        scope = scope.joins(:observer_contexts).where(observer_contexts: { context: params[:context] }).distinct
      end
      if params[:q].present?
        like = "%#{params[:q].to_s.strip.downcase}%"
        scope = scope.where('LOWER(observers.name) LIKE :q OR LOWER(observers.email) LIKE :q', q: like)
      end

      { status: 200, data: scope }
    end

    def create(attrs:, actor:)
      observer = Observer.new(
        name: attrs[:name],
        email: attrs[:email],
        is_internal: attrs.key?(:is_internal) ? attrs[:is_internal] : true,
        user: actor
      )
      observer.contexts = attrs[:contexts]

      return unprocessable(observer) unless observer.save

      notify_safely { ObserverMailer.added(observer).deliver_later }
      { status: 201, data: observer }
    end

    def update(id:, attrs:, actor:)
      observer = Observer.find_by(id: id)
      return not_found unless observer

      observer.name = attrs[:name] if attrs.key?(:name)
      observer.email = attrs[:email] if attrs.key?(:email)
      observer.is_internal = attrs[:is_internal] if attrs.key?(:is_internal)
      observer.last_updated_user = actor
      observer.contexts = attrs[:contexts] if attrs.key?(:contexts)

      return unprocessable(observer) unless observer.save

      { status: 200, data: observer.reload }
    end

    def destroy(id:)
      observer = Observer.find_by(id: id)
      return not_found unless observer

      notify_safely { ObserverMailer.removed(observer).deliver_later }
      observer.destroy
      { status: 200, data: { deleted: true } }
    end

    private

    # O e-mail é NOTIFICAÇÃO, não parte da transação: SMTP fora não pode
    # impedir o cadastro nem a remoção de um observador. O legado deixava a
    # exceção subir e o `create` inteiro virava 500 — o registro gravado, o
    # usuário vendo erro. Falha de entrega vira log.
    def notify_safely
      yield
    rescue StandardError => e
      Rails.logger.error "[ObserversService] falha ao enfileirar e-mail: #{e.message}"
    end

    def not_found
      { status: 404, error: 'Observador não encontrado.' }
    end

    def unprocessable(record)
      { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
    end
  end
end
