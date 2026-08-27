# frozen_string_literal: true

module Sfg
  # S11 / BE-127, DC-29 — **dias úteis**, a base da correção de valor.
  #
  # No legado isto era um monkey patch em `Date`
  # (`app/decorators/models/date_decorator.rb`):
  #
  #     def business_days_in_this_month
  #       (self.beginning_of_month..self.end_of_month).to_a.reject { |d| d.cwday == 7 || d.cwday == 6 }.count
  #     end
  #
  #     def business_days_until_now
  #       (self.beginning_of_month..self).to_a.reject { |d| d.cwday == 7 || d.cwday == 6 }.count
  #     end
  #
  # **Duas coisas que parecem erradas e são replicadas de propósito:**
  #
  # 1. **Nenhum feriado entra na conta** — só sábado e domingo saem. É o defeito
  #    **D-03**, e a **DEC-28** o manteve conscientemente: em todo mês com
  #    feriado o multiplicador de correção fica alto, como sempre esteve.
  #    Incluir feriados mudaria o resultado financeiro de **todo o histórico** e
  #    exigiria escolher o calendário (nacional, estadual, bancário). O
  #    calendário é aditivo e entra depois sem refazer nada.
  # 2. **`business_days_until_now` ignora "now"** — apesar do nome, ele conta do
  #    primeiro dia do mês **até a data do lançamento**, inclusive. A data de
  #    hoje não participa. Renomear seria mentir menos, mas o nome do método do
  #    legado é o que o `availability_entry.rb:98` chama; aqui o nome ficou
  #    honesto (`until_date`) e o comportamento, idêntico.
  #
  # **Este módulo é golden-testado** (`spec/lib/sfg/business_days_spec.rb`).
  # O teste não existe para provar que a regra está certa — existe para
  # **reprovar quem a "consertar"** sem passar por uma DEC nova (DEC-30).
  module BusinessDays
    # `cwday`: 1 = segunda … 6 = sábado, 7 = domingo.
    WEEKEND_CWDAYS = [6, 7].freeze

    module_function

    # Dias úteis do mês inteiro a que a data pertence.
    def in_month(date)
      count_between(date.beginning_of_month, date.end_of_month)
    end

    # Dias úteis do primeiro dia do mês **até a data**, inclusive.
    def until_date(date)
      count_between(date.beginning_of_month, date)
    end

    # O multiplicador da correção: proporção do mês já decorrida em dias úteis.
    #
    # Divisão em `Float`, como o legado (`business_days_until_now*1.0 / …`).
    # Trocar por `BigDecimal` mudaria os centavos de todo o histórico — é o
    # mesmo motivo do DEC-02.
    def multiplier(date)
      total = in_month(date)
      return 0.0 if total.zero?

      until_date(date) * 1.0 / total
    end

    def count_between(from, to)
      return 0 if to < from

      (from..to).count { |day| WEEKEND_CWDAYS.exclude?(day.cwday) }
    end
  end
end
