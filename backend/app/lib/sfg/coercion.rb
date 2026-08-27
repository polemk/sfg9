# frozen_string_literal: true

module Sfg
  # Coerção booleana e de moeda — OPS-619.
  #
  # No legado isto era `config/initializers/type_casting.rb`, o initializer com **mais
  # regra de negócio do sistema inteiro**: `String#to_bool`, `Integer#to_bool`,
  # `NilClass#to_bool`, `TrueClass#to_i` e um módulo `Currency` reaberto em `String`,
  # `Integer`, `Float` e `BigDecimal`.
  #
  # Por que vira helper explícito e não monkey patch: coerção em nível de linguagem
  # produz a classe de bug "por que este `\"false\"` virou `true` aqui e não ali" — e
  # aqui ela decide centavo. Reabrir `String` na base ai9 espalharia esse risco por
  # todo código que nunca ouviu falar do Safegold. Chamada explícita aparece no diff e
  # no grep; `String#to_bool` não aparece em nenhum dos dois.
  #
  # **O comportamento numérico é preservado, inclusive onde é estranho.** Os casos
  # estão em `golden/coercion.json`, extraídos executando o initializer do legado. Em
  # especial: `to_number("1.234,56")` devolve `nil`, porque o `numeric?` do legado
  # aceita **um** separador só — e `to_number("1.234")` devolve `1.234`, não `1234`.
  # Isso não é bug a corrigir aqui; é o valor que o legado gravou por anos. Quem
  # quiser mudar muda com o golden test apontando exatamente o que muda.
  module Coercion
    TRUTHY = /\A(true|t|yes|y|s|sim|1)\z/i
    FALSY  = /\A(false|f|no|n|não|0)\z/i

    # Aceita **um** separador, decimal ou milhar — indistintamente. É a regra do
    # legado, copiada carácter a carácter de `Currency::String#numeric?`.
    NUMERIC = /\A(|-)?[0-9]+((\.|,)[0-9]+)?\z/

    BRL = { delimiter: '.', separator: ',', unit: 'R$', precision: 2, position: 'before' }.freeze

    module_function

    # Coerção booleana. Levanta `ArgumentError` no que não reconhece — como o legado:
    # engolir entrada desconhecida como `false` é o jeito de um "2" virar "não".
    def to_bool(value)
      case value
      when true, false then value
      when nil then false
      when Integer
        return true if value == 1
        return false if value.zero?

        raise ArgumentError, "invalid value for Boolean: \"#{value}\""
      when String
        return true if value.match?(TRUTHY)
        return false if value.strip.empty? || value.match?(FALSY)

        raise ArgumentError, "invalid value for Boolean: \"#{value}\""
      else
        raise ArgumentError, "invalid value for Boolean: \"#{value}\""
      end
    end

    # `true` → 1, `false` → 0. No legado era `TrueClass#to_i`/`FalseClass#to_i`.
    def bool_to_i(value)
      to_bool(value) ? 1 : 0
    end

    def numeric?(value)
      value.is_a?(String) && value.match?(NUMERIC)
    end

    # String → Float, ou `nil`. Ver a nota do módulo antes de "consertar".
    def to_number(value)
      return nil unless numeric?(value)

      value.tr(',', '.').to_f
    end

    # Float/Integer/BigDecimal → "R$1.234,56". Reproduz `Currency::Number#to_currency`,
    # inclusive o sinal negativo DEPOIS da unidade ("R$-1.234,56") e o arredondamento
    # do `"%1.2f"`, que é o do printf e não o do `round` do Ruby.
    def to_currency(number, options = {})
      opts = BRL.merge(options)
      precision = opts[:precision]
      separator = precision.positive? ? opts[:separator] : ''

      parts = with_precision(number, precision).split('.')
      formatted = with_delimiter(parts[0].to_i, opts[:delimiter]) + separator + parts[1].to_s

      opts[:position] == 'before' ? "#{opts[:unit]}#{formatted}" : "#{formatted}#{opts[:unit]}"
    rescue StandardError
      number
    end

    def with_delimiter(number, delimiter = ',', separator = '.')
      parts = number.to_s.split(separator)
      parts[0] = parts[0].gsub(/(\d)(?=(\d\d\d)+(?!\d))/) { "#{Regexp.last_match(1)}#{delimiter}" }
      parts.join(separator)
    rescue StandardError
      number
    end

    def with_precision(number, precision = 3)
      format("%1.#{precision}f", number)
    end
  end
end
