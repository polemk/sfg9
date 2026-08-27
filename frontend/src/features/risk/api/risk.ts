import { apiClient } from '@/lib/api/client'
import { catalogApi, type CatalogPage, type CatalogQuery } from '@/lib/api/catalogs'
import type { Carrier } from '@/lib/api/catalogs'
import { pageParams, readPageMeta } from '@/lib/api/pagination'

/**
 * S5 — **o cliente do bloco de risco**.
 *
 * Duas regras que valem para tudo o que está aqui:
 *
 * 1. **Nenhum componente React recalcula exposição.** O front formata o que o
 *    serviço devolveu, e ponto. Se uma tela precisa de um número que o serviço
 *    não devolve, o serviço ganha o número — não o front. É o contrato **C2**, e
 *    é o que impede a prévia e a gravação de divergirem.
 * 2. **Os campos `formatted_*` do console vêm PRONTOS do servidor.** Não é
 *    preguiça: é neles que vivem os dois erros de rótulo do D-95, que a
 *    **DEC-01** manda preservar. Formatá-los aqui "consertaria" o D-95 sem
 *    ninguém ter decidido isso.
 *
 * Escopo: `risk_controls` é **escopado por projeto** (o servidor resolve pelo
 * `current_project!`; o cliente não manda `project_id`), enquanto
 * `risk_operation_types` e `risk_movement_types` são **catálogos globais** —
 * regra 4 do contrato C1.
 */

// --- Tipos ------------------------------------------------------------------

export interface RiskOperationSubtype {
  id: string
  title: string
  integration_key: string
  is_pre: boolean
  is_default_for_type: boolean
  is_active: boolean
  allow_manual_operations: boolean
  allow_receivable_entries: boolean
  pair_id: string | null
  risk_operation_type_id: string
}

export interface RiskOperationType {
  id: string
  title: string
  integration_key: string
  is_active: boolean
  is_default: boolean
  allow_manual_operations: boolean
  allow_receivable_entries: boolean
  /** Imutável depois da criação — o servidor recusa a alteração. */
  has_pre_faturamento: boolean
  subtypes: RiskOperationSubtype[]
  dependents_count: number
  created_at: string
  updated_at: string
}

export interface RiskMovementType {
  id: string
  title: string
  integration_key: string
  /** `'C'` = crédito (−1 no saldo) · `'D'` = débito (+1). */
  credit_type: 'C' | 'D'
  credit_type_description: string
  is_active: boolean
  is_default: boolean
  is_system_exclusive: boolean
  is_transfer: boolean
  dependents_count: number
  created_at: string
  updated_at: string
}

export interface RiskControl {
  id: string
  title: string
  company_id: string
  company_title: string | null
  carrier_id: string
  carrier_title: string | null
  carrier_group_title: string | null
  risk_operation_type_id: string | null
  risk_operation_type_title: string | null
  has_pre_faturamento: boolean
  /** Decimal como string — a formatação é da tela. */
  limite: string
  taxa: string
  original_balance: string
  original_balance_pre: string
  is_active: boolean
  has_safegold_management: boolean
  /** DB-240/DEC-43 — linha do modelo pré-2022, sem tipo. Some dos agregados. */
  is_legacy_shape: boolean
  dependents_count: number
  created_at: string
  updated_at: string
}

/** Uma linha do resumo — um limite (por empresa) ou um portador (por projeto). */
export interface ExposureRow {
  /** `null` no modo "grupo econômico": a linha agrega os limites do portador. */
  id: string | null
  carrier_id?: string | null
  /** Quantos limites a linha soma. Maior que 1 = dado legado, e a tela avisa. */
  controls_count?: number
  risk_title: string
  risk_subtitle: string
  operation_type_title: string
  has_pre: boolean
  limits: {
    limite_utilizado: string | number
    limite_liquidavel: string | number
    limite_pre: string | number
    limite_disponivel: number
    limite_total: string | number
    limite_utilizado_percent: number
    limite_liquidavel_percent: number
    limite_pre_percent: number
    formatted_limite_disponivel: string
    formatted_limite_total: string
    formatted_limite_utilizado: string
    formatted_limite_liquidavel: string
    formatted_limite_pre: string
    taxa: string | number
  }
}

