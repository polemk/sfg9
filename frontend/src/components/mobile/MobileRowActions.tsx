import {
  useCallback,
  useEffect,
  useRef,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
  type RefObject,
} from 'react'
import { createPortal } from 'react-dom'
import { MoreHorizontal, X } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { FloatingPanel } from '@/components/ui/FloatingPanel'
import { useMobile } from '@/hooks/useMobile'
import { cn } from '@/lib/utils'

/**
 * **Ações de uma linha, no telefone** — DEC-100.
 *
 * Nasce na biblioteca compartilhada (`components/mobile/`), e não dentro de uma
 * tela, porque toda lista do Safegold tem o mesmo problema: a linha tem três a
 * cinco ações e a largura do telefone comporta uma. As duas saídas erradas já
 * existiam na base:
 *
 * - **menu suspenso** (`MobileMenuActions`): 44 px de alvo espremidos contra a
 *   borda direita, e a lista de ações é FIXA (ver/editar/excluir). Serve à tela
 *   para a qual foi escrita e a mais nenhuma;
 * - **tabela com `overflow-x`**: a coluna de ações fica fora da tela, e o
 *   usuário nunca descobre que ela existe.
 *
 * Aqui as ações são **declaradas** — cada tela diz as suas, com rótulo, ícone e
 * o motivo de estarem desabilitadas — e sobem numa **folha ancorada no rodapé**,
 * com alvos de 48 px, na zona que o polegar alcança.
 *
 * ### Três coisas que o componente garante
 *
 * 1. **A ação bloqueada aparece e diz por quê.** `disabledReason` vira texto
 *    visível embaixo do rótulo. Sumir com a ação é o que fazia o usuário do
 *    legado clicar em "Remover" e receber "removido com sucesso" sem nada ter
 *    sido removido (D-24).
 * 2. **Renderiza em portal, no `body`.** Uma folha flutuante presa dentro de um
 *    ancestral com `transform`/`backdrop-filter` fica atrás do conteúdo —
 *    §5.4.4 das convenções, o defeito do `SidebarModeToggle`.
 * 3. **Cor só por token.** `bg-popover`/`text-popover-foreground` na folha,
 *    `bg-modal-backdrop` no fundo: nasce certa nos dois modos, sem `dark:`.
 *
 * ### A folha é do TELEFONE. No desktop, o mesmo menu é um dropdown ancorado
 *
 * Achado do usuário (26/08/2026), sobre `/project-availabilities`: *"o `more` de
 * disponibilidade não faz sentido ser assim no desktop; no mobile faz, no
 * desktop tem que ser dropdown"*. Ele está certo, e o motivo é proporção: a
 * folha ocupa a metade de baixo da janela para oferecer **três** itens, e o
 * contexto — de que LINHA são essas ações — sai de vista junto. No telefone
 * esse mesmo tamanho é o acerto (é a zona do polegar, e a linha some de
 * qualquer jeito); em 1440 px é desperdício com perda de contexto.
 *
 * A correção é aqui, no componente, e **não na tela** — foi a lição do
 * `KpiCard`, remendado cinco vezes em cinco telas antes de alguém consertar no
 * lugar certo. Abaixo de 768 px (`useMobile`, o mesmo corte do `DataTable`)
 * continua sendo a folha; acima, é um menu ancorado no próprio botão "…".
 *
 * **O painel flutuante NÃO é novo.** É o `FloatingPanel` da biblioteca, que já
 * resolve o portal no `body`, a virada quando não cabe embaixo, o reposicionar
 * na rolagem e o fechar por clique fora — os mesmos problemas que o
 * `MobileMenuActions` (obsoleto) resolvia errado, com `absolute` preso ao
 * contexto de empilhamento do ancestral. Uma lista de ações, duas apresentações;
 * nunca duas listas.
 */
export interface MobileRowAction {
  key: string
  label: string
  icon?: ReactNode
  onSelect: () => void
  /** Ação destrutiva: recebe o token `destructive`. */
  destructive?: boolean
  /** Quando presente, a ação fica inerte E o motivo aparece embaixo do rótulo. */
  disabledReason?: string
}

export interface MobileRowActionsProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Cabeçalho da folha: o nome do registro sobre o qual as ações agem. */
  title: string
  subtitle?: string
  actions: MobileRowAction[]
  /** Rótulo do botão que abre a folha. */
  triggerLabel?: string
  className?: string
}

