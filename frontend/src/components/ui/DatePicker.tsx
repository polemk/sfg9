import * as React from 'react'
import { CalendarDays, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { FloatingPanel } from './FloatingPanel'
import { Calendar } from './Calendar'
import { formatDate, toDate } from '@/lib/utils/date'

/**
 * DatePicker pt-BR — **crítico**: quase toda tela financeira do Safegold filtra
 * por período (FE-745).
 *
 * Duas maneiras de informar a data, porque as duas populações existem: o
 * operador **digita** `31/12/2026` sem tirar a mão do teclado, e quem está
 * conferindo **escolhe no calendário**. Um datepicker só-calendário obriga
 * navegação de mês para uma data de dois anos atrás; um só-texto não deixa ver
 * em que dia da semana cai o vencimento.
 *
 * O texto digitado só vira valor quando forma uma data completa e válida — a
 * cada tecla intermediária (`3`, `31`, `31/1`) o campo não emite nada, senão o
 * filtro dispararia uma consulta por dígito.
 *
 * O painel vai em portal (`FloatingPanel`): a barra de filtro costuma viver
 * dentro de um bloco com `backdrop-filter`, que aprisiona qualquer `absolute`.
 */
export interface DatePickerProps {
  value: Date | string | null | undefined
  onChange: (value: Date | null) => void
  min?: Date | null
  max?: Date | null
  placeholder?: string
  disabled?: boolean
  clearable?: boolean
  id?: string
  name?: string
  'aria-label'?: string
  className?: string
}

/** Máscara leve: só insere as barras enquanto o usuário digita dígito. */
/**
 * A data cai fora dos limites do campo? Compara por DIA, e não por instante.
 *
 * Serve ao atalho "Hoje" (FE-745): um campo "até" com `min` no futuro não pode
 * oferecer hoje, porque o próprio calendário recusaria a escolha.
 */
function foraDaFaixa(data: Date, min?: Date | null, max?: Date | null): boolean {
  const dia = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  if (min && dia(data) < dia(min)) return true
  if (max && dia(data) > dia(max)) return true
  return false
}

function mascarar(bruto: string): string {
  const d = bruto.replace(/\D/g, '').slice(0, 8)
  if (d.length <= 2) return d
  if (d.length <= 4) return `${d.slice(0, 2)}/${d.slice(2)}`
  return `${d.slice(0, 2)}/${d.slice(2, 4)}/${d.slice(4)}`
}

export function DatePicker({
  value,
  onChange,
  min,
  max,
  placeholder = 'dd/mm/aaaa',
  disabled,
  clearable = true,
  id,
  name,
  className,
  ...aria
}: DatePickerProps) {
  const [open, setOpen] = React.useState(false)
  const [rascunho, setRascunho] = React.useState<string | null>(null)
  const wrapRef = React.useRef<HTMLDivElement>(null)

  const data = toDate(value ?? null)
  // Meia-noite local: o calendário compara por DIA, e um `new Date()` com hora
  // faria "hoje" cair fora de um `max` que é o próprio dia de hoje.
  const hoje = React.useMemo(() => {
    const agora = new Date()
    return new Date(agora.getFullYear(), agora.getMonth(), agora.getDate())
  }, [])
  const texto = rascunho !== null ? rascunho : data ? formatDate(data, '') : ''
  const invalido = rascunho !== null && rascunho.length === 10 && !toDate(rascunho)

  const escrever = (bruto: string) => {
    const m = mascarar(bruto)
    setRascunho(m)
    if (m === '') {
      onChange(null)
      return
    }
    if (m.length === 10) {
      const d = toDate(m)
      if (d) onChange(d)
    }
  }

  const escolher = (d: Date) => {
    onChange(d)
    setRascunho(null)
    setOpen(false)
  }

  const limpar = () => {
    onChange(null)
    setRascunho(null)
  }

  return (
    <div ref={wrapRef} className={cn('relative inline-flex w-full items-center', className)}>
      <input
        id={id}
        name={name}
        type="text"
        inputMode="numeric"
        autoComplete="off"
        value={texto}
        placeholder={placeholder}
        disabled={disabled}
        aria-label={aria['aria-label']}
        aria-invalid={invalido || undefined}
        onChange={(e) => escrever(e.target.value)}
        onBlur={() => setRascunho(null)}
        className={cn(
          // 44 px no telefone, como o resto dos campos (§5.4.8, critério 1) — e
          // porque o botão do calendário, que também é 44, mora dentro dele.
          'h-10 max-md:h-11 w-full rounded-md border border-input bg-background py-2 pl-3 font-numeric text-sm text-foreground tabular-nums transition-colors',
          'placeholder:font-sans placeholder:text-muted-foreground',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
          'disabled:cursor-not-allowed disabled:opacity-50',
          invalido && 'border-destructive focus-visible:ring-destructive',
          clearable && data ? 'pr-16' : 'pr-10',
        )}
      />

      {clearable && data && !disabled && (
        <button
          type="button"
          aria-label="Limpar data"
          onClick={limpar}
          className="absolute right-9 flex h-7 w-7 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      )}

      <button
        type="button"
        aria-label="Abrir calendário"
        aria-haspopup="dialog"
        aria-expanded={open}
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        className="absolute right-1.5 flex h-11 w-11 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring md:h-7 md:w-7 disabled:opacity-50"
      >
        <CalendarDays className="h-4 w-4" />
      </button>

      <FloatingPanel
        open={open}
        anchorRef={wrapRef as React.RefObject<HTMLElement>}
        onDismiss={() => setOpen(false)}
        matchWidth={false}
        maxHeight={360}
        role="dialog"
        aria-label="Calendário"
      >
        <Calendar selected={data} onSelect={escolher} min={min} max={max} />

        {/*
          **FE-745 — o atalho "Hoje".** O legado (`air-datepicker`) trazia os dois
          botões de rodapé, "Hoje" e "Limpar", e o mapa nomeia os dois
          (`map/auth-admin.md:403`). "Limpar" já existe como o `X` do campo; o
          "Hoje" tinha ficado de fora.

          Não é atalho de conveniência num sistema de crédito: data de operação,
          data de crédito e a data da grade de disponibilidade são preenchidas com
          o dia corrente o tempo todo, e sem ele o usuário navega o calendário
          até achar o próprio dia de hoje.

          **Desabilitado quando hoje está fora da faixa** — num campo "até" com
          `min` no futuro, oferecer "Hoje" seria oferecer uma data que o próprio
          componente recusa.
        */}
        <div className="flex justify-end border-t border-border px-2 py-1.5">
          <button
            type="button"
            disabled={foraDaFaixa(hoje, min, max)}
            onClick={() => escolher(hoje)}
            className="rounded-sm px-2 py-1 text-xs font-medium text-primary transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:text-muted-foreground disabled:hover:bg-transparent"
          >
            Hoje
          </button>
        </div>
      </FloatingPanel>
    </div>
  )
}

export interface DateRangePickerProps {
  from: Date | string | null | undefined
  to: Date | string | null | undefined
  onChange: (range: { from: Date | null; to: Date | null }) => void
  min?: Date | null
  max?: Date | null
  disabled?: boolean
  className?: string
  labelFrom?: string
  labelTo?: string
}

/**
 * Faixa de período — o par "de/até" que toda tela financeira repete.
 *
 * A regra que ele carrega, e que cada tela erraria sozinha: **o fim nunca é
 * anterior ao início**. O campo "até" recebe `min` do "de", e escolher um
 * início posterior ao fim atual limpa o fim em vez de deixar uma faixa
 * impossível na tela.
 */
export function DateRangePicker({
  from,
  to,
  onChange,
  min,
  max,
  disabled,
  className,
  labelFrom = 'De',
  labelTo = 'Até',
}: DateRangePickerProps) {
  const de = toDate(from ?? null)
  const ate = toDate(to ?? null)

  return (
    <div className={cn('flex items-center gap-2', className)}>
      <DatePicker
        value={de}
        onChange={(d) => onChange({ from: d, to: ate && d && ate < d ? null : ate })}
        min={min}
        max={ate ?? max}
        disabled={disabled}
        aria-label={labelFrom}
      />
      <span aria-hidden="true" className="shrink-0 text-xs font-medium text-muted-foreground">
        até
      </span>
      <DatePicker
        value={ate}
        onChange={(d) => onChange({ from: de, to: d })}
        min={de ?? min}
        max={max}
        disabled={disabled}
        aria-label={labelTo}
      />
    </div>
  )
}
