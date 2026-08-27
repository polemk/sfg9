import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { cleanup, render, screen, within } from '@testing-library/react'
import { DataTable, type Column } from '@/components/ui/DataTable'

/**
 * **A tabela larga avisa que é larga** — e no telefone ela deixa de ser tabela.
 *
 * O defeito que estes exemplos travam foi achado pelo usuário em `/renegotiations`
 * a 1440×900: treze colunas, a última visível cortada no meio de um valor
 * (`R$ 2…`), as seguintes inexistentes para quem olha, e **nenhum** sinal de que
 * dava para rolar — porque `globals.css` apaga a barra de rolagem de todo
 * container do app. `tsc` passava, a suíte passava, e a tela mostrava meio número
 * numa aplicação de crédito.
 *
 * Por que testar aqui e não na tela: **18 telas** usam este componente. Se a
 * garantia morar numa delas, as outras dezessete continuam sem ela — foi assim
 * que o corte do `KpiCard` foi remendado cinco vezes antes de alguém notar que a
 * conta era do componente.
 */

interface Linha {
  id: string
  cliente: string
  valor: number
  vencimento: string
  situacao: string
}

const DADOS: Linha[] = [
  { id: '1', cliente: 'Beta Comércio', valor: 300, vencimento: '2026-03-01', situacao: 'Em dia' },
  { id: '2', cliente: 'Alfa Log', valor: 1000, vencimento: '2026-01-15', situacao: 'Vencido' },
]

const COLUNAS: Column<Linha>[] = [
  { key: 'cliente', header: 'Cliente', sortable: true },
  { key: 'valor', header: 'Valor', variant: 'money', sortable: true },
  { key: 'vencimento', header: 'Vencimento', variant: 'date' },
  { key: 'situacao', header: 'Situação' },
]

/**
 * jsdom não faz layout: `scrollWidth` e `clientWidth` são sempre 0, então sem isto
 * a medição de transbordo devolve "cabe" para qualquer tabela. Aqui a largura é
 * declarada à mão para reproduzir o que o navegador reporta na tela larga.
 */
function fingirLarguras({ conteudo, visivel }: { conteudo: number; visivel: number }) {
  Object.defineProperty(HTMLDivElement.prototype, 'scrollWidth', {
    configurable: true,
    get() {
      return conteudo
    },
  })
  Object.defineProperty(HTMLDivElement.prototype, 'clientWidth', {
    configurable: true,
    get() {
      return visivel
    },
  })
}

/**
 * jsdom também devolve 0 em `offsetLeft`/`offsetWidth`. Aqui cada coluna passa a
 * ter `larguraDaColuna` px e a posição que a sua ordem implica — é o que permite
 * conferir a conta da cortina sem navegador.
 */
function fingirColunas(larguraDaColuna: number) {
  Object.defineProperty(HTMLTableCellElement.prototype, 'offsetWidth', {
    configurable: true,
    get() {
      return larguraDaColuna
    },
  })
  Object.defineProperty(HTMLTableCellElement.prototype, 'offsetLeft', {
    configurable: true,
    get() {
      const irmaos = Array.from(this.parentElement?.children ?? [])
      return irmaos.indexOf(this) * larguraDaColuna
    },
  })
}

function desfazerColunas() {
  // @ts-expect-error — devolvendo o getter nativo do jsdom.
  delete HTMLTableCellElement.prototype.offsetWidth
  // @ts-expect-error — idem.
  delete HTMLTableCellElement.prototype.offsetLeft
}

function desfazerLarguras() {
  // @ts-expect-error — devolvendo o getter nativo do jsdom.
  delete HTMLDivElement.prototype.scrollWidth
  // @ts-expect-error — idem.
  delete HTMLDivElement.prototype.clientWidth
}

const larguraOriginal = window.innerWidth

function definirLarguraDaJanela(px: number) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: px })
}

beforeEach(() => {
  // A S15 registrou que `src/test/setup.ts` não chama `cleanup()` (UF-S15-04):
  // sem isto a tela do exemplo anterior continua montada e a consulta pega a dela.
  cleanup()
  definirLarguraDaJanela(1440)
})

afterEach(() => {
  desfazerLarguras()
  desfazerColunas()
  definirLarguraDaJanela(larguraOriginal)
})

