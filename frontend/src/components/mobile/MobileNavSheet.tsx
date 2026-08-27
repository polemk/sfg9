import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import { Link, useLocation } from 'react-router-dom'
import { X, type LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useNavGroups } from '@/hooks/useNavItems'

/**
 * **O menu inteiro, no telefone** — DEC-100.
 *
 * Existe por causa de um defeito que nenhum portão pegava e que a captura em
 * 390×844 mostrou de imediato: **a `MobileBottomBar` mostra cinco abas
 * (`useNavItems().slice(0, 5)`) e não havia mais nada.** No desktop a `Sidebar`
 * lista os ~40 destinos; no telefone a `Sidebar` é `hidden md:block`, a
 * `MobileContextSheet` do avatar só tem perfil/tema/impersonação/sair, e o
 * seletor de modo do cabeçalho apenas **troca quais** cinco aparecem. Resultado:
 * Projetos, Empresas, Portadores, Limites, Contratos, Central de ajuda e o resto
 * eram **inalcançáveis** — existiam, tinham rota montada, e não havia caminho
 * até elas com o polegar.
 *
 * `tsc` e `vitest` continuam verdes com esse defeito de pé: nenhum dos dois sabe
 * que a barra corta a lista em cinco.
 *
 * ### Por que uma folha, e não mais abas
 *
 * O teto de cinco abas é regra da §5.4.8, e é regra por medida: num 390 a sexta
 * aba derruba o alvo abaixo de 44 px e o rótulo deixa de caber. A saída nativa —
 * a que iOS e Android usam desde sempre — é a última aba virar **"Mais"** e
 * abrir a lista completa. É o que este componente é.
 *
 * ### As quatro coisas que ele garante
 *
 * 1. **Portal no `body`** (§5.4.4). A `MobileBottomBar` é `fixed` com `z-appbar`,
 *    e `fixed` + `z` já cria contexto de empilhamento: uma folha renderizada
 *    dentro dela ficaria **presa** no z da barra, por mais alto que fosse o seu.
 *    É o mesmo defeito do `SidebarModeToggle`.
 * 2. **Fecha por `pointerdown`, não `mousedown`** (critério 6 da §5.4.8). O
 *    `mousedown` sintético do telefone só chega depois do `touchend`, e o atraso
 *    é visível.
 * 3. **Alvo de 48 px por linha**, com ícone **e** rótulo — nunca só o desenho:
 *    "Painel de Disponibilidade" e "Disponibilidades" usam o mesmo `CalendarRange`,
 *    e sem o nome inteiro são o mesmo item.
 * 4. **`aria-current="page"` na rota ativa**, não só cor: quem lê por voz não
 *    enxerga o ouro.
 *
 * A fonte da lista é `useNavGroups()` — o **mesmo** registro filtrado que a
 * `Sidebar` consome. Uma segunda lista aqui divergiria do menu do desktop, que é
 * exatamente o que `consoleNavigation.tsx` existe para impedir (D-118).
 */

