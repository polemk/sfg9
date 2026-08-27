# frozen_string_literal: true

module Risk
  # S5 / BE-242..BE-248, BE-266 — **o motor de exposição, por limite**.
  #
  # ## Contrato C2: uma implementação, dois chamadores
  #
  # A prévia da tela e a gravação chamam **este** serviço. Não existe uma segunda
  # implementação destas fórmulas — nem no front (que só formata), nem em
  # `Company`/`Project` (que agregam chamando daqui), nem na S6/S7 (que
  # consomem `#balance_on` e `#operations_on`).
  #
  # No legado as mesmas oito fórmulas viviam espalhadas em **três models** que
  # eram cópias literais umas das outras — `risk_control.rb:115-160`,
  # `company.rb:35-66` e `project.rb:462-493` — e **nenhuma tinha teste**
  # (D-114). Qualquer divergência entre a leitura da tela e a apuração usada na
  # gravação era invisível.
  #
  # ## DEC-01 e DEC-02: o comportamento estranho É o requisito
  #
  # As duas melhorias foram **DECLINADAS pelo usuário** (`improvements-log.md`,
  # D-93 e D-104). Portanto:
  #
  # - **o `× (−1)` fica.** Saldo devedor produz utilização negativa. Não é bug;
  #   é a convenção de sinal do produto;
  # - **o `.to_f` de `limite_disponivel_on` fica.** O retorno é Float, com o
  #   arredondamento binário que vem junto;
  # - **`balance_on` sem movimento devolve 0, não `original_balance`.**
  #
  # Cada uma dessas linhas tem golden. Se alguém "consertar" o sinal ou trocar o
  # `.to_f` por `BigDecimal`, o teste quebra e diz qual centavo mudou. **O teste
  # não existe para provar que a fórmula está certa — existe para reprovar quem
  # a mudar sem passar por uma DEC.**
  #
  #
  # **O que isso significa, com honestidade: nao ha oraculo.** Estes valores foram
  # conferidos contra o **fonte de 2022** — arquivo e linha citados em cada
  # cenario —, e nao contra comportamento observado. O golden trava a LEITURA do
  # codigo de 2022; ele nao prova que o numero esta certo, prova que nao mudamos o
  # que o legado fazia. A DEC-103b manda espelhar, e e isso que esta feito.
  #
  # **A marca serve de ponteiro:** no dia em que um numero sair estranho, ela diz
  # em segundos que a resposta esta no fonte de 2022, e nao numa base de producao
  # que nunca teve estes registros.
  #
  # O esquema tipado de risco **nunca subiu**: `change_risk_control_fields`,
  # `create_risk_operation_types`, `create_risk_operations` e
  # `create_risk_movements` estão entre as **24 migrations que nunca rodaram**
  # (`analise-dump-producao.md` §1). Não existe uma única operação, um único
  # movimento nem um único limite tipado no dump.
  #
  #
  #
  #
  # **O que é validado EM produção, e vai sem marca:** as 4 famílias de limite
  # (`auto_liquidavel`, `comissaria`, `fomento`, `intercompany`) e as taxas —
  # 600 registros reais, três anos de uso.
  #
  # ## Ordem da soma (decisão B-07)
  #
  # A soma é feita **linha a linha, na ordem em que o banco devolve**, e não por
  # `SUM()` no SQL. Com float na cadeia a ordem muda centavos. Qualquer `preload`
  # ou índice acrescentado depois tem de manter esta ordem, e os goldens rodam
  # antes e depois para provar.
  class Calculator
    class << self
      include ApiResponseHandler

      # **BE-242 / OPS-233** — as operações vigentes numa data.
      #
      # Intervalo FECHADO nos dois lados, como o legado, mais o ramo `is_static`
      # (B-08). **Operação encerrada continua entrando**: não há filtro por
      # `is_ended` aqui, e isso é DEC-35.
      #
      # A relação é a "larga" do limite (`RiskControl#operations`: por projeto,
      # empresa, portador e tipo, **sem** olhar `is_active`) — igual ao legado.
      #
      # Devolve **relação**, porque é contrato público (a S6 e a S7 consomem).
      # O caminho interno das fórmulas usa a lista materializada da memória de
      # apuração, que é esta mesma relação com `to_a`.
      def operations_on(control, date = Date.current)
        control.operations.on_date(date)
      end

      # **BE-266** — delegação explícita para que o contrato fique num lugar só.
      def balance_on(operation, date = Date.current)
        operation.balance_on(date)
      end

      # **BE-243 — limite utilizado.** `Σ balance_on(d) × (−1)`. DEC-01.
      def limite_utilizado_on(control, date = Date.current, cache: nil)
        soma_de(lista(control, date, cache), date, cache) * -1
      end

      # **BE-244 — limite liquidável.**
      #
      # Tipo **com** pré-faturamento soma só os subtipos `is_pre = false`; tipo
      # **sem** soma **todas** as operações da janela — e por isso, nele,
      # `liquidavel == utilizado`. Não é engano do porte: é o `else` do legado
      # (`risk_control.rb:131-133`).
      def limite_liquidavel_on(control, date = Date.current, cache: nil)
        # A linha herdada do formato pré-2022 não tem tipo (600 em produção) e
        # portanto não tem bucket. Ela já fica de fora de todos os agregados,
        # que partem de `RiskOperationType.active`; a guarda existe para que uma
        # chamada direta devolva **zero** em vez de `NoMethodError` em `nil`.
        return 0 if control.legacy_shape?

        operacoes = lista(control, date, cache)
        if control.risk_operation_type.has_pre_faturamento?
          ids = control.risk_operation_type.subtype_ids_for(is_pre: false)
          operacoes = operacoes.select { |op| ids.include?(op.operation_subtype_id) }
        end

        soma_de(operacoes, date, cache) * -1
      end

      # **BE-245 — limite de pré-faturamento.** Tipo sem pré devolve 0.
      def limite_pre_on(control, date = Date.current, cache: nil)
        return 0 if control.legacy_shape?
        return 0 unless control.risk_operation_type.has_pre_faturamento?

        ids = control.risk_operation_type.subtype_ids_for(is_pre: true)
        operacoes = lista(control, date, cache).select { |op| ids.include?(op.operation_subtype_id) }

        soma_de(operacoes, date, cache) * -1
      end

      # **BE-246 — limite disponível.** `(limite − utilizado).to_f`.
      #
      # O `.to_f` é **DEC-02**: a subtração é exata em BigDecimal e o resultado é
      # rebaixado a Float na saída. O golden verifica o valor **e o tipo** —
      # trocar por BigDecimal mudaria o número que a tela imprime.
      def limite_disponivel_on(control, date = Date.current, cache: nil)
        (control.limite - limite_utilizado_on(control, date, cache: cache)).to_f
      end

      # **BE-247 — vencidos.** Operações `is_ended`, **sem** a inversão de sinal.
      #
      # A convenção é a **oposta** à de `limite_utilizado_on`, no mesmo arquivo e
      # a 20 linhas de distância (`risk_control.rb:91-101` × `:115-124`).
      # Replicado. Sem endpoint exposto (decisão B-12): não há chamador no
      # legado, e inventar um seria feature nova (DEC-09).
      def vencidos_on(control, date = Date.current, cache: nil)
        soma_de(lista(control, date, cache).select(&:is_ended?), date, cache)
      end

      # **BE-248 — a vencer.** Operações não encerradas, também sem inversão.
      def a_vencer_on(control, date = Date.current, cache: nil)
        soma_de(lista(control, date, cache).reject(&:is_ended?), date, cache)
      end

      # =====================================================================
      # S7 / BE-265 + OPS-235 — **a cadeia de saldos**
      # =====================================================================
      #
      # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
      #
      # `create_risk_operations` e `create_risk_movements` estão entre as **24
      # migrations que nunca subiram** (`analise-dump-producao.md` §1): a última
      # migration aplicada em produção é de **25/05/2022** e o sistema rodou até
      # 31/05/2025 sem nenhuma delas. **Não existe uma única operação nem um
      # único movimento no dump.**
      #
      # Logo, o golden desta função tem uma **fonte**, não um **oráculo**: ele
      # trava a leitura de `../sfg/app/models/risk_operation.rb:98-111`, e não um
      # comportamento observado. Se um número sair estranho depois, a resposta
      # está no fonte de 2022 — não numa base que nunca teve estes registros.
      #
      # ## O algoritmo, linha a linha da fonte
      #
      # ```
      # prev_bal = original_balance                       # já negativo (BE-263)
      # movements.order(date: :asc, created_at: :asc).each_with_index do |mov, i|
      #   mov.balance  = prev_bal + (sinal(mov.movement_type) * mov.movement_value)
      #   mov.order    = i + 1
      #   prev_bal     = mov.balance
      # end
      # RiskMovement.import movs, validate: false, ...                # pula validações
      # self.balance = prev_bal                           # ou original_balance se vazio
      # ```
      #
      # `sinal` é `../sfg/app/models/risk_movement_type.rb:53-61`: crédito `C` →
      # **−1**, débito `D` → **+1**.
      #
      # ## Três detalhes que parecem otimizáveis e não são
      #
      # | Detalhe | Por que é comportamento |
      # | ------- | ----------------------- |
      # | Ordem `date asc, created_at asc` | Reordenar por `id` **muda saldo** quando dois movimentos caem no mesmo dia. O índice `(risk_operation_id, date, created_at)` da S5 existe para esta ordenação |
      # | `sequence` reatribuído a partir de 1 a cada recálculo | É a coluna "sequência" do extrato **e** o critério de `last_movement` |
      # | A persistência **pula validações** | Consequência preservada: a janela de datas de `BE-274` **não** é reaplicada aqui. Reaplicá-la faria recálculo legítimo de dado histórico falhar |
      #
      # `activerecord-import` (do legado) **não existe** no `Gemfile` do ai9 —
      # conferido. O equivalente é `upsert_all` (Rails 8), que também pula
      # validações e também escreve **uma vez** para a cadeia inteira
      # (correção **C-03** do mapa, `OPS-235`).
      #
      # Devolve o saldo final — que é o que o chamador grava em
      # `risk_operations.balance`.
      def recalculate_chain(operation)
        anterior = operation.original_balance || 0
        linhas = []

        # `.reload` deliberado quando a associação já está carregada: o
        # recálculo roda no `before_validation` de TODO save, inclusive logo
        # depois de um movimento novo entrar, e uma associação em cache não
        # enxergaria a linha recém-criada.
        movimentos_de(operation).each_with_index do |movimento, indice|
          sinal = movimento.movement_type&.credit_type_value || 0
          movimento.balance = anterior + (sinal * movimento.movement_value)
          movimento.sequence = indice + 1
          anterior = movimento.balance
          linhas << movimento
        end

        persist_chain(linhas)

        anterior
      end

      # **BE-255** — o cartão "última movimentação".
      #
      # Réplica de `../sfg/app/controllers/pub/risk_operations_controller.rb:163-176`
      # (`geral_update_values`), com **uma** diferença, que é a razão de o ID
      # existir: o legado faz `@last_movement.date` sem checar `nil`, então
      # **abrir o detalhe de qualquer operação sem movimento é 500** — e o par
      # estático da S5 nasce exatamente assim. Aqui devolve payload vazio.
      #
      # O último movimento é o de **maior `sequence`**, não o de maior data. Os
      # dois coincidem depois de um recálculo (o `sequence` é reatribuído na
      # ordem de data), e o legado usa `order(order: :asc).last` — replicado.
      def last_movement(operation)
        return {} if operation.nil? || operation.id.nil?

        ultimo = operation.movements.includes(:movement_type).order(sequence: :asc).last
        return {} if ultimo.nil?

        {
          movement_id: ultimo.id,
          movement_date: ultimo.date,
          movement_type: ultimo.movement_type&.title,
          movement_value: ultimo.movement_value,
          movement_value_sign: ultimo.movement_type&.credit_type_value,
          sequence: ultimo.sequence,
          total_balance: operation.balance,
          original_balance: operation.original_balance
        }
      end

      private

      # A cadeia, na ordem canônica. Operação sem `id` (ainda não gravada) não
      # tem movimento — e perguntar ao banco por `risk_operation_id = NULL`
      # devolveria a cadeia de ninguém.
      def movimentos_de(operation)
        return [] if operation.id.nil?

        RiskMovement.where(risk_operation_id: operation.id)
                    .includes(:movement_type)
                    .chain_order
                    .to_a
      end

      # **OPS-235** — uma escrita para a cadeia inteira, pulando validações.
      #
      # `update_only` limita o `DO UPDATE` a `balance` e `sequence`; as demais
      # colunas vão no payload porque o Postgres **monta a tupla antes** de
      # resolver o conflito e recusaria as `NOT NULL` ausentes.
      # `record_timestamps: false` mantém `updated_at` intacto: recalcular saldo
      # não é o usuário tocando no movimento.
      def persist_chain(movimentos)
        alterados = movimentos.select { |m| m.changed? }
        return if alterados.empty?

        RiskMovement.upsert_all(
          alterados.map(&:attributes),
          update_only: %i[balance sequence],
          record_timestamps: false
        )
        alterados.each { |m| m.changes_applied }
      end

      # As operações da janela, **materializadas na ordem do banco**. Sem memória
      # de apuração é a mesma relação com `to_a` — nenhuma diferença de conjunto
      # nem de ordem.
      def lista(control, date, cache)
        return cache.operations_on(control, date) if cache

        operations_on(control, date).to_a
      end

      # A soma linha a linha (B-07): `sum = sum + saldo`, na ordem do banco —
      # nunca `SUM()` no SQL, nunca `.sum { }` sobre um `pluck`. Com float na
      # cadeia, a ordem decide o centavo.
      #
      # O que mudou em relação à primeira versão: os saldos são **carregados em
      # lote antes do laço** (uma consulta para o conjunto, `BalanceReader`), em
      # vez de uma consulta por operação dentro dele. O laço, e portanto a ordem
      # da soma, é o mesmo.
      def soma_de(operacoes, date, cache = nil)
        cache&.prime!(operacoes, date)

        total = 0
        operacoes.each do |operacao|
          total += cache ? cache.balance_on(operacao, date) : operacao.balance_on(date)
        end
        total
      end
    end
  end
end
