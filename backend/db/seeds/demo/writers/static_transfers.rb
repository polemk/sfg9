# frozen_string_literal: true

module Demo
  module Writers
    # **A transferência pré → antecipação (BE-275), gravada pelo SERVIÇO.**
    #
    # ## O que estava faltando, medido
    #
    # O seed criava 78 operações estáticas (39 pares pré ↔ antecipação, abertas
    # pelo `after_create` do `RiskControl`) com **saldo zero e zero
    # movimentos**. Abrir uma delas na apresentação mostrava uma operação morta,
    # e o botão "Transferir" — que é a razão de o par existir — não tinha o que
    # demonstrar.
    #
    # Do outro lado, o razão lançava "Transferência Recebida" solta em 12% das
    # operações comuns: **105 movimentos de transferência sem contrapartida**, e
    # sem `pair_id`. O sistema não produz isso: `is_transfer` está fora de
    # `RiskMovementType.manual` (o usuário não pode lançar) e o único caminho é
    # o `Risk::TransferService`, que **sempre** cria as duas pontas. Era dado
    # que a tela mostrava e que nenhum caminho do produto criaria.
    #
    # ## Por que chamar o serviço, e não gravar dois movimentos
    #
    # Contrato C2, o mesmo motivo do agregado da renegociação: o **sinal** de
    # cada ponta, o cruzamento do `pair_id` e o refazimento das duas cadeias de
    # saldo são do `Risk::TransferService`. Reimplementá-los aqui seria criar a
    # segunda verdade — e a assimetria de sinal entre as duas pontas é
    # exatamente o tipo de detalhe que se copia errado.
    #
    # ## Idempotência
    #
    # `TransferService` **sempre cria** — não há upsert nele, e não deveria
    # haver. A guarda é anterior: se a operação pré já tem um movimento do tipo
    # "Valor Transferido", esta execução não faz nada. Sem isso, cada rodada do
    # seed acrescentaria um par novo e o saldo do par andaria entre ensaios da
    # apresentação — que é o que a §10 do desenho proíbe.
    class StaticTransfers < Base
      def self.requires = %w[RiskOperation RiskMovement RiskMovementType RiskControl]
      def self.owner_slice = 'S7'

      def call
        actor = demo_author

        ledger.static_transfers.each do |transfer|
          pre = pre_operation_for(transfer.control)
          next if pre.nil?

          if ja_transferida?(pre)
            @unchanged += 1
            next
          end

          aplicar!(pre, transfer, actor)
        end
      end

      private

      def aplicar!(pre, transfer, actor)
        resposta = ::Risk::TransferService.call(
          operation: pre,
          attrs: { date: transfer.date, movement_value: transfer.value,
                   observation: 'Transferência de pré-faturamento para antecipação' },
          actor: actor
        )

        if resposta[:status] == 201
          @created += 1
        else
          # Recusa não derruba o seed: ela aparece nomeada, com o motivo que o
          # serviço deu, e o resto do banco continua de pé.
          io.puts "   ↳ transferência recusada em #{transfer.control.key}: #{resposta[:error]}"
        end
      end

      # A ponta `is_pre` do par estático do controle. Duas linhas por controle,
      # e o subtipo é quem as distingue.
      def pre_operation_for(control)
        record = control_record(control)
        return nil if record.nil?

        ::RiskOperation.where(risk_control_id: record.id, is_static: true)
                       .includes(:operation_subtype)
                       .find { |operation| operation.operation_subtype&.is_pre }
      end

      def ja_transferida?(operation)
        ::RiskMovement.where(risk_operation_id: operation.id,
                             movement_type_id: transfer_out_id).exists?
      end

      def transfer_out_id
        @transfer_out_id ||= ::RiskMovementType.find_by(
          integration_key: ::RiskMovementType::TRANSFER_OUT_KEY
        )&.id
      end

      # O trio que identifica o limite no banco — mesmo índice que o escritor de
      # limites usa.
      def control_record(control)
        project = project_for(control.client)
        company = companies_by_key[control.company.key]
        carrier = carrier_for(control.carrier)
        type = operation_types[control.modality]
        return nil if [project, company, carrier, type].any?(&:nil?)

        ::RiskControl.find_by(project_id: project.id, company_id: company.id,
                              carrier_id: carrier.id, risk_operation_type_id: type.id)
      end

      def operation_types
        @operation_types ||=
          ::RiskOperationType.all.index_by { |t| t.integration_key.to_s.to_sym }
      end
    end
  end
end
