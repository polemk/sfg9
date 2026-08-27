import { describe, it, expect, vi, beforeEach } from 'vitest'
import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import type { Charge, ChargeStatementLine } from '@/lib/api/receivables'
import { CONSOLE_NAV_GROUPS } from '@/app/consoleNavigation'

/**
 * **O detalhe da cobrança virou PÁGINA** — e o portão prova que ela abre.
 *
 * Palavras do usuário (26/08/2026): *"o detalhe de cobrança ficou muito ruim
 * assim, ou fazemos em diálogo ou em uma página separada"*. Página, e a razão é
 * medida: o detalhe abre o extrato por remuneração e é a porta da **seleção de
 * recibos**, que numa cobrança real desta base tem **214 candidatos** e **9
 * persistidos**. Isso é tabela, e tabela não cabe numa gaveta de 480 px.
 *
 * Estes exemplos existem porque a lição da S15 já custou caro duas vezes:
 * portão verde prova que o código **carrega**, não que ele **funciona**. Um
 * `Sheet` sem `SheetContent` passou por `tsc` e por suíte verde e o detalhe da
 * auditoria simplesmente não abria. Aqui a página é montada de verdade, na rota
 * de verdade, e o conteúdo é exigido **dentro da tabela**.
 */

const get = vi.fn()
const statement = vi.fn()

vi.mock('@/lib/api/receivables', async (original) => {
  const real = await original<typeof import('@/lib/api/receivables')>()
  return {
    ...real,
    chargesApi: {
      ...real.chargesApi,
      get: (...a: any[]) => get(...a),
      statement: (...a: any[]) => statement(...a),
    },
  }
})

const COBRANCA: Charge = {
  id: 'c-1',
  date: '2026-03-31',
  state: 'editing',
  state_label: 'Edição',
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

const EXTRATO: ChargeStatementLine[] = [
  {
    kind: 'LIQ',
    remuneration_id: 'r-1',
    title: 'Taxa de liquidação',
    receipts_count: 5,
    operations_value: '800000.00',
    value: '12000.00',
  },
  {
    kind: 'EST',
    remuneration_id: 'r-2',
    title: 'Taxa de estruturação',
    receipts_count: 4,
    operations_value: '404000.00',
    value: '6450.75',
  },
]

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

async function montar() {
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
  statement.mockResolvedValue({ charge: COBRANCA, statement: EXTRATO })
})

