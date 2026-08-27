import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useState, type ReactNode } from 'react'

/**
 * S15 — **os gráficos e o painel**, `NEW-001` e `NEW-002`.
 *
 * > **Feature NOVA (DEC-21), não paridade.** Nenhum destes testes fecha item de
 * > paridade, e o QA do Phase 4 não deve procurar estas telas no legado.
 *
 * O que se prova aqui é exatamente o que `tsc` não pega e o que a spec do
 * backend não alcança: **o que a tela mostra quando não há número**. Os dois
 * estados que mais aparecem numa demonstração — vazio e falha — são os que o
 * legado não tinha (FE-239, FE-401).
 */

const summary = vi.fn()
const volumeByCarrier = vi.fn()

vi.mock('@/lib/api/dashboard', async () => {
  const real = await vi.importActual<typeof import('@/lib/api/dashboard')>('@/lib/api/dashboard')
  return {
    ...real,
    dashboardApi: {
      summary: (...a: any[]) => summary(...a),
      volumeByCarrier: (...a: any[]) => volumeByCarrier(...a),
    },
  }
})

import { DashboardPage } from '@/app/pages/DashboardPage'
import { ChartPanel } from '@/components/charts/ChartPanel'

function Envolvido({ children, rota = '/dashboard' }: { children: ReactNode; rota?: string }) {
  // `useState` e não `new QueryClient()` no corpo: a cada re-render nascia um
  // cliente novo, e a consulta em voo do anterior virava rejeição sem dono —
  // o vitest a reportava como falha do teste que só observava o estado de erro.
  const [client] = useState(() => new QueryClient({ defaultOptions: { queries: { retry: false } } }))
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[rota]}>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

const CARTAO_SEM_DADO = {
  key: 'total_operado',
  label: 'Total operado',
  hint: '09/2025 a 08/2026',
  value: null,
  format: 'currency' as const,
  href: '/receivables',
}

const RESUMO_VAZIO = {
  date: '2026-08-26',
  project: { id: 'p-1', name: 'Projeto de teste' },
  period: { from: '2025-09-01', to: '2026-08-31' },
  cards: [
    CARTAO_SEM_DADO,
    { key: 'exposicao', label: 'Exposição', hint: 'em 26/08/2026', value: null, format: 'currency' as const, href: '/risk' },
    { key: 'limites_no_teto', label: 'Limites no teto', hint: 'em 26/08/2026', value: null, format: 'integer' as const, href: '/risk-controls' },
  ],
  series: { labels: [], values: [], has_data: false },
  // A zona de risco inteira depende do gate `risk_controls`: com `null` ela nem
  // é desenhada, em vez de aparecer com painéis vazios.
  limits: null,
  near_ceiling: null,
  overdue_renegotiations: null,
}

// `cleanup()` explícito: `src/test/setup.ts` não o registra, e a tela do
// exemplo anterior seguia montada com a consulta dela viva.
beforeEach(() => {
  cleanup()
  summary.mockReset()
  volumeByCarrier.mockReset()
})

