import * as React from 'react'
import { cn } from '@/lib/utils'
import { APP_CURRENCY, minorFactor, type CurrencyConfig } from '@/lib/config/currency'

/**
 * Campo monetário com preenchimento da direita para a esquerda — como no legado.
 *
 * **A regra, nas palavras do usuário:** digitar `1` é um centavo (`R$ 0,01`),
 * digitar `100` é um real (`R$ 1,00`), e daí por diante. O usuário nunca digita
 * vírgula nem ponto: ele digita só os algarismos e a máscara vai montando o
 * número. É o comportamento de qualquer aplicativo de banco, e é o que o legado
 * fazia com o `jquery-mask-plugin` sobre a classe `.money-value`.
 *
 * **Por que isto substitui o `MoneyInput` anterior.** O anterior formatava só ao
 * sair do campo, e o comentário dele justificava a escolha assim: "formatar a
 * cada tecla move o cursor sozinho — digitar 1234 com máscara ao vivo pula o
 * cursor para o fim a cada dígito e o usuário não consegue corrigir o meio."
 * O raciocínio está certo para uma máscara da **esquerda para a direita**, onde
 * existe um "meio" para corrigir. Aqui não existe: o cursor mora no fim por
 * construção, e a correção é o próprio Backspace, que tira o último algarismo e
 * empurra o número de volta uma casa (`R$ 12,34` → Backspace → `R$ 1,23`). A
 * objeção não se aplica a este desenho.
 *
 * **Contrato preservado:** exibe formatado, envia número (FE-066). O `onChange`
 * entrega `number | null` em unidade maior — `1234.56`, nunca `"R$ 1.234,56"` e
 * nunca os centavos crus `123456`.
 *
 * **A moeda vem de `APP_CURRENCY`**, não daqui. Trocar a moeda do app troca o
 * símbolo, o separador e — o que mais importa — a **quantidade de casas**: numa
 * moeda sem subunidade, digitar `1` passa a ser uma unidade inteira.
 */
export interface MoneyInputProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'> {
  /** Valor em unidade MAIOR (reais), não em centavos. `1234.56` = R$ 1.234,56. */
  value: number | null | undefined
  onChange: (value: number | null) => void
  /** Sobrescreve a moeda do app neste campo. Raro — use para valor em moeda estrangeira. */
  currency?: CurrencyConfig
  error?: string
  /**
   * Quantos algarismos o campo aceita, contando os centavos. O padrão de 15
   * cobre trilhões e mantém o resultado dentro do inteiro seguro do JS: acima
   * disso a divisão por 100 começa a perder centavo, e num sistema de crédito
   * perder centavo em silêncio é defeito, não arredondamento.
   */
  maxDigitos?: number
}

/** Só os algarismos, na ordem — é o estado real do campo. */
function digitos(texto: string): string {
  return (texto ?? '').replace(/\D/g, '')
}

export const MoneyInput = React.forwardRef<HTMLInputElement, MoneyInputProps>(
  (
    { value, onChange, currency = APP_CURRENCY, error, maxDigitos = 15, className, disabled, onKeyDown, ...props },
    ref,
  ) => {
    const interno = React.useRef<HTMLInputElement | null>(null)
    const setRef = React.useCallback(
      (el: HTMLInputElement | null) => {
        interno.current = el
        if (typeof ref === 'function') ref(el)
        else if (ref) (ref as React.MutableRefObject<HTMLInputElement | null>).current = el
      },
      [ref],
    )

    const fator = minorFactor(currency)

    const formatador = React.useMemo(
      () =>
        new Intl.NumberFormat(currency.locale, {
          style: 'currency',
          currency: currency.code,
          minimumFractionDigits: currency.minorUnits,
          maximumFractionDigits: currency.minorUnits,
        }),
      [currency],
    )

    const texto =
      value === null || value === undefined || !Number.isFinite(value)
        ? ''
        : formatador.format(value)

    // O cursor mora no fim. Sem isto, clicar no meio do texto e digitar faria o
    // algarismo entrar no lugar errado — e num campo que preenche da direita
    // para a esquerda, "lugar errado" muda a ordem de grandeza do valor.
    const aoFim = React.useCallback(() => {
      const el = interno.current
      if (!el) return
      const fim = el.value.length
      if (el.selectionStart !== fim || el.selectionEnd !== fim) el.setSelectionRange(fim, fim)
    }, [])

    React.useEffect(() => {
      if (document.activeElement === interno.current) aoFim()
    }, [texto, aoFim])

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const d = digitos(e.target.value).slice(0, maxDigitos).replace(/^0+(?=\d)/, '')
      if (d === '') {
        onChange(null)
        return
      }
      const centavos = Number(d)
      // `Number.isSafeInteger` protege o caso em que o `maxDigitos` foi afrouxado
      // por quem consome: acima do inteiro seguro o valor deixa de ser exato.
      if (!Number.isSafeInteger(centavos)) return
      onChange(centavos / fator)
    }

    const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
      // Setas e Home/End moveriam o cursor para dentro do texto formatado, onde
      // digitar produz valor errado. Selecionar tudo e navegar por Tab seguem
      // funcionando.
      if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key) && !e.shiftKey) {
        e.preventDefault()
        aoFim()
      }
      onKeyDown?.(e)
    }

    const autoId = React.useId()
    const erroId = `${props.id ?? autoId}-erro`

    return (
      <div className="flex w-full flex-col gap-1">
        <input
          ref={setRef}
          type="text"
          inputMode="numeric"
          autoComplete="off"
          value={texto}
          disabled={disabled}
          placeholder={props.placeholder ?? formatador.format(0)}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          onClick={aoFim}
          onFocus={aoFim}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? erroId : undefined}
          className={cn(
            'flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-right font-numeric text-sm text-foreground tabular-nums transition-colors',
            'placeholder:text-muted-foreground placeholder:font-sans',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
            'disabled:cursor-not-allowed disabled:opacity-50',
            error && 'border-destructive focus-visible:ring-destructive',
            className,
          )}
          {...props}
        />
        {error && (
          <p id={erroId} role="alert" className="text-xs text-destructive">
            {error}
          </p>
        )}
      </div>
    )
  },
)
MoneyInput.displayName = 'MoneyInput'
