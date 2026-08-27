import * as React from 'react'

/**
 * **Arrastar para rolar** — a afordância que funciona onde a barra NÃO aparece.
 *
 * ## Por que existe
 *
 * A DS-01 devolveu a barra de rolagem horizontal da tabela (`.table-scroll-x`),
 * que o `globals.css` apaga no app inteiro. Ela resolve o desktop com mouse —
 * e não resolve dois casos que continuam sendo o dia a dia do usuário:
 *
 * - **o iOS nunca mostra barra persistente**: lá a barra é overlay do sistema e
 *   some sozinha. Nenhum CSS traz ela de volta;
 * - **no Chromium headless a barra reserva 0 px e não é pintada**, então a
 *   afordância que a DS-01 acrescentou **não é comprovável renderizando**.
 *
 * Arrastar o conteúdo com o mouse é a afordância que sobra: ela não depende de
 * o sistema desenhar coisa alguma, e é o tratamento do `apl9` que o usuário
 * aprovou (`apl9/frontend/src/app/pages/UserProfilePage.tsx:14-47`).
 *
 * ## O que muda em relação ao `apl9`
 *
 * Lá o hook é **inline numa página**, e a página o instancia três vezes. Aqui
 * ele é membro da biblioteca porque quem vai usá-lo é o `DataTable` — **18
 * telas**. Três diferenças, todas por causa disso:
 *
 * 1. **Limiar.** O `apl9` rola no primeiro pixel de movimento; a página dele não
 *    tem linha clicável. Aqui a linha tem `onRowClick`, e um tremor de 3 px do
 *    mouse durante um clique viraria rolagem — ou, pior, o clique da linha
 *    dispararia no fim de um arrasto de 40 px e a tela abriria um registro que o
 *    usuário não pediu. O gesto só vira rolagem depois de `threshold` px, e o
 *    clique que nasce de um arrasto é **engolido** (ver `onClickCapture`).
 * 2. **`clientX`, não `pageX`.** O `apl9` faz `e.pageX - el.offsetLeft`; o
 *    `offsetLeft` é constante durante o gesto, então subtraí-lo não muda nada —
 *    o que importa é a DIFERENÇA entre dois pontos. `clientX` dá a mesma
 *    diferença, e a página deste app nunca rola na horizontal (§5.4.8, regra 3).
 * 3. **`enabled`.** Cursor de "arraste-me" numa tabela que **cabe** na tela é
 *    promessa falsa. O `DataTable` só liga o hook quando há transbordo medido —
 *    a mesma regra da coluna congelada da DS-01.
 *
 * O `speed: 2` é o do `apl9` (`walk = (x - startX) * 2`) e fica: com 1:1 o
 * gesto acaba na borda da tela antes de a tabela de treze colunas terminar.
 */
export interface UseDragToScrollOptions {
  /** Sem transbordo não há o que arrastar — e cursor de arraste seria mentira. */
  enabled?: boolean
  /** Multiplicador do deslocamento. Padrão `2`, o do `apl9`. */
  speed?: number
  /**
   * Distância, em px, a partir da qual o gesto deixa de ser clique e vira
   * rolagem. Padrão `5`: um arrasto de 3 px é clique, um de 40 px é rolagem.
   */
  threshold?: number
}

export interface DragToScroll {
  /** Verdadeiro só DEPOIS do limiar — antes dele o gesto ainda pode ser clique. */
  dragging: boolean
  /** Para espalhar no container que rola. */
  handlers: {
    onMouseDown: (evento: React.MouseEvent) => void
    onMouseMove: (evento: React.MouseEvent) => void
    onMouseUp: () => void
    onMouseLeave: () => void
    onClickCapture: (evento: React.MouseEvent) => void
  }
  /** Cursor e supressão de seleção de texto. Vazio quando `enabled` é falso. */
  className: string
  /**
   * `scroll-snap-type: none` enquanto se arrasta — em linha, de propósito: o
   * encaixe mora numa classe (`.table-snap-x`) e classe contra classe é empate
   * de especificidade, decidido pela ordem do CSS gerado. Estilo em linha não
   * depende dessa ordem.
   */
  style: React.CSSProperties | undefined
}

