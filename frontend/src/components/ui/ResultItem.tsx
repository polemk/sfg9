import * as React from 'react'
import { Check } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Spinner } from './Spinner'

/**
 * ResultItem — a linha de um resultado de busca ou de uma lista de escolha.
 *
 * Membro da biblioteca porque a mesma linha aparece no autocomplete de membros,
 * na busca de personificação, no seletor de projeto e em toda lista de escolha
 * que vier depois. Ela tem três detalhes que sempre se perdem quando cada tela
 * desenha a sua:
 *
 * - **Spinner por item.** Quando o clique dispara uma ação (personificar,
 *   adicionar membro), o giro tem que estar *naquela linha* — um spinner global
 *   não diz em qual item o usuário clicou, e ele clica de novo.
 * - **Ícone/avatar com largura fixa**, para os títulos alinharem verticalmente.
 * - **O trecho que casou com a busca em destaque**, senão numa lista de dez
 *   nomes parecidos o usuário não vê por que aquele apareceu.
 */
export interface ResultItemProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'title'> {
  /** Ícone, avatar ou inicial. Recebe largura fixa. */
  icon?: React.ReactNode
  title: React.ReactNode
  subtitle?: React.ReactNode
  /** Valor à direita: código, contagem, papel. Recebe `font-numeric`. */
  meta?: React.ReactNode
  /** Ação em andamento neste item. Desabilita e troca a `meta` pelo spinner. */
  loading?: boolean
  selected?: boolean
  /** Realce visual de navegação por teclado (não é seleção). */
  active?: boolean
}

export const ResultItem = React.forwardRef<HTMLButtonElement, ResultItemProps>(
  ({ icon, title, subtitle, meta, loading, selected, active, className, disabled, ...props }, ref) => (
    <button
      ref={ref}
      type="button"
      role="option"
      aria-selected={selected}
      aria-busy={loading || undefined}
      disabled={disabled || loading}
      className={cn(
        'flex w-full items-center gap-3 rounded-sm px-3 py-2 text-left transition-colors',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
        'disabled:cursor-not-allowed disabled:opacity-50',
        active ? 'bg-accent text-accent-foreground' : 'text-popover-foreground hover:bg-accent hover:text-accent-foreground',
        className,
      )}
      {...props}
    >
      {icon !== undefined && (
        <span className="flex h-8 w-8 shrink-0 items-center justify-center text-muted-foreground">{icon}</span>
      )}
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-sm">{title}</span>
        {subtitle && <span className="truncate text-xs text-muted-foreground">{subtitle}</span>}
      </span>
      {loading ? (
        <Spinner size="xs" label={null} className="shrink-0 text-muted-foreground" />
      ) : selected ? (
        <Check aria-hidden="true" className="h-4 w-4 shrink-0 text-primary" />
      ) : meta ? (
        <span className="shrink-0 font-numeric text-xs tabular-nums text-muted-foreground">{meta}</span>
      ) : null}
    </button>
  ),
)
ResultItem.displayName = 'ResultItem'

/**
 * Destaca em negrito o trecho do texto que casou com o termo buscado.
 *
 * Faz o casamento sem `RegExp` construída a partir da entrada do usuário —
 * um termo com `(` ou `*` quebraria a expressão, e sanitizar entrada para
 * montar regex é um problema que não precisa existir.
 */
export function Highlight({ text, query }: { text: string; query: string }) {
  const termo = query.trim()
  if (!termo) return <>{text}</>
  const i = text.toLowerCase().indexOf(termo.toLowerCase())
  if (i < 0) return <>{text}</>
  return (
    <>
      {text.slice(0, i)}
      <mark className="bg-transparent font-semibold text-foreground">{text.slice(i, i + termo.length)}</mark>
      {text.slice(i + termo.length)}
    </>
  )
}
