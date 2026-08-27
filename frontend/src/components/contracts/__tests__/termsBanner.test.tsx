import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useAuthStore } from '@/store/authStore'

/**
 * S12 / DEC-65 — o banner de aceite pendente.
 *
 * No legado **não existe forma de aceitar pela interface**: os dois botões
 * estão comentados e o bloqueio também. Estes testes provam que o botão existe,
 * funciona, e que a pendência **não interrompe** o resto da tela.
 */

const pending = vi.fn()
const acceptAllPending = vi.fn()

vi.mock('@/lib/api/contracts', () => ({
  contractsApi: {
    pending: (...a: any[]) => pending(...a),
    acceptAllPending: (...a: any[]) => acceptAllPending(...a),
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

const PENDENTE = {
  id: 'c-1',
  kind: 'Termos de Uso',
  slug: 'termos-de-uso',
  title: 'Termos de Uso',
  version: 3,
  published_at: '2026-08-01T00:00:00Z',
  tolerance_until: '2026-08-31T00:00:00Z',
  overdue: false,
}

async function montar() {
  const { TermsBanner } = await import('@/components/contracts/TermsBanner')
  return render(
    <Envolvido>
      <TermsBanner />
    </Envolvido>,
  )
}

describe('TermsBanner', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useAuthStore.setState({ isAuthenticated: true } as any)
    pending.mockResolvedValue([PENDENTE])
    acceptAllPending.mockResolvedValue({ pending: [], accepted: [] })
  })

  it('aparece quando há pendência, com o botão de aceitar', async () => {
    await montar()
    await waitFor(() =>
      expect(screen.getByText(/ainda não aceitou os documentos vigentes/i)).toBeInTheDocument(),
    )
    expect(screen.getByRole('button', { name: 'Aceitar' })).toBeInTheDocument()
  })

  it('o link leva à página pública do contrato, pelo SLUG', async () => {
    await montar()
    const link = await screen.findByRole('link', { name: /Ler Termos de Uso/ })
    expect(link).toHaveAttribute('href', '/contract/termos-de-uso')
  })

  it('clicar em Aceitar chama o aceite em bloco', async () => {
    await montar()
    fireEvent.click(await screen.findByRole('button', { name: 'Aceitar' }))
    await waitFor(() => expect(acceptAllPending).toHaveBeenCalledTimes(1))
  })

  it('NÃO aparece quando não há pendência', async () => {
    pending.mockResolvedValue([])
    const { container } = await montar()
    await waitFor(() => expect(pending).toHaveBeenCalled())
    expect(container.querySelector('[role="status"]')).toBeNull()
  })

  it('NÃO aparece sem sessão — e nem sequer consulta o servidor', async () => {
    useAuthStore.setState({ isAuthenticated: false } as any)
    const { container } = await montar()
    expect(container.querySelector('[role="status"]')).toBeNull()
    expect(pending).not.toHaveBeenCalled()
  })

  it('dispensar esconde a faixa — e não grava nada que a mate para sempre', async () => {
    await montar()
    fireEvent.click(await screen.findByRole('button', { name: 'Dispensar aviso' }))
    await waitFor(() => expect(screen.queryByRole('status')).toBeNull())
    // A dispensa é estado de COMPONENTE: nada é gravado, e uma montagem nova
    // traz a faixa de volta. Persistir a dispensa transformaria "aceite
    // pendente" em "aviso que a pessoa fechou uma vez" — que é como o aceite
    // morreu da primeira vez.
    const chaves = Object.keys(window.localStorage)
    expect(chaves.filter((k) => /term|contract|aceite/i.test(k))).toEqual([])

    await montar()
    expect(await screen.findAllByRole('status')).toHaveLength(1)
  })

  it('passado o prazo de 30 dias, a mensagem muda — mas continua sem bloquear', async () => {
    pending.mockResolvedValue([{ ...PENDENTE, overdue: true }])
    await montar()
    expect(await screen.findByText(/pendente há mais de 30 dias/i)).toBeInTheDocument()
    // Nada de "redirect", nada de "acesso negado": é banner, não bloqueio.
    expect(screen.queryByText(/acesso bloqueado/i)).toBeNull()
  })
})
