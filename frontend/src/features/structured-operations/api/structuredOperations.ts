import { apiClient } from '@/lib/api/client'
import { catalogApi, type CatalogPage, type CatalogQuery } from '@/lib/api/catalogs'
import { pageParams, readPageMeta } from '@/lib/api/pagination'

/**
 * S8 — **o cliente das operações estruturadas, dos tipos, das remunerações e
 * das fontes de recurso**.
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `structured_operations`, `structured_operation_types` e `remunerations` estão
 * entre as **24 migrations que nunca subiram**: a última aplicada em produção é
 * de 25/05/2022 e o sistema rodou até 31/05/2025. Nenhuma operação estruturada
 * e nenhuma remuneração existiram em produção. O que está portado aqui é
 * espelho do fonte de 2022 (`../sfg/app/views/pub/console/parts/`), não de
 * comportamento observado.
 *
 * ## As duas regras que valem para tudo o que está aqui
 *
 * 1. **Nenhum componente React multiplica capital por taxa** (contrato **C2**).
 *    O `%` que aparece na célula é rótulo; o valor do recibo vem pronto do
 *    `Charges::ReceiptGenerator`, que é o único lugar que arredonda.
 * 2. **Os saldos chegam NEGATIVOS e são exibidos assim** (DEC-01 / Q-R20).
 *    `original_balance` é gravado `(-1) * |valor|` em todo save
 *    (`structured_operation.rb:37`) e o `balance` é resetado junto — ele é
 *    **decorativo** (T-D6 / BE-292): nada no legado inteiro dá baixa nele.
 *    Normalizar o sinal aqui "consertaria" o Q-R20 sem ninguém ter decidido.
 *
 * ## Escopo (contrato C1)
 *
 * `structured_operations` e `remunerations` são **por projeto** — o servidor
 * resolve pelo `current_project!` e o cliente **não** manda `project_id`.
 * `structured_operation_types` e `resource_sources` são **catálogo global**
 * (§0.6 regra 4), sem escopo.
 *
 * ## `resource_kinds` NÃO existe aqui — DEC-110
 *
 * O portão T-D7 foi respondido pelo dump: `resource_kinds` tem **0 linhas** e
 * **0 de 28.131** `receivable_entries` a referenciam. Os 9 IDs viraram
 * `dropped`. Se você veio acrescentar o cliente dela, pare: a decisão está
 * escrita e a tabela sai numa tarefa explícita.
 */

// --- Tipos ------------------------------------------------------------------

/** Espelho de `Api::Entities::StructuredOperation`. */
export interface StructuredOperation {
  id: string
  /** Em branco na criação recebe `carrier.title` — fotografia, não referência. */
  title: string
  /** DERIVADO da empresa em todo save; o do corpo é ignorado. */
  project_id: string
  company_id: string
  company_title: string | null
  carrier_id: string
  carrier_title: string | null
  operation_type_id: string
  operation_type_title: string | null
  /** Sem unicidade — a ausência é replicada (Q-R7). */
  contract_number: string | null
  /** Pode ser nula na leitura de registro antigo — a tela NÃO pode quebrar. */
  issue_date: string | null
  due_date: string | null
  /** Decimal como string. Capital: é o multiplicando da remuneração. */
  operation_value: string
  /** **NEGATIVO** por convenção do legado (DEC-01). */
  original_balance: string
  /** **DECORATIVO** (T-D6): resetado para `original_balance` em todo save. */
  balance: string
  /** **NÃO é a taxa que remunera** — quem remunera é `remunerations.value`. */
  agreed_rate: string
  observation: string | null
  is_on_variable: boolean
  /** Sem consumidor: operação encerrada CONTINUA candidata a recibo (Q-R18). */
  is_ended: boolean
  receipt_id: string | null
  /** Bloqueia a exclusão com 422 REAL (BE-287). */
  has_receipt: boolean
  user_id: string | null
  updated_by_id: string | null
  created_at: string
  updated_at: string
}

/** Espelho de `Api::Entities::StructuredOperationType`. Catálogo GLOBAL. */
export interface StructuredOperationType {
  id: string
  /** IMUTÁVEL depois do create (BE-298). */
  title: string
  /** CONGELADA na criação. */
  integration_key: string
  is_active: boolean
  /** Os 4 tipos semeados são todos `true` — na prática nenhum é removível. */
  is_default: boolean
  allow_manual_operations: boolean
  allow_receivable_entries: boolean
  /** Sem consumidor. NÃO gera subtipo nem muda bucket (≠ `risk_operation_types`). */
  has_pre_faturamento: boolean
  dependents_count: number
  created_at: string
  updated_at: string
}

/** Espelho de `Api::Entities::Remuneration`. */
export interface Remuneration {
  id: string
  project_id: string
  operation_type_type: RemunerationClass
  operation_type_id: string
  /** `LIQ` | `EST` — a sigla que o recibo congela. Nunca `"???"` (BE-304). */
  beauty_type: 'LIQ' | 'EST'
  /** DESNORMALIZADO do tipo, reescrito em todo save (B-06). A busca usa esta coluna. */
  title: string
  /** A taxa em %. **SEM limite superior nem inferior** (T-D9). */
  value: string
  /** Recibos emitidos com esta taxa — é o que bloqueia a exclusão (BE-303). */
  receipts_count: number
  created_at: string
  updated_at: string
}

