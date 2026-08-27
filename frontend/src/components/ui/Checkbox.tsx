import * as React from 'react'
import { Check, Minus } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * Checkbox do design system.
 *
 * Membro da biblioteca, não peça de tela: caixa de seleção aparece em filtro,
 * em cabeçalho de tabela (selecionar tudo, com o estado **indeterminado**), em
 * lista de permissões e em aceite de termos. Se cada tela desenhar a sua, o
 * tamanho do alvo de clique e o traço de foco divergem entre elas.
 *
 * O `<input>` nativo continua existindo — só fica visualmente escondido
 * (`sr-only`), preservando teclado, `form`, `name`, validação e leitor de tela.
 * O quadrado é um `<span>` irmão pintado por `peer-*`.
 */
export interface CheckboxProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type' | 'size'> {
  label?: React.ReactNode
  /** Descrição secundária abaixo do rótulo. */
  description?: React.ReactNode
  /** Estado "alguns marcados" — visual de traço, não de check. */
  indeterminate?: boolean
}

const Checkbox = React.forwardRef<HTMLInputElement, CheckboxProps>(
  ({ className, label, description, indeterminate = false, disabled, id, ...props }, ref) => {
    const auto = React.useId()
    const inputId = id ?? auto
    const innerRef = React.useRef<HTMLInputElement>(null)
    React.useImperativeHandle(ref, () => innerRef.current as HTMLInputElement)

    // `indeterminate` só existe como propriedade do DOM: não há atributo HTML
    // para ele, então tem que ser escrito depois da renderização.
    React.useEffect(() => {
      if (innerRef.current) innerRef.current.indeterminate = indeterminate
    }, [indeterminate])

    return (
      <label
        htmlFor={inputId}
        className={cn(
          'group relative inline-flex items-start gap-2.5 text-sm',
          disabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
          // **Caixa sem rótulo é um alvo de 16 px.** Quando há texto ao lado, o
          // próprio `<label>` já é grande e o polegar acerta; sem texto — que é
          // como a lista de portadores do projeto e as seleções em lote a usam —
          // sobra um quadrado de 16 px encostado na borda direita do cartão, e
          // errar a marcação de uma linha é conectar o portador errado.
          // O `::after` estende só a ÁREA QUE RESPONDE, para 44x44, sem mover um
          // pixel do desenho (critério 1 da §5.4.8). No desktop some.
          !label &&
            !description &&
            "after:absolute after:left-1/2 after:top-1/2 after:h-11 after:w-11 after:-translate-x-1/2 after:-translate-y-1/2 after:content-[''] md:after:hidden",
          className,
        )}
      >
        <input
          ref={innerRef}
          id={inputId}
          type="checkbox"
          disabled={disabled}
          className="peer sr-only"
          {...props}
        />
        <span
          aria-hidden="true"
          className={cn(
            // O ícone herda `currentColor`; deixar o texto transparente é o que
            // o esconde. `peer-checked:` só alcança IRMÃO do input — por isso o
            // estado é pintado neste span, e não numa classe do próprio ícone.
            'mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-sm border border-input bg-background text-transparent transition-colors',
            'peer-checked:border-primary peer-checked:bg-primary peer-checked:text-primary-foreground',
            'peer-indeterminate:border-primary peer-indeterminate:bg-primary peer-indeterminate:text-primary-foreground',
            'peer-focus-visible:ring-2 peer-focus-visible:ring-ring peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-background',
            !disabled && 'group-hover:border-ring',
          )}
        >
          {indeterminate ? (
            <Minus className="h-3 w-3" strokeWidth={3} />
          ) : (
            <Check className="h-3 w-3" strokeWidth={3} />
          )}
        </span>
        {(label || description) && (
          <span className="flex flex-col gap-0.5 leading-tight">
            {label && <span className="text-foreground">{label}</span>}
            {description && <span className="text-xs text-muted-foreground">{description}</span>}
          </span>
        )}
      </label>
    )
  },
)
Checkbox.displayName = 'Checkbox'

export { Checkbox }
