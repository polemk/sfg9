/**
 * Paginação — o **único** lugar do front que sabe o formato do envelope.
 *
 * DEC-62 fixou Kaminari no backend e o `PaginationPill` no front, com um aviso:
 * *"não pode ficar meio a meio"*. Enquanto o S0-backend não fecha se o envelope
 * vem em **cabeçalho** (`set_pagination_headers`, `controller_helpers.rb:18`) ou
 * no **corpo** (`meta: { total, page, per_page, total_pages }`), o componente e
 * as telas ficam **agnósticos**: elas só conhecem `PageMeta`. A tradução do que
 * o servidor devolve para `PageMeta` acontece aqui e em mais lugar nenhum.
 *
 * Quando a decisão sair, muda-se `readPageMeta` — e nada mais. Se a leitura do
 * envelope estivesse espalhada por tela, essa decisão viraria um mutirão.
 *
 * Hoje a base já tem **três** formatos vivos, o que prova a necessidade:
 *   - `{ users: [...], total: 42 }`                     (`endpoints.ts:99`)
 *   - `{ sessions: [...], meta: { total, page, … } }`   (`endpoints.ts:302`)
 *   - cabeçalhos `X-Total-Count` / `X-Page` / `X-Per-Page`
 */

/** Contrato que as telas e o `PaginationPill` consomem. Só isto. */
export interface PageMeta {
  page: number
  perPage: number
  total: number
  totalPages: number
}

export interface PageRequest {
  page?: number
  perPage?: number
}

export const DEFAULT_PER_PAGE = 20

export function emptyPageMeta(perPage = DEFAULT_PER_PAGE): PageMeta {
  return { page: 1, perPage, total: 0, totalPages: 1 }
}

/** Converte para inteiro positivo, ou devolve `undefined` — nunca `NaN`. */
function inteiro(v: unknown): number | undefined {
  if (v === null || v === undefined || v === '') return undefined
  const n = typeof v === 'number' ? v : parseInt(String(v), 10)
  return Number.isFinite(n) && n >= 0 ? n : undefined
}

/**
 * Lê o envelope de qualquer um dos formatos aceitos.
 *
 * `totalPages` é **derivado** quando não vem pronto, e nunca fica abaixo de 1:
 * uma lista vazia continua sendo "página 1 de 1", senão o controle some e o
 * usuário não consegue mudar o tamanho da página para tentar de novo.
 */
export function readPageMeta(
  source: { body?: unknown; headers?: Record<string, unknown> | undefined },
  pedido?: PageRequest,
): PageMeta {
  const body = (source.body ?? {}) as Record<string, any>
  const meta = (body.meta ?? body.pagination ?? {}) as Record<string, any>
  const h = source.headers ?? {}
  const cab = (nome: string) => h[nome] ?? h[nome.toLowerCase()]

  const perPage =
    inteiro(meta.per_page ?? meta.perPage) ??
    inteiro(cab('X-Per-Page')) ??
    inteiro(pedido?.perPage) ??
    DEFAULT_PER_PAGE

  const page = inteiro(meta.page ?? meta.current_page) ?? inteiro(cab('X-Page')) ?? inteiro(pedido?.page) ?? 1

  const total = inteiro(meta.total ?? meta.total_count ?? body.total) ?? inteiro(cab('X-Total-Count')) ?? 0

  const totalPages =
    inteiro(meta.total_pages ?? meta.totalPages) ??
    inteiro(cab('X-Total-Pages')) ??
    Math.max(1, Math.ceil(total / Math.max(1, perPage)))

  return { page, perPage, total, totalPages: Math.max(1, totalPages) }
}

/** Monta os parâmetros de consulta no nome que o Kaminari espera. */
export function pageParams(req: PageRequest): Record<string, number> {
  return {
    page: Math.max(1, req.page ?? 1),
    per_page: Math.max(1, req.perPage ?? DEFAULT_PER_PAGE),
  }
}
