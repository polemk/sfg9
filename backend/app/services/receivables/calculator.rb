# frozen_string_literal: true

require 'bigdecimal'

module Receivables
  # S6 — **o motor de cálculo do borderô. Um cálculo, um dono (contrato C2).**
  #
  # Fecha `BE-155`…`BE-180`.
  #
  # ## Por que este arquivo existe
  #
  # No legado a conta acontece em **dois lugares**:
  #
  # - `../sfg/app/models/receivable_entry.rb:38-118` — um `before_validation` de
  #   80 linhas que atribui ~30 colunas derivadas **antes** de qualquer validação
  #   rodar;
  # - `../sfg/app/views/pub/receivables/new/_body.js.erb:339-504` — uma
  #   reimplementação **parcial** em JavaScript que não calcula
  #   `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`, `multiplicador_*`
  #   nem os `*_percent`, e arredonda o total de tarifas de outro jeito.
  #
  # É o **D-09**: a prévia da tela e o valor gravado divergem, e não há como
  # dizer qual está certo. Aqui a fórmula vive em **um** lugar, e a prévia
  # (`POST /receivables/preview`), a criação, a edição, o serviço de tarifas e o
  # recálculo em lote chamam **este mesmo objeto**. Há teste de request provando
  # que prévia e gravação devolvem os mesmos ~30 derivados, campo a campo.
  #
  # ## Função pura
  #
  # Sem `ActiveRecord`, sem I/O, sem `save`. Recebe um `Input`, devolve um Hash
  # congelado chaveado pelo **nome da coluna**. A alíquota de IOF é **injetada**
  # (`IofRate.effective_on(date)` resolve fora) — é o que mantém o calculador
  # puro e o que permite o golden fixar a alíquota (BE-160 / D-15).
  #
  # ## A aritmética é a do legado, e isso é decisão (DEC-02 / D-104)
  #
  # Mesma ordem de operações, mesmos casts, mesmos pontos de arredondamento.
  # Melhoria **declinada** pelo usuário e registrada em `improvements-log.md`:
  # QA não deve tratar divergência de precisão como regressão. Trocar por
  # `BigDecimal` puro quebra os goldens **de propósito**.
  #
  # ### A coercão de 16 dígitos — medida, não suposta
  #
  # O legado mistura `BigDecimal` (colunas `decimal`) com `Float` (colunas
  # `float`) na mesma expressão. No **Ruby 2.6.1** de produção (DEC-03/DEC-11),
  # `BigDecimal <op> Float` converte o Float com `Float::DIG + 1` = **16 dígitos
  # significativos**. No Ruby 3.4 desta base a conversão passou a usar a
  # representação decimal mais curta, e as duas divergem no último dígito quando
  # o resultado cai exatamente no meio.
  #
  # Não é teoria: rodando o motor contra as **28.131 linhas de produção**, sem
  # `bd()` sobram **22 divergências em 927.267 comparações** — e todas somem com
  # ela. Ver `spec/services/receivables/calculator_spec.rb`.
  #
  # ## Onde as guardas viram 422 em vez de número
  #
  # As guardas que **produzem número** (`< 1`, `== 0` → `0`/`nil`) são
  # replicadas tal e qual. As que produziriam `Infinity`/`NaN` viram **validação
  # antes de calcular** (`Receivables::InputGuard`) — é o **D-10**, que o DEC-02
  # explicitamente NÃO cobre: *"isso não é precisão, é registro corrompido"*.
  # Em produção há **30 borderôs com `NaN` gravado** em colunas de dinheiro,
  # medidos no dump; o ai9 não cria o 31º.
  class Calculator
    # As alíquotas de origem, cravadas em `receivable_entry.rb:54`. Ficam aqui
    # como **fallback do golden**, não como fonte: quem resolve a vigência é
    # `IofRate.effective_on`.
    LEGACY_DAILY_IOF_RATE = 0.000041
    LEGACY_FIXED_IOF_RATE = 0.0038

    # O expoente literal de `calc_valor_liq_correto` (`receivable_entry.rb:107`).
    # São 33 casas de `3`, que **não** é `1/30` — é a aproximação que o autor
    # digitou. Replicado byte a byte (Q-B6).
    MONTHLY_ROOT_EXPONENT = 0.03333333333333333333333333333333333

    STATUS_OK = 'ok'
    STATUS_DIFFERENCE = 'difference'

    # Uma tarifa, já com os classificadores resolvidos. O calculador não conhece
    # `MovementKind` — quem denormaliza é `ReceivableTax`.
    Tax = Struct.new(:value, :is_advalorem, :is_desagio, :is_iof, keyword_init: true)

    # **Só o que o usuário digita**, mais as tarifas e a data. Nunca um
    # `ReceivableEntry`: se o calculador aceitasse o registro, alguém acabaria
    # lendo dele uma coluna derivada e a ordem de cálculo viraria implícita.
    Input = Struct.new(
      :valor_bruto, :vlr_bruto_recusado, :qtd_titulos, :qtd_recusada,
      :prz_med_pond_emp, :prz_med_pond_bco, :float_acordado, :cst_efetivo_acordado,
      :recompra, :retencao, :fomento, :outros,
      :taxes,
      keyword_init: true
    )

    class << self
      # `iof_rate` é o par `[diária, fixa]` já resolvido pela data da operação.
      def call(input, iof_rate: nil)
        new(input, iof_rate).call
      end
    end

    def initialize(input, iof_rate = nil)
      @input = input
      @daily_iof = (iof_rate && iof_rate[0])&.to_f || LEGACY_DAILY_IOF_RATE
      @fixed_iof = (iof_rate && iof_rate[1])&.to_f || LEGACY_FIXED_IOF_RATE
    end

    def call
      out = {}
      tax_buckets(out)
      base_amounts(out)
      deductions(out)
      bank_nominal_rates(out)
      bank_effective_costs(out)
      company_nominal_rates(out)
      company_effective_costs(out)
      multipliers(out)
      agreed_value_check(out)
      nominal_tax_checks(out)
      out.freeze
    end

    private

    attr_reader :input

    # ------------------------------------------------------------------
    # A coercão de 16 dígitos. Ver o cabeçalho — é o que faz o resultado
    # bater com produção linha a linha.
    # ------------------------------------------------------------------
    def bd(value)
      return nil if value.nil?
      return value if value.is_a?(BigDecimal)

      BigDecimal(value.to_f, Float::DIG + 1)
    end

    def dec(value)
      return BigDecimal(0) if value.nil?
      return value if value.is_a?(BigDecimal)

      BigDecimal(value.to_s)
    end

    def flt(value) = value.nil? ? 0.0 : value.to_f

    def valor_bruto          = @valor_bruto ||= dec(input.valor_bruto)
    def vlr_bruto_recusado   = @vlr_bruto_recusado ||= dec(input.vlr_bruto_recusado)
    def prz_med_pond_emp     = @prz_med_pond_emp ||= flt(input.prz_med_pond_emp)
    def prz_med_pond_bco     = @prz_med_pond_bco ||= flt(input.prz_med_pond_bco)
    def float_acordado       = @float_acordado ||= flt(input.float_acordado)
    def cst_efetivo_acordado = @cst_efetivo_acordado ||= flt(input.cst_efetivo_acordado)

    # ------------------------------------------------------------------
    # BE-155 — os 4 buckets (`receivable_entry.rb:42-45`)
    # ------------------------------------------------------------------
    # `tarifas_outras` é o **resto**: total − advalorem − deságio − iof. Uma
    # tarifa com dois classificadores conta nos dois buckets **e** empurra o
    # resto para NEGATIVO. Replicado (DEC-02); o dado inconsistente é
    # **reportado** pelo ETL, não corrigido em silêncio.
    #
    # Conferido em produção: nenhuma das 58.473 tarifas tem dois classificadores
    # ligados — o `check_constraint` de `movement_kinds` fecha o caminho —, mas
    # **uma** linha de `receivable_entries` tem `tarifas_outras` negativa, resto
    # de denormalização defasada.
    def tax_buckets(out)
      taxes = known_taxes
      out[:tarifas_ad_valorem] = sum_where(taxes, :is_advalorem)
      out[:tarifas_desagio]    = sum_where(taxes, :is_desagio)
      out[:tarifas_iof]        = sum_where(taxes, :is_iof)
      total = taxes.sum(BigDecimal(0)) { |t| dec(t.value) }
      out[:tarifas_outras] = total - out[:tarifas_ad_valorem] - out[:tarifas_desagio] - out[:tarifas_iof]
    end

    def sum_where(taxes, flag)
      taxes.select { |t| truthy?(t.public_send(flag)) }.sum(BigDecimal(0)) { |t| dec(t.value) }
    end

    # **DEC-120 — tarifa de valor DESCONHECIDO fica FORA das somas.**
    #
    # Não é o mesmo que somar zero, mesmo que a soma dê o mesmo número: fora da
    # lista, a tarifa nula não entra em contagem nem em média, e `dec(nil)` —
    # que devolve `BigDecimal(0)` — deixa de ser o lugar onde "desconhecido"
    # silenciosamente vira "R$ 0,00". O borderô que tem uma dessas é sinalizado
    # na tela (`ReceivableEntry#unknown_tax?`), e é a sinalização, não o zero,
    # que conta a verdade.
    def known_taxes
      @known_taxes ||= Array(input.taxes).reject { |t| t.value.nil? }
    end

    def truthy?(value)
      value == true || value == 1 || value.to_s == '1' || value.to_s == 'true'
    end

    # ------------------------------------------------------------------
    # BE-156..BE-162 — os valores base (`:48-56`)
    # ------------------------------------------------------------------
    def base_amounts(out)
      vbf = valor_bruto - vlr_bruto_recusado                                        # :48
      out[:vlr_bruto_final] = vbf
      out[:qtd_final] = input.qtd_titulos.to_i - input.qtd_recusada.to_i            # :49

      fc = prz_med_pond_bco - prz_med_pond_emp                                      # :50
      out[:float_calculado] = fc
      diff = fc - float_acordado                                                    # :51
      # `0.0`, não `0`: a coluna é `float` (DEC-117) e o legado gravava o zero
      # já convertido. Devolver `Integer` aqui faria a **prévia** responder `0` e
      # a **gravação** responder `0.0` para o mesmo payload — o contrato C2 é
      # justamente que os dois sejam o mesmo campo a campo.
      out[:diferenca_float] = diff.positive? ? diff : 0.0                           # :52

      # BE-160 — base do IOF: bruto final MENOS advalorem e deságio. Base
      # negativa continua produzindo IOF negativo (DEC-02).
      v_advlr_iof = out[:tarifas_ad_valorem] + out[:tarifas_desagio]                # :53
      out[:checagem_iof] = (((vbf - v_advlr_iof) * bd(prz_med_pond_bco * @daily_iof)) +
                            ((vbf - v_advlr_iof) * bd(@fixed_iof))).round(2)        # :54

      vtt = out[:tarifas_ad_valorem] + out[:tarifas_desagio] +
            out[:tarifas_iof] + out[:tarifas_outras]                                # :55
      out[:valor_total_tarifas] = vtt
      out[:valor_liquido] = vbf - vtt                                               # :56
    end

    # ------------------------------------------------------------------
    # BE-163..BE-165 — deduções (`:59-65`)
    # ------------------------------------------------------------------
    # `nil` vira zero: o legado fazia `self.recompra.blank? ? 0 : …` no
    # percentual, mas somava `self.recompra` cru em `total_deducoes` — e um
    # registro legado com `NULL` levantava `NoMethodError` ali. Aqui o `nil` é
    # zero nos dois lugares, que é o que o legado **fazia quando funcionava**.
    def deductions(out)
      liquido = out[:valor_liquido]
      %i[recompra retencao fomento outros].each do |campo|
        valor = input.public_send(campo)
        # **DEC-117 — o `.to_f` é o que o legado faz, e não é arredondamento.**
        # A divisão é `BigDecimal / BigDecimal` (as duas colunas de origem são
        # `decimal`), exatamente como em `receivable_entry.rb:59-62`. O legado
        # então **atribui o resultado a uma coluna `float`**, e o ActiveRecord o
        # converte para `Float` na atribuição — é esse `double` que produção
        # guardou (`19.704917111218396`) e é ele que a tela do legado mostra.
        # Fazer a conversão aqui é reproduzir esse passo, não acrescentar um:
        # sem ela a **prévia** devolveria `BigDecimal` (JSON string) e a
        # **gravação** devolveria `Float` (JSON número) para o mesmo payload,
        # quebrando o contrato C2 na serialização.
        out[:"#{campo}_percent"] = valor.nil? ? 0.0 : (100 * (dec(valor) / liquido)).to_f # :59-62
      end
      total = dec(input.recompra) + dec(input.retencao) + dec(input.fomento) + dec(input.outros)
      out[:total_deducoes] = total                                                  # :63
      out[:vlr_liq_recebido] = liquido - dec(input.recompra) - dec(input.retencao) -
                               dec(input.fomento) - dec(input.outros)               # :65
    end

    # ------------------------------------------------------------------
    # BE-166 — as 3 taxas nominais do banco (`:67-69`)
    # ------------------------------------------------------------------
    # **A assimetria é o ponto.** As duas primeiras têm guarda `< 1` (um real);
    # a terceira **não tem nenhuma**. Replicado; o que muda é que a terceira
    # deixa de gravar `Infinity` porque `InputGuard` barra `prz_med_pond_bco = 0`
    # antes de o cálculo rodar.
    def bank_nominal_rates(out)
      liquido = out[:valor_liquido]
      vbf = out[:vlr_bruto_final]
      pmb = bd(prz_med_pond_bco)

      out[:taxa_desconto_nominal_desagio_advalorem_bancos] =
        if liquido < 1 || out[:tarifas_desagio] < 1
          nil
        else
          (100 * ((((out[:tarifas_ad_valorem] + out[:tarifas_desagio]) / vbf) / pmb) * 30)).round(2)
        end

      out[:taxa_desconto_nominal_despesas_bancos] =
        if liquido < 1 || out[:tarifas_iof] < 1
          nil
        else
          (100 * ((((out[:valor_total_tarifas] - out[:tarifas_iof]) / vbf) / pmb) * 30)).round(2)
        end

      out[:taxa_desconto_nominal_despesas_iof_bancos] =
        (100 * (((out[:valor_total_tarifas] / vbf) / pmb) * 30)).round(2)
    end

    # ------------------------------------------------------------------
    # BE-167, BE-168 — os dois CETs do banco (`:71-78`)
    # ------------------------------------------------------------------
    def bank_effective_costs(out)
      vbf = out[:vlr_bruto_final]
      liquido = out[:valor_liquido]
      vlq_iof = liquido + out[:tarifas_iof]                                         # :71
      expoente = 30 / (prz_med_pond_bco + float_acordado)

      power_bco_iof = ((((vbf - vlq_iof) / vlq_iof)) + 1)**expoente                 # :72
      tx_banco_iof = ((power_bco_iof - 1) * 100).round(4)                           # :73
      # ⚠ Q-B7 — **a guarda olha `prz_med_pond_emp` numa fórmula do BANCO.**
      # Parece copy/paste (`receivable_entry.rb:74`) e NÃO é corrigido: o golden
      # existe justamente para que a "correção" quebre visivelmente.
      out[:custo_efetivo_pz_med_banco_sem_iof] = prz_med_pond_emp == 0 ? 0 : tx_banco_iof

      power_bco = ((((vbf - liquido) / liquido)) + 1)**expoente                     # :76
      tx_banco = ((power_bco - 1) * 100).round(4)                                   # :77
      out[:custo_efetivo_pz_med_banco] = prz_med_pond_bco == 0 ? 0 : tx_banco       # :78
    end

    # ------------------------------------------------------------------
    # BE-169 — as 3 taxas nominais da empresa (`:81-83`)
    # ------------------------------------------------------------------
    def company_nominal_rates(out)
      liquido = out[:valor_liquido]
      vbf = out[:vlr_bruto_final]
      pme = bd(prz_med_pond_emp)

      out[:taxa_desconto_nominal_desagio_advalorem_emp] =
        if liquido < 1 || out[:tarifas_desagio] < 1
          nil
        else
          (100 * ((((out[:tarifas_ad_valorem] + out[:tarifas_desagio]) / vbf) / pme) * 30)).round(2)
        end

      out[:taxa_desconto_nominal_despesas_emp] =
        if liquido < 1 || out[:tarifas_iof] < 1
          nil
        else
          (100 * ((((out[:valor_total_tarifas] - out[:tarifas_iof]) / vbf) / pme) * 30)).round(2)
        end

      out[:taxa_desconto_nominal_despesas_iof_emp] =
        (100 * (((out[:valor_total_tarifas] / vbf) / pme) * 30)).round(2)
    end

    # ------------------------------------------------------------------
    # BE-170..BE-174 — os CETs da empresa (`:85-101`)
    # ------------------------------------------------------------------
    def company_effective_costs(out)
      vbf = out[:vlr_bruto_final]
      liquido = out[:valor_liquido]
      vlq_iof = liquido + out[:tarifas_iof]
      expoente = 30 / (prz_med_pond_emp + float_acordado)

      power_emp_iof = ((((vbf - vlq_iof) / vlq_iof)) + 1)**expoente                 # :85
      out[:custo_efetivo_pz_med_emp_sem_iof] =
        prz_med_pond_emp == 0 ? 0 : ((power_emp_iof - 1) * 100).round(4)            # :86-87

      power_emp = ((((vbf - liquido) / liquido)) + 1)**expoente                     # :90
      # É a chave de ordenação `cet` da lista, com 4 casas.
      out[:custo_efetivo_pz_med_emp] =
        prz_med_pond_emp == 0 ? 0 : ((power_emp - 1) * 100).round(4)                # :91-92

      power_cstsf = ((((vbf - liquido) / liquido)) + 1)**(30 / prz_med_pond_emp)    # :95
      out[:custo_efetivo_sem_float] =
        prz_med_pond_emp == 0 ? 0 : ((power_cstsf - 1) * 100).round(4)              # :96-97

      # ⚠ Q-B8 — **2 casas**, sobre a MESMA base que `custo_efetivo_pz_med_emp`
      # arredonda em 4. Divergência replicada (`:99`).
      out[:custo_efetivo_com_float_total] =
        (100 * (((1 + ((vbf - liquido) / liquido))**expoente) - 1)).round(2)        # :99

      out[:custo_efetivo_com_float_sem_iof] =
        if liquido < 1 || out[:tarifas_iof] < 1
          nil
        else
          (100 * (((1 + ((vbf - vlq_iof) / vlq_iof))**expoente) - 1)).round(2)      # :101
        end
    end

    # ------------------------------------------------------------------
    # BE-175 — multiplicadores (`:104-105`)
    # ------------------------------------------------------------------
    # O produto é `BigDecimal × Float`; a coluna é `decimal(15,2)`, então o
    # **armazenamento** trunca em 2 casas. O `round(2)` aqui é esse cast, escrito
    # onde se pode ver — sem ele, prévia e gravação divergiriam na 3ª casa.
    def multipliers(out)
      vbf = out[:vlr_bruto_final]
      out[:multiplicador_pm_empresa] = (vbf * bd(prz_med_pond_emp)).round(2)
      out[:multiplicador_pm_float] = (vbf * bd(prz_med_pond_bco)).round(2)
    end

    # ------------------------------------------------------------------
    # BE-176..BE-178 — o líquido "correto" e o status (`:107-115`)
    # ------------------------------------------------------------------
    # ⚠ Q-B6 — é **aproximação linear** (juros simples), não desconto composto:
    # a taxa mensal vira taxa diária pela raiz de 30, multiplica pelo bruto e
    # depois multiplica pelo prazo em dias. Replicado, com o expoente literal.
    def agreed_value_check(out)
      vbf = out[:vlr_bruto_final]
      power_tx = (((cst_efetivo_acordado / 100.to_f) + 1)**MONTHLY_ROOT_EXPONENT) - 1  # :107
      tx = power_tx * vbf.to_f                                                         # :108
      vp = (vbf - bd(tx * (prz_med_pond_emp + float_acordado))).round(2)                # :109
      out[:calc_valor_liq_correto] = vp                                                # :112

      out[:dif_calc_vlr_liq] = (out[:valor_liquido] - vp).round(2)                     # :114
      # BE-445 — dois estados, e nenhum terceiro. No legado eram as strings
      # pt-BR "Diferença"/"OK" gravadas na coluna e comparadas por igualdade de
      # texto; aqui o valor persistido é estável e o rótulo vive na apresentação.
      out[:status] = out[:dif_calc_vlr_liq] < 0 ? STATUS_DIFFERENCE : STATUS_OK       # :115
    end

    # ------------------------------------------------------------------
    # BE-179, BE-180 — as duas checagens da taxa nominal (`:117-118`)
    # ------------------------------------------------------------------
    # A `nominal_tax` que o usuário informa **continua não sendo validada**
    # contra estas duas (Q-B10): é divergência informativa, não erro.
    def nominal_tax_checks(out)
      vbf = out[:vlr_bruto_final]
      desagio = out[:tarifas_desagio]
      out[:nominal_tax_check] =
        (100.0 * (desagio / (vbf * bd(prz_med_pond_emp / 30.0)))).round(2)
      out[:nominal_tax_check_with_float] =
        (100.0 * (desagio / (vbf * bd((prz_med_pond_emp + float_acordado) / 30.0)))).round(2)
    end
  end
end
