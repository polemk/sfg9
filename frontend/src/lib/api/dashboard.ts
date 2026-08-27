import { apiClient } from './client'

/**
 * S15 — **o cliente do painel** (`NEW-002`) e do volume por portador
 * (`NEW-001`, parte 2).
 *
 * > **Feature NOVA (DEC-21), não paridade.** Nada disto existe no legado — o
 * > `dash` de lá é uma tela vazia (`DB-399`, `dropped`). O QA do Phase 4 **não
 * > deve procurar estas telas na origem**.
 *
 * ## A regra que segura a fatia: aqui não nasce número
 *
 * O servidor devolve **valor, rótulo e destino**; o cliente formata e navega.
 * Nenhum `reduce`, nenhuma soma, nenhuma média neste arquivo nem nas telas que
 * o consomem. Somar no cliente daria ao sistema uma segunda fórmula para o
 * mesmo valor (contrato **C2**, defeito **D-09**) — e seria a segunda **sem
 * teste**, porque teste de front não conhece o dado de produção.
 *
 * ## Dinheiro chega como STRING, e é de propósito
 *
 * `valor_bruto` e a exposição são `decimal` no banco. Serializados como número
 * de JSON eles perdem centavo em valores grandes; então o servidor os manda como
 * string e a conversão para `number` acontece **num lugar só** — aqui, em
 * `numeroDe`, na fronteira. Espalhar `Number(x)` pelas telas é como uma delas
 * acaba mostrando `NaN` sem ninguém notar.
 *
 * ## Sem polling (Princípio 10)
 *
 * Nenhuma consulta desta superfície usa `refetchInterval`. A atualização é o
 * refetch normal do React Query ao navegar/focar; se algum número precisar ser
 * vivo, o caminho é Action Cable, nunca `setInterval`.
 */

/** Como o cartão deve ser formatado na tela. O servidor decide, não o layout. */
export type DashboardCardFormat = 'currency' | 'integer'

export interface DashboardCard {
  /** Chave estável — é por ela que a tela escolhe o ícone. */
  key: string
  label: string
  /** Linha de contexto: o período ou a data de apuração. */
  hint: string
  /**
   * **`null` = SEM DADO**, e nunca "zero" (D-117). Nenhum borderô no período,
   * nenhum limite ativo, nenhuma renegociação no projeto. Zero é um fato
   * apurado; ausência é falta de informação, e num sistema de crédito as duas
   * coisas levam a decisões opostas.
   *
   * Moeda vem como **string**; contagem vem como número.
   */
  value: string | number | null
  format: DashboardCardFormat
  /**
   * Para onde o cartão navega. **Vem do servidor de propósito**: com a rota
   * codificada no componente, o dia em que o menu mudasse deixaria o painel
   * apontando para uma tela que não existe mais, e ninguém olharia aqui.
   */
  href: string
}

export interface DashboardSeries {
  labels: string[]
  /** Moeda como string — ver `numeroDe`. */
  values: (string | number)[]
  /**
   * `false` = a janela inteira está zerada. Distingue "não houve operação" de
   * "há movimento", para que a tela não desenhe uma linha rente ao eixo, que
   * parece defeito de renderização.
   */
  has_data: boolean
}

/**
 * Um tipo de limite e o quanto dele já foi consumido — a resposta a "algum
 * limite está perto do teto?".
 *
 * `percent_label` e `at_ceiling` chegam **prontos** do servidor: o texto do
 * percentual é o mesmo da tabela do console de risco (com os arredondamentos que
 * a DEC-01 manda preservar) e o estado do semáforo é decidido onde o número
 * nasce. A tela não recalcula nenhum dos dois.
 */
export interface DashboardLimit {
  label: string
  used: string | number
  total: string | number
  available: string | number
  percent_label: string
  at_ceiling: boolean
}

export interface DashboardLimits {
  date: string
  items: DashboardLimit[]
  has_data: boolean
}

