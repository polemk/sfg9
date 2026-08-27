import { apiClient } from './client'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * Contratos — Termos de Uso e Política de Privacidade.
 *
 * **Dois recursos, de propósito (DEC-38):**
 *
 *  - `contracts` — **ler e aceitar**. `R` para os quatro papéis.
 *  - `contract_versions` — **publicar e administrar**. CRUD só para OG e Admin.
 *
 * O legado não tinha recurso nenhum: `contracts_controller.rb` tem 101 linhas e
 * zero autorização, e as rotas não têm constraint. Qualquer autenticado
 * publicava os Termos de Uso. **O gate é do servidor** — esta camada só
 * organiza as chamadas; esconder o botão não autoriza nada.
 *
 * **DEC-65 — o aceite é AÇÃO, sem bloqueio.** Nada aqui interrompe navegação:
 * `pending()` alimenta o banner persistente e o botão. Bloquear o acesso numa
 * demo comercial trava o cliente na primeira tela.
 */

export type ContractKind = string

export interface Contract {
  id: string
  kind: ContractKind
  slug: string
  title: string
  version: number
  published_at: string
  created_at: string
  updated_at: string
  /** Só no detalhe. Já vem **sanitizado** pelo servidor (allowlist do BE-345). */
  description_html?: string
  creator?: { id: string; name: string } | null
  /** Só para quem administra. */
  accepted_count?: number
  divergent_count?: number
}

export interface PendingContract {
  id: string
  kind: ContractKind
  slug: string
  title: string
  version: number
  published_at: string
  /** Informativo: passado o prazo a interface insiste mais. **Não bloqueia.** */
  tolerance_until: string
  overdue: boolean
}

/** DEC-66 — o histórico distingue quem aceitou de quem foi carimbado. */
export type DealSource = 'explicit' | 'implicit_legacy'

export interface ContractDeal {
  id: string
  contract_id: string
  kind: ContractKind
  version: number
  accepted_at: string
  source: DealSource
  legacy_accepted_at: string | null
  hash_matches_current: boolean
}

export interface TermsStatus {
  pending: PendingContract[]
  accepted: ContractDeal[]
}

export interface ContractCatalogEntry {
  kind: ContractKind
  slug: string
  current_version: number | null
  versions_count: number
  accepted_count: number
}

export interface ContractPrefill {
  kind: ContractKind
  slug: string
  next_version: number
  title: string
  description_html: string
  previous_version: number | null
  previous_id: string | null
  current_accepted_count: number
}

export interface ContractImpact {
  accepted_count: number
  divergent_count: number
  is_current: boolean
}

export interface ContractVersionsPage {
  versions: Contract[]
  meta: PageMeta
}

export interface ContractVersionFilters extends PageRequest {
  kind?: string
  q?: string
}

/** Leitura e aceite — o que qualquer papel alcança. */
export const contractsApi = {
  /** Uma linha por tipo, com a versão vigente. */
  list: () => apiClient.get<Contract[]>('/api/v1/contracts'),

  get: (id: string) => apiClient.get<Contract>(`/api/v1/contracts/${id}`),

  /** O que alimenta o banner. Nunca bloqueia navegação (DEC-65). */
  pending: () => apiClient.get<PendingContract[]>('/api/v1/contracts/pending'),

  /**
   * Aceita UMA versão. `PUT` porque o efeito é idempotente — e porque é o verbo
   * que o legado já usava (`routes.rb:47`).
   *
   * O usuário **não viaja no payload**: é sempre o da sessão. No legado
   * `user_id` estava no `permit` e o primeiro `create` podia gravar aceite em
   * nome de outro (D-68).
   */
  accept: (id: string) => apiClient.put<ContractDeal>(`/api/v1/contracts/${id}/accept`),

  /** Situação dos Termos para o usuário da sessão: pendências + histórico. */
  myTerms: () => apiClient.get<TermsStatus>('/api/v1/me/terms'),

  /** Aceita TUDO o que está pendente num clique — é o botão do banner. */
  acceptAllPending: () => apiClient.post<TermsStatus>('/api/v1/me/terms'),
}

/** Publicação e administração — OG e Admin (DEC-38). */
export const contractVersionsApi = {
  list: async (filters: ContractVersionFilters = {}): Promise<ContractVersionsPage> => {
    const params: Record<string, string | number> = { ...pageParams(filters) }
    if (filters.kind) params.kind = filters.kind
    if (filters.q) params.q = filters.q

    const resposta = await apiClient.getRaw<Contract[]>('/api/v1/contract_versions', { params })
    return {
      versions: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filters),
    }
  },

  catalog: () => apiClient.get<ContractCatalogEntry[]>('/api/v1/contract_versions/catalog'),

  get: (id: string) => apiClient.get<Contract>(`/api/v1/contract_versions/${id}`),

  /** O primeiro contrato de um tipo abre VAZIO — no legado esse caso estourava. */
  prefill: (kind: string) =>
    apiClient.get<ContractPrefill>('/api/v1/contract_versions/prefill', { params: { kind } }),

  /** Mitigação 2 da DEC-80: quantos aceites ficam com hash divergente. */
  impact: (id: string) => apiClient.get<ContractImpact>(`/api/v1/contract_versions/${id}/impact`),

  create: (payload: { kind: string; title: string; description: string }) =>
    apiClient.post<Contract>('/api/v1/contract_versions', payload),

  update: (id: string, payload: { title?: string; description?: string }) =>
    apiClient.put<Contract>(`/api/v1/contract_versions/${id}`, payload),

  remove: (id: string) => apiClient.delete<{ success: boolean }>(`/api/v1/contract_versions/${id}`),

  /**
   * Baixa a prova de aceite (OPS-333).
   *
   * **Não é `<a href>`.** O access token vive em memória, não em cookie: uma
   * navegação direta ao endpoint sai sem `Authorization` e volta 401 — e o
   * usuário veria uma tela de erro em vez do arquivo. O download passa pelo
   * `apiClient` (que anexa o token) e vira `blob` local.
   */
  downloadProof: async (id: string, filename: string) => {
    const blob = await apiClient.get<Blob>(`/api/v1/contract_versions/${id}/proof`, {
      responseType: 'blob',
    })
    const url = window.URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.setAttribute('download', filename)
    document.body.appendChild(link)
    link.click()
    link.parentNode?.removeChild(link)
    window.URL.revokeObjectURL(url)
  },
}

export interface PublicContract extends Contract {
  /** Caminho resolvido pelo SERVIDOR, a partir da allowlist. Nunca o parâmetro. */
  return_to: string
  return_to_allowed: boolean
}

/**
 * Superfície pública — leitura sem sessão.
 *
 * **D-69**: `returnTo` é uma **chave** (`login`, `console`, `profile`, `faq`),
 * nunca uma URL. O legado interpolava o parâmetro na view e o usava como
 * destino: XSS refletido **e** open redirect na mesma variável. Aqui o cliente
 * manda a chave e recebe de volta o caminho — texto do visitante não vira href
 * em lugar nenhum.
 */
export const publicContractsApi = {
  kinds: () =>
    apiClient.getPublic<{ kinds: { kind: string; slug: string }[]; return_destinations: string[] }>(
      '/api/v1/public/contracts',
    ),

  get: (kindOrSlug: string, returnTo?: string) =>
    apiClient.getPublic<PublicContract>(
      `/api/v1/public/contracts/${encodeURIComponent(kindOrSlug)}`,
      returnTo ? { params: { return_to: returnTo } } : undefined,
    ),
}
