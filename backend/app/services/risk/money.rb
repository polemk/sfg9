# frozen_string_literal: true

module Risk
  # S5 — **a formatação monetária do legado, replicada byte a byte**.
  #
  # Existe porque os `formatted_*` do payload de exposição **fazem parte do
  # contrato de paridade**: é neles que vivem os dois erros de rótulo do D-95,
  # que a **DEC-01** manda preservar. Se o front formatasse os números por conta
  # própria, ele "consertaria" o D-95 sem ninguém decidir isso — e passaria a
  # haver duas implementações da mesma composição, que é o que o contrato **C2**
  # existe para impedir.
  #
  # A fonte é `../sfg/config/initializers/type_casting.rb:49-83`:
  #
  # ```ruby
  # parts  = number.with_precision(2).split('.')      # "%1.2f" % number
  # number = parts[0].to_i.with_delimiter('.') + ',' + parts[1].to_s
  # "R$" + number                                      # unit colado, sem espaço
  # ```
  #
  # e todos os call sites do módulo de risco fazem `.to_currency.gsub("R$", "")`
  # logo depois — ou seja, o que chega à tela é **sem** o "R$". É esse o valor
  # que este módulo produz.
  #
  # Detalhe que importa e é fácil de perder: o delimitador de milhar é aplicado
  # sobre `parts[0].to_i`, então o sinal negativo fica **colado** no primeiro
  # grupo (`-27.500,00`), e o zero à esquerda desaparece (`0,50`, nunca `,50`).
  module Money
    module_function

    # `x.to_currency.gsub("R$", "")` do legado.
    def brl(value)
      numero = value.to_f
      inteiro, decimais = format('%1.2f', numero).split('.')
      "#{with_delimiter(inteiro)},#{decimais}"
    end

    # `with_delimiter('.')` — agrupa de três em três da direita para a esquerda.
    def with_delimiter(inteiro)
      inteiro.to_i.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/) { "#{Regexp.last_match(1)}." }
    end

    # `sprintf('%.2f', perc) + "%"` — o percentual do cabeçalho agregado
    # (`../sfg/app/models/company.rb:41`). Ponto decimal, não vírgula: é assim
    # que sai hoje.
    def percent(value)
      "#{format('%.2f', value.to_f)}%"
    end
  end
end