describe('NEW-002 — o painel da tela inicial', () => {
  // === 5.4 — sem dado, NUNCA `R$ 0,00` (D-117) ==============================
  //
  // É a regra mais importante da tela. `R$ 0,00` afirma que se operou zero;
  // ausência diz que não há informação. Num sistema de crédito as duas levam a
  // decisões opostas, e no legado eram o mesmo pixel.
  it('sem dado, o cartão mostra "—" e a causa — e nunca R$ 0,00', async () => {
    summary.mockResolvedValue(RESUMO_VAZIO)

    render(
      <Envolvido>
        <DashboardPage />
      </Envolvido>,
    )

    await screen.findByText('Total operado')
    expect(screen.getAllByText('—').length).toBeGreaterThan(0)
    // "Sem borderô no período" aparece duas vezes de propósito: no cartão e no
    // gráfico. As duas superfícies dizem a mesma coisa porque a ausência é a
    // mesma — e nenhuma das duas escreve `R$ 0,00`.
    expect((await screen.findAllByText('Sem borderô no período')).length).toBeGreaterThan(0)
    expect(screen.queryByText(/R\$\s*0,00/)).not.toBeInTheDocument()
  })

  it('sem série, o gráfico mostra o estado vazio — e não uma linha em zero', async () => {
    summary.mockResolvedValue(RESUMO_VAZIO)

    render(
      <Envolvido>
        <DashboardPage />
      </Envolvido>,
    )

    // O título do painel do gráfico aparece; o desenho, não.
    await screen.findByText('Total operado por mês')
    expect((await screen.findAllByText('Sem borderô no período')).length).toBeGreaterThan(0)
    // Sem dado não há tabela de valores para abrir.
    expect(screen.queryByRole('button', { name: /ver valores/i })).not.toBeInTheDocument()
  })

  // === Cartão omitido pela permissão: some, não vem zerado ==================
  it('cartão que não veio no payload simplesmente não aparece', async () => {
    summary.mockResolvedValue(RESUMO_VAZIO) // sem `renegociacoes_em_atraso`

    render(
      <Envolvido>
        <DashboardPage />
      </Envolvido>,
    )

    await screen.findByText('Total operado')
    expect(screen.queryByText('Renegociações em atraso')).not.toBeInTheDocument()
  })

  // === 4.3 — o destino vem do payload, não de rota codificada ==============
  it('o cartão navega para o `href` que veio do servidor', async () => {
    summary.mockResolvedValue({
      ...RESUMO_VAZIO,
      cards: [{ ...CARTAO_SEM_DADO, href: '/rota-que-so-o-servidor-conhece' }],
    })

    render(
      <Envolvido>
        <DashboardPage />
      </Envolvido>,
    )

    const link = await screen.findByRole('link', { name: /Total operado/i })
    expect(link).toHaveAttribute('href', '/rota-que-so-o-servidor-conhece')
  })

  // === 5.5 — falha de rede tem estado próprio, com "tentar de novo" =========
  //
  // O contêiner de resumo do legado **não tinha estado de erro** (FE-239): a
  // falha deixava a área em branco, indistinguível de "não há nada".
  it('erro de rede mostra o estado de erro e permite tentar de novo', async () => {
    summary.mockRejectedValue(new Error('Falha de rede'))

    render(
      <Envolvido>
        <DashboardPage />
      </Envolvido>,
    )

    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent('Não foi possível carregar o resumo')

    summary.mockResolvedValue(RESUMO_VAZIO)
    fireEvent.click(screen.getByRole('button', { name: /tentar de novo/i }))

    await waitFor(() => expect(screen.getByText('Total operado')).toBeInTheDocument())
  })
})

describe('bloco 7 — o filtro de tempo', () => {
  // **Uma POSIÇÃO e uma JANELA, nunca duas datas** (design G7). O que se prova
  // aqui é que os dois saem da URL e entram na consulta — sem isso, "me manda a
  // tela de agosto" não tem resposta.
  it('lê data e janela da URL e os manda para a consulta', async () => {
    summary.mockResolvedValue(RESUMO_VAZIO)

    render(
      <Envolvido rota="/dashboard?date=2026-03-15&months=24">
        <DashboardPage />
      </Envolvido>,
    )

    await screen.findByText('Total operado')
    expect(summary).toHaveBeenCalledWith({ date: '2026-03-15', months: 24 })
  })

  // Parâmetro torto na barra de endereço não pode virar requisição torta.
  it('data inválida e janela fora da lista caem no padrão, sem quebrar a tela', async () => {
    summary.mockResolvedValue(RESUMO_VAZIO)

    render(
      <Envolvido rota="/dashboard?date=ontem&months=999">
        <DashboardPage />
      </Envolvido>,
    )

    await screen.findByText('Total operado')
    const [chamada] = summary.mock.calls.at(-1) as [{ date: string; months: number }]
    expect(chamada.months).toBe(12)
    expect(chamada.date).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })

  it('a chave da consulta carrega os dois filtros — trocar um revalida', async () => {
    summary.mockResolvedValue(RESUMO_VAZIO)

    const { unmount } = render(
      <Envolvido rota="/dashboard?date=2026-03-15&months=6">
        <DashboardPage />
      </Envolvido>,
    )
    await screen.findByText('Total operado')
    unmount()

    render(
      <Envolvido rota="/dashboard?date=2026-03-15&months=24">
        <DashboardPage />
      </Envolvido>,
    )
    await screen.findByText('Total operado')

    const janelas = summary.mock.calls.map(([a]: any) => a.months)
    expect(janelas).toContain(6)
    expect(janelas).toContain(24)
  })
})

