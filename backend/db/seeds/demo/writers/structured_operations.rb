# frozen_string_literal: true

module Demo
  module Writers
    # Operações estruturadas — mesmas 4 modalidades da operação de risco, muito
    # menos frequentes. Chave natural: `(project_id, contract_number)`.
    #
    # `original_balance` negativo pela mesma convenção do risco (DEC-01). O
    # `balance` aqui é decorativo no legado (achado E6) e é replicado como tal.
    #
    # ## Duas correções que só apareceram quando a S8 entregou as tabelas
    #
    # Este escritor foi escrito com a tabela ainda inexistente — ele pulava com
    # aviso e ninguém o viu gravar. Na primeira execução real contra a S8 ele
    # falhou, e as duas causas ficam registradas:
    #
    # 1. **`user_id` é obrigatório** (`structured_operation.rb:95`). Sem ele o
    #    escritor inteiro voltava atrás e as 136 estruturadas sumiam do banco de
    #    demonstração — a mesma falha que a S7 causou nas operações de risco.
    # 2. **`balance` NÃO é escrito.** `before_validation
    #    :reset_balance_from_original` o reescreve em TODO save, sem `on:`
    #    (golden E6). Propô-lo aqui faria o escritor oferecer, em toda execução,
    #    um número que o model sobrescreve um instante depois — "136
    #    atualizados" para sempre, com nada tendo mudado.
    class StructuredOperations < Base
      def self.requires = %w[StructuredOperation StructuredOperationType]
      def self.owner_slice = 'S8'

      def call
        types = ensure_types!
        author_id = demo_author&.id

        ledger.structured_operations.each do |operation|
          project = project_for(operation.client)
          company = companies_by_key[operation.company.key]
          carrier = carrier_for(operation.carrier)
          type = types[operation.modality]
          next if project.nil? || company.nil? || carrier.nil? || type.nil?

          upsert!(::StructuredOperation,
                  find_by: { project_id: project.id, contract_number: operation.contract_number },
                  attributes: {
                    company_id: company.id,
                    carrier_id: carrier.id,
                    operation_type_id: type.id,
                    title: "#{operation.contract_number} — #{operation.carrier.title}",
                    operation_value: operation.operation_value,
                    agreed_rate: operation.agreed_rate,
                    original_balance: -operation.operation_value,
                    issue_date: operation.issue_date,
                    due_date: operation.due_date,
                    is_ended: operation.is_ended,
                    is_on_variable: false,
                    user_id: author_id
                  })
        end
      end

      private

      # **O catálogo NÃO é escrito aqui.** Quem o semeia é
      # `Seeds::Reference::StructuredOperationTypes` (S8, DB-292), aplicado pelo
      # `Writers::Scaffolding` no começo da corrida — e este escritor só o
      # resolve, pela `integration_key`, que é contrato.
      #
      # Enquanto ele escrevia os quatro tipos por conta própria, os dois seeds
      # discordavam: a referência semeia os quatro com `is_default: true` (é o
      # que o legado faz, e é o que faz o `before_destroy` recusar removê-los),
      # e aqui só o Fomento saía padrão. Dois donos para a mesma linha é a
      # definição de dado que oscila entre execuções.
      def ensure_types!
        found = ::StructuredOperationType.where(integration_key: Ledger::Cast::MODALITIES.keys.map(&:to_s))
                                         .index_by { |t| t.integration_key.to_s.to_sym }
        faltando = Ledger::Cast::MODALITIES.keys - found.keys
        if faltando.any?
          io.puts "   ↳ tipos de operação estruturada ausentes no catálogo de referência: #{faltando.join(', ')}"
        end
        found
      end
    end
  end
end
