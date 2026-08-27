import { apiClient } from './client'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * Trilha de auditoria — o cliente de `GET /api/v1/audit_trail` (`FE-446`).
 *
 * A trilha é o `paper_trail` (DEC-59): **uma** tabela `versions`, não uma tabela
 * por domínio. O legado tinha `GET /api/v1/trackings`; ela não é portada como
 * rota, e a evidência está no relatório da S19 — as colunas que aqueles filtros
 * usavam (`target_id`, `target_group_*`) nunca eram escritas por nenhum dos 20
 * emissores, e nenhuma tela do legado chamava o endpoint.
 *
 * **Quem lê (DEC-77):** a trilha global é de OG e Admin. O servidor devolve 403
 * para os demais; a tela não deve inferir isso do papel, deve tratar o 403.
 *
 * **Datas em ISO-8601** nos dois sentidos (`FE-440`). Nada de `dd/mm/aaaa` no
 * payload: a formatação acontece só na camada de apresentação.
 */

/** Uma pessoa citada pela trilha. `name` pode vir nulo se a conta foi apagada. */
export interface AuditActor {
  id: string
  name: string | null
  email: string | null
}

export interface AuditVersion {
  id: number
  item_type: string
  item_id: string
  /** Rótulo pt-BR do tipo, vindo do catálogo do servidor. */
  entity_label: string
  event: AuditEvent
  /**
   * A frase em pt-BR. Vem **pronta do servidor**, de propósito: é montada uma
   * vez só, no catálogo (`config/locales/pt-BR.yml`). Montá-la também aqui
   * seria a segunda implementação da mesma frase.
   */
  summary: string
  /** Autor REAL do ato. Em impersonação é quem impersonou, nunca o impersonado. */
  author: AuditActor | null
  /** Preenchido só em impersonação: quem a sessão aparentava ser. */
  impersonated: AuditActor | null
  reason: string | null
  ip_address: string | null
  /** ISO-8601 UTC. */
  occurred_at: string
  /** `campo: [antes, depois]`. */
  changes: Record<string, [unknown, unknown]>
  /** Foto completa do estado anterior — só no detalhe (DEC-78). */
  snapshot?: Record<string, unknown>
}

export type AuditEvent =
  | 'create'
  | 'update'
  | 'destroy'
  | 'impersonate_start'
  | 'impersonate_stop'

export interface AuditTrailFilters extends PageRequest {
  itemType?: string
  itemId?: string
  /** Id do autor real. */
  whodunnit?: string
  event?: AuditEvent
  /** ISO-8601. */
  from?: string
  /** ISO-8601. */
  to?: string
}

export interface AuditTrailPage {
  versions: AuditVersion[]
  meta: PageMeta
}

export interface AuditTypeOption {
  value: string
  label: string
}

function queryOf(f: AuditTrailFilters): Record<string, string | number> {
  const q: Record<string, string | number> = { ...pageParams(f) }
  if (f.itemType) q.item_type = f.itemType
  if (f.itemId) q.item_id = f.itemId
  if (f.whodunnit) q.whodunnit = f.whodunnit
  if (f.event) q.event = f.event
  if (f.from) q.from = f.from
  if (f.to) q.to = f.to
  return q
}

export const auditTrailApi = {
  /**
   * Índice da trilha. Os filtros são **combináveis**: cada um estreita o
   * anterior, e o total do envelope é o do filtrado.
   */
  list: async (filters: AuditTrailFilters = {}): Promise<AuditTrailPage> => {
    const resposta = await apiClient.getRaw<AuditVersion[]>('/api/v1/audit_trail', {
      params: queryOf(filters),
    })
    return {
      versions: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filters),
    }
  },

  /** Detalhe, com a foto completa do estado anterior. */
  get: (id: number) => apiClient.get<AuditVersion>(`/api/v1/audit_trail/${id}`),

  /**
   * Vocabulário do filtro por tipo. Vem do servidor para a tela não precisar
   * conhecer a lista de models versionados — que é declarada num lugar só
   * (`Sfg::AuditTrail::VERSIONED`) e cresce a cada fatia.
   */
  types: () => apiClient.get<AuditTypeOption[]>('/api/v1/audit_trail/types'),
}
