import { apiClient } from './client'
import { pageParams, readPageMeta, type PageMeta, type PageRequest } from './pagination'

/**
 * S9 — **renegociações**: a dívida negociada com um fornecedor, parcelada, paga
 * ao longo do tempo e documentada por anexos.
 *
 * **Nenhuma chamada daqui manda `project_id`.** O escopo é resolvido no servidor
 * por `current_project!` (contrato C1), e um `project_id` no corpo seria ignorado
 * de qualquer forma — é a ausência dele aqui que impede a tela de virar a fonte
 * de escopo. É a mesma regra de `lib/api/projects.ts`, e ela está escrita nos
 * dois arquivos para que ninguém "conserte" um na direção do outro.
 *
 * As rotas de parcela, pagamento e anexo são **aninhadas** em
 * `/renegotiations/:id/…`: o escopo pai fica visível na própria URL. No legado as
 * rotas eram planas e a renegociação vinha por parâmetro — foi assim que
 * `renegotiation_id` virou um seletor global que atravessava projeto.
 *
 * ## Duas coisas que esta tela NÃO faz, e são o contrato C2
 *
 * 1. **Não calcula nada.** Todo derivado — total da parcela, pendente, saldo,
 *    percentual pago — vem do servidor, inclusive na PRÉVIA (`installmentPreview`).
 *    A regra financeira existe num lugar só (`Renegotiations::Formulas`).
 * 2. **Não tem número escrito nela.** Tipos, estados, tipos de intervalo e os
 *    limites de anexo vêm dos endpoints `options` e `attachments/limits`.
 */

// --- Tipos ----------------------------------------------------------------

/** Estados do domínio. Os valores são os do legado e viajam como dado. */
export type RenegotiationState = 'Liquidado' | 'Pago' | 'Inconsistente' | 'Sem parcela cadastrada'

/** Chave pública do filtro de estado (o servidor traduz para o valor gravado). */
export type RenegotiationStateFilter = 'closed' | 'open' | 'inconsistent' | 'empty'

export interface Renegotiation {
  id: string
  project_id: string
  provider_id: string
  company_id: string
  title: string
  provider_name: string
  company_title: string | null
  kind: string
  integration_key: string
  renegotiation_date: string
  observation: string | null
  origin: string | null
  monetary_correction: string | null
  has_safegold_management: boolean

  // Cadastro
  original_value: string
  original_pending_value: string
  additional_value: string
  total_debt: string
  desagio_value: string
  /** Sempre igual a `total_debt` (D-47, Q-B24). */
  correct_value: string
  /** Existe e nunca é lida pelo cálculo (D-47) — fica fora da tela. */
  interest_rate_correction: number
  /** Idem. */
  grace_period: number
  operation_interest_rate: number

  // Agregados
  installments_main_value: string
  installments_interest_value: string
  installments_main_value_with_interest: string
  installments_monetary_correction_value: string
  installments_main_value_with_interest_cm: string
  main_value: string
  paid_value_with_interest_cm: string
  late_payment_value: string
  /** R$ Pago — **conta a mora**. */
  paid_value: string
  /** Pode ficar **negativo** (Q-B22). */
  pending_main_value: string
  /** R$ A Pagar — soma com piso em zero; **ignora a mora**. */
  remaining_value: string
  paid_percent: number
  total_value_with_desagio: string
  /** Valor Parcela do mês — **sobrescrito pelo VP** quando há juros (D-46). */
  current_installment_value: string
  /** VP da dívida. */
  current_value: string

  installments_count: number
  paid_installments: number
  /** total - pagas. **Inclui as vencidas** (Q-B23). */
  due_installments: number
  /** Apurado na consulta, não no cron diário (OPS-190). */
  overdue_installments: number

  first_due_date: string | null
  last_due_date: string | null
  /** Próxima parcela em aberto. Vencida nunca é "próxima". */
  next_due_date: string | null

  state: RenegotiationState
  /** "42.5% Pago" quando há pagamento. */
  beauty_state: string
  installment_status: 'Consistente' | 'Inconsistente'
  unposted_value: string