/** O cabeçalho de um tipo de limite, com as linhas dele. */
export interface ExposureTypeGroup {
  id: string
  title: string
  has_pre: boolean
  util: string | number
  disp: number
  total: string | number
  liq: string | number
  pre: string | number
  limite_utilizado_percent: number
  limite_liquidavel_percent: number
  limite_pre_percent: number
  perc_util: string
  perc_liq: string
  perc_pre: string
  formatted_util: string
  formatted_disp: string
  formatted_total: string
  formatted_liq: string
  formatted_pre: string
  rcs: ExposureRow[]
}

export interface TotalLimitsRow {
  id: string
  title: string
  total: string | number
  disp: number
  util: string | number
  perc_util: string
  /** BE-251 — as quatro chaves devolvem a MESMA string de `perc_util`. */
  liq: string
  perc_liq: string
  pre: string
  perc_pre: string
  formatted_total: string
  formatted_disp: string
  formatted_util: string
}

export interface TotalLimits {
  date: string
  limits: TotalLimitsRow[]
  /** 0/1, como o legado devolvia. */
  has_risk_controls: number
}

export interface RiskSummary {
  date: string
  scope: 'company' | 'project'
  company_id: string | null
  carrier_id: string | null
  is_single: boolean
  carrier_title: string
  total_limits: TotalLimits
  controls_info: ExposureTypeGroup[]
}

export interface RiskControlQuery extends CatalogQuery {
  companyId?: string
  carrierId?: string
  riskOperationTypeId?: string
}

// --- Fiação -----------------------------------------------------------------

/**
 * Os dois catálogos de tipo — mesma fábrica dos cinco catálogos da S3, porque
 * falam o mesmo dialeto de lista (`q`, `ordering_keys[]`, envelope em cabeçalho).
 */
export const riskOperationTypesApi = catalogApi<RiskOperationType>('/api/v1/risk_operation_types')
export const riskMovementTypesApi = catalogApi<RiskMovementType>('/api/v1/risk_movement_types')

const controlsBase = catalogApi<RiskControl, RiskControlQuery>('/api/v1/risk_controls', (f) => {
  const extra: Record<string, unknown> = {}
  if (f.companyId) extra.company_id = f.companyId
  if (f.carrierId) extra.carrier_id = f.carrierId
  if (f.riskOperationTypeId) extra.risk_operation_type_id = f.riskOperationTypeId
  return extra
})

export const riskControlsApi = {
  ...controlsBase,

  /** BE-236 / BE-237 — ativar e desativar. */
  activate: (id: string) => apiClient.put<RiskControl>(`/api/v1/risk_controls/${id}/activate`),
  deactivate: (id: string) => apiClient.put<RiskControl>(`/api/v1/risk_controls/${id}/deactivate`),

  /**
   * BE-232 — a cascata empresa → portador do formulário.
   *
   * **Um critério só**: os portadores conectados ao projeto. No legado a tela de
   * Limites populava este select com `Carrier.all` e o servidor recusava metade
   * das escolhas (FE-241).
   */
  carriersForCompany: (companyId: string) =>
    apiClient.get<Carrier[]>('/api/v1/risk_controls/carriers', { params: { company_id: companyId } }),

  /** FE-232 — só portadores que TÊM limite ativo. É o filtro do console. */
  carriersWithActiveControl: (companyId?: string) =>
    apiClient.get<Carrier[]>('/api/v1/risk_controls/filters', {
      params: companyId ? { company_id: companyId } : {},
    }),

  /** BE-252 — limites livres para lançar posição numa data (contrato com a S6). */
  availableForEntry: (params: { companyId?: string; date?: string }) =>
    apiClient.get<RiskControl[]>('/api/v1/risk_controls/available', {
      params: {
        ...(params.companyId ? { company_id: params.companyId } : {}),
        ...(params.date ? { date: params.date } : {}),
      },
    }),

  /**
   * BE-231 — o payload do console.
   *
   * Sem `companyId`, agrega o projeto inteiro (a opção "Grupo econômico");
   * com `companyId`, agrega a empresa. **Os dois ramos produzem rótulos
   * diferentes**, e isso é o legado replicado (DEC-01) — ver
   * `Risk::AggregateService` no servidor.
   */
  summary: (params: { companyId?: string; carrierId?: string; date?: string }) =>
    apiClient.get<RiskSummary>('/api/v1/risk_controls/summary', {
      params: {
        ...(params.companyId ? { company_id: params.companyId } : {}),
        ...(params.carrierId ? { carrier_id: params.carrierId } : {}),
        ...(params.date ? { date: params.date } : {}),
      },
    }),
}