/**
 * **O gatilho, para o menu de desktop se ancorar nele.**
 *
 * Só o `MobileActionsSheet` precisa dela: o `MobileRowActions` renderiza o
 * próprio botão e conhece o seu elemento. Sem esta prop o desktop cai na folha —
 * que é exatamente o comportamento de hoje, então nenhuma tela que não a passe
 * muda de aparência.
 *
 * Numa tabela o "…" é por LINHA e a folha é uma só, no fim da página: a tela
 * guarda o botão clicado (`ancora.current = evento.currentTarget`) e passa esta
 * mesma `ref`. O painel só a lê enquanto está aberto.
 */
export interface AnchoredActionsProps {
  anchorRef?: RefObject<HTMLElement>
}

/**
 * **A folha sozinha, sem gatilho** — para quem já tem o seu.
 *
 * Existe por causa de um defeito real: o `MobileRowActions` renderiza o próprio
 * botão "…" quando está fechado, e quatro telas o usavam como folha controlada
 * no fim do arquivo, com o gatilho já dentro da linha ou do card. Resultado: um
 * botão "…" **órfão** sobrava no rodapé da página — visível inclusive com a
 * lista vazia, flutuando embaixo do estado de vazio.
 *
 * As duas formas de uso são legítimas e chegavam com **props idênticas**, então
 * o componente não tinha como distinguir. A saída não é um sinalizador que se
 * esquece de passar: são dois nomes.
 *
 * - `MobileRowActions` — dentro da linha/card: renderiza **gatilho + folha**.
 * - `MobileActionsSheet` — no fim da página: renderiza **só a folha**, e some
 *   por completo quando fechada.
 *
 * A folha é a mesma implementação nos dois: uma lista de ações que divergisse
 * entre os dois caminhos é exatamente o defeito do menu do legado, que ficava
 * vazio numa combinação e cheio noutra.
 */
export function MobileActionsSheet({
  open,
  onOpenChange,
  title,
  subtitle,
  actions,
  anchorRef,
}: Omit<MobileRowActionsProps, 'triggerLabel' | 'className'> & AnchoredActionsProps) {
  useEscapeToClose(open, onOpenChange)
  const estreito = useMobile()

  // Desktop COM âncora: menu suspenso preso ao botão da linha. Sem âncora não há
  // onde ancorar, e a folha continua sendo a resposta — é o que preserva a
  // aparência das telas que ainda não passam a `ref`.
  if (!estreito && anchorRef) {
    return (
      <MenuDeAcoes
        open={open}
        anchorRef={anchorRef}
        onOpenChange={onOpenChange}
        title={title}
        actions={actions}
      />
    )
  }

  if (!open) return null
  return createPortal(
    folhaDeAcoes({ onOpenChange, title, subtitle, actions }),
    document.body,
  )
}

/** Fechar no `Escape` é o mínimo de teclado que uma superfície flutuante deve. */
function useEscapeToClose(open: boolean, onOpenChange: (open: boolean) => void) {
  useEffect(() => {
    if (!open) return
    const aoTeclar = (evento: KeyboardEvent) => {
      if (evento.key === 'Escape') onOpenChange(false)
    }
    document.addEventListener('keydown', aoTeclar)
    return () => document.removeEventListener('keydown', aoTeclar)
  }, [open, onOpenChange])
}

export function MobileRowActions({
  open,
  onOpenChange,
  title,
  subtitle,
  actions,
  triggerLabel,
  className,
}: MobileRowActionsProps) {
  useEscapeToClose(open, onOpenChange)
  const estreito = useMobile()
  // O próprio botão é a âncora do menu de desktop — aqui não há o que a tela
  // precise passar.
  const gatilhoRef = useRef<HTMLButtonElement>(null)

  const gatilho = (
    <Button
      ref={gatilhoRef}
      variant="ghost"
      size="icon"
      aria-label={triggerLabel ?? `Ações de ${title}`}
      aria-haspopup={estreito ? 'dialog' : 'menu'}
      aria-expanded={open}
      // 48x48. O `size="icon"` do Button dá 40, e este é o **único** caminho para
      // editar e excluir a linha no telefone — critério 1 da §5.4.8 e o motivo de
      // a decisão ter tirado as ações da borda direita da tabela.
      className={cn('h-12 w-12', className)}
      onClick={(evento) => {
        evento.stopPropagation()
        onOpenChange(true)
      }}
    >
      <MoreHorizontal aria-hidden="true" className="h-5 w-5" />
    </Button>
  )

  if (!estreito) {
    return (
      <>
        {gatilho}
        <MenuDeAcoes
          open={open}
          anchorRef={gatilhoRef}
          onOpenChange={onOpenChange}
          title={title}
          actions={actions}
        />
      </>
    )
  }

  if (!open) return gatilho

  return (
    <>
      {gatilho}
      {createPortal(folhaDeAcoes({ onOpenChange, title, subtitle, actions }), document.body)}
    </>
  )
}

