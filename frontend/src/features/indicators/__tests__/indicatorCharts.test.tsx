import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, cleanup } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useState, type ReactNode } from 'react'

/**
 * S15 / `NEW-001` — **os dois gráficos da tela de lançamentos**.
 *
 * > **Feature NOVA (DEC-21), não paridade.** `Doughnut` é global em
 * > `index.js.erb:31,37` e nenhuma view do legado o instancia. O QA do Phase 4
 * > **não deve procurar estes gráficos na origem**.
 *
 * O que se prova aqui é o que `tsc` não vê: **mês não lançado não vira ponto em
 * zero** (DEC-70 / D-117), e a data de apuração do volume por portador nunca
 * cai no futuro.
 */

const volumeByCarrier = vi.fn()

vi.mock('@/lib/api/dashboard', async () => {
  const real = await vi.importActual<typeof import('@/lib/api/dashboard')>('@/lib/api/dashboard')
  return {
    ...real,
    dashboardApi: { summary: vi.fn(), volumeByCarrier: (...a: any[]) => volumeByCarrier(...a) },
  }
})

import { IndicatorSeriesChart } from '../components/IndicatorSeriesChart'
import { CarrierVolumeChart, dataDeApuracao } from '../components/CarrierVolumeChart'
import type { GridRow } from '@/lib/api/indicators'

function Envolvido({ children }: { children: ReactNode }) {
  // `useState` e não `new QueryClient()` no corpo: a cada re-render nascia um
  // cliente novo, e a consulta em voo do anterior virava rejeição sem dono —
  // o vitest a reportava como falha do teste que só observava o estado de erro.
  const [client] = useState(() => new QueryClient({ defaultOptions: { queries: { retry: false } } }))
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

function indicador(id: string, title: string) {
  return {
    id,
    title,
    key: title.toLowerCase(),
    value_type: 'decimal',
    is_active: true,
    project_id: null,
    scope: 'global' as const,
    description_html: null,
    entries_count: 0,
    projects_count: 0,
    discarded_at: null,
    created_at: '',
    updated_at: '',
  }
}

function celula(month: number, value: string | null) {
  return {
    month,
    entry:
      value === null
        ? null
        : {
            id: `e-${month}`,
            indicator_id: 'i-1',
            year: 2026,
            month,
            value,
            title: 'MARGEM',
            value_type: 'decimal',
            created_by: null,
            updated_by: null,
            created_at: '',
            updated_at: '',
          },
  }
}

/** Doze meses, com **só três lançados**: jan, mar e jul. */
const LINHA_COM_BURACO: GridRow = {
  indicator: indicador('i-1', 'MARGEM'),
  cells: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map((m) =>
    m === 1 ? celula(m, '1000.00') : m === 3 ? celula(m, '0.00') : m === 7 ? celula(m, '2500.50') : celula(m, null),
  ),
}

// **`cleanup()` explícito.** `src/test/setup.ts` não o registra, então a tela
// do exemplo anterior continuava montada — e a consulta dela, viva. O sintoma
// era a rejeição do exemplo seguinte aparecer como rejeição sem dono, e o
// teste que provava o tratamento do erro reprovar por causa dele.
beforeEach(() => {
  cleanup()
  volumeByCarrier.mockReset()
})

describe('NEW-001 parte 1 — série mensal do indicador', () => {
  // === DEC-70 / D-117 — o coração desta fatia ==============================
  //
  // `RechartsLine` transforma `null` em `0` e não desenha buraco. Se a série
  // levasse os 12 meses, nove deles apareceriam como "o indicador valeu zero" —
  // uma afirmação que o dado não sustenta, e o defeito que a S10 fechou na
  // grade voltaria pelo gráfico.
  it('só os meses LANÇADOS entram na série — mês em branco não vira zero', () => {
    render(<IndicatorSeriesChart linhas={[LINHA_COM_BURACO]} indicadorId="i-1" ano={2026} mes={null} />)

    expect(screen.getByText(/3 de 12 meses lançados/)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /ver valores/i }))
    const linhas = screen.getAllByRole('row')
    // 1 cabeçalho + 3 meses lançados. Nada de doze.
    expect(linhas).toHaveLength(4)
    // O mês lançado COMO ZERO continua na série: zero lançado é um dado.
    expect(screen.getByText('R$ 0,00')).toBeInTheDocument()
    expect(screen.getByText('R$ 2.500,50')).toBeInTheDocument()
  })

  it('nenhum mês lançado mostra o estado vazio, não uma linha em zero', () => {
    const vazia: GridRow = {
      indicator: indicador('i-1', 'MARGEM'),
      cells: [1, 2, 3].map((m) => celula(m, null)),
    }

    render(<IndicatorSeriesChart linhas={[vazia]} indicadorId="i-1" ano={2026} mes={null} />)

    expect(screen.getByText('Sem lançamentos no período')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /ver valores/i })).not.toBeInTheDocument()
  })

  // === Sem filtro próprio: o gráfico segue a tela (design G3) ==============
  it('com vários indicadores e nenhum escolhido, pede a escolha em vez de adivinhar', () => {
    const outra: GridRow = { indicator: indicador('i-2', 'ATRASO'), cells: [celula(1, '5.00')] }

    render(<IndicatorSeriesChart linhas={[LINHA_COM_BURACO, outra]} indicadorId={null} ano={2026} mes={null} />)

    expect(screen.getByText('Escolha um indicador')).toBeInTheDocument()
  })

  it('com UM indicador só não há ambiguidade, e o gráfico desenha sem escolha', () => {
    render(<IndicatorSeriesChart linhas={[LINHA_COM_BURACO]} indicadorId={null} ano={2026} mes={null} />)

    expect(screen.getByText(/Série mensal — MARGEM/)).toBeInTheDocument()
  })

  it('filtro em um mês só diz que a série precisa de mais de um mês', () => {
    render(<IndicatorSeriesChart linhas={[LINHA_COM_BURACO]} indicadorId="i-1" ano={2026} mes={3} />)

    expect(screen.getByText('A série precisa de mais de um mês')).toBeInTheDocument()
  })
})