/**
 * Lista de limites com o envelope de paginação — a única leitura do envelope é
 * `readPageMeta`, aqui como em todo o resto (DEC-62).
 */
export async function listRiskControls(filtros: RiskControlQuery = {}): Promise<CatalogPage<RiskControl>> {
  const params: Record<string, unknown> = { ...pageParams(filtros) }
  if (filtros.q) params.q = filtros.q
  if (filtros.companyId) params.company_id = filtros.companyId
  if (filtros.carrierId) params.carrier_id = filtros.carrierId
  if (filtros.riskOperationTypeId) params.risk_operation_type_id = filtros.riskOperationTypeId
  if (filtros.orderingKey) {
    params['ordering_keys[]'] = [filtros.orderingKey]
    params['ordering_style[]'] = [filtros.orderingStyle ?? 'up']
  }

  const resposta = await apiClient.getRaw<RiskControl[]>('/api/v1/risk_controls', { params })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
  }
}

// ============================================================================
// S7 — OPERAÇÕES DE RISCO, movimentos, prorrogações e renovação
// ============================================================================
//
// ⚠ **NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b.** As seis migrations desta
// família estão entre as 24 que nunca subiram (`analise-dump-producao.md` §1):
// em três anos de uso real nenhuma operação de risco tipada existiu. O que está
// portado aqui espelha o fonte de 2022.
//
// Duas regras que valem para tudo o que vem abaixo:
//
// 1. **Nenhum componente React soma saldo.** `balance`, `movement_value_sign` e
//    o payload do cartão "última movimentação" vêm prontos do
//    `Risk::Calculator` (contrato **C2**). O sufixo `C`/`D` e a cor da célula
//    são formatação.
// 2. **`original_balance` chega NEGATIVO** (DEC-01): é o que a aba GERAL exibe
//    (FE-265). Para o formulário existe `original_balance_abs`. Normalizar aqui
//    "consertaria" o D-93 sem ninguém ter decidido isso.

export interface RiskOperation {
  id: string
  title: string
  project_id: string
  company_id: string
  company_title: string | null
  carrier_id: string
  carrier_title: string | null
  operation_type_id: string
  operation_type_title: string | null
  operation_subtype_id: string | null
  /** A coluna "Tipo" da lista mostra ESTE (FE-250). */
  operation_subtype_title: string | null
  /** Do TIPO. Sem datas, sem aba PRORROGAÇÕES, sem Renovar/Prorrogar. */
  has_pre_faturamento: boolean
  /** Do SUBTIPO. Habilita o botão "Transferir" (FE-272). */
  is_pre: boolean
  risk_control_id: string
  contract_number: string
  issue_date: string | null
  due_date: string | null
  original_due_date: string | null
  operation_value: string
  /** Gravado NEGATIVO (DEC-01). O detalhe exibe assim. */
  original_balance: string
  /** O mesmo valor em módulo — é o que o FORMULÁRIO edita. */
  original_balance_abs: string | null
  balance: string
  agreed_rate: string
  observation: string
  is_on_variable: boolean
  /** Rótulo. Não bloqueia nada e não sai da exposição (DEC-35). */
  is_ended: boolean
  is_static: boolean
  /** A RAIZ da cadeia de renovações, não o elo anterior. */
  original_id: string | null
  pair_id: string | null
  receivable_id: string | null
  receipt_id: string | null
  extensions_count: number
  renewals_count: number
  movements_count: number
  created_at: string
  updated_at: string
}