describe('DataTable — rolagem horizontal com afordância', () => {
  it('a barra de rolagem VOLTA a existir no container da tabela', () => {
    const { container } = render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)
    const rolagem = container.querySelector('[data-table-scroll]')!
    // `overflow-auto` sozinho não basta: a regra `*::-webkit-scrollbar { height: 0 }`
    // do `globals.css` apaga a barra do app inteiro. `.table-scroll-x` a devolve.
    expect(rolagem).toHaveClass('table-scroll-x')
    // A rolagem é LIVRE: o encaixe obrigatório saiu em 26/08/2026, porque parava
    // numa posição em que a coluna seguinte ficava inteira sob a congelada.
    expect(rolagem).not.toHaveClass('table-snap-x')
  })

  it('tabela que CABE não mostra sombra nenhuma e não vira parada de tabulação', () => {
    fingirLarguras({ conteudo: 600, visivel: 600 })
    const { container } = render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)

    expect(container.querySelector('[data-scroll-edge]')).toBeNull()
    // Sombra que fica lá o tempo todo deixa de ser aviso e vira enfeite.
    expect(container.querySelector('[data-table-scroll]')).not.toHaveAttribute('role', 'region')
    expect(container.querySelector('th')).not.toHaveClass('sticky')
  })

  it('tabela que TRANSBORDA à direita avisa, e a coluna de identificação congela', () => {
    fingirLarguras({ conteudo: 1600, visivel: 700 })
    const { container } = render(
      <DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} caption="Renegociações" />,
    )

    // Quem avisa NÃO é mais cortina opaca (removida em 26/08/2026): é a barra fina
    // flutuante, o arrastar, e a sombra da coluna congelada na divisa.
    expect(container.querySelector('[data-scroll-edge]')).toBeNull()
    expect(container.querySelector('th')).toHaveClass('sticky')

    // WCAG 2.1.1 — quem navega por teclado precisa alcançar a região que rola.
    const rolagem = container.querySelector('[data-table-scroll]')!
    expect(rolagem).toHaveAttribute('role', 'region')
    expect(rolagem).toHaveAttribute('tabindex', '0')
    expect(rolagem).toHaveAttribute('aria-label', 'Renegociações')

    // De quem é a linha não sai da tela — e a célula fixa é marcada para receber
    // a superfície MEDIDA (`data-sticky-col`), porque ela precisa ser opaca e
    // `bg-card` cravado erraria na tela que põe a tabela direto na página.
    const primeiroCabecalho = container.querySelectorAll('th')[0]
    expect(primeiroCabecalho).toHaveClass('sticky')
    expect(primeiroCabecalho).toHaveAttribute('data-sticky-col')
    const primeiraCelula = container.querySelectorAll('tbody td')[0]
    expect(primeiraCelula).toHaveClass('sticky')
    expect(primeiraCelula).toHaveAttribute('data-sticky-col')
    // E as outras colunas NÃO são marcadas.
    expect(container.querySelectorAll('th')[1]).not.toHaveAttribute('data-sticky-col')
  })

  // **A cortina saiu (26/08/2026).** O usuário mandou três capturas em que a tabela
  // parecia quebrada por causa dela: rolando, um vão entre a coluna congelada e o
  // resto fazia ler como DUAS tabelas; parada, um retângulo opaco encostava na última
  // coluna. Meia célula é ruim, mas é **legível como corte**; retângulo opaco lê como
  // falha de renderização. Este exemplo tranca a decisão.
  it('NÃO existe cortina opaca em nenhuma borda, mesmo transbordando', () => {
    fingirLarguras({ conteudo: 1600, visivel: 700 })
    const { container } = render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)

    expect(container.querySelector('[data-scroll-edge="right"]')).toBeNull()
    expect(container.querySelector('[data-scroll-edge="left"]')).toBeNull()
  })

  // **O encaixe saiu (26/08/2026).** Com `scroll-snap-type: x mandatory` a rolagem
  // parava numa posição em que a coluna seguinte ficava EXATAMENTE sob a congelada,
  // que é opaca — a coluna sumia da tela e, por ser encaixe obrigatório, não havia
  // onde parar para vê-la. Coluna inalcançável é pior que coluna cortada.
  it('a rolagem é LIVRE: sem encaixe obrigatório e sem recuo de encaixe', () => {
    fingirLarguras({ conteudo: 1600, visivel: 700 })
    const { container } = render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)

    const rolagem = container.querySelector<HTMLElement>('[data-table-scroll]')!
    expect(rolagem.className).not.toContain('table-snap-x')
    expect(rolagem.style.scrollPaddingLeft).toBe('')
  })

  it('`stickyFirstColumn={false}` troca a coluna congelada pelo degradê da esquerda', () => {
    fingirLarguras({ conteudo: 1600, visivel: 700 })
    const { container } = render(
      <DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} stickyFirstColumn={false} />,
    )
    expect(container.querySelector('th')).not.toHaveClass('sticky')
    expect(container.querySelector('[data-scroll-edge]')).toBeNull()
  })
})

