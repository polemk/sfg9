import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { DataTable, type Column } from '@/components/ui/DataTable'

/**
 * **Arrastar para rolar, sem roubar o clique da linha.**
 *
 * O usuário pediu o tratamento do `apl9` (*"o apl9 tem o tratamento de tabelas
 * com scroll que ficou bom"*). O que o `apl9` faz e faltava aqui é arrastar o
 * conteúdo com o mouse — a única afordância de rolagem que sobrevive onde a
 * barra não é pintada: o **iOS** não mostra barra persistente e o **Chromium
 * headless** reserva 0 px, o que também impede provar a barra renderizando.
 *
 * O risco que vem junto é o que estes exemplos travam: as linhas destas tabelas
 * têm `onRowClick`, e um arrasto que termina em cima de uma linha emite um
 * `click`. Sem limiar, rolar 40 px abriria um registro que ninguém pediu; com
 * limiar mal posto, o tremor de 3 px do clique deixaria de abrir o registro que
 * o usuário pediu. Os dois casos estão aqui, e nenhum dos dois é visível para o
 * `tsc`.
 */

interface Linha {
  id: string
  cliente: string
  valor: number
}

const DADOS: Linha[] = [
  { id: '1', cliente: 'Beta Comércio', valor: 300 },
  { id: '2', cliente: 'Alfa Log', valor: 1000 },
]

const COLUNAS: Column<Linha>[] = [
  { key: 'cliente', header: 'Cliente' },
  { key: 'valor', header: 'Valor', variant: 'money' },
]

/** jsdom não faz layout: sem isto toda tabela "cabe" e o arraste nasce desligado. */
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
 * jsdom aceita a atribuição de `scrollLeft` e devolve 0 na leitura — o elemento
 * não tem caixa de rolagem de verdade. Aqui ele passa a guardar o valor, que é
 * o que permite conferir **quanto** a tabela rolou.
 */
const rolagens = new WeakMap<HTMLElement, number>()
function fingirScrollLeft() {
  Object.defineProperty(HTMLDivElement.prototype, 'scrollLeft', {
    configurable: true,
    get() {
      return rolagens.get(this) ?? 0
    },
    set(valor: number) {
      rolagens.set(this, valor)
      this.dispatchEvent(new Event('scroll'))
    },
  })
}

function desfazerFingimentos() {
  for (const prop of ['scrollWidth', 'clientWidth', 'scrollLeft']) {
    // @ts-expect-error — devolvendo o getter nativo do jsdom.
    delete HTMLDivElement.prototype[prop]
  }
}

const larguraOriginal = window.innerWidth

beforeEach(() => {
  // `src/test/setup.ts` não chama `cleanup()` (UF-S15-04): sem isto a tela do
  // exemplo anterior continua montada e a consulta pega a dela.
  cleanup()
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 1440 })
})

afterEach(() => {
  desfazerFingimentos()
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: larguraOriginal,
  })
})

function montarTabelaLarga(onRowClick?: (linha: Linha) => void, colunas: Column<Linha>[] = COLUNAS) {
  fingirLarguras({ conteudo: 1600, visivel: 700 })
  fingirScrollLeft()
  const utils = render(
    <DataTable columns={colunas} data={DADOS} rowKey={(l) => l.id} onRowClick={onRowClick} />,
  )
  const container = utils.container.querySelector<HTMLDivElement>('[data-table-scroll]')!
  return { ...utils, container }
}