export interface RiskMovement {
  id: string
  risk_operation_id: string
  sequence: number | null
  date: string
  movement_type_id: string
  movement_type_title: string | null
  /** `'C'` = crédito · `'D'` = débito. É o sufixo do extrato (FE-270). */
  credit_type: 'C' | 'D' | null
  credit_type_description: string | null
  /** −1 crédito · +1 débito. Vem pronto — a tela não deduz. */
  movement_value_sign: number | null
  is_transfer: boolean
  movement_value: string
  /** Saldo ACUMULADO depois deste movimento. */
  balance: string
  observation: string
  pair_id: string | null
  receivable_id: string | null
  user_id: string | null
  user_name: string | null
  created_at: string
  updated_at: string
}

export interface RiskOperationExtension {
  id: string
  risk_operation_id: string
  original_due_date: string
  new_due_date: string
  observation: string
  user_id: string | null
  user_name: string | null
  created_at: string
}

export interface LastMovement {
  movement_id?: string
  movement_date?: string
  movement_type?: string
  movement_value?: string
  movement_value_sign?: number
  sequence?: number
  total_balance?: string
  original_balance?: string
}

export interface RenewalPreview {
  original_id: string
  root_id: string
  issue_date: string
  due_date: string
  elapsed_days: number
  original_due_date: string
  title: string
  operation_value: string
  agreed_rate: string
}

export interface ExtensionPreview {
  risk_operation_id: string
  original_due_date: string
  min_due_date: string
  new_due_date: string
}

export interface MovementFormOptions {
  mode: 'new' | 'transfer'
  movement_type_id: string | null
  movement_type_locked: boolean
  movement_types: RiskMovementType[]
  min_date: string | null
  max_date: string | null
}

export interface RiskOperationQuery extends CatalogQuery {
  companyId?: string
  carrierId?: string
  operationTypeId?: string
  from?: string
  to?: string
  /**
   * Ordenação MULTI-COLUNA (FE-254): pares paralelos `ordering_keys[]` /
   * `ordering_style[]`, exatamente como o servidor espera. A allowlist do
   * servidor é a mesma — chave fora dela devolve **400**, não 500.
   */
  orderingKeys?: string[]
  orderingStyles?: Array<'up' | 'down'>
}

export interface RiskOperationInput {
  company_id: string
  carrier_id: string
  operation_type_id: string
  operation_subtype_id?: string | null
  title?: string
  contract_number?: string
  issue_date: string
  due_date: string
  operation_value: number
  original_balance?: number
  agreed_rate?: number
  observation?: string
  is_on_variable?: boolean
  is_ended?: boolean
}

const OPERACOES = '/api/v1/risk_operations'

export async function listRiskOperations(
  filtros: RiskOperationQuery = {},
): Promise<CatalogPage<RiskOperation>> {
  const params: Record<string, unknown> = { ...pageParams(filtros) }
  if (filtros.q) params.q = filtros.q
  if (filtros.companyId) params.company_id = filtros.companyId
  if (filtros.carrierId) params.carrier_id = filtros.carrierId
  if (filtros.operationTypeId) params.operation_type_id = filtros.operationTypeId
  if (filtros.from) params.from = filtros.from
  if (filtros.to) params.to = filtros.to
  if (filtros.orderingKeys?.length) {
    params['ordering_keys[]'] = filtros.orderingKeys
    params['ordering_style[]'] = filtros.orderingStyles ?? filtros.orderingKeys.map(() => 'up')
  }

  const resposta = await apiClient.getRaw<RiskOperation[]>(OPERACOES, { params })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
  }
}

export async function listRiskMovements(
  operationId: string,
  filtros: CatalogQuery = {},
): Promise<CatalogPage<RiskMovement>> {
  const resposta = await apiClient.getRaw<RiskMovement[]>(`${OPERACOES}/${operationId}/movements`, {
    params: pageParams(filtros),
  })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
  }
}