/**
 * **O menu suspenso do desktop** — as MESMAS ações, ancoradas no botão.
 *
 * Sem cabeçalho de propósito: no telefone o título existe porque a linha não
 * está mais visível; aqui ela está logo ali, e o menu nasce colado nela. O que
 * NÃO se perde da folha é o item bloqueado — ele continua aparecendo, com o
 * motivo escrito (D-24: sumir com a ação é o que fazia o usuário do legado
 * clicar em "Remover" e ler "removido com sucesso" sem nada ter sido removido).
 */
function MenuDeAcoes({
  open,
  anchorRef,
  onOpenChange,
  title,
  actions,
}: {
  open: boolean
  anchorRef: RefObject<HTMLElement>
  onOpenChange: (open: boolean) => void
  title: string
  actions: MobileRowAction[]
}) {
  const menuRef = useRef<HTMLDivElement | null>(null)
  const escolheuAcao = useRef(false)
  const fechar = useCallback(() => onOpenChange(false), [onOpenChange])

  /**
   * O painel só existe no SEGUNDO render (o `FloatingPanel` devolve `null` até
   * medir a âncora), então um `useEffect` sobre `open` acharia o menu vazio. A
   * `ref` de função é chamada quando o nó entra — que é o momento certo para
   * levar o foco ao primeiro item utilizável.
   */
  const aoMontar = useCallback((no: HTMLDivElement | null) => {
    menuRef.current = no
    no?.querySelector<HTMLElement>('[role="menuitem"]:not([disabled])')?.focus()
  }, [])

  // Fechar sem escolher devolve o foco ao gatilho — senão o teclado volta ao
  // começo do documento. Fechar ESCOLHENDO não devolve: a ação abre um diálogo
  // ou navega, e disputar o foco com ele é como se perde o foco de um formulário.
  useEffect(() => {
    if (!open) return
    escolheuAcao.current = false
    const ancora = anchorRef.current
    return () => {
      if (!escolheuAcao.current) ancora?.focus?.()
    }
  }, [open, anchorRef])

  /** Setas percorrem o menu, como em qualquer menu de aplicação. */
  const aoTeclar = (evento: ReactKeyboardEvent<HTMLDivElement>) => {
    if (evento.key !== 'ArrowDown' && evento.key !== 'ArrowUp') return
    evento.preventDefault()
    const itens = Array.from(
      menuRef.current?.querySelectorAll<HTMLElement>('[role="menuitem"]:not([disabled])') ?? [],
    )
    if (itens.length === 0) return
    const atual = itens.indexOf(document.activeElement as HTMLElement)
    const passo = evento.key === 'ArrowDown' ? 1 : -1
    itens[(atual + passo + itens.length) % itens.length].focus()
  }

  return (
    <FloatingPanel
      ref={aoMontar}
      open={open}
      anchorRef={anchorRef}
      align="end"
      matchWidth={false}
      maxHeight={380}
      onDismiss={fechar}
      role="menu"
      aria-label={`Ações de ${title}`}
      // **Largura FIXA de 240 px, e ela não é gosto.** O `useAnchoredPanel` só
      // conhece a largura do painel quando `matchWidth` está ligado; sem ela,
      // ele usa 240 como estimativa para não deixar o painel sair da janela.
      // Com uma largura livre (248 px, medidos), a estimativa erra por 8 px e o
      // menu encosta na borda direita da tela. Igualar a largura real à
      // estimativa acerta a conta sem tocar no componente compartilhado, que é
      // do `Select`, do `DatePicker` e do `Autocomplete` (Princípio 6b).
      className="w-[15rem] py-1"
      onKeyDown={aoTeclar}
    >
      {actions.map((acao) => {
        const bloqueada = Boolean(acao.disabledReason)
        return (
          <button
            key={acao.key}
            type="button"
            role="menuitem"
            disabled={bloqueada}
            aria-describedby={bloqueada ? `${acao.key}-motivo-menu` : undefined}
            onClick={() => {
              escolheuAcao.current = true
              fechar()
              acao.onSelect()
            }}
            className={cn(
              'flex w-full items-start gap-2.5 px-3 py-2 text-left text-sm',
              'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
              bloqueada
                ? 'cursor-not-allowed text-muted-foreground'
                : acao.destructive
                  ? 'text-destructive hover:bg-destructive/10'
                  : 'text-popover-foreground hover:bg-accent hover:text-accent-foreground',
            )}
          >
            {acao.icon && <span aria-hidden="true" className="mt-0.5 shrink-0">{acao.icon}</span>}
            <span className="min-w-0">
              <span className="block">{acao.label}</span>
              {bloqueada && (
                <span
                  id={`${acao.key}-motivo-menu`}
                  className="mt-0.5 block text-xs leading-snug text-muted-foreground"
                >
                  {acao.disabledReason}
                </span>
              )}
            </span>
          </button>
        )
      })}
    </FloatingPanel>
  )
}

