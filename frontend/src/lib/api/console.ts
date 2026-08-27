import { apiClient } from './client'
import { readPageMeta, pageParams, type PageMeta, type PageRequest } from './pagination'

/**
 * S2 — a camada de dados do console: seletor de projeto, mensagens
 * administrativas e observadores.
 *
 * Todo endpoint de lista aqui devolve `{ items, meta }`: o envelope de
 * paginação vem em **cabeçalho** (`X-Total-Count`, `X-Page`, `X-Per-Page`,
 * `X-Total-Pages`) e quem o traduz é `readPageMeta`, um lugar só. Nenhuma tela
 * lê cabeçalho.
 */

// --- Seletor de projeto (BE-412, contrato C1) --------------------------------

export interface ProjectOption {
  id: number
  name: string
  slug: string
  is_active: boolean
}

export interface CurrentProjectPayload {
  current: ProjectOption | null
  projects: ProjectOption[]
}

export const currentProjectApi = {
  get: () => apiClient.get<CurrentProjectPayload>('/api/v1/current_project'),
  /** Troca o projeto corrente. Projeto sem participação responde 404, igual a inexistente. */
  set: (projectId: number) =>
    apiClient.put<ProjectOption>('/api/v1/current_project', { project_id: projectId }),
}

// --- Mensagens administrativas ----------------------------------------------

export type AdminMessageState =
  | 'unread' | 'read' | 'open' | 'evaluated' | 'answered' | 'done' | 'closed' | 'rejected'

export type AdminMessageContext = 'other' | 'problem' | 'contact' | 'suggestion'

export interface MessageNote {
  id: number
  description: string
  author_name: string
  author_email: string
  unread: boolean
  from_admin: boolean
  quoted_note_id: number | null
  top_parent_quote_id: number | null
  created_at: string
}

export interface AdminMessage {
  id: number
  sender_name: string
  sender_email: string
  message: string
  state: AdminMessageState
  state_label: string
  context: AdminMessageContext
  context_label: string
  is_read: boolean
  is_favorite: boolean
  is_internal: boolean
  read_at: string | null
  public_token: string
  extra1_enabled: boolean
  extra1_label: string | null
  extra1_value: string | null
  extra2_enabled: boolean
  extra2_label: string | null
  extra2_value: string | null
  notes_count: number
  unread_notes_count: number
  created_at: string
  updated_at: string
  notes?: MessageNote[]
}

export interface VocabularyEntry<T extends string> {
  key: T
  label: string
}

export interface MessagesFilter extends PageRequest {
  state?: AdminMessageState | ''
  context?: AdminMessageContext | ''
  q?: string
}

export interface Paged<T> {
  items: T[]
  meta: PageMeta
}

function query(params: Record<string, unknown>): string {
  const sp = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v === undefined || v === null || v === '') return
    sp.set(k, String(v))
  })
  const s = sp.toString()
  return s ? `?${s}` : ''
}

export const adminMessagesApi = {
  list: async (filter: MessagesFilter = {}): Promise<Paged<AdminMessage>> => {
    const req = { page: filter.page, perPage: filter.perPage }
    const res = await apiClient.getRaw<AdminMessage[]>(
      `/api/v1/admin_messages${query({ ...pageParams(req), state: filter.state, context: filter.context, q: filter.q })}`,
    )
    return {
      items: (res.data ?? []) as AdminMessage[],
      meta: readPageMeta({ body: res.data, headers: res.headers as any }, req),
    }
  },

  get: (id: number | string) => apiClient.get<AdminMessage>(`/api/v1/admin_messages/${id}`),

  vocabulary: () =>
    apiClient.get<{
      states: VocabularyEntry<AdminMessageState>[]
      contexts: VocabularyEntry<AdminMessageContext>[]
    }>('/api/v1/admin_messages/vocabulary'),

  create: (data: { message: string; context?: AdminMessageContext; sender_name?: string; sender_email?: string }) =>
    apiClient.post<AdminMessage>('/api/v1/admin_messages', data),

  /**
   * DEC-73: pedir `done` ("Concluído") grava `closed` ("Fechado"). A inversão do
   * legado é REPLICADA e travada por golden test no servidor — a tela mostra o
   * que o servidor devolveu, nunca o que ela pediu.
   */
  update: (id: number, data: { state?: AdminMessageState; is_read?: boolean; is_favorite?: boolean }) =>
    apiClient.put<AdminMessage>(`/api/v1/admin_messages/${id}`, data),

  /** O outro lado da inversão: esta ação grava "Concluído". */
  close: (id: number) => apiClient.put<AdminMessage>(`/api/v1/admin_messages/${id}/close`, {}),

  addNote: (id: number, description: string) =>
    apiClient.post<MessageNote>(`/api/v1/admin_messages/${id}/notes`, { description }),

  remove: (id: number) => apiClient.delete(`/api/v1/admin_messages/${id}`),
}

// --- Observadores ------------------------------------------------------------

export interface Observer {
  id: number
  name: string
  email: string
  is_internal: boolean
  contexts: AdminMessageContext[]
  created_at: string
  updated_at: string
}

export interface ObserverInput {
  name: string
  email: string
  contexts: AdminMessageContext[]
  is_internal: boolean
}

export const observersApi = {
  list: async (req: PageRequest = {}): Promise<Paged<Observer>> => {
    const res = await apiClient.getRaw<Observer[]>(`/api/v1/observers${query(pageParams(req))}`)
    return {
      items: (res.data ?? []) as Observer[],
      meta: readPageMeta({ body: res.data, headers: res.headers as any }, req),
    }
  },

  create: (data: ObserverInput) => apiClient.post<Observer>('/api/v1/observers', data),
  update: (id: number, data: Partial<ObserverInput>) => apiClient.put<Observer>(`/api/v1/observers/${id}`, data),
  remove: (id: number) => apiClient.delete(`/api/v1/observers/${id}`),
}
