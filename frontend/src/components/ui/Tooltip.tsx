import React from 'react'
import { createPortal } from 'react-dom'

interface TooltipProps {
  content: React.ReactNode
  /** Lado preferido. Se não couber na tela, o tooltip vira para o oposto sozinho. */
  side?: 'right' | 'left' | 'top' | 'bottom'
  children: React.ReactNode
  disabled?: boolean
  className?: string
}

type Lado = NonNullable<TooltipProps['side']>

const GAP = 8
/** Respiro mínimo até a borda da janela. */
const MARGEM = 8

const OPOSTO: Record<Lado, Lado> = { right: 'left', left: 'right', top: 'bottom', bottom: 'top' }

/**
 * Tooltip do app — **renderizado em portal, sempre**.
 *
 * Por que portal e não `absolute` dentro do gatilho: a versão anterior era
 * `absolute` + `z-tooltip`, e sumia atrás da interface na sidebar recolhida.
 * O `z-index` não era o problema. O `<aside>` usa `.glass-panel`, que aplica
 * `backdrop-filter: blur()` — e `backdrop-filter` **cria um contexto de
 * empilhamento**. A partir dali, todo descendente fica preso ao `z-drawer` (55)
 * do próprio aside, por mais alto que seja o seu `z-index`. Subir o número não
 * resolveria; o teto não é o número.
 *
 * Além do empilhamento, `absolute` também é recortado por qualquer ancestral com
 * `overflow` — e o `<nav>` da sidebar é `overflow-y-auto`. Eram dois problemas
 * diferentes com o mesmo sintoma.
 *
 * Em `document.body` com `position: fixed`, o tooltip não tem ancestral que o
 * recorte nem que o aprisione. Vale para todos os consumidores de uma vez.
 *
 * ## Por que ele mede a si mesmo antes de aparecer
 *
 * A versão anterior calculava a posição **uma vez, sem perguntar se cabia**, e
 * empurrava o resto com `transform`. Num gatilho perto da borda direita — que é
 * o caso de toda coluna de valor alinhada à direita — o `side="right"` jogava o
 * tooltip **para fora da janela**, e o texto era cortado pela tela. Apareceu no
 * Painel de Disponibilidade, nos selos "Corrigido por dias úteis" e
 * "Consolidação": o usuário via meia frase e nenhuma rolagem trazia o resto,
 * porque `position: fixed` não gera rolagem.
 *
 * Agora são duas passadas: monta invisível, **mede o próprio tamanho**, e só
 * então decide. Se o lado preferido não couber, vira para o oposto; se nenhum
 * dos dois couber, fica no que tem mais espaço e é **grudado na borda** com uma
 * margem. Tooltip que não cabe é preferível deslocado a ilegível.
 */
export function Tooltip({ content, side = 'right', children, disabled, className = 'inline-block' }: TooltipProps) {
  const ref = React.useRef<HTMLDivElement>(null)
  const balaoRef = React.useRef<HTMLDivElement>(null)

  // `rect` é o gatilho no momento do hover; `pos` é o resultado já medido.
  const [rect, setRect] = React.useState<DOMRect | null>(null)
  const [pos, setPos] = React.useState<{ top: number; left: number } | null>(null)

  const show = React.useCallback(() => {
    const el = ref.current
    if (!el) return
    setRect(el.getBoundingClientRect())
  }, [])

  const hide = React.useCallback(() => {
    setRect(null)
    setPos(null)
  }, [])

  // Segunda passada: o balão já está no DOM (invisível), então dá para medi-lo.
  // `useLayoutEffect` para posicionar ANTES da pintura — com `useEffect` o
  // usuário veria o balão saltar do lugar errado para o certo.
  React.useLayoutEffect(() => {
    const balao = balaoRef.current
    if (!rect || !balao) return

    const { width: w, height: h } = balao.getBoundingClientRect()
    const vw = window.innerWidth
    const vh = window.innerHeight

    const paraLado = (l: Lado) => {
      switch (l) {
        case 'right':
          return { left: rect.right + GAP, top: rect.top + rect.height / 2 - h / 2 }
        case 'left':
          return { left: rect.left - GAP - w, top: rect.top + rect.height / 2 - h / 2 }
        case 'top':
          return { left: rect.left + rect.width / 2 - w / 2, top: rect.top - GAP - h }
        case 'bottom':
          return { left: rect.left + rect.width / 2 - w / 2, top: rect.bottom + GAP }
      }
    }

    const cabe = (p: { top: number; left: number }) =>
      p.left >= MARGEM && p.top >= MARGEM && p.left + w <= vw - MARGEM && p.top + h <= vh - MARGEM

    // Preferido; se não couber, o oposto; se nenhum couber, fica no preferido e
    // a fixação na borda resolve.
    const preferido = paraLado(side)
    const alternativo = paraLado(OPOSTO[side])
    const escolhido = cabe(preferido) ? preferido : cabe(alternativo) ? alternativo : preferido

    // Fixar na borda cobre o eixo cruzado também: um tooltip `top` num gatilho
    // colado na direita transborda na horizontal mesmo com o lado certo.
    const fixar = (v: number, tamanho: number, limite: number) =>
      Math.min(Math.max(MARGEM, v), Math.max(MARGEM, limite - tamanho - MARGEM))

    setPos({
      left: fixar(escolhido.left, w, vw),
      top: fixar(escolhido.top, h, vh),
    })
  }, [rect, side, content])

  // Rolar ou redimensionar com o tooltip aberto deixaria ele parado no lugar
  // errado, porque a posição foi calculada uma vez. Fechar é mais honesto que
  // recalcular a cada frame.
  React.useEffect(() => {
    if (!rect) return
    window.addEventListener('scroll', hide, true)
    window.addEventListener('resize', hide)
    return () => {
      window.removeEventListener('scroll', hide, true)
      window.removeEventListener('resize', hide)
    }
  }, [rect, hide])

  const ativo = !disabled && content && rect

  return (
    <div
      ref={ref}
      className={`relative ${className}`}
      onMouseEnter={show}
      onMouseLeave={hide}
      onFocus={show}
      onBlur={hide}
    >
      {children}
      {ativo &&
        createPortal(
          <div
            ref={balaoRef}
            role="tooltip"
            style={{
              position: 'fixed',
              top: pos?.top ?? 0,
              left: pos?.left ?? 0,
              // Invisível na primeira passada — e `hidden`, não `opacity: 0`,
              // porque ele ainda precisa ocupar espaço para ser medido.
              visibility: pos ? 'visible' : 'hidden',
              // O balão nunca é mais largo que a janela: sem isto, um texto longo
              // fica numa linha só e a fixação na borda não tem o que salvar.
              maxWidth: `calc(100vw - ${MARGEM * 2}px)`,
            }}
            className="pointer-events-none z-tooltip rounded-md border border-border bg-popover px-2 py-1 text-xs text-popover-foreground shadow-e2"
          >
            {content}
          </div>,
          document.body,
        )}
    </div>
  )
}
