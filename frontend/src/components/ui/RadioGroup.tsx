import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * RadioGroup — escolha única entre poucas opções visíveis.
 *
 * Membro da biblioteca porque a regra "rádio quando são poucas opções e todas
 * precisam ser lidas, `Select` quando são muitas" só se sustenta se existir um
 * rádio pronto. Sem ele, toda tela cai no `Select` e o usuário perde a leitura
 * das alternativas.
 *
 * O agrupamento é `<fieldset>`/`<legend>` de verdade: é o que faz o leitor de
 * tela anunciar "opção 2 de 4, grupo Papel". Um `<div>` com rótulo solto não
 * anuncia. O `name` compartilhado vem do contexto — o consumidor não repete.
 */
interface RadioGroupContextValue {
  name: string
  value?: string
  onChange?: (value: string) => void
  disabled?: boolean
}

const RadioGroupContext = React.createContext<RadioGroupContextValue | null>(null)

export interface RadioGroupProps extends Omit<React.HTMLAttributes<HTMLFieldSetElement>, 'onChange'> {
  /** Rótulo do grupo. Vira `<legend>`; use `srOnlyLegend` para escondê-lo. */
  legend?: React.ReactNode
  srOnlyLegend?: boolean
  name?: string
  value?: string
  defaultValue?: string
  onValueChange?: (value: string) => void
  disabled?: boolean
  /** `vertical` (padrão) empilha; `horizontal` alinha em linha com quebra. */
  orientation?: 'vertical' | 'horizontal'
}

export function RadioGroup({
  legend,
  srOnlyLegend,
  name,
  value,
  defaultValue,
  onValueChange,
  disabled,
  orientation = 'vertical',
  className,
  children,
  ...props
}: RadioGroupProps) {
  const auto = React.useId()
  const [uncontrolled, setUncontrolled] = React.useState(defaultValue)
  const current = value !== undefined ? value : uncontrolled

  const handleChange = React.useCallback(
    (next: string) => {
      if (value === undefined) setUncontrolled(next)
      onValueChange?.(next)
    },
    [value, onValueChange],
  )

  const ctx = React.useMemo<RadioGroupContextValue>(
    () => ({ name: name ?? auto, value: current, onChange: handleChange, disabled }),
    [name, auto, current, handleChange, disabled],
  )

  return (
    <fieldset className={cn('min-w-0 border-0 p-0', className)} disabled={disabled} {...props}>
      {legend && (
        <legend className={cn('mb-2 text-sm font-medium text-foreground', srOnlyLegend && 'sr-only')}>
          {legend}
        </legend>
      )}
      <div className={cn('flex gap-3', orientation === 'vertical' ? 'flex-col' : 'flex-row flex-wrap items-center')}>
        <RadioGroupContext.Provider value={ctx}>{children}</RadioGroupContext.Provider>
      </div>
    </fieldset>
  )
}

export interface RadioProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type' | 'value' | 'onChange'> {
  value: string
  label?: React.ReactNode
  description?: React.ReactNode
}

export const Radio = React.forwardRef<HTMLInputElement, RadioProps>(
  ({ value, label, description, className, disabled, id, ...props }, ref) => {
    const ctx = React.useContext(RadioGroupContext)
    const auto = React.useId()
    const inputId = id ?? auto
    const isDisabled = disabled || ctx?.disabled

    return (
      <label
        htmlFor={inputId}
        className={cn(
          'group inline-flex items-start gap-2.5 text-sm',
          isDisabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
          className,
        )}
      >
        <input
          ref={ref}
          id={inputId}
          type="radio"
          name={ctx?.name}
          value={value}
          checked={ctx ? ctx.value === value : undefined}
          onChange={() => ctx?.onChange?.(value)}
          disabled={isDisabled}
          className="peer sr-only"
          {...props}
        />
        <span
          aria-hidden="true"
          className={cn(
            // Mesma técnica do Checkbox: o miolo é `currentColor` e some por
            // transparência, porque `peer-checked:` não alcança descendente.
            'mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border border-input bg-background text-transparent transition-colors',
            'peer-checked:border-primary peer-checked:text-primary',
            'peer-focus-visible:ring-2 peer-focus-visible:ring-ring peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-background',
            !isDisabled && 'group-hover:border-ring',
          )}
        >
          <span className="h-2 w-2 rounded-full bg-current" />
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
Radio.displayName = 'Radio'
