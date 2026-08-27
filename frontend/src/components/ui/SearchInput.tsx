import * as React from 'react'
import { Search, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Spinner } from './Spinner'

/**
 * SearchInput — campo de busca da biblioteca.
 *
 * Existe porque "input + ícone de lupa + botão de limpar + spinner enquanto
 * busca" aparece em ~40 telas (FE-420). Cada uma montando o seu produz alturas
 * diferentes, ícone em posição diferente e — o pior — telas sem o botão de
 * limpar, onde o usuário precisa apagar o termo caractere a caractere.
 *
 * O par natural é o hook `useDebouncedSearch` (300 ms, espaço em branco
 * ignorado). O componente é só a apresentação: ele não sabe buscar nada, o que
 * o deixa reutilizável em busca local (filtro de array) e remota.
 */
export interface SearchInputProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'onChange' | 'value' | 'type' | 'size'> {
  value: string
  onValueChange: (value: string) => void
  /** Mostra o spinner no lugar da lupa enquanto a consulta não estabilizou. */
  loading?: boolean
  onClear?: () => void
  size?: 'sm' | 'default'
}

export const SearchInput = React.forwardRef<HTMLInputElement, SearchInputProps>(
  ({ value, onValueChange, loading, onClear, size = 'default', className, disabled, placeholder = 'Buscar…', ...props }, ref) => {
    const innerRef = React.useRef<HTMLInputElement>(null)
    React.useImperativeHandle(ref, () => innerRef.current as HTMLInputElement)

    const limpar = () => {
      onClear ? onClear() : onValueChange('')
      innerRef.current?.focus()
    }

    return (
      <div className={cn('relative flex w-full items-center', className)}>
        <span className="pointer-events-none absolute left-3 flex items-center text-muted-foreground">
          {loading ? <Spinner size="xs" label={null} /> : <Search aria-hidden="true" className="h-4 w-4" />}
        </span>
        <input
          ref={innerRef}
          type="search"
          role="searchbox"
          value={value}
          disabled={disabled}
          placeholder={placeholder}
          onChange={(e) => onValueChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Escape' && value) {
              e.preventDefault()
              limpar()
            }
            props.onKeyDown?.(e)
          }}
          className={cn(
            'w-full rounded-md border border-input bg-background pl-9 pr-9 text-sm text-foreground transition-colors',
            'placeholder:text-muted-foreground',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
            'disabled:cursor-not-allowed disabled:opacity-50',
            // O `type=search` do WebKit desenha um "x" próprio, sem estilo e
            // fora de posição — o nosso botão substitui.
            '[&::-webkit-search-cancel-button]:appearance-none',
            // 44 px no telefone: o campo é o alvo, e o botão de limpar (também
            // 44) tem de caber dentro dele sem transbordar (§5.4.8, critério 1).
            size === 'sm' ? 'h-9 max-md:h-11' : 'h-10 max-md:h-11',
          )}
          {...props}
        />
        {value && !disabled && (
          <button
            type="button"
            aria-label="Limpar busca"
            onClick={limpar}
            className="absolute right-1.5 flex h-11 w-11 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring md:h-7 md:w-7"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    )
  },
)
SearchInput.displayName = 'SearchInput'
