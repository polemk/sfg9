import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { renderHook, act } from '@testing-library/react'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { usePagination } from '@/hooks/usePagination'
import { readPageMeta } from '@/lib/api/pagination'

/**
 * FE-053 — o teste que importa é "mudar de página **muda a consulta**".
 * Um teste que só verifica que o botão existe passa com o `onPageChange`
 * desligado, que é exatamente o defeito que o legado tinha.
 */
describe('PaginationPill', () => {
  const base = {
    page: 3,
    totalPages: 7,
    perPage: 20,
    onPageChange: vi.fn(),
    onPerPageChange: vi.fn(),
  }

  it('avança, volta e vai às pontas chamando onPageChange com a página certa', () => {
    const onPageChange = vi.fn()
    render(<PaginationPill {...base} onPageChange={onPageChange} />)

    fireEvent.click(screen.getByLabelText('Próxima página'))
    fireEvent.click(screen.getByLabelText('Página anterior'))
    fireEvent.click(screen.getByLabelText('Primeira página'))
    fireEvent.click(screen.getByLabelText('Última página'))

    expect(onPageChange.mock.calls.map((c) => c[0])).toEqual([4, 2, 1, 7])
  })

  it('desabilita as pontas quando já está nelas', () => {
    const { rerender } = render(<PaginationPill {...base} page={1} />)
    expect(screen.getByLabelText('Primeira página')).toBeDisabled()
    expect(screen.getByLabelText('Página anterior')).toBeDisabled()
    expect(screen.getByLabelText('Próxima página')).not.toBeDisabled()

    rerender(<PaginationPill {...base} page={7} />)
    expect(screen.getByLabelText('Última página')).toBeDisabled()
    expect(screen.getByLabelText('Próxima página')).toBeDisabled()
  })

  it('trocar o tamanho da página emite onPerPageChange no blur', () => {
    const onPerPageChange = vi.fn()
    render(<PaginationPill {...base} onPerPageChange={onPerPageChange} />)
    const campo = screen.getByLabelText('Itens por página')
    fireEvent.change(campo, { target: { value: '50' } })
    fireEvent.blur(campo)
    expect(onPerPageChange).toHaveBeenCalledWith(50)
  })

  it('tamanho de página inválido volta ao valor anterior e não emite', () => {
    const onPerPageChange = vi.fn()
    render(<PaginationPill {...base} onPerPageChange={onPerPageChange} />)
    const campo = screen.getByLabelText('Itens por página') as HTMLInputElement
    fireEvent.change(campo, { target: { value: '0' } })
    fireEvent.blur(campo)
    expect(onPerPageChange).not.toHaveBeenCalled()
    expect(campo.value).toBe('20')
  })
})

describe('MobilePagination', () => {
  it('some quando há uma página só — não ocupa espaço à toa no celular', () => {
    const { container } = render(
      <MobilePagination page={1} total={5} perPage={20} onPageChange={vi.fn()} />,
    )
    expect(container).toBeEmptyDOMElement()
  })

  it('muda de página compartilhando a mesma API do desktop', () => {
    const onPageChange = vi.fn()
    render(<MobilePagination page={2} total={140} perPage={20} onPageChange={onPageChange} />)
    fireEvent.click(screen.getByText(/Próxima/))
    expect(onPageChange).toHaveBeenCalledWith(3)
  })
})

describe('usePagination', () => {
  it('trocar o tamanho da página volta para a primeira', () => {
    const { result } = renderHook(() => usePagination({ initialPerPage: 20 }))
    act(() => result.current.setPage(5))
    expect(result.current.page).toBe(5)
    act(() => result.current.setPerPage(50))
    expect(result.current.page).toBe(1)
    expect(result.current.perPage).toBe(50)
  })
})

/**
 * DEC-62 deixou em aberto se o envelope vem em cabeçalho ou no corpo. O
 * componente é agnóstico porque `readPageMeta` entende os dois — este teste é
 * o que garante que a decisão do backend não vai exigir mexer em tela nenhuma.
 */
describe('readPageMeta', () => {
  it('lê o envelope do corpo (meta)', () => {
    expect(readPageMeta({ body: { meta: { total: 140, page: 3, per_page: 20, total_pages: 7 } } })).toEqual({
      page: 3,
      perPage: 20,
      total: 140,
      totalPages: 7,
    })
  })

  it('lê o envelope dos cabeçalhos', () => {
    expect(
      readPageMeta({ headers: { 'X-Total-Count': '140', 'X-Page': '3', 'X-Per-Page': '20' } }),
    ).toEqual({ page: 3, perPage: 20, total: 140, totalPages: 7 })
  })

  it('lê o formato antigo `{ total }` no corpo e deriva o total de páginas', () => {
    expect(readPageMeta({ body: { users: [], total: 45 } }, { page: 2, perPage: 20 })).toEqual({
      page: 2,
      perPage: 20,
      total: 45,
      totalPages: 3,
    })
  })

  it('lista vazia continua sendo "1 de 1" — o controle não pode sumir', () => {
    expect(readPageMeta({ body: {} }).totalPages).toBe(1)
  })
})
