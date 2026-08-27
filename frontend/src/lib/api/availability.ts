import { apiClient } from './client'
import { catalogApi, type CatalogQuery } from './catalogs'
import { APP_CURRENCY } from '@/lib/config/currency'

/**
 * **Disponibilidades** — S11 (DEC-15.1: as quatro telas estão vivas em produção).
 *
 * Três recursos com **duas regras de escopo opostas**, e as duas são de
 * propósito:
 *
 * - `availabilityTemplatesApi` é o **catálogo global** ("Tipos de
 *   disponibilidade"). Não manda projeto nenhum, e o servidor não chama
 *   `current_project!`. Mesma regra dos cinco catálogos da S3.
 * - `projectAvailabilitiesApi` e `availabilityEntriesApi` são **escopados por
 *   projeto** (contrato C1). O cliente **não** manda `project_id`: o servidor o
 *   resolve do `X-Project-Id`/participação, e um `project_id` no corpo é
 *   ignorado. É isso que fecha a família D-01/D-16/D-29/D-76/D-100.
 *
 * O legado embutia `AvailabilityTemplate.all` — **todos os padrões de todos os
 * projetos** — num atributo `data-templates` do HTML, e o filtro de "níveis
 * derivados do pai" rodava sobre esse JSON. Aqui os pais válidos vêm de
 * `available_parents`, uma busca sob demanda no servidor, já escopada.
 */

export type OperationType = 'C' | 'D' | 'S' | 'M'
export type DeadlineType = 'CP' | 'LP'

export interface AvailabilityTemplate {
  id: string
  type: 'GlobalAvailabilityTemplate' | 'ProjectAvailabilityTemplate'
  project_id: string | null
  global_availability_template_id: string | null
  title: string
  level: number
  position: number
  /** `"1.2.3"` — derivado da `sort_key`, nunca guardado em segundo lugar. */
  position_path: string
  sort_key: string
  default_position: number | null
  parent_template_id: string | null
  top_parent_id: string | null
  operation_type: OperationType
  /** FE-129 — o legado exibia o código `C`/`D` cru na tela. */
  operation_type_label: string
  deadline_type: DeadlineType
  deadline_type_label: string
  is_global: boolean
  is_mandatory: boolean
  is_active: boolean
  is_cumulative: boolean
  is_adjusted: boolean
  should_insert_on_existing_projects: boolean
  is_locked: boolean
  locked_message: string | null
  locked_at: string | null
  locked_by_name: string | null
  job_state: string | null
  job_progress: number | null
  scope_label: string | null
  has_children: boolean
  deletable: boolean | null
  /** FE-140 — quem cadastrou. O `author` existia no model e nao saia da API. */
  author_name: string | null
  /**
   * FE-140 — o projeto do padrao de projeto. Nulo no catalogo global.
   *
   * O legado tinha um painel "Projetos", no PLURAL, chamando uma associacao que
   * nao existe em nenhum dos models (BE-133): abrir aquele detalhe levantava
   * `NoMethodError`. Um padrao de projeto pertence a UM projeto.
   */
  project_name: string | null
  created_at: string
  updated_at: string
}

export interface AvailabilityEntry {
  id: string
  project_id: string
  company_id: string | null
  availability_template_id: string
  title: string | null
  date: string
  /** Números como string decimal — formatação é da tela. */
  value: string
  /**
   * FE-134 — a **base** da correção por dias úteis. Ela é regravada a cada
   * alteração de `value` (DEC-24 / D-02, replicado de propósito), e a tela
   * mostra os **dois** números: no legado o usuário digitava X e via Y, sem
   * nenhuma indicação.
   */
  original_value: string
  /** DEC-27 — *saldo acumulado*, métrica DIFERENTE de `value`. */
  virtual_value: string
  is_adjusted: boolean
  is_cumulative: boolean | null
  business_days_multiplier: number | null
  is_consolidation: boolean
  author_name: string | null
  created_at: string
  updated_at: string
}

/** Como o valor desta linha foi produzido — DEC-26, o rótulo É a decisão. */
export type ValueSemantics = 'input' | 'group_total' | 'consolidation'

export interface AvailabilityGridRow {
  template: AvailabilityTemplate
  entry: AvailabilityEntry | null
  has_children: boolean
  /**
   * FE-132 / D-23 — **vem do servidor**. No legado o bloqueio da célula era
   * exclusivamente de interface, e um `PUT` direto gravava em consolidação
   * geral e em nó com filhos sem nenhuma recusa.
   */
  editable: boolean
  value_semantics: ValueSemantics
  value_semantics_label: string
}

export interface AvailabilityGrid {
  date: string | null
  company_id: string | null
  mode: 'company' | 'consolidation'
  mode_label: string
  rows: AvailabilityGridRow[]
}

export interface AvailabilityPanelEntry {
  id: string
  name: string
  /** Já com **sinal** — FE-125. O legado mandava o módulo e pintava de vermelho. */
  total: string
  operation_type: OperationType
  position_path: string
}

export interface AvailabilityPanel {
  project_id: string
  observation_html: string | null
  company_id: string | null
  /** FE-122 — os dias do mês que têm lançamento, para o calendário marcar. */
  dates: string[]
  count: number
  by_entry_label: string
  by_entry: AvailabilityPanelEntry[]
}