describe('NEW-001 parte 2 — volume por portador', () => {
  // A exposição é um número **de uma data**; a tela filtra por **período**. A
  // tradução tem de ser determinística e nunca cair no futuro — apurar
  // exposição em 31/12 de um ano que ainda não acabou mostra um saldo que
  // ninguém pode conferir.
  it('a data de apuração é o fim do período, e nunca o futuro', () => {
    const hoje = new Date(2026, 7, 26) // 26/08/2026

    expect(dataDeApuracao(2025, 3, hoje)).toBe('2025-03-31')
    expect(dataDeApuracao(2025, null, hoje)).toBe('2025-12-31')
    // O ano corrente terminaria em 31/12/2026, que ainda não aconteceu.
    expect(dataDeApuracao(2026, null, hoje)).toBe('2026-08-26')
    expect(dataDeApuracao(2026, 12, hoje)).toBe('2026-08-26')
    // Fevereiro de ano bissexto, sem tabela de dias escrita à mão.
    expect(dataDeApuracao(2024, 2, hoje)).toBe('2024-02-29')
  })

  it('sem limite ativo, mostra o estado próprio — não um gráfico zerado', async () => {
    volumeByCarrier.mockResolvedValue({ date: '2026-08-26', labels: [], values: [], has_data: false })

    render(
      <Envolvido>
        <CarrierVolumeChart ano={2026} mes={null} />
      </Envolvido>,
    )

    expect(await screen.findByText('Nenhum limite ativo neste projeto')).toBeInTheDocument()
  })

  // DEC-01 — utilização negativa aparece como está. Foi observada no seed
  // (dois de três portadores), e "consertar" o sinal aqui mudaria número de
  // tela sem ninguém ter decidido isso.
  it('valor negativo vai para a tabela com o sinal, sem correção', async () => {
    volumeByCarrier.mockResolvedValue({
      date: '2026-08-26',
      labels: ['Banco Meridiano S.A.', 'FIDC Aurora Crédito'],
      values: ['46751.05', '-7548.14'],
      has_data: true,
    })

    render(
      <Envolvido>
        <CarrierVolumeChart ano={2026} mes={null} />
      </Envolvido>,
    )

    fireEvent.click(await screen.findByRole('button', { name: /ver valores/i }))
    expect(screen.getByText('R$ 46.751,05')).toBeInTheDocument()
    expect(screen.getByText('-R$ 7.548,14')).toBeInTheDocument()
  })

  it('erro de rede mostra o estado de erro com "tentar de novo"', async () => {
    // A rejeição ganha um dono explícito **antes** de entrar no mock. Sem o
    // `.catch` vazio o vitest a contabiliza como rejeição sem tratamento e
    // reprova o exemplo que está justamente provando que ela É tratada —
    // reprovando o teste certo pelo motivo errado.
    const falha = Promise.reject(new Error('Falha de rede'))
    falha.catch(() => {})
    volumeByCarrier.mockImplementation(() => falha)

    render(
      <Envolvido>
        <CarrierVolumeChart ano={2026} mes={null} />
      </Envolvido>,
    )

    expect(await screen.findByRole('alert')).toHaveTextContent('Não foi possível carregar o gráfico')
    expect(screen.getByRole('button', { name: /tentar de novo/i })).toBeInTheDocument()
  })
})
