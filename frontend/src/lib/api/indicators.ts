import { apiClient } from './client'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * S10 — **indicadores, conexões e a grade mensal** (`FE-310..FE-329`, `FE-718`,
 * `FE-719`).
 *
 * Três superfícies com duas regras de escopo opostas, e as duas de propósito:
 *
 * - **`indicatorsApi`** fala com o **catálogo GLOBAL** (`indicators.project_id IS NULL`).
 *   Não manda projeto nenhum, e o servidor não chama `current_project!`
 *   (contrato C1, regra 4). O Colaborador lê (DEC-18.4) — é o que faz o
 *   dropdown dele subir populado.
 * - **`indicatorConnectionsApi`** e **`indicatorEntriesApi`** são **escopadas
 *   pelo projeto corrente**, resolvido no servidor. O `project_id` NUNCA vai no
 *   corpo: no legado ele vinha num campo escondido do formulário e era isso que
 *   permitia gravar em projeto alheio.
 *
 * O envelope de paginação vem em **cabeçalho** (DEC-62) e é lido por
 * `readPageMeta` — aqui e em lugar nenhum mais.
 */

// --- Tipos ----------------------------------------------------------------

/** `global` = catálogo compartilhado; `project` = específico de um projeto. */
export type IndicatorScope = 'global' | 'project'

export interface Indicator {
  id: string
  /**
   * **CAIXA ALTA e sem acento, sempre** (DEC-89). Não é formatação de exibição:
   * é o que está gravado. "Inadimplência" chega aqui como "INADIMPLENCIA".
   */
  title: string
  /** Chave de Integração. Congelada na criação (DEC-85). */
  key: string
  value_type: string
  is_active: boolean
  project_id: string | null
  scope: IndicatorScope
  /** A "Instrução", em HTML (ActionText). **Sanitizar na leitura** — ver `RichTextField`. */
  description_html: string | null
  /** Lançamentos existentes. É o número que a confirmação de exclusão mostra. */
  entries_count: number
  projects_count: number
  discarded_at: string | null
  created_at: string
  updated_at: string
}

export interface IndicatorConnectionRow {
  id: string
  title: string
  key: string
  is_active: boolean
  scope: IndicatorScope
  connected: boolean
  description_html: string | null
  entries_count: number
}

export interface IndicatorEntry {
  id: string
  indicator_id: string
  year: number
  month: number
  /** **String**, sempre: é `decimal(15,2)` e float no JSON arredonda torto. */
  value: string
  title: string
  value_type: string
  created_by: string | null
  updated_by: string | null
  created_at: string
  updated_at: string
}

export interface GridCell {
  month: number
  /**
   * **`null` = NÃO LANÇADO** (DEC-70). Um lançamento de zero vem como objeto com
   * `value: "0.0"`. Os dois são estados diferentes e a tela tem de mostrá-los
   * diferentes — no legado ambos apareciam como `0`.
   */
  entry: IndicatorEntry | null
}

export interface GridRow {
  indicator: Indicator
  cells: GridCell[]
}

export interface DeletionImpact {
  id: string
  title: string
  entries_count: number
  projects: { id: string; name: string }[]
}

export interface IndicatorPage {
  items: Indicator[]
  meta: PageMeta
}

export interface IndicatorQuery extends PageRequest {
  q?: string
  active?: boolean
  orderingKey?: string
  orderingStyle?: 'up' | 'down'
}

export interface IndicatorInput {
  title?: string
  key?: string
  is_active?: boolean
  description?: string
  scope?: IndicatorScope
}

export interface GridQuery {
  year: number
  /** Omitido = os 12 meses. */
  month?: number | null
  indicatorId?: string | null
}

export interface ConnectionResult {
  items: { indicator_id: string; title?: string; ok: boolean; state?: string; error?: string }[]
  connected_ids: string[]
}

// --- Fiação ---------------------------------------------------------------

function queryOf(f: IndicatorQuery): Record<string, string | number | string[]> {
  const q: Record<string, string | number | string[]> = { ...pageParams(f) }
  if (f.q) q.q = f.q
  if (f.active) q.active = 'true'
  // Arrays paralelos: é o contrato de `Sfg::Sortable` no servidor, e é o
  // formato que o legado já falava (`ordering_keys[]` / `ordering_style[]`).
  if (f.orderingKey) {
    q['ordering_keys[]'] = [f.orderingKey]
    q['ordering_style[]'] = [f.orderingStyle ?? 'up']
  }
  return q
}

