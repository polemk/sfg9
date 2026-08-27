import { useCallback, useMemo, useState } from 'react'
import { DEFAULT_PER_PAGE, type PageMeta, type PageRequest } from '@/lib/api/pagination'

/**
 * Estado de paginação de uma listagem.
 *
 * Existe para que "mudar de página" signifique a mesma coisa em toda tela:
 * trocar o tamanho da página **volta para a primeira** (senão o usuário fica
 * numa página 7 que passou a não existir), e o valor de página nunca passa do
 * total conhecido. Cada tela reimplementando isso é como se chega a três
 * comportamentos de "próxima página" (DS0-3 do `design.md`).
 *
 * O hook não sabe buscar dado: ele devolve `page`/`perPage` para entrar na
 * `queryKey` do React Query e os dois `on*Change` que o `PaginationPill` espera.
 */
export interface UsePaginationOptions {
  initialPage?: number
  initialPerPage?: number
  /** Chamado quando página ou tamanho mudam — útil para sincronizar a URL. */
  onChange?: (req: Required<PageRequest>) => void
}

export function usePagination({ initialPage = 1, initialPerPage = DEFAULT_PER_PAGE, onChange }: UsePaginationOptions = {}) {
  const [page, setPageState] = useState(Math.max(1, initialPage))
  const [perPage, setPerPageState] = useState(Math.max(1, initialPerPage))

  const setPage = useCallback(
    (next: number) => {
      const p = Math.max(1, Math.floor(next) || 1)
      setPageState(p)
      onChange?.({ page: p, perPage })
    },
    [perPage, onChange],
  )

  const setPerPage = useCallback(
    (next: number) => {
      const pp = Math.max(1, Math.floor(next) || 1)
      setPerPageState(pp)
      // Trocar o tamanho da página invalida o número da página atual.
      setPageState(1)
      onChange?.({ page: 1, perPage: pp })
    },
    [onChange],
  )

  const reset = useCallback(() => setPageState(1), [])

  return useMemo(
    () => ({ page, perPage, setPage, setPerPage, reset, request: { page, perPage } as Required<PageRequest> }),
    [page, perPage, setPage, setPerPage, reset],
  )
}

/** Ajusta a página quando o total encolheu (filtro novo, item apagado). */
export function clampPage(page: number, meta: PageMeta | undefined): number {
  if (!meta) return page
  return Math.min(Math.max(1, page), Math.max(1, meta.totalPages))
}
