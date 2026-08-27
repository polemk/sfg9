# frozen_string_literal: true

module Risk
  # S5 / BE-266 — **a única leitura de "saldo da operação numa data"**, em lote.
  #
  # ## Por que existe
  #
  # `RiskOperation#balance_on` era uma consulta **por operação**. O painel de
  # exposição chama as fórmulas quatro vezes por limite, e cada fórmula percorre
  # todas as operações da janela: num projeto com 212 operações isso dava
  # **495 consultas e 437 ms** só para desenhar a tela — e é a tela principal do
  # produto.
  #
  # Aqui a pergunta é feita **uma vez para o conjunto**: `DISTINCT ON` devolve o
  # último movimento de cada operação até a data, numa consulta só. O índice que
  # a S5 já criou em `risk_movements` — `(risk_operation_id, date, created_at)` —
  # é exatamente o que ela usa.
  #
  # ## A regra que isto NÃO pode quebrar (decisão B-07)
  #
  # **A ordem da soma não muda.** O que virou lote foi a *leitura do saldo*, não
  # o somatório: as fórmulas continuam percorrendo as operações na ordem em que o
  # banco as devolve e acumulando uma a uma. Com float na cadeia, mudar a ordem
  # mudaria centavos — e é por isso que o ganho foi buscado aqui, e não trocando
  # o laço por um `SUM()`.
  #
  # ## Uma implementação, não duas
  #
  # `RiskOperation#balance_on` **delega para cá**. Não existe uma versão "de uma
  # operação" e outra "de várias" que possam divergir: a de uma é a de várias com
  # um elemento. É o contrato **C2** aplicado dentro do próprio motor.
  #
  # ## O desempate, que o legado deixava indefinido
  #
  # O legado faz `.order(date: :asc, created_at: :asc).last` — e, quando dois
  # movimentos têm **a mesma data e o mesmo `created_at`** (carga em lote na
  # mesma transação), qual deles é "o último" é indefinido: depende da ordem
  # física das linhas. Aqui o desempate final é `id DESC`, o que torna o
  # resultado determinístico **sem mudar nenhum caso que já era determinado**.
  class BalanceReader
    class << self
      # `{operation_id => balance}` para as operações dadas, na data dada.
      # Operação sem nenhum movimento até a data **não aparece no Hash** — quem
      # chama devolve `0`, que é o comportamento replicado (BE-266).
      def last_balances(operation_ids, date)
        ids = Array(operation_ids).compact.uniq
        return {} if ids.empty?

        RiskMovement
          .where(risk_operation_id: ids)
          .where('DATE(risk_movements.date) <= DATE(:d)', d: date.to_date)
          .select('DISTINCT ON (risk_movements.risk_operation_id) ' \
                  'risk_movements.risk_operation_id, risk_movements.balance')
          .order(Arel.sql('risk_movements.risk_operation_id, risk_movements.date DESC, ' \
                          'risk_movements.created_at DESC, risk_movements.id DESC'))
          .each_with_object({}) { |movimento, acc| acc[movimento.risk_operation_id] = movimento.balance }
      end

      # O saldo de UMA operação. É `last_balances` com um elemento — de
      # propósito: assim não há duas leituras que possam divergir.
      #
      # **Sem movimento devolve 0, não `original_balance`** (BE-266). A linha
      # mais fácil de "consertar sem querer" do bloco: o par estático nasce sem
      # movimento, e é por isso que o saldo inicial configurado no limite não
      # entra em agregado nenhum até alguém lançar algo.
      def balance_for(operation, date)
        return 0 if operation.nil? || operation.id.nil?

        last_balances([operation.id], date).fetch(operation.id, 0)
      end
    end
  end
end
