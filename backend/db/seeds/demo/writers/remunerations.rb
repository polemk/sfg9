# frozen_string_literal: true

module Demo
  module Writers
    # A **remuneração** — a tabela de preço da gestora com cada cliente, uma
    # linha por tipo de operação.
    #
    # ## Por que ele existe, e o que estava quebrado sem ele
    #
    # `remunerations` nasceu na S8 e o seed não a escrevia: `writers/charges.rb`
    # gravava `remuneration_id: nil` com um comentário dizendo que a tabela não
    # existia. A consequência não era a tela de Remunerações vazia — era a
    # **cadeia inteira de faturamento muda**: `Charges::ReceiptGenerator#candidates`
    # parte de `Remuneration.where(project_id:)`, então sem nenhuma taxa
    # cadastrada a tela de recibos de uma cobrança não tem um único candidato a
    # marcar, e o botão de faturar não faz nada.
    #
    # ## A chave natural é o índice único do banco (DB-284)
    #
    # `(project_id, operation_type_type, operation_type_id)`. É ele que garante
    # que `Receipt#fetch` (`receipt.rb:47-51`, um `.first`) ache **UMA** taxa —
    # e é por ele que este escritor casa, o que o torna idempotente por
    # construção: rodar duas vezes reencontra a mesma linha.
    #
    # ## As duas classes, e por que as duas importam
    #
    # `LIQ` aponta para `RiskOperationType` e `EST` para
    # `StructuredOperationType` — o polimorfismo de `remuneration.rb:31-46`.
    # Semear só `LIQ` deixaria metade da tela e metade da lista de candidatos de
    # fora: as 136 operações estruturadas do razão só viram candidatas a recibo
    # se existir remuneração `EST` do tipo delas.
    #
    # ## `title` NÃO é escrito aqui, e isso é deliberado
    #
    # `Remuneration#copy_title_from_operation_type` reescreve `title =
    # operation_type.title` em **todo** save, sem `on:` (decisão B-06, BE-304).
    # Propor a coluna aqui faria o escritor oferecer, em toda execução, um valor
    # que o model sobrescreve um instante depois — "65 atualizados" para sempre,
    # com nada tendo mudado. É a mesma armadilha já registrada em
    # `writers/risk_operations.rb` (o `balance`) e em `writers/carriers.rb`.
    class Remunerations < Base
      def self.requires = %w[Remuneration RiskOperationType StructuredOperationType]
      def self.owner_slice = 'S8'

      def call
        author_id = demo_author&.id
        types = types_by_class_and_modality

        ledger.remunerations.each do |remuneration|
          project = project_for(remuneration.client)
          type = types.dig(remuneration.operation_type_class, remuneration.modality)
          # Sem tipo de operação não há remuneração: `operation_type_id` é
          # `null: false` e o `check_constraint` fecha o domínio da classe.
          next if project.nil? || type.nil?

          upsert!(::Remuneration,
                  find_by: { project_id: project.id,
                             operation_type_type: remuneration.operation_type_class,
                             operation_type_id: type.id },
                  attributes: { value: remuneration.value, user_id: author_id })
        end
      end

      private

      # Os dois catálogos, indexados pela **chave de integração** — que é
      # contrato (`fomento` / `comissaria` / `intercompany` / `auto_liquidavel`),
      # ao contrário do título, que a tela pode editar.
      #
      # `RiskOperationType` vem dos seeds de REFERÊNCIA (OPS-230, aplicados pelo
      # `Writers::Scaffolding`); `StructuredOperationType`, do
      # `Writers::StructuredOperations`. Os dois já rodaram quando este chega —
      # é o que a posição dele na ordem do orquestrador garante.
      def types_by_class_and_modality
        {
          'RiskOperationType' => index_by_modality(::RiskOperationType),
          'StructuredOperationType' => index_by_modality(::StructuredOperationType)
        }
      end

      def index_by_modality(model)
        model.all.each_with_object({}) do |type, acc|
          key = type.integration_key.to_s
          acc[key.to_sym] = type if Ledger::Cast::MODALITIES.key?(key.to_sym)
        end
      end
    end
  end
end