export interface MobileNavSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function MobileNavSheet({ open, onOpenChange }: MobileNavSheetProps) {
  const grupos = useNavGroups()
  const location = useLocation()
  const painelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    function aoApontarFora(evento: PointerEvent) {
      if (painelRef.current?.contains(evento.target as Node)) return
      onOpenChange(false)
    }
    function aoTeclar(evento: KeyboardEvent) {
      if (evento.key === 'Escape') onOpenChange(false)
    }
    // O `pointerdown` do gatilho que abriu a folha ainda está em voo quando o
    // efeito monta; ouvir só a partir do próximo quadro evita fechar na abertura.
    const id = window.setTimeout(() => {
      document.addEventListener('pointerdown', aoApontarFora)
    }, 0)
    document.addEventListener('keydown', aoTeclar)
    return () => {
      window.clearTimeout(id)
      document.removeEventListener('pointerdown', aoApontarFora)
      document.removeEventListener('keydown', aoTeclar)
    }
  }, [open, onOpenChange])

  if (!open) return null

  const ativo = (path: string) =>
    location.pathname === path || location.pathname.startsWith(path + '/')

  return createPortal(
    <div className="fixed inset-0 z-modal flex items-end md:hidden" role="dialog" aria-modal="true" aria-label="Todos os menus">
      {/* Mesmo véu do `MobileRowActions`, do `dialog` e do `SideDrawer`:
          `bg-brand-ink/70`, sem `backdrop-blur` — no headless com `--disable-gpu`
          o `backdrop-filter` compõe errado e o pixel mente. */}
      <div className="absolute inset-0 bg-brand-ink/70 animate-in fade-in duration-200" aria-hidden="true" />

      <div
        ref={painelRef}
        className={cn(
          'relative flex max-h-[82dvh] w-full flex-col',
          'rounded-t-lg border-t border-border bg-popover text-popover-foreground shadow-e3',
          'animate-in slide-in-from-bottom duration-300',
        )}
        // A folha encosta na barra de abas, que já reserva a inset do aparelho;
        // aqui a inset entra de novo porque a folha a cobre por inteiro.
        style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
      >
        <div className="flex items-center justify-between border-b border-border px-4 py-3">
          <div className="min-w-0">
            <p className="text-sm font-bold">Todos os menus</p>
            <p className="text-xs text-muted-foreground">
              As abas do rodapé mostram os primeiros; o resto do console está aqui.
            </p>
          </div>
          <button
            type="button"
            onClick={() => onOpenChange(false)}
            aria-label="Fechar menu"
            className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <X aria-hidden="true" className="h-5 w-5" />
          </button>
        </div>

        <div className="overflow-y-auto overscroll-contain px-2 py-2">
          {grupos.map((grupo) => {
            // Grupo-destino (o `independent_group_menu_item` do legado) e grupo de um
            // item só por desenho: viram **um** link, e não um cabeçalho com uma linha
            // debaixo. A regra é a mesma que a `Sidebar` aplica — duas leituras
            // diferentes do mesmo registro seriam dois menus.
            const soLink = (grupo.path && grupo.items.length === 0) || grupo.linkToSingleItem
            if (soLink) {
              const destino = grupo.items[0]?.path ?? grupo.path
              if (!destino) return null
              const Icone = grupo.items[0]?.icon ?? grupo.icon
              return (
                <ul key={grupo.id}>
                  <LinhaDeMenu
                    to={destino}
                    label={grupo.items[0]?.label ?? grupo.title}
                    icone={Icone}
                    ativo={ativo(destino)}
                    aoNavegar={() => onOpenChange(false)}
                  />
                </ul>
              )
            }
            return (
              <section key={grupo.id} className="mb-2">
                <h2 className="px-3 pb-1 pt-2 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  {grupo.title}
                </h2>
                <ul>
                  {grupo.items.map((item) => (
                    <LinhaDeMenu
                      key={item.path}
                      to={item.path}
                      label={item.label}
                      icone={item.icon}
                      ativo={ativo(item.path)}
                      aoNavegar={() => onOpenChange(false)}
                    />
                  ))}
                </ul>
              </section>
            )
          })}
        </div>
      </div>
    </div>,
    document.body,
  )
}

/** Uma linha do menu: 48 px de alvo, ícone **e** rótulo inteiro, `aria-current` na ativa. */
function LinhaDeMenu({
  to,
  label,
  icone: Icone,
  ativo,
  aoNavegar,
}: {
  to: string
  label: string
  icone: LucideIcon
  ativo: boolean
  aoNavegar: () => void
}) {
  return (
    <li>
      <Link
        to={to}
        onClick={aoNavegar}
        aria-current={ativo ? 'page' : undefined}
        className={cn(
          'flex min-h-[3rem] items-center gap-3 rounded-sm px-3 py-2 text-sm font-medium',
          'transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          ativo
            ? 'bg-accent text-primary'
            : 'text-popover-foreground hover:bg-accent hover:text-accent-foreground',
        )}
      >
        <Icone aria-hidden="true" className="h-5 w-5 shrink-0" />
        {/* Sem `truncate`: o nome inteiro é o que separa dois itens que compartilham
            o desenho. Quebra em duas linhas antes de cortar. */}
        <span className="min-w-0 flex-1 leading-tight">{label}</span>
      </Link>
    </li>
  )
}
