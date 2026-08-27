import * as React from 'react'
import { ArrowDown, ArrowUp, ChevronsUpDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from './Table'
import { AsyncSection } from './AsyncSection'
import { MobileCard } from '@/components/mobile/MobileCard'
import { useMobile } from '@/hooks/useMobile'
import { useDragToScroll } from '@/hooks/useDragToScroll'
import { formatAmount, formatMoney, formatPercent } from '@/lib/utils/number'
import { formatDate, formatDateTime } from '@/lib/utils/date'

/**
 * DataTable — tabela de listagem da biblioteca.
 *
 * Dois defeitos do legado que este componente fecha por construção:
 *
 * 1. **Cabeçalho que parece ordenável e não ordena** (FE-061). Aqui a seta só
 *    aparece em coluna com `sortable`, e a coluna sem ele não recebe `cursor`,
 *    nem hover, nem `aria-sort` — ela não *parece* clicável porque não é.
 *    Coluna ordenável ordena de verdade: no modo `client` a ordenação acontece
 *    aqui; no modo `server` ela sobe para quem consulta, e é obrigatório passar
 *    `onSortChange` (sem ele, o clique não faria nada — que é exatamente o
 *    defeito original).
 * 2. **Coluna de valor desalinhada** (FE-416). As variantes `money`, `percent`,
 *    `number` e `date` já vêm com `font-numeric`, `tabular-nums` e alinhamento
 *    à direita nas numéricas. Sem isso, a coluna de valor de um borderô não
 *    alinha — e neste app isso é defeito, não estética.
 *
 * 3. **Coluna que some sem avisar** (26/08/2026, visto em `/renegotiations` a
 *    1440×900). Treze colunas não cabem: a última visível vinha **cortada no meio
 *    de um valor** — `R$ 2…` — e as seguintes simplesmente não existiam para o
 *    usuário. A rolagem existia (`Table` é `overflow-auto`) e era **invisível**,
 *    porque `globals.css` apaga a barra de todo container do app. Rolagem que não
 *    se vê é rolagem que não há, e meio número numa tela de crédito é número
 *    errado — a mesma família do corte do `KpiCard` (UF-S15-03), que já tinha sido
 *    remendado tela a tela cinco vezes. A conta é do componente, não da tela:
 *    ver `useTransbordoHorizontal` e as props `mobile` / `stickyFirstColumn`.
 *
 * 4. **Rolagem sem afordância NENHUMA onde a barra não existe** (26/08/2026,
 *    apontado pelo usuário: *"o apl9 tem o tratamento de tabelas com scroll que
 *    ficou bom"*). A barra da DS-01 resolve o mouse no desktop, e não resolve o
 *    iOS — que nunca mostra barra persistente — nem o headless, que reserva
 *    0 px e não pinta nada, e por isso a afordância anterior sequer é
 *    **comprovável** renderizando. A tabela passa a se deixar **arrastar**
 *    (`useDragToScroll`), com um limiar que separa clique de rolagem para o
 *    arrasto não roubar o `onRowClick` das linhas.
 *
 * A tabela também é a dona dos quatro estados (via `AsyncSection`): carregando,
 * vazio, erro e conteúdo. Uma listagem que só sabe mostrar linhas obriga cada
 * tela a inventar o vazio e a esquecer o erro.
 */
export type SortDirection = 'asc' | 'desc'

export interface SortState {
  key: string
  direction: SortDirection
}

export type ColumnVariant = 'text' | 'number' | 'money' | 'percent' | 'date' | 'datetime'

export interface Column<T> {
  key: string
  header: React.ReactNode
  /** Valor bruto: usado na ordenação local e na formatação por variante. */
  accessor?: (row: T) => unknown
  /** Conteúdo customizado da célula. Vence a variante. */
  cell?: (row: T, index: number) => React.ReactNode
  sortable?: boolean
  variant?: ColumnVariant
  align?: 'left' | 'center' | 'right'
  /** Largura fixa (`'10rem'`, `'15%'`). Sem ela a coluna se acomoda sozinha. */
  width?: string
  headerClassName?: string
  cellClassName?: string
  /**
   * Fora do cartão do telefone (`mobile: 'cards'`). Use em coluna que já está
   * representada de outro jeito ali — a de ações, tipicamente, que no telefone
   * vive na folha de ações e não no corpo do cartão.
   */
  hideOnMobile?: boolean
}

export interface DataTableProps<T> {
  columns: Column<T>[]
  data: T[] | null | undefined
  rowKey: (row: T, index: number) => string
  loading?: boolean
  error?: unknown
  onRetry?: () => void
  /** `client` ordena aqui; `server` delega. Padrão: `client`. */
  sortMode?: 'client' | 'server'
  sort?: SortState | null
  defaultSort?: SortState | null
  /**
   * O segundo argumento é a **coluna clicada**, e existe por causa do terceiro
   * clique: quando o tri-state chega a `null`, o primeiro argumento não diz
   * mais QUAL coluna foi desligada. Quem guarda uma ordenação só o ignora; quem
   * empilha (`useSortStack`, FE-159/194/254) precisa dele para tirar a chave
   * certa da pilha em vez de limpar tudo.
   */
  onSortChange?: (sort: SortState | null, columnKey: string) => void
  onRowClick?: (row: T) => void
  emptyTitle?: React.ReactNode
  emptyDescription?: React.ReactNode
  emptyAction?: React.ReactNode
  loadingLabel?: string
  /** Rótulo acessível da tabela. */
  caption?: string
  className?: string
  /**
   * Como o navegador reparte a largura das colunas.
   *
   * `'auto'` (padrão) é o comportamento histórico e **continua sendo o de todas as
   * telas existentes**: a `width` declarada em `Column` vira um mínimo negociável e
   * quem manda é o conteúdo. Um nome de portador longo empurra a tabela para fora do
   * container e a coluna de ações some à direita.
   *
   * `'fixed'` faz a `width` declarada valer, e o `truncate` funcionar sem precisar de
   * `max-w` em cada célula. **Use em toda tabela que declara `width`.**
   *
   * Existe porque o contorno manual já tinha aparecido duas vezes (listas de operações
   * de risco e de estruturadas), escrito à mão nas duas. Duas telas remendando a mesma
   * coisa é sinal de que o lugar é aqui.
   */
  layout?: 'auto' | 'fixed'
  /**
   * O que a tabela vira **abaixo de 768 px**. Padrão: `'cards'`.
   *
   * **Por que cartão e não "a mesma tabela menor".** Numa tabela de 10+ colunas o
   * telefone não tem para onde encolher: rolar na horizontal esconde da 5ª coluna
   * em diante, e — como está escrito no próprio `MobileCard` — *coluna fora da
   * tela é coluna que o usuário nunca descobre*. A régua do produto é explícita:
   * o desktop é onde o trabalho acontece, o telefone é onde ele é **conferido**, e
   * conferir mal é pior que não conferir. Conferir exige ver **todos** os campos.
   *
   * **Por que aqui e não em cada tela.** Não é invenção: **treze** telas desta
   * migração já escrevem essa mesma lista de cartões à mão (renegociações,
   * borderôs, cobranças, operações de risco, estruturadas, indicadores,
   * catálogos…), cada uma com o seu `MobileCard` + `<dl>` de duas colunas. O
   * componente passa a fazer de fábrica o que treze cópias já provaram ser o
   * padrão — e as treze continuam intactas, porque elas nem chegam a montar o
   * `DataTable` no telefone (trocam por `useMobile` antes).
   *
   * Os rótulos do cartão são os `header` das colunas e os valores são as mesmas
   * células: não há segunda fonte de verdade para formatar. Use `'scroll'` quando
   * a tabela for pequena e a grade for a informação (uma matriz, um calendário).
   */
  mobile?: 'cards' | 'scroll'
  /**
   * Congela a primeira coluna ao rolar na horizontal. Padrão: `true`.
   *
   * **Decisão, não gosto:** rolar para ver "R$ A Pagar" e perder de vista **de quem
   * é a linha** é o que torna rolagem horizontal insuportável numa tabela
   * financeira — o usuário volta ao começo só para reler o nome. A primeira coluna
   * destas listas é sempre a identificação (nome, portador, empresa), então
   * congelá-la é o que faz a rolagem valer a pena.
   *
   * Só entra em vigor **quando há transbordo de verdade** — sem rolagem, `sticky`
   * não teria efeito visual e ainda assim mudaria o realce de linha das 18 telas
   * que usam este componente. Tabela que cabe continua exatamente como estava.
   */
  stickyFirstColumn?: boolean
}

const alinhamento: Record<'left' | 'center' | 'right', string> = {
  left: 'text-left',
  center: 'text-center',
  right: 'text-right',
}

const numericas: ColumnVariant[] = ['number', 'money', 'percent']

function formatarPorVariante(valor: unknown, variant: ColumnVariant | undefined): React.ReactNode {
  if (variant === 'money') return formatMoney(valor as number)
  if (variant === 'percent') return formatPercent(valor as number)
  if (variant === 'number') return formatAmount(valor as number, 0)
  if (variant === 'date') return formatDate(valor as any)
  if (variant === 'datetime') return formatDateTime(valor as any)
  if (valor === null || valor === undefined || valor === '') return '—'
  return valor as React.ReactNode
}

/** Comparação estável: nulo sempre por último, texto com `localeCompare` pt-BR. */
function comparar(a: unknown, b: unknown): number {
  const vazioA = a === null || a === undefined || a === ''
  const vazioB = b === null || b === undefined || b === ''
  if (vazioA && vazioB) return 0
  if (vazioA) return 1
  if (vazioB) return -1
  if (typeof a === 'number' && typeof b === 'number') return a - b
  if (a instanceof Date && b instanceof Date) return a.getTime() - b.getTime()
  if (typeof a === 'boolean' && typeof b === 'boolean') return Number(a) - Number(b)
  return String(a).localeCompare(String(b), 'pt-BR', { numeric: true, sensitivity: 'base' })
}

/** O conteúdo de uma célula: `cell` vence a variante. Um lugar só — a tabela e o
 *  cartão do telefone leem daqui, para não existir segunda forma de formatar. */
function conteudoDaCelula<T>(col: Column<T>, row: T, index: number): React.ReactNode {
  if (col.cell) return col.cell(row, index)
  const pegar = col.accessor ?? ((r: T) => (r as any)?.[col.key])
  return formatarPorVariante(pegar(row), col.variant)
}

/**
 * A primeira cor de fundo **totalmente opaca** subindo a árvore.
 *
 * A célula congelada e a cortina precisam ser OPACAS — conteúdo rolado que se lê
 * por baixo delas é justamente o defeito que elas existem para evitar. Mas a cor
 * não pode ser cravada: quase toda tela põe a tabela num cartão (`--card`) e a
 * lista de operações de risco a põe direto na página (`--background`), que no modo
 * escuro é outro cinza. `bg-card` cravado deixaria um bloco de cor errada lá.
 *
 * `null` quando ninguém pintou nada — aí o CSS cai em `--card`, que é onde a
 * tabela vive na maioria das telas. Em ambiente sem layout `getComputedStyle`
 * devolve vazio, e a guarda é o que mantém a suíte em jsdom indiferente a isto.
 */
function superficieAtras(el: HTMLElement): string | null {
  let no: HTMLElement | null = el.parentElement
  while (no) {
    const cor = getComputedStyle(no).backgroundColor
    // **Opacidade TOTAL, não "alguma cor".** A primeira versão aceitava qualquer
    // alfa acima de zero e pegava um `bg-muted/20` da lista de operações de risco:
    // a coluna congelada saiu 20% opaca sobre o conteúdo rolado, ou seja, sem
    // resolver nada. `rgb(...)` já é opaco; `rgba(...)` só vale com alfa 1.
    if (cor && /^rgb\([^)]*\)$/.test(cor)) return cor
    if (cor && /^rgba\([^)]*,\s*1\s*\)$/.test(cor)) return cor
    no = no.parentElement
  }
  return null
}

