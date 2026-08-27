# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `receivable_taxes` (legado) -> `ReceivableTax` (ai9). **S6**, **DB-161**.
      #
      # **58.473 linhas em produção.** Conferido no dump: **zero órfãs** — toda
      # tarifa aponta para um borderô que existe.
      #
      # ## Título e classificadores vêm da ORIGEM, não do `MovementKind` atual
      #
      # É denormalização deliberada (D-B13): a tarifa guarda a classificação do
      # **dia do lançamento**. Se este conversor relesse os flags do
      # `MovementKind`, uma reclassificação feita entre 2022 e hoje reescreveria
      # a base do IOF de borderôs históricos — 28 mil números mudando por causa
      # de uma edição de catálogo.
      #
      # ## A conferência que este conversor sustenta
      #
      # Somando as tarifas por borderô e comparando com os `tarifas_*`
      # denormalizados de `receivable_entries`: **28.127 de 28.131 batem**. Os
      # quatro que não batem (21608, 21871, 21872, 26246) são o **D-09** no
      # dado — no legado o recálculo do pai dependia de o JavaScript da tela
      # chamar `update_and_save()`. Os quatro vêm como estão e o relatório os
      # nomeia; "consertar" a soma aqui apagaria a evidência do defeito.
      class ReceivableTaxes < Base
        def self.source_table = 'receivable_taxes'
        def self.target_model = 'ReceivableTax'
        def self.owner_slice = 'S6'

        def self.references
          {
            'receivable_entry_id' => 'receivable_entries',
            'movement_kind_id' => 'movement_kinds'
          }
        end

        # Os três textos que o Postgres aceita em coluna `numeric` e que
        # **não são número**. `numeric` guarda `NaN` — foi por essa porta que o
        # D-10 entrou.
        NONFINITE = %w[NaN Infinity -Infinity].freeze

        def self.booleans = %w[is_advalorem is_desagio is_iof]
        def self.sums = %w[value]

        def convert(row)
          {
            receivable_entry_id: ref('receivable_entries', row['receivable_entry_id']),
            movement_kind_id: ref('movement_kinds', row['movement_kind_id']),
            # **DEC-120** — `NaN` entra como NULO, não como zero. Ver
            # `Values.to_decimal_finite` e `anomalies` abaixo.
            value: Values.to_decimal_finite(row['value']),
            title: row['title'],
            is_advalorem: Values.to_boolean(row['is_advalorem']).value,
            is_desagio: Values.to_boolean(row['is_desagio']).value,
            is_iof: Values.to_boolean(row['is_iof']).value,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Dois classificadores na mesma tarifa fazem o valor contar em dois
        # buckets **e** `tarifas_outras` ficar negativa. Conferido no dump:
        # nenhuma das 58.473 tem. O relatório existe para o dia em que tiver.
        def anomalies(row)
          linhas = []
          marcados = %w[is_advalorem is_desagio is_iof].count { |c| Values.to_boolean(row[c]).value }
          if marcados > 1
            linhas << Values.anomaly_line(
              "#{marcados} classificadores na mesma tarifa: o valor conta em dois buckets e " \
              '`tarifas_outras` fica NEGATIVA. Replicado (DEC-02), reportado aqui.',
              self.class.source_table, row['id'], 'is_advalorem/is_desagio/is_iof', marcados
            )
          end
          # **DEC-120, e é por isso que o borderô PAI aparece na linha.** A
          # decisão manda listar *"a linha e o borderô pai"*: quem for conferir
          # precisa do número do borderô, não do id da tarifa — é pelo borderô
          # que se abre a tela.
          if NONFINITE.include?(row['value'].to_s.strip)
            linhas << Values.anomaly_line(
              "D-10 / DEC-120 — valor não finito na tarifa: CARREGADA COM VALOR NULO (desconhecido), " \
              "não zero. Borderô pai (legado): `receivable_entries` id=#{row['receivable_entry_id']}. " \
              'As somas do borderô ignoram tarifa nula e a tela sinaliza o borderô.',
              self.class.source_table, row['id'], 'value', row['value']
            )
          end
          linhas
        end
      end
    end
  end
end
