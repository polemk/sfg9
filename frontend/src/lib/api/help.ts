import { apiClient } from './client'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * Central de ajuda, FAQ e **ajuda de campo**.
 *
 * Três coisas que o legado errava e que a forma do cliente já impede:
 *
 *  1. **Categoria é obrigatória** em `faqItems`. No legado ausente virava
 *     `where(help_category_id: nil)`, zero itens, e a tela dizia "nenhum
 *     resultado" — mentira sobre o acervo.
 *  2. **A contagem total vem no envelope.** Sem ela o front pedia `l = 30` e
 *     qualquer instalação com mais de 30 itens perdia itens em silêncio.
 *  3. **A busca é por texto, e só.** Não existe `q` virando `id` — era o
 *     `q.to_i` que fazia o termo `0` casar a base inteira.
 */

export interface HelpGroup {
  id: string
  title: string
  position: number
  categories?: HelpCategory[]
}

export interface HelpCategory {
  id: string
  title: string
  /** **Persistido** (DB-368). Não muda ao renomear: é deep-link. */
  slug: string
  help_group_id: string
  position: number
  items_count: number
}

export interface HelpItem {
  id: string
  title: string
  help_category_id: string
  position: number
  created_at: string
  updated_at: string
  category: { id: string; title: string; slug: string } | null
  group: { id: string; title: string } | null
  /** AUTOR — preservado na edição (FE-366). */
  author: { id: string; name: string } | null
  last_updated_user: { id: string; name: string } | null
  description_html?: string
  /** Trecho em volta do termo buscado. Determinístico. */
  excerpt?: string
}

export interface HelpItemsPage {
  items: HelpItem[]
  meta: PageMeta
}

export interface HelpImpact {
  categories: number
  items: number
}

/** `{ escopo: { coluna: texto } }`. Chaves `TODO:` já vêm removidas. */
export type FieldHelpMap = Record<string, Record<string, string>>

async function listaPaginada(url: string, params: Record<string, any>, req: PageRequest) {
  const resposta = await apiClient.getRaw<HelpItem[]>(url, { params })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, req),
  }
}

export const faqApi = {
  /** A árvore de grupos e categorias. */
  tree: () => apiClient.get<HelpGroup[]>('/api/v1/faq'),

  /** Itens de UMA categoria — `categoryId` é obrigatório de propósito. */
  items: (categoryId: string, options: PageRequest & { q?: string } = {}) =>
    listaPaginada(
      '/api/v1/faq/items',
      { category_id: categoryId, q: options.q || undefined, ...pageParams(options) },
      options,
    ),

  /** Busca em todo o acervo — o conteúdo rico, não a coluna morta (D-58). */
  search: (q: string, options: PageRequest = {}) =>
    listaPaginada('/api/v1/faq/search', { q, ...pageParams(options) }, options),

  get: (id: string) => apiClient.get<HelpItem>(`/api/v1/faq/items/${id}`),
}

export const helpAdminApi = {
  tree: () => apiClient.get<HelpGroup[]>('/api/v1/help_groups'),

  createGroup: (payload: { title: string }) => apiClient.post<HelpGroup>('/api/v1/help_groups', payload),
  updateGroup: (id: string, payload: { title?: string; position?: number }) =>
    apiClient.put<HelpGroup>(`/api/v1/help_groups/${id}`, payload),
  /** A contagem da subárvore vem do SERVIDOR — no legado era texto fixo no JS. */
  groupImpact: (id: string) => apiClient.get<HelpImpact>(`/api/v1/help_groups/${id}/impact`),
  removeGroup: (id: string) =>
    apiClient.delete<{ success: boolean; deleted: HelpImpact }>(`/api/v1/help_groups/${id}`),

  createCategory: (payload: { help_group_id: string; title: string }) =>
    apiClient.post<HelpCategory>('/api/v1/help_categories', payload),
  updateCategory: (id: string, payload: { title?: string; help_group_id?: string; position?: number }) =>
    apiClient.put<HelpCategory>(`/api/v1/help_categories/${id}`, payload),
  categoryImpact: (id: string) => apiClient.get<HelpImpact>(`/api/v1/help_categories/${id}/impact`),
  removeCategory: (id: string) =>
    apiClient.delete<{ success: boolean; deleted: HelpImpact }>(`/api/v1/help_categories/${id}`),

  items: (options: PageRequest & { q?: string; categoryId?: string } = {}) =>
    listaPaginada(
      '/api/v1/help_items',
      { q: options.q || undefined, category_id: options.categoryId || undefined, ...pageParams(options) },
      options,
    ),
  getItem: (id: string) => apiClient.get<HelpItem>(`/api/v1/help_items/${id}`),
  createItem: (payload: { help_category_id: string; title: string; description: string }) =>
    apiClient.post<HelpItem>('/api/v1/help_items', payload),
  /** `user_id` NÃO viaja: a autoria é preservada pelo servidor (FE-366). */
  updateItem: (id: string, payload: { title?: string; description?: string; help_category_id?: string }) =>
    apiClient.put<HelpItem>(`/api/v1/help_items/${id}`, payload),
  removeItem: (id: string) => apiClient.delete<{ success: boolean }>(`/api/v1/help_items/${id}`),
}

/**
 * Ajuda de campo (OPS-545 / DEC-88) — o mapa `coluna → texto`.
 *
 * Os 91 textos vivem em `backend/db/seed_assets/*_help_inputs.yml`; trocar um
 * texto é editar YAML, sem deploy. As **4 chaves `TODO:`** não vêm na resposta:
 * campo sem resposta não ganha tooltip, porque texto que diz "TODO: precisa
 * saber…" a um operador é pior que tooltip nenhum.
 */
export const fieldHelpApi = {
  all: () => apiClient.get<FieldHelpMap>('/api/v1/help/fields'),
  scope: (scope: string) => apiClient.get<FieldHelpMap>('/api/v1/help/fields', { params: { scope } }),
}
