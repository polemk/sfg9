# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_entries` (legado) -> `RiskEntry` (ai9). **Escrito pela S5.**
      #
      # **DEC-57: o dado sobrevive, a tela não volta.** Não há endpoint nem
      # superfície para `risk_entries` no ai9 — este conversor existe justamente
      # porque a tabela tem dado em produção e não carregá-la seria perda.
      #
      # **Quanta perda:** `.migration-ai9/analise-dump-producao.md` §2, consulta 4
      # — **642.447 linhas**, com dado até **31/05/2025**. É a **maior tabela do
      # sistema**. A rotina de conversão do legado
      # (`generate_new_controls_on_migration`) faz `risk_entries.destroy_all`
      # antes de apagar o limite antigo; não é conversão, é perda, e é por isso
      # que a expansão em linhas tipadas (`RiskControls#expand_typed_controls!`)
      # **preserva a linha herdada** em vez de apagá-la: é nela que estas 642 mil
      # posições se penduram.
      #
      # ### Os cinco totais são DERIVADOS, e por isso não se comparam
      #
      # `total_carteira_value`, `total_reducoes_value` e os três `*_total_value`
      # são recalculados pelo `before_validation` do model a partir das dez
      # parcelas. Copiá-los da origem e depois compará-los acusaria divergência em
      # toda linha em que o legado tenha gravado um total inconsistente — e o
      # legado gravava, porque lá o cálculo também era no `before_validation` mas
      # nada impedia um `update_column`.
      #
      # Eles vão no `convert` mesmo assim, com o valor calculado das parcelas: o
      # motor grava por `insert_all` (sem callbacks), então o model não teria
      # chance de derivá-los. `derived` diz à reconciliação para não os comparar
      # literalmente.
      #
      # ### `observacoes` → `observation`
      #
      # É a única coluna renomeada. Os nomes de domínio (`vencidos_value`,
      # `fomento_total_value`…) ficam como no legado — a tabela não tem leitor de
      # código, e traduzir os 15 campos só acrescentaria risco de mapeamento. O
      # genérico foi alinhado ao resto do bloco (`risk_operations`,
      # `risk_movements` já usam `observation`).
      class RiskEntries < Base
        # `total_carteira_value` etc.: coluna do ai9 => as duas parcelas.
        DERIVED_TOTALS = {
          total_carteira_value: %w[vencidos_value a_vencer_value],
          total_reducoes_value: %w[liquidacao_value descontos_value],
          comissaria_total_value: %w[comissaria_vencidos_value comissaria_a_vencer_value],
          fomento_total_value: %w[fomento_vencidos_value fomento_a_vencer_value],
          intercompany_total_value: %w[intercompany_vencidos_value intercompany_a_vencer_value]
        }.freeze

        PARCELAS = %w[
          vencidos_value a_vencer_value liquidacao_value descontos_value
          comissaria_vencidos_value comissaria_a_vencer_value
          fomento_vencidos_value fomento_a_vencer_value
          intercompany_vencidos_value intercompany_a_vencer_value
        ].freeze

        def self.source_table = 'risk_entries'
        def self.target_model = 'RiskEntry'
        def self.requires = %w[RiskEntry RiskControl Company Project]
        def self.owner_slice = 'S5'
        # `has_safegold_management` é `integer` 0/1 na origem (D-30) — declarada
        # para o `scan` conferir anomalias de valor, como nas outras cinco.
        def self.booleans = %w[has_safegold_management]

        def self.references = {
          'project_id' => 'projects',
          'company_id' => 'companies',
          'risk_control_id' => 'risk_controls'
        }

        def self.uniques = [%w[date risk_control_id company_id]]
        def self.sums = PARCELAS
        def self.year_column = 'date'
        def self.derived = DERIVED_TOTALS.keys.map(&:to_s) + %w[risk_control_title]

        def convert(row)
          base = {
            # Derivado da EMPRESA, não copiado: é o que o model faz
            # (`RiskEntry#derive_scope_and_totals`), e a coluna `project_id` da
            # origem pode não existir — a tabela é de 2021. Uma regra só.
            project_id: ref('projects', row['project_id']) ||
                        ::Company.where(id: ref('companies', row['company_id'])).pick(:project_id),
            # DEC-112 — CARIMBO histórico, vindo da origem. Se o callback o
            # recopiasse do projeto/empresa, o valor de hoje apagaria a foto do
            # momento — ver `SafegoldStamped`.
            has_safegold_management: Values.to_boolean(row['has_safegold_management']).value,
            company_id: ref('companies', row['company_id']),
            risk_control_id: ref('risk_controls', row['risk_control_id']),
            date: row['date'],
            risk_control_title: row['risk_control_title'],
            observation: row['observacoes'],
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }

          PARCELAS.each { |coluna| base[coluna.to_sym] = Values.to_decimal(row[coluna]) }

          # Derivados na carga. A regra é a MESMA de
          # `RiskEntry#derive_scope_and_totals` — se uma mudar, a outra muda junto
          # —, com a exceção que a DEC-129.2 abriu (ver `total_preservado`).
          preservou = false
          DERIVED_TOTALS.each do |destino, parcelas|
            derivado = parcelas.sum { |coluna| Values.to_decimal(row[coluna]) || 0 }
            origem = Values.to_decimal(row[destino.to_s])
            if preservar_total?(derivado, origem)
              base[destino] = origem
              preservou = true
            else
              base[destino] = derivado
            end
          end
          # O model recalcularia zero por cima no `before_validation`. A chave é
          # ligada **por linha**, e só quando houve o que preservar.
          base[:preserve_legacy_totals] = true if preservou

          base
        end

        # **DEC-129.2 — o total da origem vence quando as parcelas vierem zeradas.**
        #
        # *"manter como é no legado"* (palavras do usuário). Medido no dump de
        # 31/05/2025: **4.082 linhas**, 161 limites, 19 projetos,
        # **R$ 4.884.851.467,94**, entre 28/01/2022 e 14/04/2022.
        #
        # Nessas linhas o legado tem a abertura por modalidade nos TOTAIS
        # (`comissaria_total_value`, `fomento_total_value`,
        # `intercompany_total_value`) e as duas parcelas correspondentes zeradas.
        # Derivar das parcelas mantém a contagem batendo (4.082/4.082) e **apaga o
        # detalhe** — a tela de limites daquele período deixa de ser legível por
        # modalidade, que é exatamente como ela mostra.
        #
        # A condição é estreita de propósito: só quando o derivado é **zero** e a
        # origem **não é**. Total da origem que diverge das parcelas em qualquer
        # outro sentido continua sendo o derivado — ali o legado gravou um total
        # inconsistente (era `before_validation` lá também, e `update_column`
        # passava por cima), e copiá-lo seria propagar o erro.
        def preservar_total?(derivado, origem)
          derivado.zero? && !origem.nil? && !origem.zero?
        end

        # DEC-129.2 — as linhas preservadas saem LISTADAS, com a modalidade, o
        # total da origem e as parcelas zeradas lado a lado. Sem a lista, "4.082
        # linhas mantiveram o total" é uma afirmação que ninguém pode conferir.
        def anomalies(row)
          DERIVED_TOTALS.filter_map do |destino, parcelas|
            derivado = parcelas.sum { |coluna| Values.to_decimal(row[coluna]) || 0 }
            origem = Values.to_decimal(row[destino.to_s])
            next unless preservar_total?(derivado, origem)

            {
              key: 'risk_entries:legacy_total_without_installments',
              title: 'DEC-129.2 — abertura por modalidade preservada da origem',
              line: Values.anomaly_line(
                "total da origem PRESERVADO (#{origem.to_s('F')}) porque as parcelas "                 "#{parcelas.join(' + ')} vieram zeradas. Derivar daria 0,00 e apagaria a abertura "                 "por modalidade da tela de limites.",
                self.class.source_table, row['id'], destino.to_s, row[destino.to_s]
              )
            }
          end
        end

        # DEC-57 pede a contagem: se `risk_entries` vier **vazia** do dump, a
        # fatia R8 inteira vira descarte com evidência, e o model pode sair.
        def self.post_load!
          return { rows: 0 } unless model_ready?('RiskEntry')

          total = ::RiskEntry.count
          {
            rows: total,
            note: if total.zero?
                    'DEC-57: a origem não tinha nenhuma posição diária. R8 vira descarte com evidência.'
                  else
                    "DEC-57: #{total} posição(ões) diária(s) preservada(s). Sem endpoint e sem tela, " \
                    'como no legado — a decisão de trazer a tela de volta continua aberta.'
                  end
          }
        end
      end
    end
  end
end
