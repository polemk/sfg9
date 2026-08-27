# frozen_string_literal: true

module Sfg
  # S6 / **OPS-159 (parte de backend)** — **nulo não é zero.** Corrige o
  # **D-117**.
  #
  # ## O defeito
  #
  # No legado toda exibição monetária passa por `to_currency`
  # (`../sfg/config/initializers/type_casting.rb:49-83`), que faz
  # `number.with_precision(2)` sobre `value.to_f` — e `nil.to_f` é `0.0`. Num
  # sistema de crédito, **"não informado" e "zero" viraram o mesmo `R$ 0,00`**
  # na tela: "sem retenção" e "retenção de zero reais" são coisas diferentes
  # para quem confere um borderô.
  #
  # ## Uma implementação, não duas (contrato C2, Princípio 6b)
  #
  # A **composição** do número — `%1.2f`, ponto de milhar, vírgula decimal,
  # sinal colado no primeiro grupo — já existe em `Risk::Money.brl`, replicada
  # byte a byte do legado pela S5 porque os `formatted_*` do painel de exposição
  # **fazem parte do contrato de paridade** (D-95 / DEC-01). Reescrevê-la aqui
  # daria duas formatações que divergem no dia em que uma for "consertada".
  #
  # Então este módulo **delega** a composição e acrescenta a única coisa que
  # falta: o `nil` que continua `nil`. `Risk::Money` fica como está, e o
  # comentário dele explica por quê.
  #
  # No front o par é `frontend/src/lib/format/money.ts`, com a mesma regra:
  # nulo rende travessão, zero rende `R$ 0,00`.
  module Money
    module_function

    # `nil` devolve `nil` — quem exibe decide o travessão. Qualquer número
    # devolve exatamente o que o legado devolveria.
    def format(value)
      return nil if value.nil?

      ::Risk::Money.brl(value)
    end

    # Com o símbolo, para relatório e log — onde não há tela para pôr o "R$".
    def with_symbol(value, blank: '—')
      formatado = format(value)
      formatado.nil? ? blank : "R$ #{formatado}"
    end
  end
end
