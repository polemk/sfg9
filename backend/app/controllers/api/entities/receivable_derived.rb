# frozen_string_literal: true

module Api
  module Entities
    # S6 — **os derivados do cálculo, num lugar só** (contrato C2).
    #
    # É o formato de saída de `POST /receivables/preview` **e** o bloco
    # `derived` de `Api::Entities::ReceivableEntry`. Uma definição, dois usos:
    # é o que garante que a prévia e o registro gravado tenham exatamente os
    # mesmos campos, com os mesmos nomes.
    #
    # Se este arquivo virasse dois, voltaríamos ao D-09 pela porta da
    # serialização — a conta seria a mesma e a tela mostraria campos diferentes.
    #
    # **Os números saem crus.** A formatação (vírgula, milhar, `R$`, e o
    # travessão do nulo) é do front, em `lib/format/money.ts` — nulo **não** é
    # zero (D-117).
    class ReceivableDerived < Grape::Entity
      expose :tarifas_ad_valorem, documentation: { type: 'BigDecimal', desc: 'Soma das tarifas AdValorem' }
      expose :tarifas_desagio, documentation: { type: 'BigDecimal', desc: 'Soma das tarifas de deságio' }
      expose :tarifas_iof, documentation: { type: 'BigDecimal', desc: 'Soma das tarifas de IOF' }
      expose :tarifas_outras,
             documentation: { type: 'BigDecimal', desc: 'Resto. Fica negativo se uma tarifa tiver dois classificadores' }

      expose :vlr_bruto_final, documentation: { type: 'BigDecimal', desc: 'Bruto menos recusado' }
      expose :qtd_final, documentation: { type: 'Integer', desc: 'Títulos menos recusados' }
      expose :float_calculado,
             documentation: { type: 'Float', desc: 'Banco menos empresa, em dias. `float` (DEC-117)' }
      expose :diferenca_float,
             documentation: { type: 'Float', desc: 'Calculado menos acordado, piso em zero. `float` (DEC-117)' }
      expose :checagem_iof, documentation: { type: 'BigDecimal', desc: 'IOF esperado pela alíquota vigente na data' }
      expose :valor_total_tarifas, documentation: { type: 'BigDecimal', desc: 'Soma dos 4 buckets' }
      expose :valor_liquido, documentation: { type: 'BigDecimal', desc: 'Bruto final menos tarifas' }

      expose :recompra_percent,
             documentation: { type: 'Float', desc: '% da recompra sobre o líquido, sem arredondar. `float` (DEC-117)' }
      expose :retencao_percent, documentation: { type: 'Float' }
      expose :fomento_percent, documentation: { type: 'Float' }
      expose :outros_percent, documentation: { type: 'Float' }
      expose :total_deducoes, documentation: { type: 'BigDecimal', desc: 'Soma das 4 deduções' }
      expose :vlr_liq_recebido, documentation: { type: 'BigDecimal', desc: 'Líquido menos as deduções' }

      expose :taxa_desconto_nominal_desagio_advalorem_bancos,
             documentation: { type: 'BigDecimal', desc: 'Nula quando líquido < 1 ou deságio < 1 (guarda replicada)' }
      expose :taxa_desconto_nominal_despesas_bancos,
             documentation: { type: 'BigDecimal', desc: 'Nula quando líquido < 1 ou IOF < 1 — 97% dos borderôs' }
      expose :taxa_desconto_nominal_despesas_iof_bancos,
             documentation: { type: 'BigDecimal', desc: 'Sem guarda — assimetria do legado, replicada' }
      expose :custo_efetivo_pz_med_banco, documentation: { type: 'BigDecimal', desc: 'CET PM BCO, 4 casas' }
      expose :custo_efetivo_pz_med_banco_sem_iof,
             documentation: { type: 'BigDecimal', desc: 'Guarda no prazo da EMPRESA numa fórmula do banco (Q-B7)' }
      expose :taxa_desconto_nominal_desagio_advalorem_emp, documentation: { type: 'BigDecimal' }
      expose :taxa_desconto_nominal_despesas_emp, documentation: { type: 'BigDecimal' }
      expose :taxa_desconto_nominal_despesas_iof_emp, documentation: { type: 'BigDecimal' }
      expose :custo_efetivo_pz_med_emp,
             documentation: { type: 'BigDecimal', desc: 'CET PM EMP, 4 casas. Chave de ordenação `cet`' }
      expose :custo_efetivo_pz_med_emp_sem_iof, documentation: { type: 'BigDecimal' }
      expose :custo_efetivo_sem_float,
             documentation: { type: 'BigDecimal', desc: 'CET sem float. Chave de ordenação `cetsf`' }
      expose :custo_efetivo_com_float_total,
             documentation: { type: 'BigDecimal', desc: '2 casas sobre a mesma base do CET PM EMP, que usa 4 (Q-B8)' }
      expose :custo_efetivo_com_float_sem_iof, documentation: { type: 'BigDecimal' }

      expose :multiplicador_pm_empresa, documentation: { type: 'BigDecimal' }
      expose :multiplicador_pm_float, documentation: { type: 'BigDecimal' }

      expose :calc_valor_liq_correto,
             documentation: { type: 'BigDecimal', desc: 'Líquido correto pela taxa acordada. Aproximação LINEAR (Q-B6)' }
      expose :dif_calc_vlr_liq, documentation: { type: 'BigDecimal', desc: 'Líquido menos o líquido correto' }
      expose :status, documentation: { type: 'String', desc: 'ok | difference. Dois estados e nenhum terceiro (Q-B9)' }
      expose :status_label, documentation: { type: 'String', desc: 'Rótulo pt-BR: OK | Diferença' } do |o|
        valor = o.is_a?(Hash) ? o[:status] : o.status
        ::Entry.status_label(valor)
      end
      expose :nominal_tax_check, documentation: { type: 'BigDecimal', desc: 'Taxa nominal apurada' }
      expose :nominal_tax_check_with_float, documentation: { type: 'BigDecimal', desc: 'Idem, com o float no prazo' }
    end
  end
end
