import { apiClient } from './client'
import { catalogApi, type CatalogPage, type CatalogQuery } from './catalogs'
import { pageParams, readPageMeta, type PageRequest } from './pagination'
import { formatMoney } from '@/lib/utils/number'

/**
 * S4 — os recursos **escopados por projeto**: projeto, empresas, fornecedores,
 * garantias e conexões com portador.
 *
 * **Nenhuma destas chamadas manda `project_id`.** O escopo é resolvido no
 * servidor por `current_project!` (contrato C1), e o `project_id` que fosse no
 * corpo seria ignorado de qualquer forma — é a ausência dele aqui que impede a
 * tela de virar a fonte de escopo. Quando é preciso operar noutro projeto, quem
 * troca é o seletor da topbar (`useCurrentProject`), que grava a preferência no
 * servidor.
 *
 * É o **oposto** de `lib/api/catalogs.ts`, e oposto de propósito: lá o catálogo
 * é global e a tela de administração é que fica escondida por papel. As duas
 * regras estão escritas nos dois arquivos para que ninguém "conserte" uma na
 * direção da outra.
 *
 * A fábrica de lista é a MESMA (`catalogApi`): mesmo `q`, mesmos
 * `ordering_keys[]`/`ordering_style[]`, mesmo envelope de paginação em
 * cabeçalho lido por `readPageMeta` (DEC-62).
 */

// --- Tipos ----------------------------------------------------------------

export interface Company {
  id: string
  project_id: string
  title: string
  /** **Derivada do projeto** — `companies` não tem coluna própria (D-30 / Q-02). */
  has_safegold_management: boolean
  carriers_count: number
  /** ⏳ Zero até a S5 entregar `risk_controls`. */
  risk_controls_count: number
  created_at: string
  updated_at: string
}

export const DOCUMENT_TYPES = ['CPF', 'CNPJ'] as const
export type DocumentType = (typeof DOCUMENT_TYPES)[number]

export interface Provider {
  id: string
  project_id: string
  title: string
  resume: string | null
  integration_key: string
  is_active: boolean
  /** O documento é o PAR (tipo, número) e é opcional (DC-11). */
  document_type: DocumentType | null
  /** Somente dígitos — a máscara é da tela. */
  document: string | null
  formatted_document: string
  cnpj_fetched_at: string | null
  legal_name: string | null
  trade_name: string | null
  status: string | null
  opened_at: string | null
  status_changed_at: string | null
  email: string | null
  phone: string | null
  zip_code: string | null
  street: string | null
  number: string | null
  complement: string | null
  district: string | null
  city: string | null
  state: string | null
  activities: Record<string, unknown>
  logo_url: string | null
  /** ⏳ Zero até a S9 entregar `renegotiations`. */
  renegotiations_count: number
  created_at: string
  updated_at: string
}

export interface ProjectGuarantee {
  id: string
  project_id: string
  title: string
  /** Número em string decimal — a formatação é da tela, nunca do servidor. */
  value: string
  observation: string | null
  carrier_id: string
  carrier_title: string | null
  carrier_group_title: string | null
  guarantee_type_id: string
  guarantee_type_title: string | null
  guarantee_type_is_provisional: boolean | null
  created_at: string
  updated_at: string
}

export interface CarrierConnection {
  id: string
  project_id: string
  carrier_id: string
  carrier_title: string | null
  carrier_group_title: string | null
  carrier_is_active: boolean | null
  created_at: string
}

export interface CarrierCandidate {
  id: string
  title: string
  integration_key: string
  is_active: boolean
  group_title: string | null
  connected: boolean
}