  attachments_count: number
  created_at: string
  updated_at: string
}

export interface RenegotiationPayment {
  id: string
  renegotiation_id: string
  renegotiation_installment_id: string
  payment_number: number | null
  date: string
  days_late: number
  installment_paid_value_with_interest_cm: string
  late_payment_value: string
  total_paid_value: string
  created_at: string
  updated_at: string
}

export interface RenegotiationInstallment {
  id: string
  renegotiation_id: string
  number: number | null
  due_date: string
  month: number | null
  year: number | null
  main_value: string
  interest_value: string
  main_value_with_interest: string
  monetary_correction_value: string
  main_value_with_interest_cm: string
  late_payment_value: string
  installment_total_value: string
  paid_value: string
  /** `pago - devido`: **negativo** enquanto falta pagar. */
  saldo: string
  /** `devido - pago`, com **piso em zero**. */
  pending_value: string
  is_paid: boolean
  batch_token: string
  color: string | null
  has_payments: boolean
  payments: RenegotiationPayment[]
  created_at: string
  updated_at: string
}

export interface RenegotiationAttachment {
  id: string
  renegotiation_id: string
  title: string
  format: string
  filename: string
  is_image: boolean
  byte_size: number | null
  content_type: string | null
  /** Identificador **assinado** do binário — nunca o id da linha. */
  file_id: string | null
  author_id: string | null
  author_name: string | null
  /** Conveniência da tela; a regra é a do servidor (BE-229). */
  can_delete: boolean
  created_at: string
}

export interface RenegotiationGeneralValues {
  renegotiation_id: string
  paid_value: string
  remaining_value: string
  total_debt: string
  installments_value: string
  unposted_value: string
  installment_status: 'Consistente' | 'Inconsistente'
  show_remove_all_option: boolean
}

export interface RenegotiationOptions {
  kinds: string[]
  origins: string[]
  states: { value: RenegotiationStateFilter; label: string }[]
  delay_types: string[]
}

export interface RenegotiationAttachmentLimits {
  max_files: number
  max_size_bytes: number
  max_size_megabytes: number
  content_types: string[]
  used: number
  remaining: number
}

export interface RenegotiationQuery extends PageRequest {
  q?: string
  state?: RenegotiationStateFilter
  kind?: string
  orderingKey?: string
  orderingStyle?: 'up' | 'down'
  /**
   * **A PILHA — FE-194.** A coluna clicada vira primária e as anteriores viram
   * desempate, como no legado. Tem precedência sobre a forma singular, que é
   * açúcar para uma pilha de um elemento. Ver `useSortStack`.
   */
  orderingKeys?: string[]
  orderingStyles?: ('up' | 'down')[]
}

export interface RenegotiationPage {
  items: Renegotiation[]
  meta: PageMeta
}

/** O que o painel de parcela manda para a prévia **e** para a gravação. */
export interface InstallmentDraft {
  due_date: string
  main_value: number | null
  interest_value?: number | null
  monetary_correction_value?: number | null
  multiple?: boolean
  repetitions?: number | null
  repetition_delay?: number | null
  repetition_type?: string | null
}

/** Derivados que o SERVIDOR calcula para o rascunho (FE-221 / C2). */
export interface InstallmentPreview {
  installments: Array<{
    due_date: string
    main_value: string
    interest_value: string
    monetary_correction_value: string
    main_value_with_interest: string
    main_value_with_interest_cm: string
    installment_total_value: string
    paid_value: string
    saldo: string
    pending_value: string
    is_paid: boolean
  }>
  renegotiation: Partial<Renegotiation> & { state: RenegotiationState }
}

// --- Fiação ---------------------------------------------------------------

const BASE = '/api/v1/renegotiations'

const sub = (renegotiationId: string, recurso: string) =>
  `${BASE}/${encodeURIComponent(renegotiationId)}/${recurso}`