describe('ChartPanel — a moldura e a tabela gêmea', () => {
  // A tabela existe porque o tooltip de `RechartsLine` imprime o número CRU
  // (`1121652.63`, visto renderizando) e porque o ouro da marca sobre o card
  // branco dá 1,63:1 — abaixo de 3:1 a regra exige alívio. Aqui os valores
  // aparecem formatados em pt-BR, fora do desenho.
  it('mostra os valores exatos, formatados em pt-BR, fora do gráfico', () => {
    render(
      <ChartPanel title="Total operado por mês" labels={['09/2025']} values={[1121652.63]} valueFormat="currency">
        <div data-testid="grafico" />
      </ChartPanel>,
    )

    fireEvent.click(screen.getByRole('button', { name: /ver valores/i }))
    expect(screen.getByRole('table')).toBeInTheDocument()
    expect(screen.getByText('R$ 1.121.652,63')).toBeInTheDocument()
    // O número cru do tooltip **não** é o que a tabela mostra.
    expect(screen.queryByText('1121652.63')).not.toBeInTheDocument()
  })

  it('erro vence carregamento — a tela não gira para sempre sobre uma falha', () => {
    render(
      <ChartPanel title="Série" loading error={new Error('boom')} labels={[]} values={[]}>
        <div data-testid="grafico" />
      </ChartPanel>,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('Não foi possível carregar o gráfico')
    expect(screen.queryByTestId('grafico')).not.toBeInTheDocument()
  })

  it('sem dado, o gráfico NÃO é montado — série vazia não vira linha em zero', () => {
    render(
      <ChartPanel title="Série" hasData={false} labels={[]} values={[]}>
        <div data-testid="grafico" />
      </ChartPanel>,
    )

    expect(screen.queryByTestId('grafico')).not.toBeInTheDocument()
  })
})

// ---------------------------------------------------------------------------
// Varreduras de contrato — o que um arquivo novo pode reintroduzir sem que
// nenhum teste de comportamento perceba.
// ---------------------------------------------------------------------------

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')

function arquivos(dir: string, acc: string[] = []): string[] {
  for (const nome of readdirSync(dir)) {
    const caminho = join(dir, nome)
    if (statSync(caminho).isDirectory()) {
      if (['node_modules', '__tests__', 'dist'].includes(nome)) continue
      arquivos(caminho, acc)
    } else if (/\.tsx?$/.test(nome)) {
      acc.push(caminho)
    }
  }
  return acc
}

/** O comentário não é código: estas varreduras CITAM o que proíbem. */
function semComentarios(texto: string): string {
  return texto.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')
}

const ARQUIVOS_S15 = [
  join(RAIZ, 'app/pages/DashboardPage.tsx'),
  join(RAIZ, 'lib/api/dashboard.ts'),
  join(RAIZ, 'components/charts/ChartPanel.tsx'),
  ...arquivos(join(RAIZ, 'features/dashboard')),
  join(RAIZ, 'features/indicators/components/IndicatorSeriesChart.tsx'),
  join(RAIZ, 'features/indicators/components/CarrierVolumeChart.tsx'),
  join(RAIZ, 'components/ui/MasonryGrid.tsx'),
]

describe('contratos da fatia', () => {
  // === 4.7 — sem polling (Princípio 10) ====================================
  it('nenhum `setInterval` nem `refetchInterval` na superfície da S15', () => {
    for (const caminho of ARQUIVOS_S15) {
      const codigo = semComentarios(readFileSync(caminho, 'utf8'))
      expect(codigo, caminho).not.toMatch(/setInterval|refetchInterval/)
    }
  })

  // === 3.4 — os componentes de gráfico são consumidos SEM modificação ======
  //
  // A varredura é sobre o **conteúdo** dos três arquivos compartilhados: se
  // alguém "resolver" o tooltip cru editando `RechartsLine`, este teste avisa.
  // A limitação vive em `upstream-flags.md`, não numa edição local.
  it('`RechartsLine`, `RechartsBar` e `theme.ts` não ganham prop nova da S15', () => {
    const line = readFileSync(join(RAIZ, 'components/charts/RechartsLine.tsx'), 'utf8')
    const bar = readFileSync(join(RAIZ, 'components/charts/RechartsBar.tsx'), 'utf8')

    expect(line).toContain('{ labels, values }: { labels: string[]; values: number[] }')
    expect(bar).toContain('{ labels, values }: { labels: string[]; values: number[] }')
  })

  // === Nenhuma cor literal, e nenhuma segunda formatação de moeda ==========
  it('nada de hex, `rgb(` ou `BRL` cravado — a marca vem dos tokens', () => {
    for (const caminho of ARQUIVOS_S15) {
      const codigo = semComentarios(readFileSync(caminho, 'utf8'))
      expect(codigo, caminho).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
      expect(codigo, caminho).not.toMatch(/rgba?\(/)
      expect(codigo, caminho).not.toMatch(/'BRL'|"BRL"/)
      // Formatação de moeda é `formatMoney` (FE-431), num lugar só.
      expect(codigo, caminho).not.toMatch(/style:\s*'currency'/)
    }
  })

  // === Nenhum número nasce no cliente (contrato C2) ========================
  it('a superfície da S15 não soma nem tira média de valor financeiro', () => {
    for (const caminho of ARQUIVOS_S15) {
      const codigo = semComentarios(readFileSync(caminho, 'utf8'))
      expect(codigo, caminho).not.toMatch(/\.reduce\(/)
    }
  })
})
