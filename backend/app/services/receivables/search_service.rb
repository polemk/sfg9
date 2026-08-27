# frozen_string_literal: true

module Receivables
  # S6 / **BE-150**, **OPS-157**, **OPS-158** — leitura da lista de borderôs.
  #
  # Herda de `ProjectScopedService`, que é o molde vivo do contrato **C1**: o
  # escopo é a primeira linha de toda consulta, o filtro por id é aplicado
  # **dentro** dele, e id de outro projeto responde **404, igual a id
  # inexistente** — distinguir 403 de 404 transformaria o endpoint num oráculo
  # de existência de ids.
  #
  # ## Três defeitos do legado fechados aqui
  #
  # - **D-16** — `receivable_id` por parâmetro **descartava** o filtro de
  #   projeto (`pub/receivables_controller.rb`), família D-01/D-29/D-76/D-100.
  # - **D-20** — `limit`/`offset` eram lidos e **descartados**: a UI de
  #   paginação era decorativa e a última página ia para o lugar errado. Agora é
  #   Kaminari + envelope em cabeçalho (DEC-62), aplicado pelo endpoint.
  # - **OPS-158** — limite de data ausente virava `DateTime.dinosaurs` (ano
  #   −2000) ou `DateTime.mars` (ano +2000). Agora a cláusula é **omitida**.
  #
  # ## Desempenho (Princípio 9), com a prova junto
  #
  # 28 mil linhas é volume real. A listagem carrega portador, carteira, empresa
  # e tipo em `includes` — sem isso são 4 consultas por linha, 200 por página de
  # 50. A ordenação por `carrier`/`wallet` exige `joins`, e ele é aplicado
  # **sempre** para que a consulta seja a mesma com e sem ordenação: dois ramos
  # diferentes foi o que fez a busca do legado devolver conjuntos diferentes
  # conforme a coluna clicada (BE-067).
  class SearchService < ProjectScopedService
    class << self
      def model = ::ReceivableEntry
      def resource_label = 'Borderô'

      def base_scope(project)
        model.for_project(project)
             .joins(:carrier, :wallet)
             .includes(:carrier, :wallet, :company, :receivable_kind, :resource_source, :taxes)
      end

      # **O escopo de AGREGAÇÃO não leva `includes`.** Não é economia: com
      # `includes` + `references`, o `pick`/`pluck` do Rails embrulha a consulta
      # num `SELECT ... FROM (SELECT ... LIMIT 1)` e o `COUNT(*)` passa a contar
      # **a subconsulta**, devolvendo 1 em vez de 120. Foi assim que apareceu,
      # rodando o teste do resumo.
      def summary_scope(project, params)
        scope = model.for_project(project).joins(:carrier, :wallet)
        scope = scope.search(params[:q]) if params[:q].present?
        filter(scope, params)
      end

      # ---------------------------------------------------------------------
      # BE-150 (resumo) — os totais da lista, numa consulta
      # ---------------------------------------------------------------------
      # **Estava dentro do endpoint** (`api/v1/receivables.rb`, `get 'summary'`).
      # Subiu para cá quando a S15 precisou do mesmo número no dashboard: com a
      # consulta no endpoint, o resumo da tela inicial teria de reescrever o
      # `SUM(valor_bruto)`, e o sistema passaria a ter duas fórmulas para "total
      # operado" — o D-09. Uma origem só, dois consumidores.
      def totals(project, params)
        linha = summary_scope(project, params).reorder(nil).pick(
          Arel.sql('COUNT(*)'),
          Arel.sql('COALESCE(SUM(receivable_entries.valor_bruto), 0)'),
          Arel.sql('COALESCE(SUM(receivable_entries.valor_total_tarifas), 0)'),
          Arel.sql('COALESCE(SUM(receivable_entries.valor_liquido), 0)')
        )

        { count: linha[0], valor_bruto: linha[1], valor_total_tarifas: linha[2], valor_liquido: linha[3] }
      end

      # ---------------------------------------------------------------------
      # S15 / NEW-002 — o total operado MÊS A MÊS
      # ---------------------------------------------------------------------
      # Mesmo escopo (`summary_scope`) e mesma coluna (`valor_bruto`) do resumo
      # acima, agrupados pelo mês da operação. Não é métrica nova: é o número do
      # cartão "Total operado", recortado por mês, para que a série e o cartão
      # nunca contem coisas diferentes.
      #
      # **Mês sem borderô é zero, e isso não é o D-117.** Aqui zero é um fato
      # apurado: a janela existe e nela nada foi operado. É diferente do
      # lançamento de indicador, onde "não lançado" é ausência de informação.
      # Por isso este método preenche a janela inteira, mês a mês, em vez de
      # devolver só os meses com movimento.
      #
      # Dono: **S6** (a capability de recebíveis). Consumidor: S15.
      def monthly_totals(project, from:, to:)
        somas = summary_scope(project, { date_from: from, date_to: to })
                .reorder(nil)
                .group(Arel.sql("date_trunc('month', receivable_entries.date)"))
                .sum(:valor_bruto)

        # As chaves voltam como `Time`/`Date` conforme o adaptador; normaliza
        # para o primeiro dia do mês antes de casar com a janela.
        por_mes = somas.transform_keys { |chave| chave.to_date.beginning_of_month }

        meses_entre(from, to).map { |mes| { month: mes, value: por_mes[mes] || 0 } }
      end

      def meses_entre(from, to)
        inicio = from.to_date.beginning_of_month
        fim = to.to_date.beginning_of_month
        return [] if inicio > fim

        meses = []
        atual = inicio
        while atual <= fim
          meses << atual
          atual = atual.next_month
        end
        meses
      end

      def filter(scope, params)
        scope = scope.where(wallet_id: params[:wallet_id]) if params[:wallet_id].present?
        scope = scope.where(carrier_id: params[:carrier_id]) if params[:carrier_id].present?
        scope = scope.where(company_id: params[:company_id]) if params[:company_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope.between_dates(params[:date_from], params[:date_to])
      end
    end
  end
end
