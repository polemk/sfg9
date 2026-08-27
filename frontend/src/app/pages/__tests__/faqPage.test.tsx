import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

/**
 * S12 / tarefa 5.21 — os três defeitos observáveis da tela de FAQ do legado.
 */

const tree = vi.fn()
const items = vi.fn()
const search = vi.fn()

vi.mock('@/lib/api/help', () => ({
  faqApi: {
    tree: (...a: any[]) => tree(...a),
    items: (...a: any[]) => items(...a),
    search: (...a: any[]) => search(...a),
    get: vi.fn(),
  },
}))

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

const CATEGORIA = {
  id: 'cat-1',
  title: 'Dúvidas frequentes',
  slug: 'duvidas-frequentes',
  help_group_id: 'g-1',
  position: 0,
  items_count: 1,
}

const paginaVazia = { items: [], meta: { page: 1, perPage: 20, total: 0, totalPages: 1 } }

async function montar() {
  const { FaqPage } = await import('@/app/pages/FaqPage')
  return render(
    <Envolvido>
      <FaqPage />
    </Envolvido>,
  )
}

describe('FaqPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.useRealTimers()
    tree.mockResolvedValue([{ id: 'g-1', title: 'Primeiros passos', position: 0, categories: [CATEGORIA] }])
    items.mockResolvedValue(paginaVazia)
    search.mockResolvedValue(paginaVazia)
  })

  // (b) do FE-364 — o legado buscava no `keyup`: uma requisição por tecla.
  it('faz DEBOUNCE da busca: digitar 5 letras não dispara 5 requisições', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    await montar()
    await waitFor(() => expect(tree).toHaveBeenCalled())

    const campo = screen.getByPlaceholderText('Buscar na ajuda…')
    for (const letra of ['p', 'r', 'a', 'z', 'o']) {
      fireEvent.change(campo, { target: { value: (campo as HTMLInputElement).value + letra } })
    }

    expect(search).not.toHaveBeenCalled()

    await act(async () => {
      vi.advanceTimersByTime(400)
    })
    await waitFor(() => expect(search).toHaveBeenCalledTimes(1))
    expect(search).toHaveBeenCalledWith('prazo', expect.anything())
    vi.useRealTimers()
  })

  // (a) do FE-364 — o legado punha `" "` no termo ao trocar de categoria, e
  // itens de título curto sem espaço sumiam.
  it('trocar de categoria LIMPA a busca — nunca a deixa com um espaço', async () => {
    await montar()
    await waitFor(() => expect(tree).toHaveBeenCalled())

    const campo = screen.getByPlaceholderText('Buscar na ajuda…') as HTMLInputElement
    fireEvent.change(campo, { target: { value: 'prazo' } })
    // O título aparece duas vezes (item da árvore e cabeçalho do painel); o
    // botão é o da árvore.
    fireEvent.click(screen.getByRole('button', { name: /Dúvidas frequentes/ }))

    expect(campo.value).toBe('')
    expect(campo.value).not.toBe(' ')
  })

  // O legado chamava `setEmpty(false)` nos DOIS ramos do `if`.
  it('o estado vazio APARECE de fato', async () => {
    await montar()
    await waitFor(() => expect(screen.getByText('Nenhum item neste assunto')).toBeInTheDocument())
  })

  // (c) do FE-364 — o callback de falha era VAZIO: falha de rede não mostrava nada.
  it('falha de rede mostra erro com botão de tentar de novo', async () => {
    items.mockRejectedValue(new Error('rede caiu'))
    await montar()
    await waitFor(() => expect(screen.getByRole('button', { name: /tentar de novo/i })).toBeInTheDocument())
  })

  it('árvore vazia mostra o estado vazio da lista de assuntos', async () => {
    tree.mockResolvedValue([])
    await montar()
    await waitFor(() => expect(screen.getByText('Nenhum assunto cadastrado')).toBeInTheDocument())
  })
})
