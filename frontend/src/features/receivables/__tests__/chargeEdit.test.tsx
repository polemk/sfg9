import { describe, it, expect, vi, beforeEach } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import type { Charge } from '@/lib/api/receivables'

/**
 * **FE-181 / FE-183 / FE-186 — a edição da cobrança, e a situação "Faturado".**
 *
 * A conferência de paridade da Phase 4 (27/08/2026) achou o buraco: o
 * `chargesApi.update` e o `PUT /api/v1/charges/:id` existiam e funcionavam, e
 * `grep -rn 'chargesApi.update' src` **não achava um consumidor**. A tela de
 * edição nunca foi construída.
 *
 * A consequência não é cosmética. No legado só se chegava a "Faturado"
 * editando o pacote, então **o estado final era inalcançável pela interface** —
 * a lista exibia uma coluna "Situação" que ninguém conseguia mudar, e o ciclo
 * de vida da cobrança terminava em "Disponível" para sempre.
 *
 * Estes exemplos existem porque a lição já custou caro: **portão verde prova que
 * o código carrega, não que ele funciona**. `chargesApi.update` estava lá,
 * tipado, exportado e testado como cliente — e a funcionalidade não existia. O
 * que fecha o buraco não é o método existir: é alguém CHAMAR o método a partir
 * de um clique, e é isso que se exige aqui.
 */

const get = vi.fn()
const statement = vi.fn()
const update = vi.fn()

vi.mock('@/lib/api/receivables', async (original) => {
  const real = await original<typeof import('@/lib/api/receivables')>()
  return {
    ...real,
    chargesApi: {
      ...real.chargesApi,
      get: (...a: any[]) => get(...a),
      statement: (...a: any[]) => statement(...a),
      update: (...a: any[]) => update(...a),
    },
  }
})

const COBRANCA: Charge = {
  id: 'c-1',
  date: '2026-03-31',
  state: 'available',
  state_label: 'Disponível',
  done: false,
  value: '18450.75',
  risk_operations_value: '12000.00',
  structured_operations_value: '6450.75',
  total_operations_value: '1204000.00',
  receipts_count: 9,
  risk_operations_count: 5,
  structured_operations_count: 4,
  user_id: null,
  created_at: '2026-03-01T12:00:00Z',
  updated_at: '2026-03-01T12:00:00Z',
}

const FATURADA: Charge = { ...COBRANCA, state: 'done', state_label: 'Faturado', done: true }

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/charges/c-1']}>
        <Routes>
          <Route path="/charges/:id" element={children} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  )
}

async function montarDetalhe() {
  const { ChargeDetailPage } = await import('../pages/ChargeDetailPage')
  return render(
    <Envolvido>
      <ChargeDetailPage />
    </Envolvido>,
  )
}

beforeEach(() => {
  // `src/test/setup.ts` não chama `cleanup()` (UF-S15-04).
  cleanup()
  vi.clearAllMocks()
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 1440 })
  get.mockResolvedValue(COBRANCA)
  statement.mockResolvedValue({ charge: COBRANCA, statement: [] })
  update.mockResolvedValue(FATURADA)
})

describe('Edição da cobrança — a situação "Faturado" é alcançável pela tela', () => {
  it('o detalhe oferece "Editar", e a gaveta abre com os valores da cobrança', async () => {
    await montarDetalhe()

    await screen.findByText(/Cobrança de/i)
    fireEvent.click(await screen.findByRole('button', { name: /^Editar$/i }))

    expect(await screen.findByText('Editar cobrança')).toBeInTheDocument()
    // A situação abre no valor ATUAL, e não no primeiro da lista: abrir em
    // "Edição" faria o usuário rebaixar o pacote sem perceber, só por salvar.
    expect(await screen.findByText('Disponível')).toBeInTheDocument()
  })

  it('salvar CHAMA `chargesApi.update` — o método existia e ninguém o chamava', async () => {
    await montarDetalhe()

    await screen.findByText(/Cobrança de/i)
    fireEvent.click(await screen.findByRole('button', { name: /^Editar$/i }))
    await screen.findByText('Editar cobrança')
    fireEvent.click(await screen.findByRole('button', { name: /^Salvar$/i }))

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1))
    const [id, dados] = update.mock.calls[0]
    expect(id).toBe('c-1')
    // A data volta EXATAMENTE como veio. `new Date('2026-03-31')` seria lido
    // como UTC e voltaria um dia no fuso de São Paulo: o usuário abriria a
    // gaveta, salvaria sem tocar em nada, e a data mudaria sozinha para 30/03.
    expect(dados.date).toBe('2026-03-31')
    expect(dados.state).toBe('available')
  })

  it('"Faturado" pode ser escolhido, e vai para o servidor', async () => {
    await montarDetalhe()

    await screen.findByText(/Cobrança de/i)
    fireEvent.click(await screen.findByRole('button', { name: /^Editar$/i }))
    await screen.findByText('Editar cobrança')

    fireEvent.click(screen.getByLabelText('Situação'))
    fireEvent.click(await screen.findByRole('option', { name: 'Faturado' }))

    // O aviso de porta de uma via aparece ANTES de salvar. `done` é
    // irreversível pelo servidor (D-18): descobrir isso depois não serve.
    expect(await screen.findByText(/Faturado não tem volta/i)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /^Salvar$/i }))

    await waitFor(() => expect(update).toHaveBeenCalledTimes(1))
    expect(update.mock.calls[0][1].state).toBe('done')
  })

  it('a cobrança JÁ faturada não oferece "Editar" — o servidor recusaria de qualquer forma', async () => {
    get.mockResolvedValue(FATURADA)
    statement.mockResolvedValue({ charge: FATURADA, statement: [] })

    await montarDetalhe()
    await screen.findByText(/Cobrança de/i)

    expect(screen.queryByRole('button', { name: /^Editar$/i })).not.toBeInTheDocument()
  })
})