export interface Project {
  id: string
  name: string
  /** **Imutável após a criação** (DC-17): renomear não muda a URL. */
  slug: string
  integration_key: string
  color: string | null
  is_active: boolean
  segment_id: string | null
  segment_title: string | null
  sub_segment_id: string | null
  sub_segment_title: string | null
  address_type: string | null
  address: string | null
  address_number: string | null
  address_complement: string | null
  neighborhood: string | null
  cep: string | null
  address_state: string | null
  /** UMA coluna de cidade. O legado tinha duas e lia da errada (D-124). */
  address_city: string | null
  formatted_address: string
  closing_date: string | null
  responsible_id: string | null
  responsible_name: string | null
  responsible_email: string | null
  owner_id: string
  owner_name: string | null
  has_safegold_management: boolean
  has_bi: boolean
  is_sandbox: boolean
  avatar_url: string | null
  job_state: 'running' | 'done' | 'failed' | null
  job_progress: number | null
  availability_note_html: string
  availability_note_text: string
  members_count: number
  created_at: string
  updated_at: string
}

export interface ProjectOption {
  id: string
  name: string
  slug: string
  is_active: boolean
}

export interface BatchResultItem {
  carrier_id: string
  status: 'ok' | 'error' | 'not_found'
  message: string
  id?: string
}

export interface BatchResult {
  action: 'connect' | 'disconnect'
  results: BatchResultItem[]
  applied: number
  failed: number
}

// --- Consultas ------------------------------------------------------------

export interface CompanyQuery extends CatalogQuery {
  companyId?: string
  orderMode?: 'dash'
}

export interface ProviderQuery extends CatalogQuery {
  providerId?: string
}

export interface GuaranteeQuery extends CatalogQuery {
  projectGuaranteeId?: string
  carrierId?: string
  guaranteeTypeId?: string
  orderMode?: 'dash'
}

export interface ProjectQuery extends CatalogQuery {
  projectId?: string
  importingId?: number
  orderMode?: 'dash'
}

// --- Clientes -------------------------------------------------------------

export const companiesApi = catalogApi<Company, CompanyQuery>('/api/v1/companies', (f) => {
  const extra: Record<string, unknown> = {}
  if (f.companyId) extra.company_id = f.companyId
  if (f.orderMode) extra.order_mode = f.orderMode
  return extra
})

export const providersApi = {
  ...catalogApi<Provider, ProviderQuery>('/api/v1/providers', (f) => {
    const extra: Record<string, unknown> = {}
    if (f.providerId) extra.provider_id = f.providerId
    return extra
  }),

  /**
   * Logo do fornecedor — ActiveStorage no próprio model (DEC-91), num caminho
   * PRÓPRIO de requisição.
   *
   * Separado do `update` pelo mesmo motivo do portador: `multipart` é outro
   * caminho, e misturar os dois obrigaria todo salvamento de formulário a ser
   * multipart. O tamanho e o tipo REAL são conferidos **no servidor**
   * (`config/attachments.yml`, 1 MB); o que a tela checa antes de enviar é
   * conveniência, nunca a regra.
   */
  uploadLogo: (id: string, file: File) => {
    const form = new FormData()
    form.append('file', file)
    return apiClient.post<Provider>(`/api/v1/providers/${id}/logo`, form)
  },
  removeLogo: (id: string) => apiClient.delete<Provider>(`/api/v1/providers/${id}/logo`),
}

export const projectGuaranteesApi = {
  ...catalogApi<ProjectGuarantee, GuaranteeQuery>('/api/v1/project_guarantees', (f) => {
    const extra: Record<string, unknown> = {}
    if (f.projectGuaranteeId) extra.project_guarantee_id = f.projectGuaranteeId
    if (f.carrierId) extra.carrier_id = f.carrierId
    if (f.guaranteeTypeId) extra.guarantee_type_id = f.guaranteeTypeId
    if (f.orderMode) extra.order_mode = f.orderMode
    return extra
  }),

  /**
   * **Um único critério** de "o projeto tem portador": a conexão. O legado
   * usava `active_risk_controls_carriers` no botão e `project.carriers` no
   * formulário — a tela oferecia portador que o servidor recusava.
   */
  availableCarriers: () =>
    apiClient.get<CarrierCandidate[]>('/api/v1/project_guarantees/available_carriers'),
}

