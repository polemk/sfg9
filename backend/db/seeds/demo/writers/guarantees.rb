# frozen_string_literal: true

module Demo
  module Writers
    # Garantias dadas ao carrier (`project_guarantees`).
    #
    # **Nem todo projeto tem** — e é isso que faz a coluna significar alguma coisa
    # quando tem. Garantia em 12 de 12 clientes é ruído; em 8 de 12, é informação.
    class Guarantees < Base
      def self.requires = %w[ProjectGuarantee ProjectGuaranteeType]
      def self.owner_slice = 'S4'

      def call
        types = ::ProjectGuaranteeType.all.index_by(&:title)

        ledger.guarantees.each do |guarantee|
          project = project_for(guarantee.client)
          carrier = carrier_for(guarantee.carrier)
          type = types[guarantee.guarantee_type]
          next if project.nil? || carrier.nil? || type.nil?

          upsert!(::ProjectGuarantee,
                  find_by: { project_id: project.id, title: guarantee.title },
                  attributes: {
                    carrier_id: carrier.id,
                    guarantee_type_id: type.id,
                    value: guarantee.value,
                    observation: guarantee.observation
                  })
        end
      end
    end
  end
end
