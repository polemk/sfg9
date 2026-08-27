import { apiClient } from './client'
import { catalogApi, type CatalogRecord } from './catalogs'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * S6 — **recebíveis, cobranças e os três catálogos do borderô**.
 *
 * ## O que este arquivo NÃO tem, e é a decisão que mais importa
 *
 * **Nenhuma fórmula.** Nem uma multiplicação de valor, nem um `Math.pow`, nem
 * um arredondamento sobre campo derivado. O cálculo do borderô vive em **um**
 * lugar — `Receivables::Calculator`, no servidor — e chega aqui pronto, pelo
 * `POST /receivables/preview` (contrato **C2**).
 *
 * No legado a conta existia **duas vezes**: no `before_validation` do model
 * (`../sfg/app/models/receivable_entry.rb:38-118`) e numa reimplementação
 * **parcial** em JavaScript (`receivables/new/_body.js.erb:339-504`) que não
 * calculava `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`,
 * `multiplicador_*` nem os `*_percent`, e arredondava o total de tarifas de
 * outro jeito. Era o **D-09**: o usuário via um número na tela e outro depois
 * de salvar, e não havia como dizer qual estava certo. Há teste de varredura
 * (tarefa 4.28) que reprova se qualquer fórmula do calculador reaparecer em
 * `frontend/src/**`.
 *
 * ## Escopo por projeto
 *
 * `receivables` e `charges` são **escopados** (C1): o servidor resolve o
 * projeto por `current_project!` e o `X-Project-Id` viaja no interceptor do
 * `apiClient`. `project_id` nunca é enviado no corpo.
 *
 * `wallets`, `receivable_kinds` e `movement_kinds` são **catálogos GLOBAIS**
 * (C1, regra 4) e usam a mesma fábrica dos catálogos da S3 — uma leitura só do
 * envelope de paginação, aqui como lá.
 */

// ---------------------------------------------------------------- catálogos

export interface Wallet extends CatalogRecord {
  receivable_entries_count: number
}

export type ReceivableKind = Wallet

/** Os quatro classificadores de taxa. **No máximo um** por tipo (BE-447). */
export type TaxClassifier = 'is_advalorem' | 'is_desagio' | 'is_iof' | 'is_liquidation'

export interface MovementKind extends CatalogRecord {
  /** `credit` | `debit`. No legado era o texto pt-BR gravado na coluna. */
  kind: 'credit' | 'debit' | null
  kind_label: string | null
  /** Só os `is_operation` entram na lista de tarifas do borderô. */
  is_operation: boolean
  is_advalorem: boolean
  is_desagio: boolean
  is_iof: boolean
  /** Portados SEM consumidor (D-74, Q-B13): nenhuma regra os lê, nem no legado. */
  is_liquidation: boolean
  is_title: boolean
  tax_classifier: TaxClassifier | null
  receivable_taxes_count: number
}

/**
 * **Fonte de recurso — catálogo da S8, lido pela S6.**
 *
 * `receivable_entries.resource_source_id` é obrigatório (28.131 de 28.131
 * linhas de produção têm valor), então o formulário de borderô precisa do
 * select. O servidor entrega **só a leitura**; criação e edição são da S8
 * (`BE-725`…`BE-729`) e este cliente não as expõe de propósito.
 */
export type ResourceSource = Wallet

export const resourceSourcesApi = catalogApi<ResourceSource>('/api/v1/resource_sources')
export const walletsApi = catalogApi<Wallet>('/api/v1/wallets')
export const receivableKindsApi = catalogApi<ReceivableKind>('/api/v1/receivable_kinds')
export const movementKindsApi = catalogApi<MovementKind>('/api/v1/movement_kinds')

// ---------------------------------------------------------------- borderô

/**
 * Os 37 valores calculados. **Somente leitura, sempre** — a tela nunca os
 * escreve, nem quando o usuário digita por cima.
 *
 * Os números chegam como `string` (o `decimal` do Postgres serializado) ou
 * `null`. **Nulo não é zero** (D-117): `formatMoney(null)` rende travessão e
 * `formatMoney(0)` rende `R$ 0,00`. No legado os dois viravam `R$ 0,00`, o que
 * num sistema de crédito confunde "não informado" com "zero".
 *
 * **Seis chegam como `number`, e isso é decisão** (DEC-117): `float_calculado`,
 * `diferenca_float` e os quatro `*_percent` voltaram a ser `float` no banco —
 * como sempre foram no legado —, porque a fórmula delas não arredonda e o
 * `decimal(15,6)` acrescentava um arredondamento que o legado não tinha (48
 * divergências em 5.321 comparações contra o dump de 31/05/2025). `float` do
 * Postgres serializa como número JSON; `decimal` serializa como string. O `n()`
 * do `CalculationPanel` já aceita os dois, e é por isso que a tela não muda.
 */
