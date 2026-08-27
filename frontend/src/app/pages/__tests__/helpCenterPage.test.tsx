import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

/**
 * S12 / tarefa 5.21 — a renomeação inline da Central de ajuda.
 *
 * O defeito do legado era uma **corrida**: um `focusout` de 200 ms revertia a
 * edição competindo com o `Enter`, e o resultado dependia de qual dos dois
 * chegasse antes. Renomear e clicar fora perdia a edição — às vezes.
 */

const tree = vi.fn()
const updateGroup = vi.fn()
const createGroup = vi.fn()
const items = vi.fn()

vi.mock('@/lib/api/help', () => ({
  helpAdminApi: {
    tree: (...a: any[]) => tree(...a),
    createGroup: (...a: any[]) => createGroup(...a),
    updateGroup: (...a: any[]) => updateGroup(...a),
    groupImpact: vi.fn(),
    removeGroup: vi.fn(),
    createCategory: vi.fn(),
    updateCategory: vi.fn(),
    categoryImpact: vi.fn(),
    removeCategory: vi.fn(),
    items: (...a: any[]) => items(...a),
    getItem: vi.fn(),
    createItem: vi.fn(),
    updateItem: vi.fn(),
    removeItem: vi.fn(),
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

async function montar() {
  const { HelpCenterPage } = await import('@/app/pages/admin/HelpCenterPage')
  return render(
    <Envolvido>
      <HelpCenterPage />
    </Envolvido>,
  )
}

describe('HelpCenterPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.useRealTimers()
    tree.mockResolvedValue([{ id: 'g-1', title: 'Primeiros passos', position: 0, categories: [] }])
    updateGroup.mockResolvedValue({ id: 'g-1', title: 'Renomeado', position: 0 })
    items.mockResolvedValue({ items: [], meta: { page: 1, perPage: 20, total: 0, totalPages: 1 } })
  })

  it('a edição inline NÃO é revertida por temporizador: `blur` grava', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    await montar()
    const rotulo = await screen.findByText('Primeiros passos')

    fireEvent.doubleClick(rotulo)
    const campo = screen.getByRole('textbox', { name: /Renomear Primeiros passos/ })
    fireEvent.change(campo, { target: { value: 'Começando' } })
    fireEvent.blur(campo)

    // Passa MUITO mais que os 200 ms do temporizador do legado: nada reverte.
    await act(async () => {
      vi.advanceTimersByTime(1000)
    })
    await waitFor(() => expect(updateGroup).toHaveBeenCalledWith('g-1', { title: 'Começando' }))
    vi.useRealTimers()
  })

  it('`Enter` grava a mesma coisa que o `blur` — o resultado é determinístico', async () => {
    await montar()
    fireEvent.doubleClick(await screen.findByText('Primeiros passos'))
    const campo = screen.getByRole('textbox', { name: /Renomear Primeiros passos/ })
    fireEvent.change(campo, { target: { value: 'Começando' } })
    fireEvent.keyDown(campo, { key: 'Enter' })

    await waitFor(() => expect(updateGroup).toHaveBeenCalledWith('g-1', { title: 'Começando' }))
  })

  it('`Escape` cancela, e NÃO grava', async () => {
    await montar()
    fireEvent.doubleClick(await screen.findByText('Primeiros passos'))
    const campo = screen.getByRole('textbox', { name: /Renomear Primeiros passos/ })
    fireEvent.change(campo, { target: { value: 'Descartado' } })
    fireEvent.keyDown(campo, { key: 'Escape' })

    expect(updateGroup).not.toHaveBeenCalled()
    expect(screen.getByText('Primeiros passos')).toBeInTheDocument()
  })

  // O legado chamava `setEmpty(false)` nos DOIS ramos do `if`.
  it('o estado vazio da árvore APARECE', async () => {
    tree.mockResolvedValue([])
    await montar()
    expect(await screen.findByText('A central de ajuda está vazia')).toBeInTheDocument()
  })

  it('sem categoria escolhida, o painel da direita explica o que fazer', async () => {
    await montar()
    expect(await screen.findByText('Escolha uma categoria')).toBeInTheDocument()
  })
})