/**
 * **Fonte de recurso** — o cliente **não é redeclarado aqui**.
 *
 * `resourceSourcesApi` já existe em `lib/api/receivables.ts`: a S6 o trouxe
 * porque `receivable_entries.resource_source_id` é obrigatório (28.131 de
 * 28.131 linhas de produção têm valor) e o formulário de borderô não sobe sem o
 * select. Ele nasce de `catalogApi`, então `create`/`update`/`remove` — a
 * superfície de ESCRITA que é desta fatia (`BE-308`, `BE-725`…`BE-729`) — já
 * estão lá. Declarar um segundo cliente daria uma segunda leitura do envelope
 * de paginação, que é exatamente o que `lib/api/pagination.ts` existe para
 * impedir.
 *
 * **`resource_kinds` NÃO ganha cliente — DEC-110.** É coisa diferente, e só
 * `resource_sources` tem dado.
 */
export { resourceSourcesApi, type ResourceSource } from '@/lib/api/receivables'

export const REMUNERATION_CLASSES = ['RiskOperationType', 'StructuredOperationType'] as const
export type RemunerationClass = (typeof REMUNERATION_CLASSES)[number]

/** Os rótulos do select "Remuneração para", como o legado os escreve. */
export const REMUNERATION_CLASS_LABELS: Record<RemunerationClass, string> = {
  RiskOperationType: 'Operações liquidáveis',
  StructuredOperationType: 'Operações estruturadas',
}

export interface StructuredOperationQuery extends CatalogQuery {
  companyId?: string
  carrierId?: string
  operationTypeId?: string
  from?: string
  to?: string
  /**
   * Ordenação MULTI-COLUNA: pares paralelos `ordering_keys[]` /
   * `ordering_style[]`, como `Sfg::Sortable` espera. A allowlist do servidor
   * (BE-283) **não** tem `company`: a chave existia no legado mapeada para
   * `companies.title` e **não há coluna "Empresa" na tela** (decisão B-13).
   * Chave fora da allowlist devolve **400**, não 500.
   */
  orderingKeys?: string[]
  orderingStyles?: Array<'up' | 'down'>
}

export interface StructuredOperationInput {
  company_id: string
  carrier_id: string
  operation_type_id: string
  title?: string
  contract_number?: string
  /** `YYYY-MM-DD`. Imutável depois da criação (T-D5). */
  issue_date?: string
  due_date?: string
  operation_value: number
  /** Enviado em MÓDULO: quem inverte o sinal é o servidor (DEC-01). */
  original_balance?: number
  agreed_rate?: number
  observation?: string
  is_on_variable?: boolean
  is_ended?: boolean
  /**
   * **BE-291** — exigido quando a empresa escolhida é de OUTRO projeto.
   * `project_id` é derivado de `company.project_id` em todo save, e no legado
   * bastava trocar um select para a operação mudar de tenant, deixando para trás
   * a remuneração e o recibo do projeto original. O servidor recusa com
   * `code: 'PROJECT_CHANGE_REQUIRES_CONFIRMATION'` até este campo vir `true`.
   */
  confirm_project_change?: boolean
}

export interface RemunerationQuery extends CatalogQuery {
  /** `of_kind` no servidor: filtra a classe (LIQ × EST). */
  operationTypeType?: RemunerationClass
}

export interface RemunerationInput {
  operation_type_type: RemunerationClass
  operation_type_id: string
  value: number
}

// --- Operações estruturadas -------------------------------------------------

const OPERACOES = '/api/v1/structured_operations'

export async function listStructuredOperations(
  filtros: StructuredOperationQuery = {},
): Promise<CatalogPage<StructuredOperation>> {
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

  const resposta = await apiClient.getRaw<StructuredOperation[]>(OPERACOES, { params })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
  }
}

export const structuredOperationsApi = {
  list: listStructuredOperations,
  /** Id inexistente (ou de outro projeto) responde **404**, não 500 (FE-299). */
  get: (id: string) => apiClient.get<StructuredOperation>(`${OPERACOES}/${id}`),
  create: (dados: StructuredOperationInput) => apiClient.post<StructuredOperation>(OPERACOES, dados),
  update: (id: string, dados: Partial<StructuredOperationInput>) =>
    apiClient.put<StructuredOperation>(`${OPERACOES}/${id}`, dados),
  /**
   * Bloqueada por recibo → **422 com a dependência**. No legado o ternário
   * degenerado `errors.any? ? :ok : :ok` respondia **200**, a tela tratava como
   * sucesso e recarregava a lista com o registro ainda lá (BE-287 / FE-292).
   */
  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`${OPERACOES}/${id}`),
}

// --- Tipos de operação estruturada (catálogo GLOBAL) ------------------------

export const structuredOperationTypesApi = catalogApi<StructuredOperationType>(
  '/api/v1/structured_operation_types',
)

// --- Remunerações -----------------------------------------------------------

const REMUNERACOES = '/api/v1/remunerations'

export async function listRemunerations(
  filtros: RemunerationQuery = {},
): Promise<CatalogPage<Remuneration>> {
  const params: Record<string, unknown> = { ...pageParams(filtros) }
  if (filtros.q) params.q = filtros.q
  if (filtros.operationTypeType) params.operation_type_type = filtros.operationTypeType
  if (filtros.orderingKey) {
    params['ordering_keys[]'] = [filtros.orderingKey]
    params['ordering_style[]'] = [filtros.orderingStyle ?? 'up']
  }

  const resposta = await apiClient.getRaw<Remuneration[]>(REMUNERACOES, { params })
  return {
    items: resposta.data ?? [],
    meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
  }
}

export const remunerationsApi = {
  list: listRemunerations,
  get: (id: string) => apiClient.get<Remuneration>(`${REMUNERACOES}/${id}`),
  /** `project_id` é **forçado** ao projeto corrente no servidor (BE-301). */
  create: (dados: RemunerationInput) => apiClient.post<Remuneration>(REMUNERACOES, dados),
  update: (id: string, dados: Partial<RemunerationInput>) =>
    apiClient.put<Remuneration>(`${REMUNERACOES}/${id}`, dados),
  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`${REMUNERACOES}/${id}`),
}