interface Transbordo {
  esquerda: boolean
  direita: boolean
  /**
   * Quantos pixels de coluna estão aparecendo cortados em cada borda. É a largura
   * exata da cortina que os cobre — ver `useTransbordoHorizontal`.
   */
  sobra: number
  sobraEsquerda: number
  /** Largura da primeira coluna, para o `scroll-padding-left` do encaixe. */
  larguraFixa: number
  /** A cor de fundo real atrás da tabela — ver `superficieAtras`. */
  superficie: string | null
}

/**
 * Mede se sobrou conteúdo fora da área visível, e de que lado.
 *
 * É a peça que faz a rolagem **aparecer**: sem medição não há como mostrar a
 * sombra só quando ela significa alguma coisa — e sombra que fica lá o tempo todo
 * deixa de ser aviso e vira enfeite, inclusive quando o usuário já chegou ao fim.
 *
 * Ouve `scroll` (o lado muda a cada rolagem) **e** `ResizeObserver` no container e
 * na própria tabela: uma coluna que cresce quando o dado chega muda o transbordo
 * sem que ninguém role e sem que o container mude de tamanho.
 *
 * Em jsdom `scrollWidth`/`clientWidth` são 0 e `ResizeObserver` pode não existir:
 * o resultado é "sem transbordo", que é o estado neutro — nenhuma suíte muda.
 */