export async function listRiskExtensions(
  operationId: string,
  filtros: CatalogQuery = {},
): Promise<CatalogPage<RiskOperationExtension>> {
  const resposta = await apiClient.getRaw<RiskOperationExtension[]>(
    `${OPERACOES}/${operationId}/extensions`,
    { params: pageParams(filtros) },
  )
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
  }
}

export interface OperationAvailability {
  /** O projeto tem ao menos um limite ATIVO com portador. */
  carrier_available: boolean
  /** …e ao menos um limite ativo de tipo que aceita lançamento manual. */
  manual_control: boolean
}

export const riskOperationsApi = {
  get: (id: string) => apiClient.get<RiskOperation>(`${OPERACOES}/${id}`),

  /**
   * FE-257 — as duas guardas do botão "Cadastrar". No legado os predicados
   * eram calculados **na view** e despejados em `data-` para o JavaScript
   * decidir; aqui vêm do servidor, que é onde o dado está.
   */
  availability: () => apiClient.get<OperationAvailability>(`${OPERACOES}/availability`),
  create: (dados: RiskOperationInput) => apiClient.post<RiskOperation>(OPERACOES, dados),
  update: (id: string, dados: Partial<RiskOperationInput>) =>
    apiClient.put<RiskOperation>(`${OPERACOES}/${id}`, dados),
  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`${OPERACOES}/${id}`),

  /** BE-254 — a cascata do formulário. Um endpoint, dois modos. */
  carriersForCompany: (companyId: string) =>
    apiClient.get<Carrier[]>(`${OPERACOES}/filters`, {
      params: { search_type: 'company', company_id: companyId },
    }),
  typesForCarrier: (companyId: string, carrierId: string) =>
    apiClient.get<RiskOperationType[]>(`${OPERACOES}/filters`, {
      params: { search_type: 'carrier', company_id: companyId, carrier_id: carrierId },
    }),

  /** BE-255 — payload VAZIO quando não há movimento (no legado, 500). */
  lastMovement: (id: string) => apiClient.get<LastMovement>(`${OPERACOES}/${id}/last_movement`),

  // --- Movimentos -----------------------------------------------------------
  movementOptions: (id: string, mode: 'new' | 'transfer' = 'new') =>
    apiClient.get<MovementFormOptions>(`${OPERACOES}/${id}/movements/options`, { params: { mode } }),
  createMovement: (
    id: string,
    dados: { movement_type_id: string; date: string; movement_value: number; observation?: string },
  ) => apiClient.post<RiskMovement>(`${OPERACOES}/${id}/movements`, dados),
  updateMovement: (
    id: string,
    movementId: string,
    dados: { movement_type_id?: string; date?: string; movement_value?: number; observation?: string },
  ) => apiClient.put<RiskMovement>(`${OPERACOES}/${id}/movements/${movementId}`, dados),
  removeMovement: (id: string, movementId: string) =>
    apiClient.delete<{ deleted: boolean }>(`${OPERACOES}/${id}/movements/${movementId}`),

  // --- Prorrogação ----------------------------------------------------------
  extensionPreview: (id: string) => apiClient.get<ExtensionPreview>(`${OPERACOES}/${id}/extensions/new`),
  createExtension: (id: string, dados: { new_due_date: string; observation?: string }) =>
    apiClient.post<RiskOperationExtension>(`${OPERACOES}/${id}/extensions`, dados),

  // --- Renovação ------------------------------------------------------------
  renewalPreview: (id: string, issueDate?: string) =>
    apiClient.get<RenewalPreview>(`${OPERACOES}/${id}/renewal`, {
      params: issueDate ? { issue_date: issueDate } : {},
    }),
  createRenewal: (id: string, dados: { issue_date: string; due_date: string }) =>
    apiClient.post<RiskOperation>(`${OPERACOES}/${id}/renewal`, dados),
  renewals: (id: string) => apiClient.get<RiskOperation[]>(`${OPERACOES}/${id}/renewals`),
}