// --- Catálogo global: NÃO escopado (regra 4 do C1) ----------------------
export const availabilityTemplatesApi = {
  ...catalogApi<AvailabilityTemplate, CatalogQuery>('/api/v1/availability_templates'),

  /** BE-111 — só pais válidos para o nível pretendido. */
  availableParents: (level?: number) =>
    apiClient.get<AvailabilityTemplate[]>(
      `/api/v1/availability_templates/available_parents${level ? `?level=${level}` : ''}`,
    ),

  /** BE-138 — reordenar; movimento inválido é recusado pelo SERVIDOR. */
  move: (id: string, position: number) =>
    apiClient.put<AvailabilityTemplate>(`/api/v1/availability_templates/${id}/position`, { position }),
}

// --- Padrões do projeto: escopados por projeto (C1) ---------------------
export const projectAvailabilitiesApi = {
  list: (params?: { q?: string; is_active?: boolean }) =>
    apiClient.get<AvailabilityTemplate[]>('/api/v1/project_availabilities', { params }),

  get: (id: string) => apiClient.get<AvailabilityTemplate>(`/api/v1/project_availabilities/${id}`),

  /** FE-110 / FE-148 — **nenhum padrão de outro projeto neste payload**. */
  availableParents: (level?: number) =>
    apiClient.get<AvailabilityTemplate[]>(
      `/api/v1/project_availabilities/available_parents${level ? `?level=${level}` : ''}`,
    ),

  create: (dados: Record<string, unknown>) =>
    apiClient.post<AvailabilityTemplate>('/api/v1/project_availabilities', dados),

  /** BE-143 / DC-24 — na edição **só o título** muda. */
  rename: (id: string, title: string) =>
    apiClient.put<AvailabilityTemplate>(`/api/v1/project_availabilities/${id}`, { title }),

  move: (id: string, position: number) =>
    apiClient.put<AvailabilityTemplate>(`/api/v1/project_availabilities/${id}/position`, { position }),

  // As três operações em segundo plano. Respondem **202**: o trabalho de
  // verdade acontece no job, e o fim chega pelo `ProjectProgressChannel` — não
  // por um temporizador perguntando "já terminou?" de segundo em segundo
  // (Princípio 10).
  activate: (id: string) =>
    apiClient.post<AvailabilityTemplate>(`/api/v1/project_availabilities/${id}/activate`, {}),
  deactivate: (id: string) =>
    apiClient.post<AvailabilityTemplate>(`/api/v1/project_availabilities/${id}/deactivate`, {}),
  remove: (id: string) =>
    apiClient.delete<{ scheduled: boolean; id: string }>(`/api/v1/project_availabilities/${id}`),
}

// --- Grade e painel: escopados por projeto (C1) -------------------------
export const availabilityEntriesApi = {
  /** BE-120 — a grade de um dia. **Ler não cria registro** (DC-30). */
  grid: (params: { date?: string; company_id?: string; q?: string }) =>
    apiClient.get<AvailabilityGrid>('/api/v1/availability_entries', { params }),

  create: (dados: {
    availability_template_id: string
    company_id: string
    date: string
    value: number
  }) => apiClient.post<AvailabilityEntry>('/api/v1/availability_entries', dados),

  update: (id: string, value: number) =>
    apiClient.put<AvailabilityEntry>(`/api/v1/availability_entries/${id}`, { value }),

  remove: (id: string) =>
    apiClient.delete<{ deleted: boolean }>(`/api/v1/availability_entries/${id}`),
}

export const availabilityPanelApi = {
  /**
   * BE-117 / BE-149 — os indicadores do mês.
   *
   * No legado esta rota (`/api/v1/project_availability`) herdava de
   * `ApplicationController` e respondia **sem sessão nenhuma**, a qualquer
   * projeto por id: o **D-01**. Aqui não existe parâmetro de projeto — o
   * servidor o resolve.
   */
  get: (params: { date?: string; month?: number; year?: number; company_id?: string }) =>
    apiClient.get<AvailabilityPanel>('/api/v1/availability', { params }),
}

/**
 * Valor monetário, **com o sinal no próprio número** (FE-125).
 *
 * A moeda vem de `APP_CURRENCY`, **nunca cravada** (§5.4.9): `currency: 'BRL'`
 * já esteve escrito em sete lugares do frontend, e sete cópias não são sete
 * decisões — são uma decisão que ninguém consegue mudar sem esquecer uma delas.
 * As casas decimais saem de `minorUnits`, então uma moeda sem subunidade (JPY)
 * não ganha ",00" inventado.
 */
export function formatarValor(valor: string | number): string {
  const numero = typeof valor === 'string' ? Number(valor) : valor
  if (!Number.isFinite(numero)) return '—'
  return numero.toLocaleString(APP_CURRENCY.locale, {
    style: 'currency',
    currency: APP_CURRENCY.code,
    minimumFractionDigits: APP_CURRENCY.minorUnits,
    maximumFractionDigits: APP_CURRENCY.minorUnits,
  })
}
