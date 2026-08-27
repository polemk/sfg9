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

            # **Sem `is_active`, e não por esquecimento.**
            #
            # O conversor do ETL já registra a razão, e ela vale igual aqui:
            # "não há `user_id` nem `is_active`, nem na origem nem no destino. A
            # conexão é um fato binário — existe ou não existe. Desligá-la é
            # apagá-la, e é assim nos dois lados"
            # (`etl/converters/project_to_carrier_connections.rb:54`).
            #
            # A ponte é o próprio registro, então o `upsert` não tem atributo
            # nenhum a gravar além da chave.
            upsert!(::ProjectToCarrierConnection,
                    find_by: { project_id: project.id, carrier_id: carrier.id },
                    attributes: {})
          end
        end
      end
    end
  end
end
