import * as React from 'react'
import { cn } from '@/lib/utils'
import { formatAmount, formatMoney, formatPercent, parseNumberPtBr } from '@/lib/utils/number'

/**
 * Campo numérico pt-BR — a base de `PercentInput` e do decimal solto.
 *
 * Contrato do app: **exibe formatado, envia número** (FE-066). O `onChange`
 * entrega `number | null`, nunca a string da tela. Quem consome não faz parse.
 *
 * Comportamento de foco, que é o que faz o campo ser usável: **com foco, o
 * usuário vê o que digitou**; ao sair, o valor é reformatado. Formatar a cada
 * tecla move o cursor sozinho — digitar "1234" com máscara ao vivo pula o
 * cursor para o fim a cada dígito e o usuário não consegue corrigir o meio.
 *
 * Separador duplo (`1.234.56`, o copiar-e-colar de planilha em locale errado)
 * **não é adivinhado**: o campo mostra o aviso e não emite valor. O legado
 * engolia e gravava valor torto.
 *
 * É membro da biblioteca porque valor monetário aparece em recebível, em
 * renegociação, em indicador e em contrato — quatro telas, uma regra de parse.
 */
export type NumericKind = 'money' | 'percent' | 'decimal'

export interface NumericInputProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'> {
  value: number | null | undefined
  onChange: (value: number | null) => void
  kind?: NumericKind
  /** Casas decimais na exibição. Moeda e percentual usam 2. */
  casas?: number
  /** Mensagem de erro vinda de fora (validação de formulário). */
  error?: string
  /** Some com o aviso interno de separador — use só se você o exibe. */
  hideWarning?: boolean
  onWarningChange?: (aviso: string | undefined) => void
}

function exibir(value: number | null | undefined, kind: NumericKind, casas: number): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return ''
  if (kind === 'money') return formatMoney(value, '')
  if (kind === 'percent') return formatPercent(value, casas, '')
  return formatAmount(value, casas, '')
}

export const NumericInput = React.forwardRef<HTMLInputElement, NumericInputProps>(
  (
    { value, onChange, kind = 'decimal', casas = 2, error, hideWarning, onWarningChange, className, disabled, onFocus, onBlur, ...props },
    ref,
  ) => {
    const [rascunho, setRascunho] = React.useState<string | null>(null)
    const [aviso, setAviso] = React.useState<string | undefined>()
    const autoId = React.useId()
    const avisoId = `${props.id ?? autoId}-aviso`

    const emEdicao = rascunho !== null
    const texto = emEdicao ? (rascunho as string) : exibir(value, kind, casas)

    const anunciar = React.useCallback(
      (msg: string | undefined) => {
        setAviso(msg)
        onWarningChange?.(msg)
      },
      [onWarningChange],
    )

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const bruto = e.target.value
      setRascunho(bruto)
      const { value: n, aviso: msg } = parseNumberPtBr(bruto)
      anunciar(msg)
      // Só emite quando o texto é interpretável. Enquanto houver aviso, o
      // consumidor mantém o último valor bom — nunca recebe `null` por engano.
      if (!msg) onChange(n)
    }

    const handleBlur = (e: React.FocusEvent<HTMLInputElement>) => {
      const { value: n, aviso: msg } = parseNumberPtBr(e.target.value)
      if (!msg) {
        anunciar(undefined)
        onChange(n)
      }
      setRascunho(null)
      onBlur?.(e)
    }

    const handleFocus = (e: React.FocusEvent<HTMLInputElement>) => {
      // Entra em edição com o número cru: sem "R$", sem ponto de milhar. É o
      // que permite selecionar tudo e redigitar sem lutar com a máscara.
      setRascunho(value === null || value === undefined ? '' : String(value).replace('.', ','))
      e.target.select()
      onFocus?.(e)
    }

    const problema = error ?? (!hideWarning ? aviso : undefined)

    return (
      <div className="flex w-full flex-col gap-1">
        <input
          ref={ref}
          type="text"
          inputMode="decimal"
          value={texto}
          disabled={disabled}
          onChange={handleChange}
          onFocus={handleFocus}
          onBlur={handleBlur}
          aria-invalid={problema ? true : undefined}
          aria-describedby={problema ? avisoId : undefined}
          className={cn(
            'flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-right font-numeric text-sm text-foreground tabular-nums transition-colors',
            'placeholder:text-muted-foreground placeholder:font-sans',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
            'disabled:cursor-not-allowed disabled:opacity-50',
            problema && 'border-destructive focus-visible:ring-destructive',
            className,
          )}
          {...props}
        />
        {problema && (
          <p id={avisoId} role="alert" className="text-xs text-destructive">
            {problema}
          </p>
        )}
      </div>
    )
  },
)
NumericInput.displayName = 'NumericInput'

/**
 * `MoneyInput` mora em `./MoneyInput` e e **reexportado aqui** de proposito.
 *
 * Ele deixou de ser um `NumericInput` com `kind="money"`: virou um acumulador da
 * direita para a esquerda (digitar `1` e um centavo), que e como o legado se
 * comporta e como o usuario pediu. O desenho e a justificativa estao no arquivo.
 *
 * A reexportacao existe pela Regra de fronteira: sete telas ja importam
 * `MoneyInput` deste caminho. Trocar a implementacao sem trocar o caminho
 * entrega o comportamento novo a todas elas sem quebrar um unico import.
 */
export { MoneyInput, type MoneyInputProps } from './MoneyInput'

export type PercentInputProps = Omit<NumericInputProps, 'kind'>

/** Percentual. Exibe `12,50%`, envia `12.5` — o número é o percentual, não a fração. */
export const PercentInput = React.forwardRef<HTMLInputElement, PercentInputProps>((props, ref) => (
  <NumericInput ref={ref} kind="percent" placeholder="0,00%" {...props} />
))
PercentInput.displayName = 'PercentInput'