function queryOf(f: RenegotiationQuery): Record<string, unknown> {
  const q: Record<string, unknown> = { ...pageParams(f) }
  if (f.q) q.q = f.q
  if (f.state) q.state = f.state
  if (f.kind) q.kind = f.kind
  // Arrays paralelos: é o contrato de `Sfg::Sortable` no servidor, e é o formato
  // que o legado já falava.
  if (f.orderingKeys?.length) {
    q['ordering_keys[]'] = f.orderingKeys
    q['ordering_style[]'] = f.orderingKeys.map((_, i) => f.orderingStyles?.[i] ?? 'up')
  } else if (f.orderingKey) {
    q['ordering_keys[]'] = [f.orderingKey]
    q['ordering_style[]'] = [f.orderingStyle ?? 'up']
  }
  return q
}

/** Limpa o rascunho antes de enviar: o servidor recusa `null` em campo numérico. */
function draftParams(draft: InstallmentDraft): Record<string, unknown> {
  const params: Record<string, unknown> = {
    due_date: draft.due_date,
    main_value: draft.main_value ?? 0,
    interest_value: draft.interest_value ?? 0,
    monetary_correction_value: draft.monetary_correction_value ?? 0,
    multiple: !!draft.multiple,
  }
  if (draft.multiple) {
    params.repetitions = draft.repetitions ?? 1
    params.repetition_delay = draft.repetition_delay ?? 1
    params.repetition_type = draft.repetition_type
  }
  return params
}

