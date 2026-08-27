import { describe, it, expect, vi, beforeEach } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import type { Renegotiation } from '@/lib/api/renegotiations'

/**
 * **FE-198 — remover a renegociação passa a PERGUNTAR antes.**
 *
 * A conferência de paridade da Phase 4 (27/08/2026) achou o buraco: o "Remover"
 * do menu de ações chamava a mutação **no clique**. Um toque errado apagava a
 * renegociação, sem volta e sem aviso.
 *
 * O critério de habilitação já existia — só remove acordo sem parcela e sem
 * pagamento — e ele **não cobre este caso**: ele protege o dado com histórico,
 * não protege contra o clique errado numa renegociação que ainda está vazia. São
 * duas defesas para dois riscos diferentes, e só uma estava montada.
 *
 * O texto da caixa NOMEIA a renegociação. Uma confirmação que só diz "tem
 * certeza?" não ajuda quem clicou na linha errada — que é exatamente o caso
 * contra o qual ela existe.
 */

const list = vi.fn()
const remove = vi.fn()
const options = vi.fn()

vi.mock('@/lib/api/renegotiations', async (original) => {
  const real = await original<typeof import('@/lib/api/renegotiations')>()
  return {
    ...real,
    renegotiationsApi: {
      ...real.renegotiationsApi,
      list: (...a: any[]) => list(...a),
      remove: (...a: any[]) => remove(...a),
      options: (...a: any[]) => options(...a),
    },
  }
})

const REGISTRO = {
  id: 'r-1',
  title: 'Acordo Aço Norte',
  provider_name: 'Aço Norte',
  state: 'open',
  state_label: 'Em aberto',
  beauty_state: 'Em aberto',
  remaining_value: '1000.00',
  paid_value: '0.00',
  paid_installments: 0,
  installments_count: 0,
  next_due_date: null,
  next_installment_value: '0.0',
} as unknown as Renegotiation

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

async function montar() {
  const { RenegotiationsPage } = await import('../RenegotiationsPage')
  return render(
    <Envolvido>
      <RenegotiationsPage />
    </Envolvido>,
  )
}

beforeEach(() => {
  // `src/test/setup.ts` não chama `cleanup()` (UF-S15-04).
  cleanup()
  vi.clearAllMocks()
  // **375, e nao 1440.** O menu de acoes da linha so existe no cartao de telefone:
  // no desktop a lista NAO tem menu nenhum, que e o FE-196 — ainda aberto. O fluxo
  // de remocao que este arquivo cobre e o que EXISTE hoje.
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 375 })
  list.mockResolvedValue({ items: [REGISTRO], meta: { page: 1, perPage: 50, total: 1, totalPages: 1 } })
  options.mockResolvedValue({ states: [], kinds: [] })
  remove.mockResolvedValue({ deleted: true })
})

describe('Remoção de renegociação — confirmação (FE-198)', () => {
  async function abrirMenuERemover() {
    await screen.findByText('Acordo Aço Norte')
    fireEvent.click(screen.getByRole('button', { name: /ações/i }))
    fireEvent.click(await screen.findByText('Remover'))
  }

  it('o clique em "Remover" NÃO chama a API — abre a confirmação', async () => {
    await montar()
    await abrirMenuERemover()

    expect(await screen.findByText(/Remover esta renegociação\?/i)).toBeInTheDocument()
    expect(remove).not.toHaveBeenCalled()
  })

  it('a caixa NOMEIA a renegociação e o fornecedor', async () => {
    await montar()
    await abrirMenuERemover()
    await screen.findByText(/Remover esta renegociação\?/i)

    // Dentro do DIÁLOGO: o nome também aparece no cartão da lista atrás dele, e
    // uma busca solta acharia os dois — passando mesmo que a caixa não nomeasse
    // nada, que é justamente o que este exemplo existe para impedir.
    const caixa = screen.getByRole('dialog')
    expect(caixa.textContent).toMatch(/Acordo Aço Norte/)
    expect(caixa.textContent).toMatch(/Aço Norte/)
  })

  it('confirmando, a API é chamada com o registro certo', async () => {
    await montar()
    await abrirMenuERemover()
    await screen.findByText(/Remover esta renegociação\?/i)

    fireEvent.click(screen.getByRole('button', { name: /Remover renegociação/i }))

    await waitFor(() => expect(remove).toHaveBeenCalledTimes(1))
    expect(remove).toHaveBeenCalledWith('r-1')
  })

  // **FE-196 — o mesmo fluxo no DESKTOP.** Antes deste conserto a lista só tinha
  // menu de ações no cartão de telefone: no computador não havia como remover
  // uma renegociação, nem afordância de que a linha tivesse ações.
  it('no DESKTOP a linha também oferece ações, e a remoção passa pela confirmação', async () => {
    Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 1440 })
    await montar()

    await screen.findByText('Acordo Aço Norte')
    fireEvent.click(screen.getByRole('button', { name: /ações de acordo aço norte/i }))
    fireEvent.click(await screen.findByText('Remover'))

    expect(await screen.findByText(/Remover esta renegociação\?/i)).toBeInTheDocument()
    expect(remove).not.toHaveBeenCalled()

    fireEvent.click(screen.getByRole('button', { name: /Remover renegociação/i }))
    await waitFor(() => expect(remove).toHaveBeenCalledWith('r-1'))
  })

  it('cancelando, nada é removido', async () => {
    await montar()
    await abrirMenuERemover()
    await screen.findByText(/Remover esta renegociação\?/i)

    fireEvent.click(screen.getByRole('button', { name: /^Cancelar$/i }))

    await waitFor(() =>
      expect(screen.queryByText(/Remover esta renegociação\?/i)).not.toBeInTheDocument(),
    )
    expect(remove).not.toHaveBeenCalled()
  })
})
