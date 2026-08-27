# frozen_string_literal: true

module Demo
  module Writers
    # Os movimentos das operações. Chave natural: `(risk_operation_id, sequence)`.
    #
    # **`sequence` é o `order` do legado**, renomeado porque `order` é palavra
    # reservada em SQL (DB-236/DB-579). É este escritor — e nenhum outro lugar —
    # que sabe disso: o razão chama o campo de `sequence` porque é o que ele
    # significa, e a renomeação não custou nada.
    #
    # A ordem importa de verdade: o índice `(risk_operation_id, date, created_at)`
    # existe porque é essa ordenação que dirige o recálculo do saldo. Gravar fora
    # de ordem produz uma coluna `balance` que não corresponde a nenhuma
    # sequência de lançamentos.
    class RiskMovements < Base
      def self.requires = %w[RiskMovement RiskOperation RiskMovementType]
      def self.owner_slice = 'S7'

      def call
        types = resolve_movement_types!
        operations = index_operations

        ledger.operations.each do |operation|
          record = operations[[operation.client.slug, operation.contract_number]]
          next if record.nil?

          # **A `sequence` gravada é a POSIÇÃO NA CADEIA CANÔNICA, não a do
          # razão.** Desde a S7, `Risk::Calculator.recalculate_chain` reatribui
          # `sequence` a cada gravação da operação, percorrendo os movimentos em
          # `date ASC, created_at ASC` (`calculator.rb:208-214`). Como o razão
          # insere em ordem própria, 71 dos 4.547 movimentos ficavam com um
          # número que o model reescrevia — e aí a chave natural
          # `(operação, sequence)` deixava de encontrar a linha que a gravou:
          # a execução seguinte reescrevia o movimento ERRADO com os valores de
          # outro. Não era só contador inflado; era dado trocado.
          #
          # Ordenar aqui pela mesma chave que o model usa (`created_at` empata
          # na ordem de inserção, que é a do razão) faz os dois números
          # coincidirem por construção.
          ordenados = operation.movements.each_with_index.sort_by { |m, i| [m.date, i] }.map(&:first)

          ordenados.each_with_index do |movement, index|
            type = types[movement.type_key]
            next if type.nil?

            upsert!(::RiskMovement,
                    find_by: { risk_operation_id: record.id, sequence: index + 1 },
                    attributes: {
                      movement_type_id: type.id,
                      project_id: record.project_id,
                      company_id: record.company_id,
                      carrier_id: record.carrier_id,
                      date: movement.date,
                      # **`created_at` é o desempate da cadeia, e por isso é
                      # explícito.** A ordem canônica é `date ASC, created_at
                      # ASC`; dois movimentos do mesmo dia (juros e IOF na
                      # liberação, por exemplo) empatam na data, e se empatarem
                      # também no carimbo o Postgres devolve a ordem que quiser.
                      # A renumeração então troca os dois de lugar de uma
                      # execução para a outra — foram 56 movimentos assim, e o
                      # efeito não era contador inflado: era o valor de um
                      # movimento indo para a linha do outro.
                      #
                      # Derivado da data, não de `Time.current`: um carimbo novo
                      # a cada execução seria "atualizado" para sempre.
                      created_at: movement.date.in_time_zone + index,
                      movement_value: movement.value
                      # **`balance` NÃO é escrito** — mesma razão do escritor de
                      # operações: desde a S7 quem preenche a coluna é
                      # `Risk::Calculator.recalculate_chain`, que percorre a
                      # cadeia em toda gravação da operação e reatribui `balance`
                      # **e** `sequence` (`calculator.rb:200-219`). Escrevê-lo
                      # aqui rendia "4.547 atualizados" em toda execução.
                    })
          end
        end
      end

      private

      # Os 8 movimentos de risco são dado de REFERÊNCIA (OPS-231): três deles são
      # resolvidos POR CHAVE pelo próprio sistema (B-09), e por isso quem os
      # escreve é `Seeds::Reference::RiskMovementTypes`, aplicado pelo
      # `scaffolding`. Aqui só resolvemos — as chaves do razão são as mesmas da
      # referência, e o spec do razão reprova se divergirem.
      def resolve_movement_types!
        keys = Ledger::Operations::MOVEMENT_TYPES.keys.map(&:to_s)
        found = ::RiskMovementType.where(integration_key: keys).index_by(&:integration_key)
        missing = keys - found.keys
        raise "Tipos de movimentação ausentes: #{missing.join(', ')} — rode `rake reference:seed`" if missing.any?

        found.transform_keys(&:to_sym)
      end

      def index_operations
        ledger.operations.each_with_object({}) do |operation, acc|
          project = project_for(operation.client)
          next if project.nil?

          record = ::RiskOperation.find_by(project_id: project.id,
                                           contract_number: operation.contract_number)
          acc[[operation.client.slug, operation.contract_number]] = record if record
        end
      end
    end
  end
end