function useTransbordoHorizontal(
  ref: React.RefObject<HTMLDivElement>,
  quando: React.DependencyList,
): Transbordo {
  const [transbordo, setTransbordo] = React.useState<Transbordo>({
    esquerda: false,
    direita: false,
    sobra: 0,
    sobraEsquerda: 0,
    larguraFixa: 0,
    superficie: null,
  })

  React.useEffect(() => {
    const el = ref.current
    if (!el) return

    const medir = () => {
      const restaDireita = el.scrollWidth - el.clientWidth - el.scrollLeft
      const bordaVisivel = el.scrollLeft + el.clientWidth
      const cabecalhos = Array.from(el.querySelectorAll<HTMLTableCellElement>('thead > tr > th'))

      // **Quanto de coluna está espiando cortado em cada borda.** `offsetLeft` é
      // medido no sistema de coordenadas do CONTEÚDO (não desconta a rolagem), então
      // dá para comparar direto com a janela visível `[inicioUtil, bordaVisivel]`.
      //
      // Teto de 45% nas duas: numa coluna larguíssima é melhor mostrá-la cortada com
      // sombra do que apagar metade da tela.
      const teto = el.clientWidth * 0.45

      // Direita: a primeira coluna que TERMINA depois da borda é a partida, e o
      // pedaço visível dela é `bordaVisivel - offsetLeft`.
      let sobra = 0
      if (restaDireita > 1) {
        const partida = cabecalhos.find((th) => th.offsetLeft + th.offsetWidth > bordaVisivel + 0.5)
        if (partida) sobra = Math.min(Math.max(bordaVisivel - partida.offsetLeft, 0), teto)
      }

      // Esquerda: o começo da área ÚTIL é depois da coluna congelada. A coluna que
      // contém esse ponto está com o começo escondido por baixo dela — e meio valor
      // à esquerda é ainda pior que à direita, porque `2.500,00` cortado vira
      // `500,00`, um número plausível. O encaixe zera isto na maior parte das
      // posições; sobra o fim da rolagem, que é sempre alcançável e nem sempre é
      // ponto de encaixe.
      let sobraEsquerda = 0
      if (el.scrollLeft > 1) {
        const inicioUtil = el.scrollLeft + (cabecalhos[0]?.offsetWidth ?? 0)
        const partida = cabecalhos.find(
          (th, i) => i > 0 && th.offsetLeft < inicioUtil - 0.5 && th.offsetLeft + th.offsetWidth > inicioUtil + 0.5,
        )
        if (partida) {
          sobraEsquerda = Math.min(partida.offsetLeft + partida.offsetWidth - inicioUtil, teto)
        }
      }

      const proximo: Transbordo = {
        esquerda: el.scrollLeft > 1,
        direita: restaDireita > 1,
        sobra: Math.round(sobra),
        sobraEsquerda: Math.round(sobraEsquerda),
        larguraFixa: Math.round(cabecalhos[0]?.offsetWidth ?? 0),
        superficie: superficieAtras(el),
      }
      setTransbordo((atual) =>
        atual.esquerda === proximo.esquerda &&
        atual.direita === proximo.direita &&
        atual.sobra === proximo.sobra &&
        atual.sobraEsquerda === proximo.sobraEsquerda &&
        atual.larguraFixa === proximo.larguraFixa &&
        atual.superficie === proximo.superficie
          ? atual
          : proximo,
      )
    }

    medir()
    el.addEventListener('scroll', medir, { passive: true })

    const observador = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(medir) : null
    observador?.observe(el)
    if (el.firstElementChild) observador?.observe(el.firstElementChild)

    // **Trocar de tema muda a superfície.** Sem isto a coluna congelada guardava a
    // cor medida no modo anterior — visto renderizando: em `/risk-operations` a
    // primeira coluna ficava clara sobre a tabela escura, porque nada tinha rolado
    // nem redimensionado desde a troca. `class` no `<html>` é onde o tema mora.
    const observadorDeTema =
      typeof MutationObserver !== 'undefined'
        ? new MutationObserver(() => setTransbordo((atual) => ({ ...atual, superficie: superficieAtras(el) })))
        : null
    observadorDeTema?.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] })

    return () => {
      el.removeEventListener('scroll', medir)
      observador?.disconnect()
      observadorDeTema?.disconnect()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, quando)

  return transbordo
}

