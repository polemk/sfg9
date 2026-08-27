# frozen_string_literal: true

module Demo
  module Writers
    # Quais contrapartes cada cliente opera (`project_to_carrier_connections`).
    #
    # Não é enfeite: a tela de garantias só oferece **carriers conectados ao
    # projeto**, e a matriz de limites da S5 se apoia nesta lista. Sem ela, os
    # selects da demo abrem com as 5 contrapartes para todos os 12 clientes — e o
    # cliente pequeno, que opera com uma factoring só, aparece podendo escolher um
    # FIDC.
    class CarrierConnections < Base
      def self.requires = %w[ProjectToCarrierConnection]
      def self.owner_slice = 'S4'

      def call
        ledger.clients.each do |client|
          project = project_for(client)
          next if project.nil?

          client.carrier_keys.each do |key|
            carrier = carrier_for(Ledger::Cast.carrier(key))
            next if carrier.nil?

            upsert!(::ProjectToCarrierConnection,
                    find_by: { project_id: project.id, carrier_id: carrier.id },
                    attributes: { is_active: true })
          end
        end
      end
    end
  end
end