export const carrierConnectionsApi = {
  list: async (filtros: PageRequest & { carrierId?: string } = {}): Promise<CatalogPage<CarrierConnection>> => {
    const params: Record<string, unknown> = { ...pageParams(filtros) }
    if (filtros.carrierId) params.carrier_id = filtros.carrierId
    const resposta = await apiClient.getRaw<CarrierConnection[]>('/api/v1/project_carrier_connections', { params })
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  candidates: async (
    filtros: PageRequest & { q?: string; groupId?: string; active?: boolean } = {},
  ): Promise<CatalogPage<CarrierCandidate>> => {
    const params: Record<string, unknown> = { ...pageParams(filtros) }
    if (filtros.q) params.q = filtros.q
    if (filtros.groupId) params.group_id = filtros.groupId
    if (filtros.active) params.active = 'true'
    const resposta = await apiClient.getRaw<CarrierCandidate[]>(
      '/api/v1/project_carrier_connections/candidates',
      { params },
    )
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  /**
   * Lote com resultado **por item**. Lote vazio é 400 no servidor — a tela não
   * precisa adivinhar, e não deve mandar lote vazio de qualquer forma.
   */
  batch: (action: 'connect' | 'disconnect', carrierIds: string[]) =>
    apiClient.put<BatchResult>('/api/v1/project_carrier_connections/batch', {
      action_kind: action,
      carrier_ids: carrierIds,
    }),

  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`/api/v1/project_carrier_connections/${id}`),
}

export const projectsApi = {
  ...catalogApi<Project, ProjectQuery>('/api/v1/projects', (f) => {
    const extra: Record<string, unknown> = {}
    if (f.projectId) extra.project_id = f.projectId
    if (f.importingId) extra.importing_id = f.importingId
    if (f.orderMode) extra.order_mode = f.orderMode
    return extra
  }),

  autocomplete: (q: string, limit = 10) =>
    apiClient.get<ProjectOption[]>('/api/v1/projects/autocomplete', { params: { q, limit } }),

  /** Filtrados por hierarquia de papel **no servidor** (BE-084). */
  responsibleCandidates: (q?: string) =>
    apiClient.get<{ id: string; name: string; email: string }[]>(
      '/api/v1/projects/responsible_candidates',
      { params: q ? { q } : {} },
    ),

  setSafegoldManagement: (id: string, value: boolean) =>
    apiClient.patch<Project>(`/api/v1/projects/${id}/safegold_management`, { value }),

  setBi: (id: string, value: boolean) => apiClient.patch<Project>(`/api/v1/projects/${id}/bi`, { value }),

  /** DC-18 — aba informativa do detalhe de um usuário. */
  ofUser: (userId: string) => apiClient.get<ProjectOption[]>(`/api/v1/users/${userId}/projects`),

  /**
   * Logo do projeto (DB-089 / OPS-088). A ausência é **explícita**
   * (`avatar_url: null`): o legado tratava a string literal `"missing.jpg"`
   * como "sem arquivo", e um projeto cujo logo se chamasse assim ficava sem.
   */
  uploadLogo: (id: string, file: File) => {
    const form = new FormData()
    form.append('file', file)
    return apiClient.post<Project>(`/api/v1/projects/${id}/logo`, form)
  },
  removeLogo: (id: string) => apiClient.delete<Project>(`/api/v1/projects/${id}/logo`),
}

/**
 * Valor monetário do servidor (string decimal) para o texto monetário da tela.
 * A formatação é **da tela**: o servidor devolve número. No legado ele devolvia
 * `"R$ 1.234,56"` e quem precisava somar tinha de desfazer a máscara.
 *
 * A moeda **não** é cravada aqui: `formatMoney` lê `APP_CURRENCY`
 * (`lib/config/currency`), que é a fonte única da §5.4.9. Esta função tinha
 * `currency: 'BRL'` literal — a oitava cópia da decisão que aquele arquivo
 * existe para centralizar. O que sobra dela é só a coerção de string decimal
 * para número, que é o que os ~20 chamadores da S9 precisam.
 *
 * O **nome** ficou herdado ("Reais") e passa a ser mais estreito que o
 * comportamento; renomear mexe em todos os chamadores da S9 e é decisão do dono
 * da fatia — registrado em `upstream-flags.md`.
 */
export function formatarReais(valor: string | number | null | undefined): string {
  const numero = typeof valor === 'string' ? Number(valor) : (valor ?? 0)
  if (!Number.isFinite(numero)) return '—'
  return formatMoney(numero, '—')
}

/** Máscara de CPF/CNPJ para digitação. Só dígitos vão para o servidor. */
export function mascararDocumento(tipo: DocumentType | null, valor: string): string {
  const digitos = valor.replace(/\D/g, '')
  if (tipo === 'CPF') {
    return digitos
      .slice(0, 11)
      .replace(/(\d{3})(\d)/, '$1.$2')
      .replace(/(\d{3})(\d)/, '$1.$2')
      .replace(/(\d{3})(\d{1,2})$/, '$1-$2')
  }
  if (tipo === 'CNPJ') {
    return digitos
      .slice(0, 14)
      .replace(/(\d{2})(\d)/, '$1.$2')
      .replace(/(\d{3})(\d)/, '$1.$2')
      .replace(/(\d{3})(\d)/, '$1/$2')
      .replace(/(\d{4})(\d{1,2})$/, '$1-$2')
  }
  return digitos
}

// --- Participação (aba "Membros") ----------------------------------------

export interface Membership {
  id: string
  role: string
  project_id: string
  is_project_owner: boolean
  user: { id: string; name: string; email: string | null; phone: string | null }
  created_at: string
}

export interface MembershipCandidate {
  id: string
  name: string
  email: string | null
  phone: string | null
}

/** Os quatro rótulos. **`role` NUNCA autoriza nada** (DEC-18.6). */
export const MEMBERSHIP_ROLES = ['responsavel', 'participante', 'coordenador', 'gestor'] as const
export type MembershipRole = (typeof MEMBERSHIP_ROLES)[number]

export const MEMBERSHIP_ROLE_LABELS: Record<MembershipRole, string> = {
  responsavel: 'Responsável',
  participante: 'Participante',
  coordenador: 'Coordenador',
  gestor: 'Gestor',
}

/**
 * Participação no projeto **corrente** — S0 entregou o serviço, a S4 usa.
 *
 * **Não existe `project_id` em nenhuma destas chamadas**, nem no corpo nem na
 * rota: o projeto vem de `current_project!`. É essa ausência que fecha o D-28 +
 * D-34, em que qualquer sessão se auto-adicionava a qualquer projeto e ganhava
 * o grupo "Gestão" inteiro.
 *
 * As três condições (não-readonly, não remover o dono, não remover a si mesmo)
 * são **do servidor**. A tela as espelha para não oferecer o que será recusado —
 * mas quem decide é o servidor, e forçar pela API responde 403.
 */
export const membershipsApi = {
  list: (params: PageRequest = {}) =>
    apiClient.get<{ memberships: Membership[]; total: number; page: number; per_page: number; total_pages: number }>(
      '/api/v1/memberships',
      { params: pageParams(params) },
    ),

  candidates: (q?: string) =>
    apiClient.get<{ candidates: MembershipCandidate[]; total: number }>('/api/v1/memberships/candidates', {
      params: q ? { q } : {},
    }),

  create: (userId: string, role: MembershipRole = 'participante') =>
    apiClient.post<Membership>('/api/v1/memberships', { user_id: userId, role }),

  remove: (id: string) => apiClient.delete<unknown>(`/api/v1/memberships/${id}`),
}
