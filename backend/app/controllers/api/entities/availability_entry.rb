# frozen_string_literal: true

module Api
  module Entities
    # S11 / BE-122..124, FE-129, FE-133, FE-134 — **o lançamento de
    # disponibilidade**, serializado.
    #
    # **Os valores saem como número**, nunca como texto formatado — formatação
    # é da tela. O legado devolvia `"R$ 1.234,56"` do servidor e o JS desfazia a
    # máscara para somar.
    #
    # **FE-134 — os dois valores viajam.** `original_value` é a base da correção
    # por dias úteis e `value` é o resultado. O legado mostrava só o resultado:
    # o usuário digitava X e via Y, sem nenhuma indicação. Aqui a tela mostra os
    # dois, com o multiplicador.
    class AvailabilityEntry < Grape::Entity
      expose :id
      expose :project_id, documentation: { desc: 'NUNCA aceito no corpo (C1)' }
      expose :company_id
      expose :availability_template_id
      expose :title
      expose :date

      expose :value, documentation: { type: 'String', desc: 'decimal(15,2). Número, nunca texto formatado' }
      expose :original_value,
             documentation: { desc: 'Base da correção. **É regravado a cada alteração de value** — DEC-24 / D-02' }
      expose :virtual_value,
             documentation: { desc: 'Saldo acumulado do 1º nível (DEC-27). Métrica diferente de `value`' }

      # FE-133 / FE-134 — os dois marcadores da célula, e o par de números que
      # torna a correção legível.
      expose :is_adjusted do |e|
        e.availability_template&.is_adjusted? || false
      end
      expose :is_cumulative do |e|
        e.availability_template&.is_cumulative?
      end
      expose :business_days_multiplier, documentation: { desc: 'Só quando o padrão é corrigido' } do |e|
        e.adjusted? && e.date.present? ? Sfg::BusinessDays.multiplier(e.date).round(6) : nil
      end

      # DB-126 — marca **explícita** de consolidação, não inferida por empresa
      # nula. A tela usa isto para rotular "Consolidação geral (soma bruta)",
      # que é a metade da DEC-26 que impede o D-08 de virar defeito silencioso.
      expose :is_consolidation

      expose :author_name do |e|
        e.author&.name
      end
      expose :created_at
      expose :updated_at
    end
  end
end