export function DataTable<T>({
  columns,
  data,
  rowKey,
  loading,
  error,
  onRetry,
  sortMode = 'client',
  sort,
  defaultSort = null,
  onSortChange,
  onRowClick,
  emptyTitle = 'Nenhum registro encontrado',
  emptyDescription,
  emptyAction,
  loadingLabel,
  caption,
  className,
  layout = 'auto',
  mobile = 'cards',
  stickyFirstColumn = true,
}: DataTableProps<T>) {
  const [sortInterno, setSortInterno] = React.useState<SortState | null>(defaultSort)
  const sortAtual = sort !== undefined ? sort : sortInterno

  const alternar = (col: Column<T>) => {
    if (!col.sortable) return
    // asc → desc → sem ordenação. O terceiro clique volta à ordem do servidor,
    // que é a única maneira de o usuário desfazer uma ordenação.
    const proximo: SortState | null =
      sortAtual?.key !== col.key
        ? { key: col.key, direction: 'asc' }
        : sortAtual.direction === 'asc'
          ? { key: col.key, direction: 'desc' }
          : null
    if (sort === undefined) setSortInterno(proximo)
    onSortChange?.(proximo, col.key)
  }

  const estreito = useMobile()
  const emCartoes = mobile === 'cards' && estreito
  const rolagemRef = React.useRef<HTMLDivElement>(null)
  const transbordo = useTransbordoHorizontal(rolagemRef, [data, columns, layout, emCartoes])
  // `sticky` só quando há rolagem de verdade: sem transbordo ele não teria efeito
  // visual e ainda assim mexeria no realce de linha das 18 telas que usam isto.
  const fixarPrimeira = stickyFirstColumn && (transbordo.esquerda || transbordo.direita)
  // **Arrastar para rolar** — a afordância que sobrevive onde a barra não é
  // pintada (iOS, headless). Ligada só quando há transbordo MEDIDO, pela mesma
  // razão da coluna congelada: numa tabela que cabe, o cursor de arraste seria
  // uma promessa que a tela não cumpre.
  const arraste = useDragToScroll(rolagemRef, {
    enabled: transbordo.esquerda || transbordo.direita,
  })
  // O encaixe de rolagem para a coluna colada no começo da área ÚTIL, que com a
  const colunasDoCartao = React.useMemo(() => columns.filter((c) => !c.hideOnMobile), [columns])

  const linhas = React.useMemo(() => {
    if (!data) return data
    if (sortMode !== 'client' || !sortAtual) return data
    const col = columns.find((c) => c.key === sortAtual.key)
    if (!col?.sortable) return data
    const pegar = col.accessor ?? ((row: T) => (row as any)?.[col.key])
    const fator = sortAtual.direction === 'asc' ? 1 : -1
    // Cópia: ordenar o array recebido mutaria o cache do React Query.
    return [...data].sort((a, b) => comparar(pegar(a), pegar(b)) * fator)
  }, [data, sortAtual, sortMode, columns])

  return (
    <AsyncSection
      className={className}
      loading={loading}
      error={error}
      data={linhas}
      onRetry={onRetry}
      emptyTitle={emptyTitle}
      emptyDescription={emptyDescription}
      emptyAction={emptyAction}
      loadingLabel={loadingLabel}
    >
      {(rows) =>
        emCartoes ? (
          // **O telefone não recebe a tabela encolhida.** Ver a prop `mobile`.
          <ul className="flex flex-col gap-3" aria-label={caption}>
            {rows.map((row, i) => (
              <li key={rowKey(row, i)}>
                <CartaoDaLinha
                  columns={colunasDoCartao}
                  row={row}
                  index={i}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                />
              </li>
            ))}
          </ul>
        ) : (
        <div className="relative">
          <Table
            wrapperRef={rolagemRef}
            wrapperProps={{
              // `table-scroll-x` devolve a barra que o `globals.css` apaga no app
              // começo da área útil — que, com a primeira congelada, é depois dela,
              // e é o que o `scrollPaddingLeft` abaixo informa. O lado direito quem
              // resolve é a cortina.
              className: cn('table-scroll-x', arraste.className),
              'data-table-scroll': '',
              // Enquanto se arrasta, o cursor de "agarrado" tem de valer para a
              // tabela INTEIRA — a linha clicável declara `cursor-pointer` e
              // ganharia do container por ser mais específica. A regra
              // `[data-table-dragging]` em `globals.css` resolve num lugar só.
              ...(arraste.dragging ? { 'data-table-dragging': '' } : {}),
              ...arraste.handlers,
              style: {
                ...(transbordo.superficie ? { '--table-surface': transbordo.superficie } : {}),
                ...arraste.style,
              } as React.CSSProperties,
              // WCAG 2.1.1: região que rola tem de ser alcançável pelo teclado.
              // Só quando ela rola de fato — parada de tabulação sem função é ruído.
              ...(transbordo.esquerda || transbordo.direita
                ? { role: 'region', tabIndex: 0, 'aria-label': caption ?? 'Tabela com rolagem horizontal' }
                : {}),
            }}
            className={layout === 'fixed' ? 'table-fixed' : undefined}
          >
          {caption && <caption className="sr-only">{caption}</caption>}
          <TableHeader>
            <TableRow>
              {columns.map((col, indiceColuna) => {
                const align = col.align ?? (numericas.includes(col.variant as ColumnVariant) ? 'right' : 'left')
                const ordenadaPor = sortAtual?.key === col.key
                return (
                  <TableHead
                    key={col.key}
                    style={col.width ? { width: col.width } : undefined}
                    aria-sort={
                      col.sortable
                        ? ordenadaPor
                          ? sortAtual!.direction === 'asc'
                            ? 'ascending'
                            : 'descending'
                          : 'none'
                        : undefined
                    }
                    className={cn(
                      alinhamento[align],
                      // A identificação da linha não sai da tela. A COR vem da
                      // regra de `data-sticky-col` em `globals.css`, que lê a
                      // superfície MEDIDA — ver `superficieAtras`.
                      //
                      // `z-10` de propósito, ABAIXO do `z-sticky` (20) do
                      // `PageHeader`: a célula fixa só precisa cobrir as células
                      // vizinhas da própria tabela. No mesmo degrau do cabeçalho
                      // de página ela passaria por cima dele ao rolar, porque no
                      // empate vence quem vem depois no DOM.
                      fixarPrimeira && indiceColuna === 0 && 'sticky left-0 z-10',
                      fixarPrimeira &&
                        indiceColuna === 0 &&
                        transbordo.esquerda &&
                        'shadow-sticky-col',
                      col.headerClassName,
                    )}
                    {...(fixarPrimeira && indiceColuna === 0 ? { 'data-sticky-col': '' } : {})}
                  >
                    {col.sortable ? (
                      <button
                        type="button"
                        onClick={() => alternar(col)}
                        className={cn(
                          // `uppercase` explícito: o preflight do Tailwind zera
                          // `text-transform` em `button` ("removes the
                          // inheritance of text transform in Edge and Firefox"),
                          // então a coluna ORDENÁVEL saía em caixa mista ao lado
                          // das não-ordenáveis em versalete. Descoberto
                          // renderizando a primeira listagem de verdade — o
                          // type-check passa limpo com o cabeçalho desalinhado.
                          'inline-flex items-center gap-1 rounded-sm text-inherit uppercase tracking-[0.05em] transition-colors hover:text-foreground',
                          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                          align === 'right' && 'flex-row-reverse',
                          ordenadaPor && 'text-foreground',
                        )}
                      >
                        {col.header}
                        {ordenadaPor ? (
                          sortAtual!.direction === 'asc' ? (
                            <ArrowUp aria-hidden="true" className="h-3 w-3" />
                          ) : (
                            <ArrowDown aria-hidden="true" className="h-3 w-3" />
                          )
                        ) : (
                          // Ícone neutro e apagado: sinaliza "dá para ordenar"
                          // sem competir com a coluna que está ordenada.
                          <ChevronsUpDown aria-hidden="true" className="h-3 w-3 opacity-40" />
                        )}
                      </button>
                    ) : (
                      // Sem `sortable` não há botão, cursor nem hover: a coluna
                      // não parece ordenável porque não é.
                      <span>{col.header}</span>
                    )}
                  </TableHead>
                )
              })}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row, i) => (
              <TableRow
                key={rowKey(row, i)}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
                tabIndex={onRowClick ? 0 : undefined}
                onKeyDown={
                  onRowClick
                    ? (e) => {
                        if (e.key === 'Enter') onRowClick(row)
                      }
                    : undefined
                }
                className={cn(
                  onRowClick && 'cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
                  // Com coluna fixa o realce da linha precisa ser OPACO: o
                  // `hover:bg-muted/50` do `Table` é translúcido e a célula fixa,
                  // que é opaca por obrigação, ficaria de outra cor no hover.
                  fixarPrimeira && 'group/row hover:bg-muted',
                )}
              >
                {columns.map((col, indiceColuna) => {
                  const align = col.align ?? (numericas.includes(col.variant as ColumnVariant) ? 'right' : 'left')
                  return (
                    <TableCell
                      key={col.key}
                      className={cn(
                        alinhamento[align],
                        fixarPrimeira &&
                          indiceColuna === 0 &&
                          'sticky left-0 z-10 group-hover/row:bg-muted',
                        fixarPrimeira &&
                          indiceColuna === 0 &&
                          transbordo.esquerda &&
                          'shadow-sticky-col',
                        // Número e data em fonte numérica: é o que faz a coluna
                        // alinhar dígito com dígito.
                        (numericas.includes(col.variant as ColumnVariant) ||
                          col.variant === 'date' ||
                          col.variant === 'datetime') &&
                          'font-numeric tabular-nums',
                        col.cellClassName,
                      )}
                      {...(fixarPrimeira && indiceColuna === 0 ? { 'data-sticky-col': '' } : {})}
                    >
                      {conteudoDaCelula(col, row, i)}
                    </TableCell>
                  )
                })}
              </TableRow>
            ))}
          </TableBody>
          </Table>

          {/* **As cortinas SAÍRAM (26/08/2026), e a decisão é do usuário vendo a tela.**

              Elas eram dois blocos opacos, do tamanho exato do pedaço de coluna que
              sobrava em cada borda. A intenção era boa — meia célula é perigosa,
              porque `R$ 2…` pode ser lido como dois reais. O resultado foi pior que
              o problema: o usuário mandou três capturas, em três estados diferentes,
              e nas três a tabela **parecia quebrada**. Rolando, a cortina da esquerda
              abria um vão entre a coluna congelada e o resto, e a tabela lia como
              **duas tabelas separadas**, cada uma com sua barra. Parada, a da direita
              deixava um **retângulo branco** encostado na última coluna — palavras
              dele: *"esse quadrado branco estranho, nada a ver"*.

              A lição: **meia célula é ruim, mas é LEGÍVEL COMO CORTE** — o olho
              entende que o conteúdo continua. Um retângulo opaco não é legível como
              nada; lê como falha de renderização, e falha de renderização derruba a
              confiança na tela inteira, inclusive nos números que estão certos.

              O que avisa que a tabela continua passa a ser o que o usuário aprovou no
              `apl9`: a **barra fina flutuante** e o **arrastar para rolar**. A sombra
              lateral da coluna congelada continua marcando a divisa. */}
        </div>
        )
      }
    </AsyncSection>
  )
}

