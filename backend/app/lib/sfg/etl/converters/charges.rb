# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `charges` (legado) -> `Charge` (ai9). **S6**, **DB-162**.
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM
      #
      # `20220707164909_create_charges` é uma das **24 migrations que nunca
      # subiram** em produção. Conferido no dump de 31/05/2025: não há
      # `COPY public.charges`. Este conversor **vai ler zero linha** — e é o
      # resultado esperado, não uma falha.
      #
      # Ele existe assim mesmo por dois motivos:
      #
      # 1. **DEC-102** — o conversor é escrito agora, com a regra na cabeça;
      # 2. se o cliente rodar as migrations pendentes no legado antes do
      #    cutover, a tabela passa a existir e a carga funciona sem ninguém
      #    precisar lembrar de escrever isto às pressas.
      #
      # O motor conta as linhas lidas; zero linhas com o conversor declarado é
      # informação, e lacuna declarada é lacuna que alguém vê.
      class Charges < Base
        def self.source_table = 'charges'
        def self.target_model = 'Charge'
        def self.owner_slice = 'S6'
        def self.references = { 'project_id' => 'projects', 'user_id' => 'livetat_auth_users' }
        def self.enums = { 'state' => CHARGE_STATE }
        def self.sums = %w[value total_operations_value]
        def self.year_column = 'date'

        # O de-para dos três estados pt-BR. Fica aqui, e não em `Values`, porque
        # é o único consumidor — e porque `Charge::LEGACY_STATE_LABELS` é a
        # fonte: este Hash é o inverso dela, montado a partir dela para que os
        # dois nunca divirjam.
        CHARGE_STATE = {
          'Edição' => 'editing', 'Edicao' => 'editing',
          'Disponível' => 'available', 'Disponivel' => 'available',
          'Faturado' => 'done'
        }.freeze

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            user_id: ref('livetat_auth_users', row['user_id']),
            date: row['date'],
            state: Values.to_enum_key(row['state'], CHARGE_STATE,
                                      table: self.class.source_table, pk: row['id'], column: 'state').value,
            value: Values.to_decimal(row['value']),
            structured_operations_value: Values.to_decimal(row['structured_operations_value']),
            risk_operations_value: Values.to_decimal(row['risk_operations_value']),
            total_operations_value: Values.to_decimal(row['total_operations_value']),
            receipts_count: row['receipts_count'].to_i,
            risk_operations_count: row['risk_operations_count'].to_i,
            structured_operations_count: row['structured_operations_count'].to_i,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
