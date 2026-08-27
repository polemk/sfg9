# frozen_string_literal: true

require 'bigdecimal'

module Receivables
  # S6 — **as guardas que o legado só tinha no cliente**. Fecha o **D-10**.
  #
  # ## O defeito, e a medição
  #
  # No legado o cálculo roda num `before_validation`
  # (`../sfg/app/models/receivable_entry.rb:38`), isto é, **antes** de qualquer
  # validação. Com `valor_liquido = 0`, `prz_med_pond_emp = 0` ou um número
  # inválido no formulário, a divisão acontece, `Infinity`/`NaN` é atribuído às
  # colunas e o registro é gravado. A única guarda existia no JavaScript da
  # tela.
  #
  # **Não é hipótese.** No dump de produção há **30 borderôs com `NaN` gravado**
  # em coluna de dinheiro (`recompra`, `tarifas_desagio`, `valor_liquido`,
  # `total_deducoes`, `vlr_liq_recebido`) — e num deles o `NaN` do deságio
  # contaminou o total de tarifas, o líquido e os quatro percentuais.
  #
  # O **DEC-02** manda replicar a aritmética em float, mas diz explicitamente
  # que o D-10 **não** está coberto: *"isso não é precisão, é registro
  # corrompido. Continua `corrigir`."*
  #
  # ## Onde isto roda
  #
  # Nos **dois** caminhos, e é o mesmo objeto (contrato C2): a prévia
  # (`POST /receivables/preview`) e a gravação. Uma combinação que a tela trava
  # é a mesma que o servidor responde 422 — a tela é conveniência, o servidor é
  # a defesa.
  #
  # As guardas que **produzem número** (`< 1` → `nil`, `== 0` → `0`) NÃO estão
  # aqui: aquelas são regra do legado e vivem no `Calculator`, replicadas. Aqui
  # ficam só as que evitariam `Infinity`/`NaN`.
  module InputGuard
    # Divisores que aparecem na cadeia de cálculo. Cada linha é
    # `[rótulo pt-BR, procedimento]` — e cada uma corresponde a uma divisão
    # concreta em `receivable_entry.rb`.
    module_function

    # Devolve um array de mensagens em pt-BR. Vazio = pode calcular.
    def check(input)
      erros = []
      erros.concat(finite_errors(input))
      return erros if erros.any?

      erros.concat(term_errors(input))
      return erros if erros.any?

      erros.concat(divisor_errors(input))
      erros.concat(exponent_base_errors(input))
      erros
    end

    # Rede de segurança do outro lado: nenhum resultado com `Infinity`/`NaN`
    # chega ao banco, aconteça o que acontecer na aritmética.
    #
    # Existe porque a lista de divisores acima é uma **enumeração**, e
    # enumeração envelhece. Esta checagem não envelhece: ela olha o resultado.
    def result_errors(result)
      corrompidas = result.filter_map do |coluna, valor|
        coluna if nonfinite?(valor)
      end
      return [] if corrompidas.empty?

      ["O cálculo produziu valor inválido (infinito ou indeterminado) em: #{corrompidas.join(', ')}. " \
       'Confira os prazos, o valor bruto e as tarifas.']
    end

    # **Devolve `true`/`false`, nunca `nil`.** `Float#infinite?` responde `nil`
    # para número finito, e o ramo antigo (`value.nan? || value.infinite?`)
    # devolvia esse `nil` — falsy, então a guarda funcionava, mas quem
    # asserta `be(false)` recebia `nil` e reprovava. Apareceu quando a DEC-117
    # trocou `float_calculado` de `decimal` para `float` e o valor passou a cair
    # no ramo `Float`. O predicado é o mesmo para os dois tipos.
    def nonfinite?(value)
      case value
      when Float, BigDecimal then value.nan? || !value.finite?
      else false
      end
    end

    # ------------------------------------------------------------------
    # 1. Nenhuma entrada pode ser `NaN`/`Infinity`
    # ------------------------------------------------------------------
    # É a porta por onde os 30 borderôs de produção entraram: `recompra` chegou
    # como `NaN` e o Postgres aceitou, porque `numeric` guarda `NaN`.
    NUMERIC_FIELDS = %i[
      valor_bruto vlr_bruto_recusado qtd_titulos qtd_recusada
      prz_med_pond_emp prz_med_pond_bco float_acordado cst_efetivo_acordado
      recompra retencao fomento outros
    ].freeze

    FIELD_LABELS = {
      valor_bruto: 'Valor bruto', vlr_bruto_recusado: 'Valor bruto recusado',
      qtd_titulos: 'Quantidade de títulos', qtd_recusada: 'Quantidade recusada',
      prz_med_pond_emp: 'Prazo médio ponderado da empresa',
      prz_med_pond_bco: 'Prazo médio ponderado do banco',
      float_acordado: 'Float acordado', cst_efetivo_acordado: 'Custo efetivo acordado',
      recompra: 'Recompra', retencao: 'Retenção', fomento: 'Fomento', outros: 'Outros'
    }.freeze

    def finite_errors(input)
      erros = NUMERIC_FIELDS.filter_map do |campo|
        valor = input.public_send(campo)
        next if valor.nil?

        "#{FIELD_LABELS[campo]} não é um número válido." if nonfinite?(coerce(valor))
      end

      # `next if tax.value.nil?`: nulo é "valor desconhecido" vindo da carga
      # (DEC-120), não entrada inválida. O que esta guarda barra é `NaN` e
      # `Infinity` — os que o legado deixava chegar ao banco.
      Array(input.taxes).each_with_index do |tax, i|
        next if tax.value.nil?

        erros << "O valor da tarifa #{i + 1} não é um número válido." if nonfinite?(coerce(tax.value))
      end

      erros
    end

    # ------------------------------------------------------------------
    # 2. Os termos que o legado já validava (BE-181)
    # ------------------------------------------------------------------
    def term_errors(input)
      erros = []
      erros << 'O prazo médio ponderado da empresa precisa ser maior que zero.' if to_f(input.prz_med_pond_emp) <= 0
      erros << 'O prazo médio ponderado do banco precisa ser maior que zero.' if to_f(input.prz_med_pond_bco) <= 0
      erros
    end

    # ------------------------------------------------------------------
    # 3. Os divisores. Cada um é uma divisão concreta do legado.
    # ------------------------------------------------------------------
    def divisor_errors(input)
      erros = []
      vbf = dec(input.valor_bruto) - dec(input.vlr_bruto_recusado)
      buckets = tax_totals(input)
      liquido = vbf - buckets[:total]
      vlq_iof = liquido + buckets[:iof]

      # `:67-69` e `:81-83` dividem por `vlr_bruto_final`.
      if vbf.zero?
        erros << 'O valor bruto final (bruto menos recusado) não pode ser zero: as taxas nominais dividem por ele.'
      end

      # `:56` grava o líquido; `:59-62`, `:76` e `:90` dividem por ele.
      if liquido.zero?
        erros << 'O valor líquido não pode ser zero. Revise o valor bruto e as tarifas — ' \
                 'o cálculo das deduções e do custo efetivo divide por ele.'
      end

      # `:72` e `:85` dividem por `valor_liquido + tarifas_iof`.
      if vlq_iof.zero?
        erros << 'O valor líquido somado ao IOF não pode ser zero: o custo efetivo sem IOF divide por ele.'
      end

      # `:72`, `:76`, `:85`, `:90`, `:99`, `:101` têm `30 / (prazo + float)` no
      # expoente. O legado não guarda nenhuma dessas.
      if (to_f(input.prz_med_pond_bco) + to_f(input.float_acordado)).zero?
        erros << 'O prazo do banco somado ao float não pode ser zero: ele é o divisor do expoente do custo efetivo.'
      end
      if (to_f(input.prz_med_pond_emp) + to_f(input.float_acordado)).zero?
        erros << 'O prazo da empresa somado ao float não pode ser zero: ele é o divisor do expoente do custo efetivo.'
      end

      erros
    end

    # ------------------------------------------------------------------
    # 4. Base negativa com expoente fracionário
    # ------------------------------------------------------------------
    # `base ** 0.68` com `base < 0` não é número real — em Ruby dá `Complex` ou
    # `NaN` conforme o tipo. Acontece de verdade quando o líquido é negativo e
    # maior em módulo que o bruto final.
    def exponent_base_errors(input)
      erros = []
      vbf = dec(input.valor_bruto) - dec(input.vlr_bruto_recusado)
      buckets = tax_totals(input)
      liquido = vbf - buckets[:total]
      vlq_iof = liquido + buckets[:iof]

      unless liquido.zero? || (((vbf - liquido) / liquido) + 1) >= 0
        erros << 'A combinação de valor bruto, tarifas e deduções produz um custo efetivo sem solução real. ' \
                 'Revise as tarifas.'
      end
      unless vlq_iof.zero? || (((vbf - vlq_iof) / vlq_iof) + 1) >= 0
        erros << 'A combinação de valor bruto e IOF produz um custo efetivo sem solução real. Revise o IOF.'
      end
      # `:107` — `(cst/100 + 1) ** 0.0333…` com base negativa vira `NaN`.
      if (to_f(input.cst_efetivo_acordado) / 100.0) + 1 < 0
        erros << 'O custo efetivo acordado não pode ser menor que -100%.'
      end

      erros
    end

    # ------------------------------------------------------------------
    # Mesma regra do `Calculator`: tarifa de valor desconhecido fica fora das
    # somas (DEC-120). As duas listas precisam ser a MESMA, senão a guarda
    # decide sobre um total que o cálculo não vai produzir.
    def tax_totals(input)
      taxes = Array(input.taxes).reject { |t| t.value.nil? }
      total = taxes.sum(BigDecimal(0)) { |t| dec(t.value) }
      iof = taxes.select { |t| truthy?(t.is_iof) }.sum(BigDecimal(0)) { |t| dec(t.value) }
      { total: total, iof: iof }
    end

    def truthy?(value)
      value == true || value == 1 || value.to_s == '1' || value.to_s == 'true'
    end

    def coerce(value)
      return value if value.is_a?(Float) || value.is_a?(BigDecimal)

      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      # Texto que não é número (`"abc"`) não é `NaN`: é entrada inválida e o
      # Grape já a barra com 400. Aqui não é caso de erro de guarda.
      BigDecimal(0)
    end

    def dec(value)
      return BigDecimal(0) if value.nil?
      return value if value.is_a?(BigDecimal)

      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      BigDecimal(0)
    end

    def to_f(value) = value.nil? ? 0.0 : value.to_f
  end
end
