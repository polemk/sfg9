import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * Spinner — indicador de trabalho em andamento da biblioteca.
 *
 * É membro da biblioteca e não peça de uma tela porque o mesmo giro aparece em
 * três lugares diferentes com exigências diferentes de cor: dentro do `Button`
 * primary (precisa herdar `text-primary-foreground`, senão some no ouro), no
 * corpo de um `AsyncSection` (herda `text-muted-foreground`) e ao lado de um
 * item de resultado de autocomplete. Por isso a cor é sempre `currentColor` —
 * o spinner nunca escolhe cor, ele herda a de quem o hospeda.
 */
export type SpinnerSize = 'xs' | 'sm' | 'md' | 'lg'

const sizes: Record<SpinnerSize, string> = {
  xs: 'h-3 w-3 border',
  sm: 'h-4 w-4 border-2',
  md: 'h-6 w-6 border-2',
  lg: 'h-9 w-9 border-[3px]',
}

export interface SpinnerProps extends React.HTMLAttributes<HTMLSpanElement> {
  size?: SpinnerSize
  /** Texto lido por leitor de tela. `null` quando o contexto já anuncia. */
  label?: string | null
}

export function Spinner({ size = 'sm', label = 'Carregando', className, ...props }: SpinnerProps) {
  return (
    <span
      role="status"
      aria-live="polite"
      className={cn('inline-flex items-center justify-center', className)}
      {...props}
    >
      <span
        aria-hidden="true"
        className={cn(
          // `border-current` + `border-t-transparent` desenha o arco sem SVG e
          // sem cor própria: o giro é da cor do texto de quem o contém.
          'inline-block animate-spin rounded-full border-current border-t-transparent',
          sizes[size],
        )}
      />
      {label ? <span className="sr-only">{label}</span> : null}
    </span>
  )
}

export default Spinner
