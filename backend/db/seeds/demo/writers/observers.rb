# frozen_string_literal: true

module Demo
  module Writers
    # Os **observadores**: quem recebe e-mail quando chega mensagem
    # administrativa. Chave natural: `email` (o índice único é sobre
    # `lower(email)`, e o model normaliza antes de validar).
    #
    # O model **recusa observador sem contexto** — cadastro que parece feito e
    # não faz efeito. `contexts=` é o setter que sincroniza a junção
    # `observer_contexts`, e ele é idempotente pelos dois caminhos: no registro
    # novo ele constrói em memória e o autosave grava; no já gravado ele apaga o
    # que saiu e cria o que entrou, o que numa segunda execução é nada.
    #
    # **Dois dos seis não são internos**, de propósito: é o par que prova
    # `Observer.for_message` — mensagem marcada como interna não sai para quem
    # está fora da casa. Com todos internos, a regra existe e a demonstração não
    # tem como mostrá-la.
    class Observers < Base
      def self.requires = %w[Observer ObserverContext]
      def self.owner_slice = 'S2'

      def call
        admin = demo_author
        if admin.nil?
          io.puts '   ⚠ nenhum administrador gravado — `observers.user_id` é obrigatório, pulando'
          return
        end

        ledger.observers.each do |observer|
          upsert!(::Observer,
                  find_by: { email: observer.email },
                  attributes: {
                    name: observer.name,
                    is_internal: observer.is_internal,
                    user_id: admin.id,
                    contexts: observer.contexts
                  })
        end
      end
    end
  end
end