export interface ReceivableDerived {
  tarifas_ad_valorem: string | null
  tarifas_desagio: string | null
  tarifas_iof: string | null
  tarifas_outras: string | null
  vlr_bruto_final: string | null
  qtd_final: number | null
  float_calculado: number | null
  diferenca_float: number | null
  checagem_iof: string | null
  valor_total_tarifas: string | null
  valor_liquido: string | null
  recompra_percent: number | null
  retencao_percent: number | null
  fomento_percent: number | null
  outros_percent: number | null
  total_deducoes: string | null
  vlr_liq_recebido: string | null
  taxa_desconto_nominal_desagio_advalorem_bancos: string | null
  taxa_desconto_nominal_despesas_bancos: string | null
  taxa_desconto_nominal_despesas_iof_bancos: string | null
  custo_efetivo_pz_med_banco: string | null
  custo_efetivo_pz_med_banco_sem_iof: string | null
  taxa_desconto_nominal_desagio_advalorem_emp: string | null
  taxa_desconto_nominal_despesas_emp: string | null
  taxa_desconto_nominal_despesas_iof_emp: string | null
  custo_efetivo_pz_med_emp: string | null
  custo_efetivo_pz_med_emp_sem_iof: string | null
  custo_efetivo_sem_float: string | null
  custo_efetivo_com_float_total: string | null
  custo_efetivo_com_float_sem_iof: string | null
  multiplicador_pm_empresa: string | null
  multiplicador_pm_float: string | null
  calc_valor_liq_correto: string | null
  dif_calc_vlr_liq: string | null
  /** `ok` | `difference`. **Dois estados e nenhum terceiro** (D-19, Q-B9). */
  status: 'ok' | 'difference' | null
  /** Rótulo pt-BR: `OK` | `Diferença`. Vem do servidor — não é derivado aqui. */
  status_label: string | null
  nominal_tax_check: string | null
  nominal_tax_check_with_float: string | null
}

export interface ReceivableTax {
  id: string
  movement_kind_id: string
  /** Denormalizado NO DIA do lançamento (D-B13), não o título atual do tipo. */
  title: string
  value: string
  is_advalorem: boolean
  is_desagio: boolean
  is_iof: boolean
}

export interface ReceivableEntry {
  id: string
  date: string
  data_credito: string | null
  /** **String**: produção tem `F-76`, `48-49`, `202023005-6`, `1540962/20`. */
  nro_bordero: string | null
  contrato: string | null
  description: string | null
  /** Visível por **DEC-52** — no legado nenhuma view o lia. */
  observacoes: string | null
  has_safegold_management: boolean

  company_id: string
  carrier_id: string
  wallet_id: string
  receivable_kind_id: string
  resource_source_id: string
  risk_operation_type_id: string | null
  risk_operation_subtype_id: string | null
  user_id: string | null

  company_title: string | null
  carrier_title: string | null
  wallet_title: string | null
  receivable_kind_title: string | null
  resource_source_title: string | null

  valor_bruto: string
  vlr_bruto_recusado: string
  qtd_titulos: number
  qtd_recusada: number
  prz_med_pond_emp: string
  prz_med_pond_bco: string
  float_acordado: string
  cst_efetivo_acordado: string
  nominal_tax: string | null
  recompra: string
  retencao: string
  fomento: string
  outros: string

  taxes: ReceivableTax[]
  /**
   * **DEC-120** — o borderô tem ao menos uma tarifa de valor **desconhecido**
   * (o legado gravou `NaN`; a carga escreve NULO em vez de afirmar zero).
   *
   * Quando é `true`, `derived.valor_total_tarifas` e tudo que dele descende são
   * o total **do que se sabe**, não o total. A tela precisa dizer isso — número
   * redondo em cima de dado incompleto é a forma mais silenciosa de mentir.
   */
  has_unknown_tax: boolean
  derived: ReceivableDerived

  created_at: string
  updated_at: string
}

/** As 10 chaves de ordenação do legado, agora numa allowlist do servidor. */
export type ReceivableOrderingKey =
  | 'carrier' | 'wallet' | 'date' | 'bruto' | 'tarifas'
  | 'liquido' | 'titulos' | 'pmr' | 'cet' | 'cetsf'

