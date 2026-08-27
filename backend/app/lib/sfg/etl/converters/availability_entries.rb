# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `availability_entries` (legado) -> `AvailabilityEntry` (ai9). **S11.**
      #
      # É a **maior tabela do módulo** (projetos × empresas × padrões × dias) e a
      # única que, no legado, não tem **nenhum** índice: a migration cria sete
      # colunas e nada mais.
      #
      # ## ATENÇÃO — três colunas desta tabela NÃO existem em produção
      #
      # A análise do dump (26/08/2026) mostrou que a última migration aplicada em
      # produção é de **25/05/2022** e que **24 migrations nunca subiram**. Três
      # delas são desta fatia:
      #
      #  - `add_company_column_to_availability_entries`
      #  - `add_original_value_column_to_availability_entries`
      #  - `add_is_adjusted_column_to_availability_templates`
      #
      # Ou seja: em produção **não há multiempresa, não há consolidação e não há
      # correção por dias úteis** nesta tabela. As 23.674 linhas são um
      # lançamento por (projeto, padrão, data), com `value` e `virtual_value`.
      # Este conversor tolera as três ausências — `row['coluna']` devolve `nil` —
      # e o `Sfg::Etl::Introspection` reporta o que encontrou (DEC-04).
      #
      # ## Os valores são COPIADOS, não recalculados
      #
      # `value`, `original_value` e `virtual_value` entram exatamente como estão.
      # A **DEC-24** foi explícita: *"o ETL de S14 NÃO reconstitui
      # `original_value`: ele copia o que estiver lá"*. Recalcular significaria
      # aplicar de novo a correção por dias úteis sobre um valor que já foi
      # corrigido N vezes — e ninguém sabe qual é o N.
      #
      # A rake `sfg:availability:report` mede o estrago; a carga não o conserta.
      #
      # ## A marca de consolidação passa a ser EXPLÍCITA (DB-126)
      #
      # No legado "é consolidação" era inferido de `company_id IS NULL`. O
      # problema é que a rotina `fix__7412` **reatribuiu empresa nula à primeira
      # empresa do projeto** (`availability_entry.rb`, `p.availability_entries
      # .where(company_id: nil).update_all(company_id: p.companies.first.id)`),
      # então a inferência não distingue mais consolidação legítima de dado sujo.
      # A carga marca `is_consolidation` pelo que o dado diz **hoje** e o
      # relatório aponta os grupos suspeitos.
      class AvailabilityEntries < Base
        def self.source_table = 'availability_entries'
        def self.target_model = 'AvailabilityEntry'
        def self.requires = %w[AvailabilityEntry AvailabilityTemplate Project Company]
        def self.owner_slice = 'S11'
        # `has_safegold_management` é `integer` 0/1 na origem (D-30) — declarada
        # para o `scan` conferir anomalias de valor, como nas outras cinco.
        def self.booleans = %w[has_safegold_management]

        def self.references = {
          'project_id' => 'projects',
          'company_id' => 'companies',
          'availability_template_id' => 'availability_templates',
          'user_id' => 'livetat_auth_users'
        }

        def self.uniques = [%w[project_id company_id availability_template_id date]]
        def self.sums = %w[value original_value virtual_value]

        # `is_consolidation` é derivado na carga; `title` é reescrito pelo
        # `before_validation` do model a partir do padrão. Sem declarar, a
        # reconciliação acusaria divergência em toda linha.
        def self.derived = %w[is_consolidation title]

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            # DEC-112 — CARIMBO histórico, vindo da origem. Se o callback o
            # recopiasse do projeto/empresa, o valor de hoje apagaria a foto do
            # momento — ver `SafegoldStamped`.
            has_safegold_management: Values.to_boolean(row['has_safegold_management']).value,
            company_id: ref('companies', row['company_id']),
            availability_template_id: ref('availability_templates', row['availability_template_id']),
            # **`company_id` NÃO EXISTE em produção.** A migration
            # `add_company_column_to_availability_entries` (ago/2022) está no
            # repositório e **nunca rodou**: a última migration aplicada em
            # produção é de 25/05/2022. Sem a coluna, a origem não tem
            # consolidação nenhuma — cada linha é um lançamento comum.
            #
            # `row['company_id'].blank?` sozinho marcaria **todas** as 23.674
            # linhas como consolidação, e no ai9 consolidação é derivada e
            # **não editável**: o cliente abriria a grade e não conseguiria
            # digitar em célula nenhuma. Por isso a marca exige que a coluna
            # EXISTA na origem.
            is_consolidation: row.key?('company_id') && row['company_id'].blank?,
            title: row['title'],

            # **Copiados como estão** — DEC-24.
            value: Values.to_decimal(row['value']),
            # `original_value` **NAO EXISTE na origem** — conferido no
            # `information_schema` contra o dump de producao: a tabela tem `value` e
            # `virtual_value`, e so. A migration
            # `add_original_value_column_to_availability_entries` e uma das que **nunca
            # subiram** em producao.
            #
            # Sem ela, `row['original_value']` e nil, a coluna do destino e `null: false`
            # e a carga morria com `NotNullViolation` — que passa por baixo do rescue do
            # motor, porque e restricao do BANCO e nao validacao do model.
            #
            # **Isto NAO contraria a DEC-24**, que proibe RECONSTITUIR o valor original
            # (aplicar de novo a correcao por dias uteis sobre um valor ja corrigido N
            # vezes, com N desconhecido). Aqui nao ha reconstituicao: num banco onde a
            # coluna nunca existiu, nao ha valor original separado a copiar — o original
            # E o valor. Copiar `value` e a leitura fiel, e a unica que nao inventa.
            original_value: Values.to_decimal(row['original_value'] || row['value']),
            virtual_value: Values.to_decimal(row['virtual_value']),

            date: row['date'],
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          linhas = []

          if row['date'].blank?
            linhas << Values.anomaly_line(
              'lançamento sem data — o ai9 tem `null: false` e a linha será recusada',
              'availability_entries', row['id'], 'date', nil
            )
          end

          # **Relatório 1 do `design.md` §8** — o par (`value`, `original_value`)
          # é INCONSISTENTE com uma única aplicação da correção por dias úteis.
          #
          # O que isto detecta, exatamente: linhas em que `value` não é
          # `original_value × (dias úteis até a data ÷ dias úteis do mês)`. Numa
          # linha corrigida uma vez só, a igualdade vale. Ela deixa de valer
          # quando houve **decaimento composto** (D-02), quando o padrão mudou de
          # `is_adjusted` depois do lançamento, ou quando alguém editou o valor à
          # mão no banco.
          #
          # O que NÃO detecta: **quantas vezes** a correção foi reaplicada. Isso
          # o dado não guarda, e nenhum relatório pode inventar.
          if inconsistent_adjustment?(row)
            linhas << Values.anomaly_line(
              'valor e valor-base INCONSISTENTES com uma única correção por dias úteis — sinal de ' \
              'decaimento composto (D-02 / DEC-24). O valor é copiado como está, de propósito',
              'availability_entries', row['id'], 'value', row['value']
            )
          end

          linhas
        end

        private

        def inconsistent_adjustment?(row)
          data = row['date']
          return false if data.blank?

          base = Values.to_decimal(row['original_value'])
          valor = Values.to_decimal(row['value'])
          return false if base.nil? || valor.nil? || base.zero?
          # Igual significa "não corrigido", e não corrigido não é anomalia.
          return false if base == valor

          data = Date.parse(data.to_s) if data.is_a?(String)
          esperado = (base.to_d * Sfg::BusinessDays.multiplier(data)).round(2)
          (esperado - valor).abs > BigDecimal('0.02')
        rescue ArgumentError, TypeError
          false
        end
      end
    end
  end
end