describe('DataTable — o telefone recebe cartões, não a tabela encolhida', () => {
  it('abaixo de 768 px não existe tabela: cada linha vira um cartão com TODOS os campos', () => {
    definirLarguraDaJanela(390)
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} caption="Renegociações" />)

    expect(screen.queryByRole('table')).toBeNull()

    const cartoes = screen.getAllByRole('listitem')
    expect(cartoes).toHaveLength(2)

    // Coluna escondida no telefone é coluna que o usuário nunca descobre: os
    // rótulos das outras três colunas aparecem, com o valor formatado do mesmo
    // jeito que na tabela.
    const primeiro = within(cartoes[0])
    expect(primeiro.getByText('Beta Comércio')).toBeInTheDocument()
    expect(primeiro.getByText('Valor')).toBeInTheDocument()
    expect(primeiro.getByText(/R\$\s?300,00/)).toBeInTheDocument()
    expect(primeiro.getByText('Vencimento')).toBeInTheDocument()
    expect(primeiro.getByText('01/03/2026')).toBeInTheDocument()
    expect(primeiro.getByText('Situação')).toBeInTheDocument()
  })

  it('valor em moeda ocupa a linha inteira do cartão e não quebra no meio', () => {
    // Visto renderizando a 390×844: em duas colunas, `R$ 1.204.000,00` quebrava
    // depois do penúltimo dígito e a linha de baixo mostrava só `0`. Número
    // partido em duas linhas é a mesma família do número cortado.
    definirLarguraDaJanela(390)
    const { container } = render(<DataTable columns={COLUNAS} data={[DADOS[0]]} rowKey={(r) => r.id} />)

    const valor = screen.getByText(/R\$\s?300,00/)
    expect(valor).toHaveClass('whitespace-nowrap')
    expect(valor.closest('div')).toHaveClass('col-span-2')

    // A data é curta: continua em meia linha, mas também não quebra.
    const data = screen.getByText('01/03/2026')
    expect(data).toHaveClass('whitespace-nowrap')
    expect(data.closest('div')).not.toHaveClass('col-span-2')
    expect(container.querySelectorAll('dt')).toHaveLength(3)
  })

  it('`hideOnMobile` tira a coluna do cartão e mais nada', () => {
    definirLarguraDaJanela(390)
    const colunas: Column<Linha>[] = [
      ...COLUNAS.slice(0, 3),
      { key: 'situacao', header: 'Situação', hideOnMobile: true },
    ]
    render(<DataTable columns={colunas} data={DADOS} rowKey={(r) => r.id} />)
    expect(screen.queryByText('Situação')).toBeNull()
    expect(screen.getAllByText('Valor')).toHaveLength(2)
  })

  it('o cartão abre o registro pelo teclado quando a tela passa `onRowClick`', () => {
    definirLarguraDaJanela(390)
    const abrir = vi.fn()
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} onRowClick={abrir} />)

    const cartao = screen.getAllByRole('button')[0]
    cartao.focus()
    cartao.click()
    expect(abrir).toHaveBeenCalledWith(DADOS[0])
  })

  it('`mobile="scroll"` preserva a tabela para quem precisa da grade', () => {
    definirLarguraDaJanela(390)
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} mobile="scroll" />)
    expect(screen.getByRole('table')).toBeInTheDocument()
  })
})