export const renegotiationsApi = {
  async list(filtros: RenegotiationQuery = {}): Promise<RenegotiationPage> {
    const resposta = await apiClient.getRaw<Renegotiation[]>(BASE, { params: queryOf(filtros) })
    return {
      items: resposta.data ?? [],
      meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, filtros),
    }
  },

  get: (id: string) => apiClient.get<Renegotiation>(`${BASE}/${encodeURIComponent(id)}`),

  /** Tipos, origens, estados e tipos de intervalo — a tela não os tem escritos. */
  options: () => apiClient.get<RenegotiationOptions>(`${BASE}/options`),

  /** Painel de consistência do lançamento. **Recalcula** antes de responder. */
  generalValues: (id: string) =>
    apiClient.get<RenegotiationGeneralValues>(`${BASE}/${encodeURIComponent(id)}/general_values`),

  create: (dados: Record<string, unknown>) => apiClient.post<Renegotiation>(BASE, dados),
  update: (id: string, dados: Record<string, unknown>) =>
    apiClient.put<Renegotiation>(`${BASE}/${encodeURIComponent(id)}`, dados),
  remove: (id: string) => apiClient.delete<{ deleted: boolean }>(`${BASE}/${encodeURIComponent(id)}`),

  // --- Parcelas -----------------------------------------------------------
  installments: {
    async list(renegotiationId: string, pedido: PageRequest = {}) {
      const resposta = await apiClient.getRaw<RenegotiationInstallment[]>(
        sub(renegotiationId, 'installments'),
        { params: pageParams({ perPage: 100, ...pedido }) },
      )
      return {
        items: resposta.data ?? [],
        meta: readPageMeta({ body: resposta.data, headers: resposta.headers as any }, pedido),
      }
    },

    /**
     * **A prévia e a gravação usam o MESMO rascunho e o MESMO serviço** (C2).
     * Se algum dia estes dois métodos divergirem no que mandam, o usuário passa a
     * ver um total na simulação e outro depois de salvar.
     */
    preview: (renegotiationId: string, draft: InstallmentDraft, replacingId?: string) =>
      apiClient.post<InstallmentPreview>(sub(renegotiationId, 'installments/preview'), {
        ...draftParams(draft),
        ...(replacingId ? { replacing_id: replacingId } : {}),
      }),

    create: (renegotiationId: string, draft: InstallmentDraft) =>
      apiClient.post<{ created: number; batch_token: string; installments: RenegotiationInstallment[] }>(
        sub(renegotiationId, 'installments'),
        draftParams(draft),
      ),

    update: (renegotiationId: string, id: string, dados: Record<string, unknown>) =>
      apiClient.put<RenegotiationInstallment>(
        `${sub(renegotiationId, 'installments')}/${encodeURIComponent(id)}`,
        dados,
      ),

    remove: (renegotiationId: string, id: string) =>
      apiClient.delete<{ deleted: boolean }>(
        `${sub(renegotiationId, 'installments')}/${encodeURIComponent(id)}`,
      ),

    /** Ou o lote inteiro sai, ou nada sai (BE-202, corrige D-51). */
    removeBatch: (renegotiationId: string, ids: string[]) =>
      apiClient.delete<{ deleted: number }>(`${sub(renegotiationId, 'installments')}/batch`, {
        params: { 'renegotiation_installment_ids[]': ids },
      }),
  },

  // --- Pagamentos ---------------------------------------------------------
  // ⚠ DEC-53: o backend existe e é usado pela SUBLINHA da parcela (FE-227).
  // **Não há aba PAGAMENTOS** — no legado ela está comentada, e no ai9 também
  // não existe. O QA do Phase 4 não deve abrir defeito pela aba ausente.
  payments: {
    create: (
      renegotiationId: string,
      dados: {
        renegotiation_installment_id: string
        date: string
        installment_paid_value_with_interest_cm: number
        late_payment_value?: number
      },
    ) => apiClient.post<RenegotiationPayment>(sub(renegotiationId, 'payments'), dados),

    update: (renegotiationId: string, id: string, dados: Record<string, unknown>) =>
      apiClient.put<RenegotiationPayment>(
        `${sub(renegotiationId, 'payments')}/${encodeURIComponent(id)}`,
        dados,
      ),

    remove: (renegotiationId: string, id: string) =>
      apiClient.delete<{ deleted: boolean }>(
        `${sub(renegotiationId, 'payments')}/${encodeURIComponent(id)}`,
      ),
  },

  // --- Anexos -------------------------------------------------------------
  attachments: {
    list: (renegotiationId: string) =>
      apiClient.get<RenegotiationAttachment[]>(sub(renegotiationId, 'attachments'), {
        params: { per_page: 100 },
      }),

    limits: (renegotiationId: string) =>
      apiClient.get<RenegotiationAttachmentLimits>(sub(renegotiationId, 'attachments/limits')),

    upload: (renegotiationId: string, arquivos: File[]) => {
      const form = new FormData()
      arquivos.forEach((arquivo) => form.append('files[]', arquivo))
      return apiClient.post<RenegotiationAttachment[]>(sub(renegotiationId, 'attachments'), form)
    },

    /** DEC-53 — renomear, que no legado levantava `NameError` garantido. */
    rename: (renegotiationId: string, id: string, title: string) =>
      apiClient.put<RenegotiationAttachment>(
        `${sub(renegotiationId, 'attachments')}/${encodeURIComponent(id)}`,
        { title },
      ),

    remove: (renegotiationId: string, id: string) =>
      apiClient.delete<{ deleted: boolean; attachments_count: number }>(
        `${sub(renegotiationId, 'attachments')}/${encodeURIComponent(id)}`,
      ),

    /**
     * Download pelo endereço **autorizado** (FE-212).
     *
     * É um `fetch` com a credencial da sessão, e não um `<a href>`: a rota exige
     * `Authorization`, então um link solto responderia 401 e a tela pareceria
     * quebrada. O servidor confere o projeto, responde sempre
     * `Content-Disposition: attachment` e nunca serve o arquivo de `public/` —
     * o oposto do legado, onde o caminho vinha no HTML e apontava para
     * `public/system/…`, estático e sem autenticação nenhuma (D-82).
     */
    async download(renegotiationId: string, id: string, filename: string) {
      const blob = await apiClient.get<Blob>(
        `${sub(renegotiationId, 'attachments')}/${encodeURIComponent(id)}/download`,
        { responseType: 'blob' },
      )
      const url = window.URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      link.setAttribute('download', filename)
      document.body.appendChild(link)
      link.click()
      link.parentNode?.removeChild(link)
      window.URL.revokeObjectURL(url)
    },
  },
}
