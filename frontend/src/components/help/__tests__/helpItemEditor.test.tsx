import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

/**
 * S12 / FE-366 — o formulário do item de ajuda.
 *
 * **A regressão que este arquivo trava foi achada RENDERIZANDO, não pelo
 * `tsc`.** A lista administrativa não devolve `description_html` (o entity só o
 * expõe com `type: :full`, para a lista não carregar o texto de todos os
 * itens). Abrir o formulário com o objeto da lista deixava o editor **vazio** —
 * e "Salvar alterações" mandaria corpo em branco por cima do texto real.
 *
 * `tsc` passava limpo: os tipos batiam, porque `description_html` é opcional.
 */

const items = vi.fn()
const getItem = vi.fn()
const updateItem = vi.fn()

vi.mock('@/lib/api/help', () => ({
  helpAdminApi: {
    items: (...a: any[]) => items(...a),
    getItem: (...a: any[]) => getItem(...a),
    updateItem: (...a: any[]) => updateItem(...a),
    createItem: vi.fn(),
    removeItem: vi.fn(),
  },
}))

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

const CATEGORIA = {
  id: 'cat-1',
  title: 'Acesso e conta',
  slug: 'acesso-e-conta',
  help_group_id: 'g-1',
  position: 0,
  items_count: 1,
}

// Como a LISTA devolve: sem `description_html`.
const DA_LISTA = {
  id: 'i-1',
  title: 'Como entro no sistema?',
  help_category_id: 'cat-1',
  position: 0,
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-01T00:00:00Z',
  category: { id: 'cat-1', title: 'Acesso e conta', slug: 'acesso-e-conta' },
  group: { id: 'g-1', title: 'Primeiros passos' },
  author: { id: 'u-1', name: 'Suporte Livetat' },
  last_updated_user: null,
}

// Como o DETALHE devolve: com o corpo.
const COMPLETO = { ...DA_LISTA, description_html: '<p>O acesso é por código de uso único.</p>' }

async function montar() {
  const { HelpItemEditor } = await import('@/components/help/HelpItemEditor')
  return render(
    <Envolvido>
      <HelpItemEditor categoria={CATEGORIA as any} onChanged={() => {}} />
    </Envolvido>,
  )
}

describe('HelpItemEditor', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    items.mockResolvedValue({ items: [DA_LISTA], meta: { page: 1, perPage: 20, total: 1, totalPages: 1 } })
    getItem.mockResolvedValue(COMPLETO)
    updateItem.mockResolvedValue(COMPLETO)
  })

  it('abrir um item BUSCA o texto completo — não abre com o corpo vazio da lista', async () => {
    await montar()
    fireEvent.click(await screen.findByText('Como entro no sistema?'))

    await waitFor(() => expect(getItem).toHaveBeenCalledWith('i-1'))
    await waitFor(() =>
      expect(screen.getByText(/O acesso é por código de uso único/)).toBeInTheDocument(),
    )
  })

  it('enquanto o texto não chega, "Salvar alterações" fica DESABILITADO', async () => {
    let resolver: (v: any) => void = () => {}
    getItem.mockImplementation(() => new Promise((r) => { resolver = r }))

    await montar()
    fireEvent.click(await screen.findByText('Como entro no sistema?'))

    await waitFor(() => expect(screen.getByText('Carregando o texto do item…')).toBeInTheDocument())
    expect(screen.queryByRole('button', { name: 'Salvar alterações' })).toBeNull()

    resolver(COMPLETO)
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Salvar alterações' })).toBeEnabled(),
    )
  })

  it('salvar NÃO manda `user_id`: a autoria é do servidor (FE-366)', async () => {
    await montar()
    fireEvent.click(await screen.findByText('Como entro no sistema?'))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Salvar alterações' })).toBeEnabled())

    fireEvent.click(screen.getByRole('button', { name: 'Salvar alterações' }))

    await waitFor(() => expect(updateItem).toHaveBeenCalled())
    const [, payload] = updateItem.mock.calls[0]
    expect(payload).not.toHaveProperty('user_id')
  })

  it('sem categoria escolhida, explica o que fazer em vez de abrir um form vazio', async () => {
    const { HelpItemEditor } = await import('@/components/help/HelpItemEditor')
    render(
      <Envolvido>
        <HelpItemEditor categoria={null} onChanged={() => {}} />
      </Envolvido>,
    )
    expect(screen.getByText('Escolha uma categoria')).toBeInTheDocument()
  })
})
