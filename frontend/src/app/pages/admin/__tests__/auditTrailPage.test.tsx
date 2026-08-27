import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, within, fireEvent, act } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import type { AuditVersion } from '@/lib/api/auditTrail'

/**
 * Trilha de auditoria — o portão que faltava.
 *
 * **Por que este arquivo existe.** O detalhe do evento não abria: o `Sheet`
 * estava sendo usado **sem** `SheetContent`, então o conteúdo era montado no
 * fluxo da página, fora da tela. `tsc` verde, suíte verde, e clicar em "Ver
 * detalhes" não fazia nada. Portão verde prova que o código CARREGA, não que
 * ele FUNCIONA — e a diferença é exatamente um teste que **clica**.
 *
 * Daí a forma dos testes abaixo: eles abrem o detalhe de verdade e exigem que
 * o conteúdo esteja **dentro do `role="dialog"`**. Um detalhe renderizado no
 * corpo da página passaria num `getByText` solto; não passa aqui.
 */

const list = vi.fn()
const get = vi.fn()
const types = vi.fn()

vi.mock('@/lib/api/auditTrail', async (original) => {
  const real = await original<typeof import('@/lib/api/auditTrail')>()
  return {
    ...real,
    auditTrailApi: {
      list: (...a: any[]) => list(...a),
      get: (...a: any[]) => get(...a),
      types: (...a: any[]) => types(...a),
    },
  }
})

const VERSAO: AuditVersion = {
  id: 42,
  item_type: 'User',
  item_id: '7b4b3a00-9b0d-4065-aa07-dd930e66234f',
  entity_label: 'conta de usuário',
  event: 'update',
  summary: 'A conta de usuário foi alterada',
  author: { id: '10', name: 'Vini', email: 'vini@exemplo.com' },
  impersonated: null,
  reason: null,
  ip_address: '127.0.0.1',
  occurred_at: '2026-08-26T19:06:00.000Z',
  changes: {
    current_project_id: [
      'a6e45873-14da-4061-ac4a-840944e6f6d5',
      '616356d5-52d3-46bb-9a4a-910d87585f84',
    ],
  },
}

/** `fireEvent` + microtarefa: a suíte não tem `user-event` instalado. */
async function clicar(el: HTMLElement) {
  await act(async () => {
    fireEvent.click(el)
  })
}

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

async function montar() {
  const { AuditTrailPage } = await import('../AuditTrailPage')
  const r = render(
    <Envolvido>
      <AuditTrailPage />
    </Envolvido>,
  )
  await screen.findByText('A conta de usuário foi alterada')
  return r
}

beforeEach(() => {
  vi.clearAllMocks()
  list.mockResolvedValue({
    versions: [VERSAO],
    meta: { page: 1, perPage: 20, total: 433, totalPages: 22 },
  })
  get.mockResolvedValue({ ...VERSAO, snapshot: { id: VERSAO.item_id, name: 'Vini' } })
  types.mockResolvedValue([{ value: 'User', label: 'conta de usuário' }])
})

describe('AuditTrailPage — filtros', () => {
  it('os três filtros ficam numa faixa própria, com rótulo visível', async () => {
    await montar()
    const faixa = screen.getByRole('region', { name: /filtros da trilha/i })
    expect(faixa).toBeInTheDocument()
    expect(screen.getByText('Tipo de registro')).toBeInTheDocument()
    expect(screen.getByText('Evento')).toBeInTheDocument()
    expect(screen.getByText('Período')).toBeInTheDocument()
    // Os três seguem existindo — a passada de layout não removeu nenhum.
    expect(faixa.querySelectorAll('[role="combobox"]')).toHaveLength(3)
  })

  it('o total responde "meu filtro pegou alguma coisa?"', async () => {
    await montar()
    expect(screen.getByText(/433\s+eventos/)).toBeInTheDocument()
  })

  it('"Limpar" só aparece quando há filtro — e devolve a lista inteira', async () => {
    await montar()
    expect(screen.queryByRole('button', { name: /limpar/i })).not.toBeInTheDocument()

    await clicar(screen.getByRole('combobox', { name: /tipo de evento/i }))
    await clicar(await screen.findByRole('option', { name: /alteração/i }))

    const limpar = await screen.findByRole('button', { name: /limpar/i })
    await clicar(limpar)
    await waitFor(() =>
      expect(screen.queryByRole('button', { name: /limpar/i })).not.toBeInTheDocument(),
    )
  })
})