/** O corpo da folha — uma implementação só, usada pelos dois componentes. */
function folhaDeAcoes({
  onOpenChange,
  title,
  subtitle,
  actions,
}: Pick<MobileRowActionsProps, 'onOpenChange' | 'title' | 'subtitle' | 'actions'>) {
  return (
    <div
      className="fixed inset-0 z-modal flex items-end"
      role="dialog"
      aria-modal="true"
      aria-label={`Ações de ${title}`}
      onClick={() => onOpenChange(false)}
    >
      {/* Mesmo véu do `dialog` e do `SideDrawer` da base: `bg-brand-ink/70`.
          Sem `backdrop-blur` — no headless com `--disable-gpu` o
          `backdrop-filter` compõe errado e pinta a folha com a cor de trás, o
          que já quase virou defeito reportado numa fatia anterior. */}
      <div className="absolute inset-0 bg-brand-ink/70" aria-hidden="true" />

      <div
        className="relative w-full rounded-t-lg border-t border-border bg-popover text-popover-foreground shadow-e3 pb-[max(1rem,env(safe-area-inset-bottom))]"
        onClick={(evento) => evento.stopPropagation()}
      >
        {/* Puxador: a affordance que diz "isto é uma folha" antes de qualquer texto. */}
        <div className="flex justify-center pt-3" aria-hidden="true">
          <span className="h-1 w-10 rounded-sm bg-border" />
        </div>

        <div className="flex items-start justify-between gap-3 px-5 pt-3 pb-2">
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-popover-foreground">{title}</p>
            {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
          </div>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Fechar"
            // 48x48 como as ações da lista abaixo: o "fechar" era o único alvo de
            // 40 px dentro de uma folha inteira desenhada para o polegar.
            className="h-12 w-12"
            onClick={() => onOpenChange(false)}
          >
            <X aria-hidden="true" className="h-5 w-5" />
          </Button>
        </div>

        <ul className="pb-2">
          {actions.map((acao) => {
            const bloqueada = Boolean(acao.disabledReason)
            return (
              <li key={acao.key}>
                <button
                  type="button"
                  disabled={bloqueada}
                  aria-describedby={bloqueada ? `${acao.key}-motivo` : undefined}
                  onClick={() => {
                    onOpenChange(false)
                    acao.onSelect()
                  }}
                  className={cn(
                    'flex min-h-[3rem] w-full items-center gap-3 px-5 py-3 text-left text-sm',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    bloqueada
                      ? 'cursor-not-allowed text-muted-foreground'
                      : acao.destructive
                        ? 'text-destructive hover:bg-destructive/10'
                        : 'text-popover-foreground hover:bg-accent hover:text-accent-foreground',
                  )}
                >
                  {acao.icon && <span aria-hidden="true" className="shrink-0">{acao.icon}</span>}
                  <span className="min-w-0">
                    <span className="block">{acao.label}</span>
                    {bloqueada && (
                      <span id={`${acao.key}-motivo`} className="block text-xs text-muted-foreground">
                        {acao.disabledReason}
                      </span>
                    )}
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      </div>
    </div>
  )
}