/**
 * Um limite na **faixa de atenção** (DEC-116): de 90% (inclusive) a 100%
 * (exclusive) do teto consumido. Quem já estourou não está aqui — ele é contado
 * pelo cartão "Limites no teto", e cada limite aparece em exatamente um lugar.
 *
 * `percent` chega como **número** (`98.7`), e a formatação é daqui — nunca do
 * domínio, pela mesma regra que tirou a formatação monetária do backend
 * (OPS-289). Limite com teto zero **não entra na lista**: `utilizado / 0` não é
 * 100%, é indefinido, e deixá-lo passar produziria `Infinity` no JSON e `NaN` na
 * tela.
 */
export interface DashboardNearCeilingItem {
  id: string
  title: string
  carrier_title: string
  operation_type_title: string
  used: string | number
  total: string | number
  available: string | number
  percent: number
}

export interface DashboardNearCeiling {
  date: string
  /** O corte, em pontos percentuais. Vem do domínio para a tela não repeti-lo. */
  threshold: number
  items: DashboardNearCeilingItem[]
  /**
   * `false` = **nenhum limite acima do corte** — que é uma resposta, e boa. Não
   * é "não há informação": para isso o bloco inteiro vem `null`.
   */
  has_data: boolean
}

/**
 * Uma renegociação **em atraso** — o par da lista de limites: o cartão conta,
 * esta lista nomeia. `overdue_count` é contagem de parcelas vencidas, apurada
 * na consulta (OPS-473/BE-207); `total_debt` é lido da coluna que o agregado da
 * renegociação mantém, exatamente como a tela de detalhe faz.
 */
export interface DashboardOverdueRenegotiation {
  id: string
  title: string
  provider_name: string
  kind: string
  overdue_count: number
  total_debt: string | number
}

export interface DashboardOverdueRenegotiations {
  date: string
  /** Truncada para caber no painel — `total` diz quantas existem de verdade. */
  items: DashboardOverdueRenegotiation[]
  total: number
  has_data: boolean
}

export interface DashboardSummary {
  date: string
  /** O escopo do que está na tela. Nome, não número. */
  project: { id: string; name: string }
  period: { from: string; to: string }
  /**
   * **Pode vir com menos de quatro itens.** Cartão que o papel não pode ver
   * **some** do payload em vez de vir zerado — zero e "não autorizado" são
   * estados diferentes.
   */
  cards: DashboardCard[]
  /** `null` quando o solicitante não pode ver recebíveis. */
  series: DashboardSeries | null
  /** `null` quando o papel não vê risco, ou quando não há limite ativo. */
  limits: DashboardLimits | null
  /** `null` quando o papel não alcança `risk_controls`, ou não há limite ativo. */
  near_ceiling: DashboardNearCeiling | null
  /** `null` quando o papel não alcança `renegotiations`. */
  overdue_renegotiations: DashboardOverdueRenegotiations | null
}

export interface CarrierVolume {
  date: string
  labels: string[]
  values: (string | number)[]
  has_data: boolean
}

/**
 * A conversão de `decimal` (string) para `number`, **num lugar só**.
 *
 * `null`/`undefined` continuam `null` — é o que preserva a distinção entre
 * ausência e zero até a última linha da tela.
 */
export function numeroDe(valor: string | number | null | undefined): number | null {
  if (valor === null || valor === undefined) return null
  const n = typeof valor === 'number' ? valor : Number(valor)
  return Number.isFinite(n) ? n : null
}

export function valoresDaSerie(serie: { values: (string | number)[] } | null | undefined): number[] {
  return (serie?.values ?? []).map((v) => numeroDe(v) ?? 0)
}

export const dashboardApi = {
  /** `date` e `months` são opcionais: o servidor usa hoje e 12 meses. */
  summary: (params?: { date?: string; months?: number }) =>
    apiClient.get<DashboardSummary>('/api/v1/dashboard/summary', { params }),

  volumeByCarrier: (params?: { date?: string }) =>
    apiClient.get<CarrierVolume>('/api/v1/dashboard/volume_by_carrier', { params }),
}

export const DASHBOARD_SUMMARY_KEY = ['dashboard', 'summary'] as const
export const CARRIER_VOLUME_KEY = ['dashboard', 'volume-by-carrier'] as const
