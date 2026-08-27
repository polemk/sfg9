import { apiClient } from './client'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * S3 — os **cinco catálogos globais** (`FE-060..FE-078`, `FE-116`, `FE-117`).
 *
 * Um cliente só para os cinco porque eles são o mesmo objeto com colunas
 * diferentes. Cinco arquivos quase iguais é como se chega a cinco leituras
 * diferentes do envelope de paginação — que é exatamente o que
 * `lib/api/pagination.ts` existe para impedir.
 *
 * **Catálogo global não é escopado por projeto** (contrato C1, regra 4): estas
 * chamadas NÃO mandam `X-Project-Id` nem `project_id`, e o servidor não chama
 * `current_project!`. O menu esconde a tela de administração do catálogo, não o
 * dado do catálogo — por isso o Colaborador não vê o grupo "Cadastro" e mesmo
 * assim os dropdowns dele sobem populados (DEC-18.4).
 *
 * O envelope vem em **cabeçalho** (`X-Total-Count`/`X-Page`/`X-Per-Page`/
 * `X-Total-Pages`, DEC-62) e é lido por `readPageMeta` — aqui e em lugar
 * nenhum mais.
 */

// --- Tipos --------------------------------------------------------------

/** O que os cinco têm em comum. */
export interface CatalogRecord {
  id: string
  title: string
  integration_key: string
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface Segment extends CatalogRecord {
  projects_count: number
}

export type SubSegment = Segment

export interface CarrierGroup extends CatalogRecord {
  carriers_count: number
}

/** Os quatro agentes financeiros — conjunto FECHADO no servidor (DB-059). */
export const FINANCIAL_AGENTS = ['FIDC', 'Securitizadora', 'Factoring', 'Cliente'] as const
export type FinancialAgent = (typeof FINANCIAL_AGENTS)[number]

export interface Carrier extends CatalogRecord {
  resume: string | null
  group_id: string | null
  group_title: string | null
  financial_agent: FinancialAgent | null
  /** **String**, sempre: `001` é `001` e nunca `1` (DC-12). */
  bank_code: string | null
  city: string | null
  uf: string | null
  /** Cidade formatada com fallback `-` — vem pronta do servidor (BE-071). */
  city_label: string
  net_worth: string | number | null
  senior_accounts: number
  subordinated_accounts: number
  /**
   * **Somente leitura**: derivado no servidor a partir das cotas (DC-09).
   * `null` = não há estrutura de cotas, que é diferente de 0%.
   */
  subordinated_accounts_percent: string | number | null
  logo_url: string | null
  projects_count: number
}

export interface GuaranteeType extends CatalogRecord {
  /** DEC-86 — o tipo foi semeado como suposição; a lista definitiva é do cliente. */
  is_provisional: boolean
  sort_order: number
  description: string | null
  observation: string | null
  guarantees_count: number
}

export interface CatalogPage<T> {
  items: T[]
  meta: PageMeta
}

export interface CatalogQuery extends PageRequest {
  q?: string
  active?: boolean
  /** Chave pública da coluna: `title`, `key`, … O servidor ignora o que não conhece. */
  orderingKey?: string
  orderingStyle?: 'up' | 'down'
}

export interface CarrierQuery extends CatalogQuery {
  groupId?: string
  financialAgent?: FinancialAgent
  uf?: string
}

export interface BrState {
  code: string
  name: string
}

// --- Fiação -------------------------------------------------------------

function queryOf(f: CatalogQuery): Record<string, string | number | string[]> {
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

async function listar<T>(path: string, params: Record<string, unknown>, pedido: PageRequest): Promise<CatalogPage<T>> {
  const resposta = await apiClient.getRaw<T[]>(path, { params })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, pedido),
  }
}

/**
 * Fábrica do cliente de um catálogo. Um molde, cinco instâncias.
 *
 * **Exportada na S4** porque os recursos ESCOPADOS POR PROJETO (empresas,
 * fornecedores, garantias) falam exatamente o mesmo dialeto de lista: `q`,
 * `ordering_keys[]`/`ordering_style[]` e o envelope de paginação em cabeçalho
 * (DEC-62). Uma segunda fábrica seria uma segunda leitura do envelope — que é
 * justamente o que `lib/api/pagination.ts` existe para impedir.
 *
 * O que NÃO se compartilha é a regra de escopo: catálogo global não manda
 * `X-Project-Id` nem `project_id`, e os recursos da S4 são resolvidos pelo
 * servidor a partir do projeto corrente. Nos dois casos o cliente não decide
 * escopo — e é por isso que a mesma fábrica serve aos dois.
 */
export function catalogApi<T, Q extends CatalogQuery = CatalogQuery>(path: string, extra?: (f: Q) => Record<string, unknown>) {
  return {
    list: (filtros: Q = {} as Q) => listar<T>(path, { ...queryOf(filtros), ...(extra?.(filtros) ?? {}) }, filtros),
    get: (id: string) => apiClient.get<T>(`${path}/${id}`),
    create: (dados: Record<string, unknown>) => apiClient.post<T>(path, dados),
    update: (id: string, dados: Record<string, unknown>) => apiClient.put<T>(`${path}/${id}`, dados),
    remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`${path}/${id}`),
  }
}

export const segmentsApi = catalogApi<Segment>('/api/v1/segments')
export const subSegmentsApi = catalogApi<SubSegment>('/api/v1/sub_segments')
export const carrierGroupsApi = catalogApi<CarrierGroup>('/api/v1/carrier_groups')
export const guaranteeTypesApi = catalogApi<GuaranteeType>('/api/v1/project_guarantee_types')

export const carriersApi = {
  ...catalogApi<Carrier, CarrierQuery>('/api/v1/carriers', (f) => {
    const extra: Record<string, unknown> = {}
    if (f.groupId) extra.group_id = f.groupId
    if (f.financialAgent) extra.financial_agent = f.financialAgent
    if (f.uf) extra.uf = f.uf
    return extra
  }),

  /**
   * Logo do portador (DEC-47). ActiveStorage no próprio model (DEC-91) — não é
   * `Medium`, cuja tabela não tem dono nem escopo (DEC-91/DEC-109).
   */
  uploadLogo: (id: string, file: File) => {
    const form = new FormData()
    form.append('file', file)
    return apiClient.post<Carrier>(`/api/v1/carriers/${id}/logo`, form)
  },
  removeLogo: (id: string) => apiClient.delete<Carrier>(`/api/v1/carriers/${id}/logo`),
}

/**
 * UFs do Brasil — **cadastro, não geocodificação** (OPS-057 / L-11). No legado
 * cidade e UF do portador saíam de um `geocoder` com timeout de ~3h20 e sem
 * cache; a gem não é portada.
 */
export const brStatesApi = {
  list: async (): Promise<BrState[]> => {
    const { states } = await apiClient.get<{ states: BrState[] }>('/api/v1/br_states')
    return states ?? []
  },
}

/** Mensagem de erro do servidor, já no formato único `{error, message, code}`. */
export function mensagemDoServidor(erro: unknown, padrao: string): string {
  const e = erro as any
  return e?.response?.data?.message ?? e?.response?.data?.error ?? e?.message ?? padrao
}
