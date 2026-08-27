import * as React from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

/**
 * FloatingPanel — a superfície flutuante ancorada da biblioteca.
 *
 * **Por que isto existe e por que todo dropdown novo tem que passar por aqui.**
 * A regressão que custou caro neste repo não foi de `z-index`: o `<aside>` da
 * sidebar usa `.glass-panel`, que aplica `backdrop-filter`, e `backdrop-filter`
 * **cria contexto de empilhamento**. A partir dali, todo descendente fica preso
 * ao `z-index` do ancestral — subir o número do filho não resolve, porque o
 * teto não é o número. E o `<nav>` da sidebar é `overflow-y-auto`, então um
 * painel `absolute` ainda seria **recortado** mesmo se o empilhamento estivesse
 * certo. São dois defeitos diferentes com o mesmo sintoma.
 *
 * A única correção que resolve os dois de uma vez é renderizar em **portal no
 * `document.body`** com `position: fixed`. Foi assim que o `Tooltip` foi
 * consertado, e este componente é a generalização daquela correção para todo
 * painel que precisa ficar **ancorado** a um gatilho (select, combobox,
 * datepicker, menu de ações).
 *
 * O painel usa `bg-popover`, que no escuro é três degraus acima do
 * `background` (9% → `card` 12% → `popover` 18%). Um painel com `bg-card` sobre
 * um card fica invisível — já aconteceu.
 */
export type FloatingSide = 'bottom' | 'top'
export type FloatingAlign = 'start' | 'end'

interface AnchorRect {
  top: number
  left: number
  width: number
  height: number
}

export interface UseAnchoredPanelOptions {
  open: boolean
  anchorRef: React.RefObject<HTMLElement>
  /** Lado preferido. Vira o oposto sozinho se não couber na viewport. */
  side?: FloatingSide
  align?: FloatingAlign
  /** Distância entre o gatilho e o painel, em px. */
  gap?: number
  /** Painel com a mesma largura do gatilho (padrão do select). */
  matchWidth?: boolean
  /** Altura máxima do painel; o disponível na tela ainda pode ser menor. */
  maxHeight?: number
}

/**
 * Calcula a posição do painel em coordenadas de viewport (`position: fixed`).
 *
 * Reposiciona em rolagem e redimensionamento em vez de fechar: um select que
 * fecha porque a página rolou 2px é pior do que um que acompanha. O cálculo
 * roda em `requestAnimationFrame` para não medir layout a cada evento.
 */
export function useAnchoredPanel({
  open,
  anchorRef,
  side = 'bottom',
  align = 'start',
  gap = 6,
  matchWidth = true,
  maxHeight = 288,
}: UseAnchoredPanelOptions) {
  const [style, setStyle] = React.useState<React.CSSProperties | null>(null)

  const measure = React.useCallback(() => {
    const el = anchorRef.current
    if (!el) return
    const r: AnchorRect = el.getBoundingClientRect()
    const vh = window.innerHeight
    const vw = window.innerWidth

    const espacoAbaixo = vh - (r.top + r.height) - gap - 8
    const espacoAcima = r.top - gap - 8
    // Vira para cima só quando embaixo não cabe E em cima cabe mais.
    const paraCima = side === 'top' ? espacoAcima > 120 : espacoAbaixo < 160 && espacoAcima > espacoAbaixo
    const altura = Math.max(120, Math.min(maxHeight, paraCima ? espacoAcima : espacoAbaixo))

    const largura = matchWidth ? r.width : undefined
    let left = align === 'start' ? r.left : r.left + r.width - (largura ?? 0)
    // Não deixa o painel sair da viewport pelas laterais.
    const larguraEfetiva = largura ?? 240
    left = Math.min(Math.max(8, left), Math.max(8, vw - larguraEfetiva - 8))

    setStyle({
      position: 'fixed',
      left,
      top: paraCima ? undefined : r.top + r.height + gap,
      bottom: paraCima ? vh - r.top + gap : undefined,
      width: largura,
      minWidth: matchWidth ? undefined : r.width,
      maxHeight: altura,
    })
  }, [anchorRef, side, align, gap, matchWidth, maxHeight])

  React.useLayoutEffect(() => {
    if (!open) {
      setStyle(null)
      return
    }
    measure()
    let frame = 0
    const onMove = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(measure)
    }
    // `true` na captura: pega rolagem de qualquer contêiner interno também.
    window.addEventListener('scroll', onMove, true)
    window.addEventListener('resize', onMove)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', onMove, true)
      window.removeEventListener('resize', onMove)
    }
  }, [open, measure])

  return style
}

export interface FloatingPanelProps extends React.HTMLAttributes<HTMLDivElement> {
  open: boolean
  anchorRef: React.RefObject<HTMLElement>
  side?: FloatingSide
  align?: FloatingAlign
  gap?: number
  matchWidth?: boolean
  maxHeight?: number
  /** Chamado em clique fora do painel e do gatilho, e em `Escape`. */
  onDismiss?: () => void
}

export const FloatingPanel = React.forwardRef<HTMLDivElement, FloatingPanelProps>(
  (
    { open, anchorRef, side, align, gap, matchWidth, maxHeight, onDismiss, className, children, style: styleProp, ...props },
    ref,
  ) => {
    const innerRef = React.useRef<HTMLDivElement>(null)
    React.useImperativeHandle(ref, () => innerRef.current as HTMLDivElement)
    const style = useAnchoredPanel({ open, anchorRef, side, align, gap, matchWidth, maxHeight })

    React.useEffect(() => {
      if (!open || !onDismiss) return
      const onPointer = (e: MouseEvent | TouchEvent) => {
        const alvo = e.target as Node
        if (innerRef.current?.contains(alvo)) return
        if (anchorRef.current?.contains(alvo)) return
        onDismiss()
      }
      const onKey = (e: KeyboardEvent) => {
        if (e.key === 'Escape') {
          e.stopPropagation()
          onDismiss()
        }
      }
      document.addEventListener('mousedown', onPointer)
      document.addEventListener('touchstart', onPointer)
      document.addEventListener('keydown', onKey)
      return () => {
        document.removeEventListener('mousedown', onPointer)
        document.removeEventListener('touchstart', onPointer)
        document.removeEventListener('keydown', onKey)
      }
    }, [open, onDismiss, anchorRef])

    if (!open || !style) return null

    return createPortal(
      <div
        ref={innerRef}
        style={{ ...style, ...styleProp }}
        className={cn(
          'z-popover flex flex-col overflow-hidden rounded-md border border-border bg-popover text-popover-foreground shadow-e3',
          'animate-in fade-in-0 zoom-in-95 duration-150',
          className,
        )}
        {...props}
      >
        {children}
      </div>,
      document.body,
    )
  },
)
FloatingPanel.displayName = 'FloatingPanel'