export interface ReceivableQuery extends PageRequest {
  q?: string
  walletId?: string
  carrierId?: string
  companyId?: string
  status?: 'ok' | 'difference'
  /** Ausente OMITE a cláusula no servidor — fim de `DateTime.dinosaurs` (OPS-158). */
  dateFrom?: string
  dateTo?: string
  /**
   * Uma coluna só. É açúcar para uma pilha de um elemento — as listas que
   * genuinamente ordenam por uma coluna (catálogos) usam esta forma.
   */
  orderingKey?: ReceivableOrderingKey
  orderingStyle?: 'up' | 'down'
  /**
   * **A PILHA — FE-159.** `Sfg::Sortable` recebe `ordering_keys[]` e
   * `ordering_style[]` como pares paralelos, e a lista de borderôs empilha:
   * a coluna clicada vira primária e as anteriores viram desempate. Numa tabela
   * de borderôs o desempate é o que separa duas linhas do mesmo dia.
   *
   * Tem precedência sobre a forma singular. Ver `useSortStack`.
   */
  orderingKeys?: ReceivableOrderingKey[]
  orderingStyles?: ('up' | 'down')[]
}

export interface ReceivablePage {
  items: ReceivableEntry[]
  meta: PageMeta
}

export interface ReceivableSummary {
  count: number
  valor_bruto: string
  valor_total_tarifas: string
  valor_liquido: string
}

/** O que a tela envia. **Números como string**, do jeito que o usuário digitou. */
export interface ReceivablePayload {
  date: string
  company_id: string
  carrier_id: string
  wallet_id: string
  receivable_kind_id: string
  resource_source_id: string
  valor_bruto: number | null
  qtd_titulos: number | null
  prz_med_pond_emp: number | null
  prz_med_pond_bco: number | null
  vlr_bruto_recusado?: number | null
  qtd_recusada?: number | null
  float_acordado?: number | null
  cst_efetivo_acordado?: number | null
  recompra?: number | null
  retencao?: number | null
  fomento?: number | null
  outros?: number | null
  nominal_tax?: number | null
  data_credito?: string | null
  nro_bordero?: string | null
  description?: string | null
  observacoes?: string | null
  risk_operation_subtype_id?: string | null
  /**
   * A lista **completa** de tarifas. Ausente = preserva as existentes; presente
   * = passa a ser esta, e o que saiu é apagado. É a exclusão pendente da
   * **DEC-72**: remover tarifa marca a exclusão no formulário e ela só acontece
   * no Salvar, dentro da mesma transação que recalcula os agregados.
   */
  taxes?: { id?: string; movement_kind_id: string; value: number | null }[]
}

function queryOf(f: ReceivableQuery): Record<string, unknown> {
  const q: Record<string, unknown> = { ...pageParams(f) }
  if (f.q) q.q = f.q
  if (f.walletId) q.wallet_id = f.walletId
  if (f.carrierId) q.carrier_id = f.carrierId
  if (f.companyId) q.company_id = f.companyId
  if (f.status) q.status = f.status
  // Data ausente é OMITIDA, nunca substituída por uma sentinela.
  if (f.dateFrom) q.date_from = f.dateFrom
  if (f.dateTo) q.date_to = f.dateTo
  // A pilha vence a forma singular; as duas viajam no MESMO par de parâmetros,
  // porque para o servidor "uma coluna" sempre foi uma pilha de um elemento.
  if (f.orderingKeys?.length) {
    q['ordering_keys[]'] = f.orderingKeys
    q['ordering_style[]'] = f.orderingKeys.map((_, i) => f.orderingStyles?.[i] ?? 'up')
  } else if (f.orderingKey) {
    q['ordering_keys[]'] = [f.orderingKey]
    q['ordering_style[]'] = [f.orderingStyle ?? 'up']
  }
  return q
}

export const receivablesApi = {
  list: async (filtros: ReceivableQuery = {}): Promise<ReceivablePage> => {
    const resposta = await apiClient.getRaw<ReceivableEntry[]>('/api/v1/receivables', {
      params: queryOf(filtros),
    })
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  /** Totais da consulta INTEIRA — o rodapé não carrega 28 mil linhas para somar. */
  summary: (filtros: ReceivableQuery = {}) => {
    const { page, per_page, ...resto } = queryOf(filtros) as Record<string, unknown>
    return apiClient.get<ReceivableSummary>('/api/v1/receivables/summary', { params: resto })
  },

  get: (id: string) => apiClient.get<ReceivableEntry>(`/api/v1/receivables/${id}`),
  create: (dados: ReceivablePayload) => apiClient.post<ReceivableEntry>('/api/v1/receivables', dados),
  update: (id: string, dados: Partial<ReceivablePayload>) =>
    apiClient.put<ReceivableEntry>(`/api/v1/receivables/${id}`, dados),
  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`/api/v1/receivables/${id}`),

  /**
   * **A prévia (C2).** Mesmo payload, mesmo serviço, mesmos números da
   * gravação. Não persiste nada.
   */
  preview: (dados: Partial<ReceivablePayload>) =>
    apiClient.post<ReceivableDerived>('/api/v1/receivables/preview', dados),

  /** Textos de ajuda dos campos. Chave ausente = o campo NÃO exibe indicador. */
  helpTexts: () => apiClient.get<Record<string, string>>('/api/v1/receivable_help_texts'),
}

