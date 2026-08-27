# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_operations` (legado) -> `RiskOperation` (ai9).
      #
      # **Este conversor esta escrito e HOJE ele PULA**, porque `RiskOperation` ainda
      # nao existe no ai9 — o model chega na S7. E de proposito: e o mecanismo que faz
      # o ETL ser executavel antes de a ultima fatia de dominio terminar. O relatorio
      # diz o nome do model e o nome da fatia, e a proxima execucao o inclui sozinha.
      #
      # **DEC-36 — o valor da operacao e COPIADO, sem recalculo.** `operation_value`
      # entra exatamente como esta no legado, ou seja calculado **sem as tarifas**, por
      # causa do D-11 (`receivable_entry.rb:161` dispara no primeiro `save`, quando
      # ainda nao existe `ReceivableTax`). Nao ha relatorio de delta como pre-condicao
      # de carga: o painel de exposicao do ai9 bate 100% com o do legado **e o dado
      # errado vai junto**, por escolha consciente do usuario.
      #
      # **Fronteira temporal, registrada aqui para ninguem ler como bug:** borderos
      # novos criados no ai9 nascem com a operacao APOS as tarifas. Convivem dois
      # regimes — historico sem tarifas, novo com.
      #
      # ---------------------------------------------------------------------------
      # ACRESCENTADO PELA S5 (decisao B-08) — `is_static` e as datas sentinela
      # ---------------------------------------------------------------------------
      #
      # O par estatico pre/antecipacao do legado e mantido dentro de toda janela de
      # data por SENTINELAS: `DateTime.dinosaurs` (ano -2000) e `DateTime.mars`
      # (ano +2000), gravadas em `issue_date`/`due_date`
      # (`../sfg/app/models/risk_control.rb:32-33,49-50`).
      #
      # No ai9 essas linhas tem `is_static = true` e as duas datas **nulas**, e ha
      # **check constraint** garantindo a exclusividade: ou e estatica com as duas
      # datas nulas, ou e normal com as duas preenchidas. Sem o mapeamento abaixo a
      # carga estouraria na primeira operacao estatica, na janela de cutover.
      #
      # O reconhecimento e por ANO fora da faixa plausivel — nao por valor exato —
      # porque o legado gravou as sentinelas com o fuso do servidor e a data
      # resultante varia em algumas horas.
      class RiskOperations < Base
        def self.source_table = 'risk_operations'
        def self.target_model = 'RiskOperation'
        def self.requires = %w[RiskOperation RiskControl Company Carrier Project]
        def self.owner_slice = 'S7'

        def self.references = {
          'user_id' => 'livetat_auth_users', 'project_id' => 'projects',
          'company_id' => 'companies', 'carrier_id' => 'carriers',
          'risk_control_id' => 'risk_controls', 'receivable_id' => 'receivable_entries',
          'operation_type_id' => 'risk_operation_types', 'operation_subtype_id' => 'risk_operation_subtypes',
          'original_id' => 'risk_operations', 'pair_id' => 'risk_operations'
        }

        def self.booleans = %w[is_on_variable is_ended]
        # `is_static` e as duas datas sao DERIVADAS das sentinelas da origem (B-08),
        # nao copiadas — comparar literalmente acusaria divergencia em todo par.
        def self.derived = %w[is_static issue_date due_date]

        # Fora desta faixa a data e sentinela, nao data. O legado usa ano -2000 e
        # ano +2000; a faixa e larga de proposito.
        STATIC_YEAR_RANGE = (1900..2200).freeze
        def self.uniques = [%w[project_id contract_number]]
        def self.sums = %w[operation_value original_balance balance]
        def self.year_column = 'issue_date'

        def convert(row)
          {
            title: row['title'],
            user_id: ref('livetat_auth_users', row['user_id']),
            project_id: ref('projects', row['project_id']),
            company_id: ref('companies', row['company_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            risk_control_id: ref('risk_controls', row['risk_control_id']),
            receivable_id: ref('receivable_entries', row['receivable_id']),
            operation_type_id: ref('risk_operation_types', row['operation_type_id']),
            operation_subtype_id: ref('risk_operation_subtypes', row['operation_subtype_id']),
            original_id: ref('risk_operations', row['original_id']),
            pair_id: ref('risk_operations', row['pair_id']),
            contract_number: row['contract_number'],
            # B-08: sentinela vira `is_static` + datas nulas.
            is_static: static_pair?(row),
            issue_date: static_pair?(row) ? nil : row['issue_date'],
            due_date: static_pair?(row) ? nil : row['due_date'],
            original_due_date: static_pair?(row) ? nil : row['original_due_date'],
            # DEC-36: copia crua. Nao ha `recalculate` nesta linha, e nao deve passar a haver.
            operation_value: Values.to_decimal(row['operation_value']),
            original_balance: Values.to_decimal(row['original_balance']),
            balance: Values.to_decimal(row['balance']),
            agreed_rate: Values.to_float(row['agreed_rate']),
            observation: row['observation'],
            is_on_variable: Values.to_boolean(row['is_on_variable']).value,
            is_ended: Values.to_boolean(row['is_ended']).value,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Uma das duas datas fora da faixa plausivel basta: e o par estatico do
        # limite, com as sentinelas de +-2000 anos do legado.
        def static_pair?(row)
          [row['issue_date'], row['due_date']].any? { |valor| sentinel_date?(valor) }
        end

        def sentinel_date?(valor)
          return false if valor.blank?

          ano = valor.respond_to?(:year) ? valor.year : Date.parse(valor.to_s).year
          !STATIC_YEAR_RANGE.cover?(ano)
        rescue ArgumentError, TypeError
          false
        end
      end
    end
  end
end
