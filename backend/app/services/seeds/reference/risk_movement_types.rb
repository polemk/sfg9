# frozen_string_literal: true

module Seeds
  module Reference
    # S5 / **OPS-231, OPS-232** — os oito tipos de movimentação. Dado de REFERÊNCIA.
    #
    # **Três destes oito são funcionais**, ou seja: o sistema os procura pelo
    # nome para conseguir operar, e sem eles a S7 não consegue lançar movimento
    # nenhum.
    #
    # | chave | usado por |
    # | ----- | --------- |
    # | `liberacao_do_recurso` | o `after_create` da operação de risco |
    # | `valor_transferido` | a transferência do par pré → antecipação |
    # | `transferencia_recebida` | o movimento espelho da transferência |
    #
    # `RiskMovementType.release`, `.transfer_out` e `.transfer_in` resolvem por
    # essas chaves e **levantam erro de negócio** quando não encontram (B-09) —
    # o legado resolvia por título literal e quebrava em silêncio quando alguém
    # renomeasse o tipo pela tela de administração.
    #
    # ### Os oito, verbatim de `../sfg/db/seeds.rb:324-331`
    #
    # ```ruby
    # RiskMovementType.create(title: "Juros",                  credit_type: "D")
    # RiskMovementType.create(title: "AdValorem",              credit_type: "D")
    # RiskMovementType.create(title: "IOF",                    credit_type: "D")
    # RiskMovementType.create(title: "Liberação do Recurso",   credit_type: "D", is_system_exclusive: 1)
    # RiskMovementType.create(title: "Liquidação",             credit_type: "C")
    # RiskMovementType.create(title: "Juros de Mora",          credit_type: "D")
    # RiskMovementType.create(title: "Transferência Recebida", credit_type: "D", is_transfer: 1)
    # RiskMovementType.create(title: "Valor Transferido",      credit_type: "C", is_transfer: 1)
    # ```
    #
    # Todos com `is_default: 1` — é o que bloqueia a exclusão deles.
    class RiskMovementTypes < Catalog
      ENTRIES = [
        { key: 'juros', title: 'Juros', credit_type: 'D' },
        { key: 'advalorem', title: 'AdValorem', credit_type: 'D' },
        { key: 'iof', title: 'IOF', credit_type: 'D' },
        { key: ::RiskMovementType::RELEASE_KEY, title: 'Liberação do Recurso',
          credit_type: 'D', is_system_exclusive: true },
        { key: 'liquidacao', title: 'Liquidação', credit_type: 'C' },
        { key: 'juros_de_mora', title: 'Juros de Mora', credit_type: 'D' },
        { key: ::RiskMovementType::TRANSFER_IN_KEY, title: 'Transferência Recebida',
          credit_type: 'D', is_transfer: true },
        { key: ::RiskMovementType::TRANSFER_OUT_KEY, title: 'Valor Transferido',
          credit_type: 'C', is_transfer: true }
      ].freeze

      class << self
        def catalog_name = 'Movimentações de risco (OPS-231)'
        def model = ::RiskMovementType
        def natural_key = %i[integration_key]

        # `credit_type` entra em `create_only`: ele é o **sinal** do movimento no
        # saldo, e reescrevê-lo num deploy mudaria retroativamente o saldo de
        # toda operação que já usou o tipo.
        def create_only_attributes
          %i[is_active is_default credit_type is_system_exclusive is_transfer title]
        end

        def entries
          ENTRIES.map do |entry|
            {
              integration_key: entry[:key],
              title: entry[:title],
              credit_type: entry[:credit_type],
              is_active: true,
              is_default: true,
              is_system_exclusive: entry.fetch(:is_system_exclusive, false),
              is_transfer: entry.fetch(:is_transfer, false)
            }
          end
        end
      end
    end
  end
end