describe('DataTable — arrastar para rolar (o tratamento do apl9)', () => {
  it('um arrasto de 3 px é CLIQUE: a linha abre e a tabela não rola', () => {
    const abrir = vi.fn()
    const { container } = montarTabelaLarga(abrir)
    const linha = screen.getAllByRole('row')[1]

    fireEvent.mouseDown(linha, { button: 0, clientX: 400 })
    fireEvent.mouseMove(linha, { clientX: 403 })
    fireEvent.mouseUp(linha)
    fireEvent.click(linha)

    expect(abrir).toHaveBeenCalledTimes(1)
    expect(abrir).toHaveBeenCalledWith(DADOS[0])
    // Abaixo do limiar nada rola — nem 1 px. Tremor de mão não é gesto.
    expect(container.scrollLeft).toBe(0)
    expect(container).not.toHaveAttribute('data-table-dragging')
  })

  it('um arrasto de 40 px é ROLAGEM: a tabela rola e a linha NÃO abre', () => {
    const abrir = vi.fn()
    const { container } = montarTabelaLarga(abrir)
    const linha = screen.getAllByRole('row')[1]

    fireEvent.mouseDown(linha, { button: 0, clientX: 400 })
    fireEvent.mouseMove(linha, { clientX: 360 })
    fireEvent.mouseUp(linha)
    // O navegador emite este `click` no fim do gesto. Ele é resto de rolagem,
    // não escolha do usuário — e é o defeito que o limiar existe para impedir.
    fireEvent.click(linha)

    expect(abrir).not.toHaveBeenCalled()
    // 40 px de gesto × `speed: 2` (o do apl9) = 80 px de conteúdo.
    expect(container.scrollLeft).toBe(80)
  })

  it('depois de um arrasto, o PRÓXIMO clique volta a abrir a linha', () => {
    // A supressão vale para UM clique. Se a bandeira ficasse levantada, a linha
    // pararia de abrir e o usuário só descobriria clicando duas vezes.
    const abrir = vi.fn()
    montarTabelaLarga(abrir)
    const linha = screen.getAllByRole('row')[1]

    fireEvent.mouseDown(linha, { button: 0, clientX: 400 })
    fireEvent.mouseMove(linha, { clientX: 360 })
    fireEvent.mouseUp(linha)
    fireEvent.click(linha)
    expect(abrir).not.toHaveBeenCalled()

    fireEvent.mouseDown(linha, { button: 0, clientX: 400 })
    fireEvent.mouseUp(linha)
    fireEvent.click(linha)
    expect(abrir).toHaveBeenCalledTimes(1)
  })

  it('enquanto arrasta: cursor agarrado e sem seleção de texto', () => {
    const { container } = montarTabelaLarga()

    // Parado, o container convida ao gesto.
    expect(container).toHaveClass('cursor-grab')
    // O encaixe obrigatório saiu em 26/08/2026 — ele parava numa posição em que a
    // coluna seguinte ficava inteira sob a congelada, e a rolagem é livre agora.
    expect(container).not.toHaveClass('table-snap-x')

    fireEvent.mouseDown(container, { button: 0, clientX: 400 })
    fireEvent.mouseMove(container, { clientX: 300 })

    expect(container).toHaveClass('cursor-grabbing')
    expect(container).toHaveClass('select-none')
    expect(container).not.toHaveClass('cursor-grab')
    // O cursor tem de valer para a tabela inteira: a linha clicável declara
    // `cursor-pointer` e ganharia do container por especificidade.
    expect(container).toHaveAttribute('data-table-dragging')
    // O desligamento em linha continua: se alguém recolocar o encaixe, o gesto não
    // pode voltar a saltar para a coluna mais próxima a cada movimento.
    expect(container.style.scrollSnapType).toBe('none')

    fireEvent.mouseUp(container)
    expect(container).toHaveClass('cursor-grab')
    expect(container).not.toHaveAttribute('data-table-dragging')
    expect(container.style.scrollSnapType).toBe('')
  })

  it('soltar o mouse FORA do container encerra o gesto', () => {
    const { container } = montarTabelaLarga()
    fireEvent.mouseDown(container, { button: 0, clientX: 400 })
    fireEvent.mouseMove(container, { clientX: 300 })
    expect(container).toHaveAttribute('data-table-dragging')

    fireEvent.mouseLeave(container)
    // Sem isto o cursor fica "agarrado" para sempre e o próximo movimento do
    // mouse dentro da tabela rola sem ninguém ter apertado nada.
    expect(container).not.toHaveAttribute('data-table-dragging')
  })

  it('tabela que CABE não promete arraste nenhum', () => {
    fingirLarguras({ conteudo: 600, visivel: 600 })
    fingirScrollLeft()
    const { container } = render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(l) => l.id} />)
    const rolagem = container.querySelector('[data-table-scroll]')!
    expect(rolagem).not.toHaveClass('cursor-grab')
    expect(rolagem).not.toHaveClass('cursor-grabbing')
  })

  it('arrasto que COMEÇA num controle da célula é do controle, não da rolagem', () => {
    const apertar = vi.fn()
    const colunas: Column<Linha>[] = [
      ...COLUNAS,
      {
        key: 'acoes',
        header: 'Ações',
        cell: () => (
          <button type="button" onClick={apertar}>
            Remover
          </button>
        ),
      },
    ]
    const { container } = montarTabelaLarga(undefined, colunas)
    const botao = screen.getAllByRole('button', { name: 'Remover' })[0]

    fireEvent.mouseDown(botao, { button: 0, clientX: 400 })
    fireEvent.mouseMove(botao, { clientX: 360 })
    fireEvent.mouseUp(botao)
    fireEvent.click(botao)

    // Apertar um botão e mexer o mouse 40 px não pode virar rolagem — e o
    // `preventDefault` do movimento mataria o clique dele.
    expect(container.scrollLeft).toBe(0)
    expect(apertar).toHaveBeenCalledTimes(1)
  })

  it('o botão do meio e o direito não arrastam', () => {
    const { container } = montarTabelaLarga()
    fireEvent.mouseDown(container, { button: 1, clientX: 400 })
    fireEvent.mouseMove(container, { clientX: 300 })
    expect(container.scrollLeft).toBe(0)

    fireEvent.mouseDown(container, { button: 2, clientX: 400 })
    fireEvent.mouseMove(container, { clientX: 300 })
    expect(container.scrollLeft).toBe(0)
  })
})
