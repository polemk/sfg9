# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_movements` (legado) -> `RiskMovement` (ai9).
      #
      # **A S7 ENTREGOU** (26/08/2026): `RiskMovement`, `Risk::Calculator#recalculate_chain`
      # e o CRUD existem. O `owner_slice` continua `S7`.
      #
      # Duas coisas que so este conversor sabe:
      #
      # 1. **`order` -> `sequence`** (DB-236): `order` e palavra reservada em SQL.
      # 2. **`balance` e saldo acumulado PERSISTIDO, sensivel a ordem de insercao.**
      #    A carga TEM de percorrer em ordem de `sequence` dentro de cada operacao, e a
      #    reconciliacao confere o **saldo final** contra a origem. Carregar fora de
      #    ordem produz um extrato que soma certo e termina errado.
      #
      # ### O que a S7 acrescenta a esse requisito (tarefa F.5 / DB-579)
      #
      # A ordem nao e so uma boa pratica de carga: e a **mesma** ordenacao que o motor
      # usa. `Risk::Calculator.recalculate_chain` percorre
      # `movements.order(date: :asc, created_at: :asc)` e reatribui `sequence` a partir
      # de 1 — replica de `../sfg/app/models/risk_operation.rb:103-105`.
      #
      # Consequencias praticas para quem for carregar:
      #
      # - **`created_at` importa.** Dois movimentos com a MESMA data sao desempatados por
      #   `created_at`; carregar todos na mesma transacao com o mesmo carimbo torna a
      #   ordem indefinida e o desempate final vira `id DESC` (`Risk::BalanceReader`).
      #   Preserve o `created_at` de origem.
      # - **`sequence` carregado pode ser SOBRESCRITO.** Ele e recalculado no
      #   `before_validation` de todo save da operacao. Se a ordem `(date, created_at)`
      #   da carga nao coincidir com o `order` do legado, o primeiro save da operacao
      #   renumera tudo — e ai o extrato migrado deixa de bater com o do legado.
      #   **Conferir as duas ordens na reconciliacao, nao so o saldo final.**
      # - **NAO salve a operacao durante a carga** so para "atualizar o cache": isso
      #   dispara o recalculo. `balance` de operacao e de movimento vem da origem.
      class RiskMovements < Base
        def self.source_table = 'risk_movements'
        def self.target_model = 'RiskMovement'
        def self.requires = %w[RiskMovement RiskOperation]
        def self.owner_slice = 'S7'

        def self.references = {
          'user_id' => 'livetat_auth_users', 'project_id' => 'projects',
          'company_id' => 'companies', 'carrier_id' => 'carriers',
          'risk_operation_id' => 'risk_operations', 'receivable_id' => 'receivable_entries',
          'movement_type_id' => 'risk_movement_types', 'pair_id' => 'risk_movements'
        }

        def self.uniques = [%w[risk_operation_id order]]
        def self.sums = %w[movement_value balance]
        def self.year_column = 'date'

        def convert(row)
          {
            user_id: ref('livetat_auth_users', row['user_id']),
            project_id: ref('projects', row['project_id']),
            company_id: ref('companies', row['company_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            risk_operation_id: ref('risk_operations', row['risk_operation_id']),
            receivable_id: ref('receivable_entries', row['receivable_id']),
            movement_type_id: ref('risk_movement_types', row['movement_type_id']),
            pair_id: ref('risk_movements', row['pair_id']),
            sequence: row['order'],
            date: row['date'],
            movement_value: Values.to_decimal(row['movement_value']),
            balance: Values.to_decimal(row['balance']),
            observation: row['observation'],
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
