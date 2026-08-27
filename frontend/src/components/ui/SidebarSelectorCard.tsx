import * as React from 'react'
import { ChevronRight } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Tooltip } from '@/components/ui/Tooltip'
import { Spinner } from '@/components/ui/Spinner'
import { cn } from '@/lib/utils'

/**
 * O cartão de seletor da sidebar — **um só desenho para os três**.
 *
 * "Vendo como", "Modo" e "Projeto" fazem a mesma coisa: mostram um rótulo fixo,
 * o valor escolhido, e abrem um painel. Cada um tinha nascido com a sua própria
 * marcação: dois eram cartão com chip de ícone e o terceiro era uma pílula
 * `Button size="sm"`. Três controles irmãos, empilhados, com três alturas e três
 * pesos de texto — é o tipo de inconsistência que se nota antes do conteúdo.
 *
 * Recolhida, o cartão vira **só o quadrado do ícone** e o rótulo migra para o
 * tooltip. O quadrado É o botão: botão com borda por fora e chip preenchido por
 * dentro desenha quadrado dentro de quadrado, que foi um defeito real desta
 * sidebar.
 *
 * O tooltip é em portal (`Tooltip`), obrigatório aqui: o `<aside>` usa
 * `.glass-panel`, que aplica `backdrop-filter`, e `backdrop-filter` cria contexto
 * de empilhamento — descendente `absolute` fica preso ao `z-index` do aside por
 * mais alto que seja o dele.
 */
export interface SidebarSelectorCardProps {
  /** Rótulo fixo, em caixa alta. Diz o que o seletor controla. */
  label: string
  /** O valor escolhido agora. */
  value: string
  icon: LucideIcon
  collapsed?: boolean
  open?: boolean
  loading?: boolean
  onClick: () => void
  /** `aria-haspopup` do gatilho. `listbox` para escolha, `dialog` para busca. */
  haspopup?: 'listbox' | 'dialog' | 'menu'
  /**
   * `warning` para estado que exige atenção — hoje só a impersonação ativa.
   * A cor vem do token `warning`, nunca de um âmbar literal.
   */
  tone?: 'default' | 'warning'
  className?: string
}

export const SidebarSelectorCard = React.forwardRef<HTMLButtonElement, SidebarSelectorCardProps>(
  ({ label, value, icon: Icon, collapsed, open, loading, onClick, haspopup = 'listbox', tone = 'default', className }, ref) => {
    const atencao = tone === 'warning'
    const botao = (
      <Button
        ref={ref}
        variant="secondary"
        onClick={onClick}
        aria-haspopup={haspopup}
        aria-expanded={open}
        aria-label={collapsed ? `${label}: ${value}` : undefined}
        className={cn(
          'group',
          collapsed
            ? 'mx-auto h-10 w-10 justify-center gap-0 p-0'
            : 'h-auto w-full justify-between gap-3 px-3 py-2',
          className,
        )}
      >
        <span className="flex min-w-0 items-center gap-3 overflow-hidden">
          <span
            className={cn(
              'flex flex-shrink-0 items-center justify-center transition-all duration-300',
              !collapsed && 'h-8 w-8 rounded-md',
              !collapsed && (atencao ? 'bg-warning/15' : 'bg-accent'),
            )}
          >
            <Icon aria-hidden="true" className={cn('h-4 w-4', atencao ? 'text-warning' : 'text-foreground')} />
          </span>

          {!collapsed && (
            <span className="flex min-w-0 flex-col items-start text-left">
              <span className={cn('text-xs font-bold uppercase tracking-wider', atencao ? 'text-warning/70' : 'text-muted-foreground')}>{label}</span>
              <span className="block w-full truncate text-sm font-medium text-foreground">{value}</span>
            </span>
          )}
        </span>

        {!collapsed &&
          (loading ? (
            <Spinner size="sm" label={null} />
          ) : (
            <ChevronRight
              aria-hidden="true"
              className={cn(
                'h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-300',
                open && 'rotate-90',
              )}
            />
          ))}
      </Button>
    )

    if (!collapsed) return botao
    return (
      <Tooltip content={`${label}: ${value}`} side="right" className="block">
        {botao}
      </Tooltip>
    )
  },
)
SidebarSelectorCard.displayName = 'SidebarSelectorCard'