describe('AuditTrailPage — detalhe do evento', () => {
  /**
   * O teste que teria pego o defeito: o conteúdo tem de estar DENTRO do
   * `role="dialog"`, não solto no corpo da página.
   */
  it('"Ver detalhes" abre um DIÁLOGO, e o conteúdo mora dentro dele', async () => {
    await montar()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await clicar(screen.getByRole('button', { name: /ver detalhes/i }))

    const dialogo = await screen.findByRole('dialog')
    expect(dialogo).toBeInTheDocument()
    const dentro = within(dialogo)
    expect(dentro.getByText('A conta de usuário foi alterada')).toBeInTheDocument()
    expect(dentro.getByText('Vini')).toBeInTheDocument()
    expect(dentro.getByText('127.0.0.1')).toBeInTheDocument()
  })

  it('o diff mostra antes E depois rotulados — o valor antigo não é texto cancelado', async () => {
    await montar()
    await clicar(screen.getByRole('button', { name: /ver detalhes/i }))
    const dentro = within(await screen.findByRole('dialog'))

    expect(dentro.getByText('current_project_id')).toBeInTheDocument()
    const antes = dentro.getByText('a6e45873-14da-4061-ac4a-840944e6f6d5')
    const depois = dentro.getByText('616356d5-52d3-46bb-9a4a-910d87585f84')
    // Monoespaçado: UUID é para ser conferido caractere a caractere.
    expect(antes.className).toMatch(/font-mono/)
    expect(depois.className).toMatch(/font-mono/)
    // `line-through` esconde dado que a auditoria precisa que se leia.
    expect(antes.className).not.toMatch(/line-through/)
    expect(dentro.getAllByText(/^Antes$/i).length).toBeGreaterThan(0)
    expect(dentro.getAllByText(/^Depois$/i).length).toBeGreaterThan(0)
  })

  it('evento sem alteração de campo diz isso, em vez de deixar a seção vazia', async () => {
    list.mockResolvedValue({
      versions: [
        {
          ...VERSAO,
          id: 43,
          event: 'impersonate_start',
          summary: 'A conta de usuário passou a ser personificada',
          changes: {},
        },
      ],
      meta: { page: 1, perPage: 20, total: 1, totalPages: 1 },
    })
    const { AuditTrailPage } = await import('../AuditTrailPage')
    render(
      <Envolvido>
        <AuditTrailPage />
      </Envolvido>,
    )
    await screen.findByText('A conta de usuário passou a ser personificada')
    await clicar(screen.getByRole('button', { name: /ver detalhes/i }))
    const dentro = within(await screen.findByRole('dialog'))
    expect(dentro.getByText(/não registra alteração de campo/i)).toBeInTheDocument()
  })

  // DEC-78 — a foto completa do estado anterior continua colapsável.
  it('o estado completo anterior vem colapsado, com rolagem própria', async () => {
    await montar()
    await clicar(screen.getByRole('button', { name: /ver detalhes/i }))
    const dialogo = await screen.findByRole('dialog')
    const resumo = await within(dialogo).findByText(/estado completo antes da mudança/i)
    const details = resumo.closest('details')
    expect(details).not.toBeNull()
    expect(details!.open).toBe(false)
    expect(details!.querySelector('pre')?.className).toMatch(/overflow-auto/)
  })
})