// ---------------------------------------------------------------- cobranças

/**
 * ⚠ **NUNCA EXECUTADO EM PRODUÇÃO** (DEC-103b). As tabelas `charges`,
 * `receipts` e `remunerations` não existem no banco de produção: as migrations
 * que as criam estão entre as 24 que nunca subiram. A regra vem espelhada do
 * código de 2022, sem correção.
 *
 * Os endpoints de **recibo** dependem de `Remuneration`, que é da **S8**.
 * Enquanto ela não existir, o servidor responde 422 nomeando a fatia — e a tela
 * mostra isso como estado, não como erro.
 */
export type ChargeState = 'editing' | 'available' | 'done'

/**
 * Os rótulos das três situações, ao lado do tipo que elas nomeiam.
 *
 * Vivem aqui, e não na tela, porque DUAS telas os usam: o filtro da lista e a
 * gaveta de edição. Copiados, divergiriam na primeira renomeação — e "Faturado"
 * é um estado sem volta, o pior lugar para dois nomes.
 */
export const CHARGE_STATES: { value: ChargeState; label: string }[] = [
  { value: 'editing', label: 'Edição' },
  { value: 'available', label: 'Disponível' },
  { value: 'done', label: 'Faturado' },
]

export interface Charge {
  id: string
  date: string
  state: ChargeState
  state_label: string
  /** `done` bloqueia alteração **no servidor**, não só na tela (D-18). */
  done: boolean
  value: string
  risk_operations_value: string
  structured_operations_value: string
  total_operations_value: string
  receipts_count: number
  risk_operations_count: number
  structured_operations_count: number
  user_id: string | null
  created_at: string
  updated_at: string
}

export interface ChargeReceipt {
  /** Identidade do candidato ANTES de existir: `RCP-<projeto>-<kind>-<remun>-<op>`. */
  temp_id: string
  id: string | null
  operation_id: string
  operation_type: 'RiskOperation' | 'StructuredOperation'
  remuneration_id: string
  kind: 'LIQ' | 'EST'
  title: string
  fee: string
  operation_value: string
  value: string
  /** **Pode ser nula**: a operação estática do par pré/antecipação não tem data. */
  date: string | null
  operation_title: string | null
  persisted: boolean
}

export interface ChargeStatementLine {
  kind: 'LIQ' | 'EST'
  remuneration_id: string
  title: string
  receipts_count: number
  operations_value: string
  value: string
}

export interface ChargeQuery extends PageRequest {
  state?: ChargeState
  month?: number
  /** Vazio = TODAS as cobranças. No legado não havia opção em branco (FE-180). */
  year?: number
  orderingKey?: 'date' | 'state' | 'value' | 'created_at'
  orderingStyle?: 'up' | 'down'
}

export const chargesApi = {
  list: async (filtros: ChargeQuery = {}): Promise<{ items: Charge[]; meta: PageMeta }> => {
    const params: Record<string, unknown> = { ...pageParams(filtros) }
    if (filtros.state) params.state = filtros.state
    if (filtros.month) params.month = filtros.month
    if (filtros.year) params.year = filtros.year
    if (filtros.orderingKey) {
      params['ordering_keys[]'] = [filtros.orderingKey]
      params['ordering_style[]'] = [filtros.orderingStyle ?? 'up']
    }
    const resposta = await apiClient.getRaw<Charge[]>('/api/v1/charges', { params })
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  get: (id: string) => apiClient.get<Charge>(`/api/v1/charges/${id}`),
  create: (dados: { date: string; state?: ChargeState }) => apiClient.post<Charge>('/api/v1/charges', dados),
  update: (id: string, dados: { date?: string; state?: ChargeState }) =>
    apiClient.put<Charge>(`/api/v1/charges/${id}`, dados),
  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`/api/v1/charges/${id}`),

  statement: (id: string) =>
    apiClient.get<{ charge: Charge; statement: ChargeStatementLine[] }>(`/api/v1/charges/${id}/statement`),

  receipts: (id: string) => apiClient.get<ChargeReceipt[]>(`/api/v1/charges/${id}/receipts`),

  /** A lista é o estado FINAL: o que não está nela é removido, tudo em UM lote. */
  setReceipts: (id: string, tempIds: string[]) =>
    apiClient.put<Charge>(`/api/v1/charges/${id}/receipts`, { temp_ids: tempIds }),
}
