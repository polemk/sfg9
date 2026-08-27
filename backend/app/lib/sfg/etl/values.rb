# frozen_string_literal: true

module Sfg
  module Etl
    # Conversores de VALOR — a camada mais baixa do motor.
    #
    # Cada função aqui converte **um campo**, sem saber de que tabela veio. É o que
    # permite testá-las com par (entrada, saída) e é onde moram as três regras
    # transversais do legado: inteiro 0/1 como booleano, enum-string em pt-BR e
    # timestamp em horário local de Brasília com DST até 2019.
    #
    # **Nenhuma delas adivinha.** Valor fora do domínio conhecido levanta ou volta
    # marcado como anomalia — nunca vira um valor plausível.
    module Values
      ZONE_NAME = 'America/Sao_Paulo'

      OutOfDomain = Class.new(StandardError)

      Converted = Struct.new(:value, :anomaly, keyword_init: true) do
        def anomaly? = !anomaly.nil?
      end

      module_function

      def zone = @zone ||= ActiveSupport::TimeZone[ZONE_NAME]

      # ---------------------------------------------------------------- tempo
      #
      # DB-ETL-04 / DEC-06. **Não existe um `AT TIME ZONE` único que sirva**: o Brasil
      # teve horário de verão até 2019-02-16 e UTC-3 fixo depois. Offset fixo erra o
      # vencimento de parcela e a data de operação em todo o histórico de 2016–2018 —
      # é o D-102.
      #
      #   2017-01-15 10:00 (DST, UTC-2) -> 2017-01-15 12:00 UTC
      #   2022-01-15 10:00 (UTC-3)      -> 2022-01-15 13:00 UTC
      #
      # A conversão usa as transições da tz database, nunca aritmética de offset.
      def to_utc(local, table: nil, pk: nil, column: nil)
        naive = normalize_naive(local)
        return Converted.new(value: nil) if naive.nil?

        periods = zone.tzinfo.periods_for_local(naive)
        case periods.size
        when 0
          # Hora que NÃO EXISTE (virada de primavera). Não se inventa: a tz database
          # a desloca para o primeiro instante válido, e a linha vai para o relatório.
          shifted = zone.tzinfo.local_to_utc(naive + 3600, true)
          Converted.new(value: shifted,
                        anomaly: anomaly_line('hora inexistente (virada de primavera)', table, pk, column, naive))
        when 1
          Converted.new(value: zone.tzinfo.local_to_utc(naive, true))
        else
          # AMBÍGUA (virada de outono: a hora acontece duas vezes). Resolvida pela
          # regra padrão — prefere o período de verão — **e listada no relatório**.
          Converted.new(value: zone.tzinfo.local_to_utc(naive, true),
                        anomaly: anomaly_line('hora ambígua (virada de outono, resolvida para o horário de verão)',
                                              table, pk, column, naive))
        end
      end

      def normalize_naive(local)
        case local
        when nil then nil
        when Time, DateTime then Time.utc(local.year, local.month, local.day, local.hour, local.min, local.sec)
        when Date then Time.utc(local.year, local.month, local.day)
        when String
          return nil if local.strip.empty?

          parsed = Time.parse(local)
          Time.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.min, parsed.sec)
        end
      rescue ArgumentError
        nil
      end

      # ------------------------------------------------------------- booleano
      #
      # Regra D-E: **todo booleano do schema legado é `integer` 0/1**. A conversão é
      # `Sfg::Coercion.to_bool` (OPS-619), que já é a peça portada do initializer do
      # legado e levanta em valor desconhecido. Aqui o levantar vira **anomalia
      # contada**: o dry-run precisa reportar o `2` antes de a carga tropeçar nele.
      def to_boolean(value, table: nil, pk: nil, column: nil)
        Converted.new(value: Sfg::Coercion.to_bool(value))
      rescue ArgumentError
        Converted.new(value: nil,
                      anomaly: anomaly_line("booleano fora de {0,1}: #{value.inspect}", table, pk, column, value))
      end

      # ----------------------------------------------------------------- enum
      #
      # BE-445/BE-448: "Diferença"/"OK" e a natureza do tipo de movimentação são
      # **texto em pt-BR gravado na coluna** e comparado por igualdade de string —
      # trocar o rótulo na tela quebrava o histórico. Viram chave estável.
      #
      # O de-para é **tabela**. Texto fora dela **não vira `nil` nem `other`**: vira
      # anomalia, porque um status desconhecido virando `nil` esconde um borderô que
      # ninguém conferiu.
      RECEIVABLE_STATUS = {
        'OK' => 'ok',
        'Diferença' => 'difference',
        'Diferenca' => 'difference'
      }.freeze

      MOVEMENT_NATURE = {
        'Crédito' => 'credit',
        'Credito' => 'credit',
        'Débito' => 'debit',
        'Debito' => 'debit'
      }.freeze

      def to_enum_key(value, table_map, table: nil, pk: nil, column: nil)
        raw = value.to_s.strip
        return Converted.new(value: nil) if raw.empty?

        mapped = table_map[raw]
        return Converted.new(value: mapped) if mapped

        Converted.new(value: nil,
                      anomaly: anomaly_line("valor fora do de-para de enum: #{value.inspect}", table, pk, column,
                                            value))
      end

      # -------------------------------------------------------------- smart_id
      #
      # Os dois formatos convivem na origem, e um deles é resquício de MySQL
      # (`limit: 16777214` em colunas de `providers`). O conversor tolera os dois e
      # devolve string — o ai9 expõe `smart_id` por URL.
      MYSQL_MEDIUMTEXT_LIMIT = 16_777_214

      def to_smart_id(value)
        raw = value.to_s.strip
        return nil if raw.empty? || raw == MYSQL_MEDIUMTEXT_LIMIT.to_s

        raw
      end

      # ------------------------------------------------------------- dinheiro
      #
      # DB-ETL-06 / DEC-02. **A imprecisão é replicada de propósito**: `remunerations.value`
      # e `receipts.fee` são `float` multiplicando `decimal(15,2)`, e as ~30 taxas de
      # `receivable_entries` também são float. "Consertar" para BigDecimal aqui mudaria
      # o centavo do histórico e o painel deixaria de bater com o legado.
      #
      # O oráculo são os **testes golden de C2** (`golden/`), não um cálculo inventado
      # nesta fatia. Aqui só há o cast, sem arredondamento extra.
      def to_decimal(value)
        return nil if value.nil? || value.to_s.strip.empty?

        BigDecimal(value.to_s)
      rescue ArgumentError
        num = Sfg::Coercion.to_number(value.to_s)
        num.nil? ? nil : BigDecimal(num.to_s)
      end

      # **DEC-120 — número NÃO FINITO vira NULO, nunca zero.**
      #
      # `BigDecimal("NaN")` **não levanta**: devolve `NaN`. E `NaN` se propaga
      # por toda soma que o encontre — foi assim que um único deságio inválido
      # contaminou nove colunas do borderô 22424 em produção (D-10). Zero seria
      # pior do que nulo: nulo diz *"não sei quanto foi"*, zero **afirma** que a
      # tarifa foi de R$ 0,00 e some da tela sem deixar rastro.
      #
      # **Por que isto NÃO é o comportamento de `to_decimal`.** As 32 linhas de
      # `receivable_entries` com `NaN` em coluna de dinheiro ainda **não têm
      # disposição do usuário**; trocar o conversor genérico decidiria por ele em
      # 32 lugares além do único que ele decidiu. Quem chama esta função é quem
      # tem decisão escrita para a coluna dele.
      def to_decimal_finite(value)
        decimal = to_decimal(value)
        return nil if decimal.is_a?(BigDecimal) && (decimal.nan? || !decimal.finite?)

        decimal
      end

      def to_float(value)
        return nil if value.nil? || value.to_s.strip.empty?

        Float(value)
      rescue ArgumentError, TypeError
        Sfg::Coercion.to_number(value.to_s)
      end

      # -------------------------------------------------------------- indicador
      #
      # DEC-89: o título do indicador continua em CAIXA ALTA **sem acento**, porque é
      # assim que `indicator.rb:39` grava desde sempre e o histórico já chegou assim.
      # Isto é replicação consciente, não descuido — golden test trava e reprova quem
      # "consertar".
      def indicator_title(value) = I18n.transliterate(value.to_s).upcase

      def anomaly_line(reason, table, pk, column, value)
        parts = []
        parts << "`#{table}`" if table
        parts << "pk=#{pk}" if pk
        parts << "`#{column}`" if column
        "- #{parts.join(' ')} — #{reason}#{value.nil? ? '' : " (origem: #{value.inspect})"}"
      end
    end
  end
end
