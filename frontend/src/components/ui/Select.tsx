import * as React from 'react'
import { Check, ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { FloatingPanel } from './FloatingPanel'

/**
 * Select do design system — aposenta o `<select>` cru com classe `glass-select`.
 *
 * Por que sair do nativo: o `<option>` do navegador **não aceita estilo** no
 * Chrome/Firefox do Linux. A lista abria com fundo branco de sistema no tema
 * escuro, ignorando `bg-popover` e a marca inteira. Um `<select>` "tematizado"
 * é sempre só a caixa fechada tematizada — DEC-98 exige o painel **aberto**
 * conferido nos dois modos, e o nativo reprova por construção.
 *
 * É membro da biblioteca (não peça de tela) porque escolha entre opções aparece
 * em filtro de listagem, em formulário e em célula de tabela. O painel vai em
 * portal via `FloatingPanel` — ver lá o motivo.
 *
 * Teclado: setas navegam, Enter/Espaço escolhe, Escape fecha, Home/End vão às
 * pontas. Digitar uma letra pula para a primeira opção que começa com ela, como
 * no nativo.
 */
export interface SelectOption<T extends string = string> {
  value: T
  label: React.ReactNode
  /** Texto usado na busca por tecla e no rótulo do gatilho. */
  text?: string
  description?: React.ReactNode
  disabled?: boolean
}

export interface SelectProps<T extends string = string> {
  options: SelectOption<T>[]
  value: T | null | undefined
  onChange: (value: T) => void
  placeholder?: string
  disabled?: boolean
  /** Estende o gatilho à largura do contêiner. Padrão: sim. */
  block?: boolean
  size?: 'sm' | 'default'
  id?: string
  name?: string
  'aria-label'?: string
  className?: string
  /** Classe do painel — só layout (largura mínima), nunca cor. */
  panelClassName?: string
}

function textoDe(o: SelectOption<any> | undefined): string {
  if (!o) return ''
  if (o.text) return o.text
  return typeof o.label === 'string' ? o.label : String(o.value)
}

export function Select<T extends string = string>({
  options,
  value,
  onChange,
  placeholder = 'Selecione…',
  disabled,
  block = true,
  size = 'default',
  id,
  name,
  className,
  panelClassName,
  ...aria
}: SelectProps<T>) {
  const [open, setOpen] = React.useState(false)
  const [ativo, setAtivo] = React.useState(0)
  const triggerRef = React.useRef<HTMLButtonElement>(null)
  const listRef = React.useRef<HTMLDivElement>(null)
  const buscaRef = React.useRef({ termo: '', em: 0 })
  const autoId = React.useId()
  const listId = `${id ?? autoId}-list`

  const selecionada = options.find((o) => o.value === value)
  const indiceSelecionado = options.findIndex((o) => o.value === value)

  React.useEffect(() => {
    if (open) setAtivo(indiceSelecionado >= 0 ? indiceSelecionado : 0)
  }, [open, indiceSelecionado])

  // Mantém a opção ativa visível ao navegar por teclado.
  React.useEffect(() => {
    if (!open) return
    const el = listRef.current?.querySelector<HTMLElement>(`[data-idx="${ativo}"]`)
    el?.scrollIntoView({ block: 'nearest' })
  }, [open, ativo])

  const escolher = (i: number) => {
    const o = options[i]
    if (!o || o.disabled) return
    onChange(o.value)
    setOpen(false)
    triggerRef.current?.focus()
  }

  const proximoHabilitado = (de: number, passo: number) => {
    for (let i = 1; i <= options.length; i++) {
      const j = (de + passo * i + options.length * options.length) % options.length
      if (!options[j]?.disabled) return j
    }
    return de
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (disabled) return
    if (!open && (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault()
      setOpen(true)
      return
    }
    if (!open) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setAtivo((i) => proximoHabilitado(i, 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setAtivo((i) => proximoHabilitado(i, -1))
    } else if (e.key === 'Home') {
      e.preventDefault()
      setAtivo(proximoHabilitado(-1, 1))
    } else if (e.key === 'End') {
      e.preventDefault()
      setAtivo(proximoHabilitado(0, -1))
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      escolher(ativo)
    } else if (e.key === 'Escape') {
      e.preventDefault()
      setOpen(false)
    } else if (e.key.length === 1) {
      // Busca por digitação, como no `<select>` nativo: as teclas somam
      // enquanto vierem rápido, e o termo zera depois de 700ms parado.
      const agora = Date.now()
      const b = buscaRef.current
      b.termo = agora - b.em > 700 ? e.key : b.termo + e.key
      b.em = agora
      const alvo = b.termo.toLowerCase()
      const i = options.findIndex((o) => !o.disabled && textoDe(o).toLowerCase().startsWith(alvo))
      if (i >= 0) setAtivo(i)
    }
  }

  return (
    <>
      <button
        ref={triggerRef}
        id={id}
        type="button"
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listId : undefined}
        aria-label={aria['aria-label']}
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        onKeyDown={onKeyDown}
        className={cn(
          'inline-flex items-center justify-between gap-2 rounded-md border border-input bg-background px-3 text-left text-sm text-foreground transition-colors',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
          'disabled:cursor-not-allowed disabled:opacity-50',
          !disabled && 'hover:border-ring',
          // No telefone o gatilho sobe para 44 px (critério 1 da §5.4.8): `h-10`
          // é 40, e um filtro que o polegar erra é um filtro que não se usa. No
          // desktop a altura volta a ser a do resto do formulário.
          size === 'sm' ? 'h-11 md:h-9' : 'h-11 md:h-10',
          block && 'w-full',
          className,
        )}
      >
        <span className={cn('truncate', !selecionada && 'text-muted-foreground')}>
          {selecionada ? selecionada.label : placeholder}
        </span>
        <ChevronDown
          aria-hidden="true"
          className={cn('h-4 w-4 shrink-0 text-muted-foreground transition-transform', open && 'rotate-180')}
        />
      </button>

      {/* Espelho nativo: mantém o valor acessível a `FormData` e ao autofill
          sem colocar o `<option>` do sistema na tela. */}
      {name && <input type="hidden" name={name} value={value ?? ''} />}

      <FloatingPanel
        open={open}
        anchorRef={triggerRef as React.RefObject<HTMLElement>}
        onDismiss={() => setOpen(false)}
        className={panelClassName}
      >
        <div ref={listRef} id={listId} role="listbox" tabIndex={-1} className="overflow-y-auto p-1">
          {options.length === 0 && (
            <p className="px-3 py-6 text-center text-xs text-muted-foreground">Nenhuma opção disponível.</p>
          )}
          {options.map((o, i) => {
            const marcada = o.value === value
            return (
              <button
                key={o.value}
                type="button"
                role="option"
                data-idx={i}
                aria-selected={marcada}
                disabled={o.disabled}
                onMouseEnter={() => setAtivo(i)}
                onClick={() => escolher(i)}
                className={cn(
                  // 48 px de alvo no telefone: a lista aberta é onde a escolha
                  // acontece, e as opções vinham com 36. `md:` devolve a densidade
                  // do desktop, onde o alvo é o ponteiro.
                  'flex w-full min-h-[3rem] items-center gap-2 rounded-sm px-3 py-2 text-left text-sm transition-colors',
                  'md:min-h-0 md:items-start',
                  'disabled:cursor-not-allowed disabled:opacity-40',
                  i === ativo && !o.disabled ? 'bg-accent text-accent-foreground' : 'text-popover-foreground',
                )}
              >
                <Check
                  aria-hidden="true"
                  className={cn('mt-0.5 h-4 w-4 shrink-0 text-primary', !marcada && 'invisible')}
                />
                <span className="flex min-w-0 flex-col">
                  <span className="truncate">{o.label}</span>
                  {o.description && <span className="text-xs text-muted-foreground">{o.description}</span>}
                </span>
              </button>
            )
          })}
        </div>
      </FloatingPanel>
    </>
  )
}