const BASE = '/api/v1/indicators'

export const indicatorsApi = {
  list: async (filtros: IndicatorQuery = {}): Promise<IndicatorPage> => {
    const resposta = await apiClient.getRaw<Indicator[]>(BASE, { params: queryOf(filtros) })
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  get: (id: string) => apiClient.get<Indicator>(`${BASE}/${id}`),

  /**
   * O que uma exclusão afeta — lido **antes** de qualquer escrita (FE-315).
   * É o que fecha o **D-66 na copy**: no legado a confirmação dizia só "A
   * operação não pode ser desfeita" e não mencionava que **todos os lançamentos
   * históricos** iriam junto.
   */
  deletionImpact: (id: string) => apiClient.get<DeletionImpact>(`${BASE}/${id}/deletion_impact`),

  create: (dados: IndicatorInput) => apiClient.post<Indicator>(BASE, dados),
  update: (id: string, dados: IndicatorInput) => apiClient.put<Indicator>(`${BASE}/${id}`, dados),

  setActive: (id: string, is_active: boolean) =>
    apiClient.put<Indicator>(`${BASE}/${id}/activation`, { is_active }),

  /** Exclusão **lógica**: os lançamentos ficam, e a resposta diz quantos. */
  remove: (id: string) =>
    apiClient.delete<{ deleted: boolean; entries_preserved: number }>(`${BASE}/${id}`),
}

const CONEXOES = '/api/v1/indicator_connections'

export const indicatorConnectionsApi = {
  list: async (filtros: IndicatorQuery = {}): Promise<{ items: IndicatorConnectionRow[]; meta: PageMeta }> => {
    const resposta = await apiClient.getRaw<IndicatorConnectionRow[]>(CONEXOES, { params: queryOf(filtros) })
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  connect: (indicatorIds: string[]) =>
    apiClient.post<ConnectionResult>(`${CONEXOES}/connect`, { indicator_ids: indicatorIds }),

  /**
   * Desconectar **esconde** o indicador da grade e **não apaga lançamento**
   * (Q-R31, replicado). Reconectar traz o histórico de volta inteiro.
   */
  disconnect: (indicatorIds: string[]) =>
    apiClient.post<ConnectionResult>(`${CONEXOES}/disconnect`, { indicator_ids: indicatorIds }),

  /** Exclui um indicador **específico** deste projeto (exclusão lógica). */
  removeSpecific: (indicatorId: string) =>
    apiClient.delete<{ deleted: boolean; entries_preserved: number }>(`${CONEXOES}/${indicatorId}`),
}

const LANCAMENTOS = '/api/v1/indicator_entries'

export const indicatorEntriesApi = {
  /**
   * A grade. **É o mesmo serviço que grava a célula** (contrato C2) — o valor
   * exibido e o gravado não podem divergir.
   *
   * É também o endpoint que a **S15** consome para o gráfico `NEW-001`: nenhuma
   * agregação nova nasce no cliente.
   */
  grid: ({ year, month, indicatorId }: GridQuery) =>
    apiClient.get<GridRow[]>(`${LANCAMENTOS}/grid`, {
      params: {
        year,
        ...(month ? { month } : {}),
        ...(indicatorId ? { indicator_id: indicatorId } : {}),
      },
    }),

  /** Autosave de UMA célula. `value` vai como string para não passar por float. */
  upsert: (dados: { indicator_id: string; year: number; month: number; value: string }) =>
    apiClient.put<IndicatorEntry>(LANCAMENTOS, dados),

  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`${LANCAMENTOS}/${id}`),
}

/** Mensagem de erro do servidor, no formato único `{error, message, code}`. */
export function mensagemDoServidor(erro: unknown, padrao: string): string {
  const e = erro as any
  return e?.response?.data?.message ?? e?.response?.data?.error ?? e?.message ?? padrao
}

/** `code` do erro do servidor — `READONLY_RESTRICTED`, `ROLE_REQUIRED`… */
export function codigoDoServidor(erro: unknown): string | undefined {
  return (erro as any)?.response?.data?.code
}