/**
 * Um arrasto que COMEÇA num controle é do controle, não da rolagem: apertar um
 * checkbox e mexer o mouse 6 px não pode virar rolagem, e o `preventDefault` do
 * movimento mataria o clique dele.
 */
const INTERACTIVE_SELECTOR =
  'a,button,input,select,textarea,label,summary,[role="button"],[role="checkbox"],[role="menuitem"],[contenteditable="true"]'

export function useDragToScroll(
  ref: React.RefObject<HTMLElement | null>,
  { enabled = true, speed = 2, threshold = 5 }: UseDragToScrollOptions = {},
): DragToScroll {
  const [dragging, setDragging] = React.useState(false)

  const gesture = React.useRef({
    active: false,
    startX: 0,
    startScrollLeft: 0,
    passedThreshold: false,
  })
  /** O clique que nasce de um arrasto não é clique — ver `onClickCapture`. */
  const swallowNextClick = React.useRef(false)

  // Desligar no meio de um gesto (a tabela encolheu, o dado mudou) tem de
  // devolver o cursor e liberar a seleção de texto.
  React.useEffect(() => {
    if (enabled) return
    gesture.current.active = false
    gesture.current.passedThreshold = false
    setDragging(false)
  }, [enabled])

  const finish = React.useCallback(() => {
    if (!gesture.current.active) return
    gesture.current.active = false
    if (gesture.current.passedThreshold) {
      // O navegador ainda vai emitir um `click` neste gesto — ele é o resto de
      // uma rolagem, não uma escolha do usuário.
      swallowNextClick.current = true
      gesture.current.passedThreshold = false
      setDragging(false)
    }
  }, [])

  const handlers = React.useMemo(
    () => ({
      onMouseDown: (evento: React.MouseEvent) => {
        if (!enabled) return
        // Só o botão principal. O do meio é rolagem automática do navegador e o
        // direito abre o menu de contexto.
        if (evento.button !== 0) return
        const el = ref.current
        if (!el) return
        if ((evento.target as HTMLElement | null)?.closest?.(INTERACTIVE_SELECTOR)) return
        // Um gesto novo começa limpo: sem isto uma bandeira deixada para trás
        // (arrasto cujo `click` nunca chegou) engoliria o clique seguinte.
        swallowNextClick.current = false
        gesture.current = {
          active: true,
          startX: evento.clientX,
          startScrollLeft: el.scrollLeft,
          passedThreshold: false,
        }
      },

      onMouseMove: (evento: React.MouseEvent) => {
        if (!gesture.current.active) return
        const el = ref.current
        if (!el) return
        const delta = evento.clientX - gesture.current.startX
        if (!gesture.current.passedThreshold) {
          // **Aqui mora a diferença entre clique e rolagem.** Abaixo do limiar
          // nada acontece: nem rolagem, nem `preventDefault`, nem supressão de
          // clique. O tremor de mão continua sendo um clique na linha.
          if (Math.abs(delta) < threshold) return
          gesture.current.passedThreshold = true
          setDragging(true)
        }
        // Sem isto o navegador começa a seleção de texto nativa e a tabela
        // inteira fica azul enquanto se arrasta.
        evento.preventDefault()
        el.scrollLeft = gesture.current.startScrollLeft - delta * speed
      },

      onMouseUp: finish,
      onMouseLeave: finish,

      onClickCapture: (evento: React.MouseEvent) => {
        if (!swallowNextClick.current) return
        swallowNextClick.current = false
        // Fase de CAPTURA, no container: o evento morre antes de chegar à linha,
        // então nem o `onClick` do `<tr>` nem o do `MobileCard` disparam. Fazer
        // isto no `onClick` do container seria tarde — a linha já teria agido.
        evento.preventDefault()
        evento.stopPropagation()
      },
    }),
    [enabled, ref, speed, threshold, finish],
  )

  return {
    dragging,
    handlers,
    className: !enabled ? '' : dragging ? 'cursor-grabbing select-none' : 'cursor-grab',
    style: dragging ? { scrollSnapType: 'none' } : undefined,
  }
}