/**
 * A linha da tabela como **cartão**, no telefone.
 *
 * O cabeçalho da coluna vira rótulo e a célula vira valor — mesma formatação da
 * tabela (`conteudoDaCelula`), sem segunda fonte de verdade. A primeira coluna
 * vira o título do cartão quando ela é texto simples, que é o caso de todas as
 * listas deste app (nome, portador, empresa).
 *
 * O contêiner é o `MobileCard` da biblioteca — dele vêm a superfície, o raio, a
 * elevação e, o que importa mais, o comportamento de clique acessível (papel de
 * botão, foco visível, Enter e Espaço). Reescrever isso aqui seria a décima quarta
 * cópia do mesmo cartão.
 */
function CartaoDaLinha<T>({
  columns,
  row,
  index,
  onClick,
}: {
  columns: Column<T>[]
  row: T
  index: number
  onClick?: () => void
}) {
  const [primeira, ...demais] = columns
  const bruto = primeira ? (primeira.accessor ? primeira.accessor(row) : (row as any)?.[primeira.key]) : undefined
  const titulo = typeof bruto === 'string' || typeof bruto === 'number' ? String(bruto) : undefined
  // Sem título de texto a primeira coluna continua no corpo: some do cartão,
  // nunca — coluna escondida no telefone é coluna que o usuário não descobre.
  const campos = titulo === undefined ? columns : demais

  return (
    <MobileCard className="mb-0" title={titulo} onClick={onClick}>
      <dl className="grid grid-cols-2 gap-x-3 gap-y-2 text-sm">
        {campos.map((col) => {
          const numerica =
            numericas.includes(col.variant as ColumnVariant) ||
            col.variant === 'date' ||
            col.variant === 'datetime'
          return (
            <div
              key={col.key}
              className={cn(
                'min-w-0',
                // **Moeda ocupa a largura inteira do cartão.** Visto renderizando a
                // 390×844: em duas colunas, `R$ 1.204.000,00` quebrava depois do
                // penúltimo dígito e a linha de baixo mostrava só `0`. Número
                // partido em duas linhas é a mesma família do número cortado que
                // originou esta tarefa — e num sistema de crédito é ele que decide.
                col.variant === 'money' && 'col-span-2',
              )}
            >
              <dt className="truncate text-xs uppercase tracking-[0.05em] text-muted-foreground">{col.header}</dt>
              <dd
                className={cn(
                  'text-foreground',
                  // Texto pode quebrar; número, não.
                  numerica ? 'whitespace-nowrap font-numeric tabular-nums' : 'break-words',
                )}
              >
                {conteudoDaCelula(col, row, index)}
              </dd>
            </div>
          )
        })}
      </dl>
    </MobileCard>
  )
}
