# frozen_string_literal: true

module Demo
  module Support
    # Dinheiro e encargos do seed.
    #
    # `demo-seed-design.md` §3, princípio 2: **`R$ 1.000.000,00` grita seed**. Todo
    # valor que sai daqui tem centavo, e nenhum é múltiplo de mil. É a diferença
    # entre um número que passa despercebido e um que entrega o ambiente.
    module Money
      # IOF de crédito para pessoa jurídica, pela regra que vale de verdade:
      # **0,0082% ao dia sobre o principal, limitado a 365 dias, mais 0,38%
      # adicional**. Cinco linhas, e é o que faz um analista de crédito reconhecer
      # a conta em vez de conferir e descartar.
      IOF_DAILY_RATE = 0.000082
      IOF_ADDITIONAL_RATE = 0.0038
      IOF_MAX_DAYS = 365

      module_function

      def round2(value)
        (value.to_f * 100).round / 100.0
      end

      # Arredonda para 2 casas **garantindo que não fique redondo**: centavos não
      # nulos e valor não múltiplo de mil.
      def natural(value, stream)
        base = round2(value)
        cents = ((base * 100).round % 100)
        base += (stream.int(3, 97) - cents) / 100.0 if cents.zero?
        base += stream.int(1, 9) if (base % 1000).abs < 0.005
        round2(base)
      end

      def iof(principal, days)
        capped = [days.to_i, IOF_MAX_DAYS].min
        round2(principal.to_f * ((IOF_DAILY_RATE * capped) + IOF_ADDITIONAL_RATE))
      end

      # Juros compostos ao mês aplicados sobre um período em dias — a forma como o
      # deságio de um borderô é calculado no desconto de duplicata.
      def monthly_interest(principal, monthly_rate, days)
        round2(principal.to_f * (((1 + (monthly_rate / 100.0))**(days / 30.0)) - 1))
      end

      def brl(value)
        int, frac = format('%.2f', value.to_f).split('.')
        sign = int.start_with?('-') ? '-' : ''
        int = int.delete('-')
        grouped = int.reverse.scan(/\d{1,3}/).join('.').reverse
        "#{sign}R$ #{grouped},#{frac}"
      end
    end
  end
end
