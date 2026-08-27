import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * **Grade masonry que preserva a ordem de leitura.**
 *
 * Numa grade comum, cada linha fica com a altura do item mais alto e os menores
 * sobram com um vazio embaixo. Num painel — onde um bloco tem quatro medidores
 * e o vizinho tem uma linha só — isso vira buraco no meio da tela.
 *
 * ## Por que não uma biblioteca — a decisão foi MEDIDA, não presumida
 *
 * As três candidatas foram baixadas e o algoritmo de distribuição lido:
 *
 * | Candidata | Como distribui | Serve? |
 * | --------- | -------------- | ------ |
 * | `react-masonry-css` 1.0.16 | `columnIndex = i % columnCount` — **rodízio por índice** | **Não.** Distribui, mas não empacota por ALTURA: com o item 1 alto, o 3 fica embaixo dele de qualquer jeito e o buraco continua. É exatamente o problema que viemos resolver |
 * | `react-plock` 3.6.1 | rodízio por padrão; `useBalancedLayout` joga cada item na coluna mais curta | **Não.** O modo que empacota **reordena entre colunas pela altura** — o Total operado iria parar onde o balanceador quisesse, e a ordem de leitura é requisito duro aqui |
 * | `masonic` 4.1.0 | mede e posiciona em absoluto, **virtualizado** | **Não.** Virtualização desmonta o que sai da tela: num painel de 4 blocos com gráfico Recharts e assinatura de React Query vivos, é custo sem benefício e risco de correção |
 *
 * `columns` do CSS está fora pelo mesmo motivo que a primeira linha da tabela,
 * e pior: preenche **coluna por coluna** (todos os itens da coluna 1 de cima a
 * baixo, depois a 2), então o segundo cartão fica **embaixo** do primeiro em vez
 * de ao lado. `grid-template-rows: masonry` resolveria nativamente e **ainda
 * não tem suporte para usar**.
 *
 * Sobra o CSS Grid, e ele é a **única** opção que faz as duas coisas ao mesmo
 * tempo: empacota por altura **e** mantém o posicionamento automático do Grid,
 * que é o que garante que o item *n* nunca renderize antes do *n−1*. Para 6–8
 * blocos, 140 linhas sem dependência é a engenharia certa — não é contorno.
 *
 * ## Como funciona
 *
 * Linhas finas (`grid-auto-rows` de poucos píxeis) e cada item declarando
 * quantas linhas ocupa, medido por `ResizeObserver`. O item só sobe para o
 * espaço livre da coluna que terminou antes; a ordem do DOM decide o resto.
 *
 * `align-items: start` é o que impede o laço de realimentação: sem ele o item
 * esticaria até a altura da área que o próprio `span` definiu, o
 * `ResizeObserver` mediria essa altura e o `span` cresceria sozinho.
 *
 * ## Coluna única
 *
 * Quando o CSS resolve **uma** coluna (o telefone), os `span` são desligados e a
 * grade volta a `auto`: com uma coluna não há o que empacotar, e as linhas finas
 * só arredondariam a altura de cada bloco para cima.
 *
 * ## O que este componente NÃO faz
 *
 * Não define altura de card. Altura chumbada corta conteúdo no primeiro texto
 * mais longo — o oposto do problema que ele veio resolver.
 */
export interface MasonryGridProps {
  children: React.ReactNode
  /** As colunas vêm daqui, em classes (`xl:grid-cols-2`). */
  className?: string
  /** Altura da linha fina, em px. Menor = empacotamento mais justo. */
  rowHeight?: number
  /** Precisa bater com o `gap` das classes — é ele que entra na conta do span. */
  gap?: number
}

/** Quantas colunas o CSS resolveu, lido do próprio elemento. */
function useColunas(ref: React.RefObject<HTMLDivElement>) {
  const [colunas, setColunas] = React.useState(1)

  React.useEffect(() => {
    const el = ref.current
    if (!el) return

    const medir = () => {
      const template = getComputedStyle(el).gridTemplateColumns || ''
      const n = template.split(' ').filter((p) => p.trim().length > 0).length
      setColunas(Math.max(1, n))
    }

    medir()
    if (typeof ResizeObserver === 'undefined') return
    const observador = new ResizeObserver(medir)
    observador.observe(el)
    return () => observador.disconnect()
  }, [ref])

  return colunas
}

function MasonryItem({
  children,
  rowHeight,
  gap,
  ativo,
}: {
  children: React.ReactNode
  rowHeight: number
  gap: number
  ativo: boolean
}) {
  const ref = React.useRef<HTMLDivElement>(null)
  const [span, setSpan] = React.useState<number | null>(null)

  React.useLayoutEffect(() => {
    const el = ref.current
    if (!el || !ativo) {
      setSpan(null)
      return
    }

    const medir = () => {
      const altura = el.getBoundingClientRect().height
      if (altura <= 0) return
      setSpan(Math.max(1, Math.ceil((altura + gap) / (rowHeight + gap))))
    }

    medir()
    if (typeof ResizeObserver === 'undefined') return
    // Observa o CONTEÚDO, não a área da grade: o conteúdo muda quando o painel
    // abre a tabela de valores, quando o gráfico recebe dado, quando o texto
    // quebra em outra largura.
    const observador = new ResizeObserver(medir)
    observador.observe(el)
    return () => observador.disconnect()
  }, [ativo, rowHeight, gap])

  // **`min-w-0` não é enfeite.** Item de grade nasce com `min-width: auto`, que
  // é o tamanho mínimo do conteúdo: um filho com colunas em `fr` calcula contra
  // uma largura que a coluna não tem e **transborda para a coluna vizinha**.
  // Visto na tela: a fileira de KPIs invadiu o gráfico e o empacotamento inteiro
  // saiu do lugar.
  return (
    <div ref={ref} className="min-w-0" style={ativo && span ? { gridRowEnd: `span ${span}` } : undefined}>
      {children}
    </div>
  )
}

export function MasonryGrid({ children, className, rowHeight = 8, gap = 16 }: MasonryGridProps) {
  const ref = React.useRef<HTMLDivElement>(null)
  const colunas = useColunas(ref)
  const ativo = colunas > 1

  return (
    <div
      ref={ref}
      className={cn('grid items-start gap-4', className)}
      style={ativo ? { gridAutoRows: `${rowHeight}px` } : undefined}
    >
      {React.Children.map(children, (filho) =>
        filho == null || filho === false ? null : (
          <MasonryItem rowHeight={rowHeight} gap={gap} ativo={ativo}>
            {filho}
          </MasonryItem>
        ),
      )}
    </div>
  )
}