describe('ChargeDetailPage — o detalhe é página, e ela abre', () => {
  it('a rota `/charges/:id` está montada, e `:id/receipts` vem ANTES dela', () => {
    // O React Router casa na ordem: a rota mais específica tem de ser declarada
    // primeiro, senão `/charges/x/receipts` cairia no detalhe.
    const charges = CONSOLE_NAV_GROUPS.flatMap((g) => g.items).find((i) => i.id === 'charges')!
    const filhos = (charges as { children?: { path: string; element: unknown }[] }).children ?? []
    expect(filhos.map((f) => f.path)).toEqual([':id/receipts', ':id'])
    for (const filho of filhos) expect(filho.element, `a tela de ${filho.path}`).toBeTruthy()
  })

  it('mostra os quatro indicadores da cobrança, em pt-BR', async () => {
    // Consultas presas ao container DESTE render: a suíte não chama `cleanup()`
    // por si (UF-S15-04), e uma consulta em `screen` alcança o `document.body`
    // inteiro — inclusive o que outro arquivo deixou montado.
    const { container } = await montar()
    const tela = within(container)
    expect(await screen.findByText(/Cobrança de 31\/03\/2026/)).toBeInTheDocument()
    expect(tela.getByText(/Edição · 9 recibo\(s\) no pacote/)).toBeInTheDocument()

    // O valor de milhão é o que quebrava no cartão do telefone (DS-04) e o que
    // o `KpiCard` corta quando o corpo não acompanha o comprimento.
    await waitFor(() => expect(tela.getByText(/R\$\s?1\.204\.000,00/)).toBeInTheDocument())
    expect(tela.getByText('Valor cobrado')).toBeInTheDocument()
    expect(tela.getByText('Operações de risco')).toBeInTheDocument()
    expect(tela.getByText('Operações estruturadas')).toBeInTheDocument()
  })

  it('o extrato é uma TABELA de verdade, com uma linha por remuneração', async () => {
    // A razão de a gaveta ter caído: isto é tabela. Numa `<ul>` desenhada à mão
    // não haveria rolagem com afordância, coluna congelada nem cartão no
    // telefone — o trabalho que o `DataTable` já faz pelas 18 telas.
    await montar()
    const tabela = await screen.findByRole('table', { name: /extrato por remuneração/i })
    const linhas = within(tabela).getAllByRole('row')
    // 1 cabeçalho + 2 remunerações.
    expect(linhas).toHaveLength(3)
    expect(within(tabela).getByText('Taxa de liquidação')).toBeInTheDocument()
    expect(within(tabela).getByText('Taxa de estruturação')).toBeInTheDocument()
  })

  it('leva à seleção de recibos — o motivo de o detalhe ser página', async () => {
    await montar()
    expect(
      await screen.findByRole('button', { name: /escolher operações da cobrança/i }),
    ).toBeInTheDocument()
  })

  it('cobrança faturada diz que está travada, e o rótulo do botão muda', async () => {
    // D-18 — o bloqueio é do servidor; o texto na tela é o aviso, nunca a defesa.
    get.mockResolvedValue({ ...COBRANCA, done: true, state_label: 'Faturado' })
    await montar()
    expect(await screen.findByText(/Esta cobrança está/)).toBeInTheDocument()
    expect(
      screen.getByRole('button', { name: /ver operações da cobrança/i }),
    ).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /escolher operações/i })).toBeNull()
  })

  it('o 422 que nomeia a fatia que falta é ESTADO, não lista vazia', async () => {
    // Uma lista vazia aqui afirmaria que não há nada a faturar — uma frase
    // diferente, e errada. É a mesma família do "ausência ≠ zero" (D-117).
    statement.mockRejectedValue({ response: { data: { error: 'Depende da fatia S8.' } } })
    await montar()
    await waitFor(() => expect(screen.getByText(/Depende da fatia S8\./)).toBeInTheDocument())
    expect(screen.queryByRole('table')).toBeNull()
    expect(screen.queryByText(/Nenhum recibo neste pacote/)).toBeNull()
  })

  it('no telefone o extrato vira cartões — nenhuma coluna fora da tela', async () => {
    // DS-02: abaixo de 768 px o `DataTable` deixa de ser tabela. Conferir exige
    // ver TODOS os campos, e coluna fora da tela é coluna que ninguém descobre.
    Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 390 })
    await montar()
    await screen.findByText('Taxa de liquidação')
    expect(screen.queryByRole('table')).toBeNull()
    expect(screen.getAllByText('Valor da remuneração').length).toBeGreaterThan(0)
  })
})

describe('ChargesPage — a lista não guarda mais o detalhe', () => {
  it('a lista NAVEGA para o detalhe; ela não tem mais a gaveta de leitura', async () => {
    const fonte = await import('fs').then((fs) =>
      fs.readFileSync('src/features/receivables/pages/ChargesPage.tsx', 'utf8'),
    )
    // Sobra UMA gaveta, e ela é a de criação — formulário curto, que é o caso
    // em que a gaveta está certa.
    expect(fonte.match(/<SideDrawer/g) ?? []).toHaveLength(1)
    expect(fonte).toContain('Nova cobrança')
    expect(fonte).toContain("navigate(`/charges/${charge.id}`)")
    // E o extrato saiu da lista junto com a gaveta.
    expect(fonte).not.toContain('chargesApi.statement')
  })
})
