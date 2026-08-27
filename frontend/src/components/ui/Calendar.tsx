import * as React from 'react'
import {
  addMonths,
  eachDayOfInterval,
  endOfMonth,
  endOfWeek,
  format,
  isAfter,
  isBefore,
  isSameDay,
  isSameMonth,
  startOfDay,
  startOfMonth,
  startOfWeek,
} from 'date-fns'
import { ptBR } from 'date-fns/locale'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * Calendário pt-BR — grade de mês, semana começando no **domingo**.
 *
 * Membro da biblioteca porque quase toda tela financeira do Safegold filtra por
 * período (FE-745): recebíveis, renegociações, indicadores e risco. É usado
 * pelo `DatePicker` e pelo `DateRangePicker`, e pode ser embutido direto num
 * painel de filtro.
 *
 * Sem dependência nova: `date-fns` já está no `package.json` e o locale pt-BR
 * vem dele. Um datepicker de terceiro traria CSS próprio, que é justamente o
 * que a tematização acabou de tirar do caminho.
 */
export interface CalendarProps {
  /** Dia selecionado (modo simples) ou início da faixa. */
  selected?: Date | null
  /** Fim da faixa. Presente = pinta o intervalo. */
  rangeEnd?: Date | null
  /** Dia sob o cursor durante a escolha do fim da faixa. */
  hoveredEnd?: Date | null
  onSelect: (date: Date) => void
  onHover?: (date: Date | null) => void
  min?: Date | null
  max?: Date | null
  /** Mês exibido (controlado). Sem ele, o calendário controla o próprio mês. */
  month?: Date
  onMonthChange?: (month: Date) => void
  /**
   * **Dias que TÊM conteúdo** (S11 / FE-122, Lacuna L-06). Recebem um ponto sob
   * o número, além do rótulo acessível — no painel de disponibilidade são os
   * dias com lançamento, e é por eles que o usuário navega o mês.
   *
   * O legado marcava com a classe `-marked-` do `air-datepicker`, e a marca era
   * **só visual**: quem usa leitor de tela não tinha como saber quais dias
   * tinham lançamento. Aqui a informação entra também no `aria-label`.
   */
  marked?: Date[]
  /** Como descrever um dia marcado para leitor de tela. */
  markedLabel?: string
  className?: string
}

const DIAS = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']

export function Calendar({
  selected,
  rangeEnd,
  hoveredEnd,
  onSelect,
  onHover,
  min,
  max,
  month,
  onMonthChange,
  marked,
  markedLabel = 'com lançamento',
  className,
}: CalendarProps) {
  const [mesInterno, setMesInterno] = React.useState(() => startOfMonth(selected ?? new Date()))
  const mes = month ?? mesInterno

  const trocarMes = (delta: number) => {
    const novo = addMonths(mes, delta)
    if (month === undefined) setMesInterno(novo)
    onMonthChange?.(novo)
  }

  // Grade fechada: sempre semanas inteiras, para a altura do painel não pular
  // entre um mês de 5 e um de 6 linhas.
  const dias = React.useMemo(
    () =>
      eachDayOfInterval({
        start: startOfWeek(startOfMonth(mes), { weekStartsOn: 0 }),
        end: endOfWeek(endOfMonth(mes), { weekStartsOn: 0 }),
      }),
    [mes],
  )

  const fimEfetivo = rangeEnd ?? hoveredEnd ?? null
  const inicio = selected ? startOfDay(selected) : null
  const fim = fimEfetivo ? startOfDay(fimEfetivo) : null
  const [faixaDe, faixaAte] = inicio && fim && isBefore(fim, inicio) ? [fim, inicio] : [inicio, fim]

  const bloqueado = (d: Date) =>
    (min ? isBefore(startOfDay(d), startOfDay(min)) : false) ||
    (max ? isAfter(startOfDay(d), startOfDay(max)) : false)

  const rotuloMes = format(mes, 'MMMM yyyy', { locale: ptBR })

  // Conjunto de chaves `aaaa-MM-dd`: comparar por string é O(1) por célula, e
  // uma varredura com `isSameDay` sobre a lista inteira seria O(dias × marcados)
  // a cada render — num mês com lançamento todo dia isso é 42 × 31.
  const diasMarcados = React.useMemo(
    () => new Set((marked ?? []).map((d) => format(d, 'yyyy-MM-dd'))),
    [marked],
  )

  return (
    <div className={cn('w-[17.5rem] select-none p-3', className)}>
      <div className="mb-2 flex items-center justify-between">
        <button
          type="button"
          aria-label="Mês anterior"
          onClick={() => trocarMes(-1)}
          className="flex h-7 w-7 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <span aria-live="polite" className="text-sm font-semibold capitalize text-foreground">
          {rotuloMes}
        </span>
        <button
          type="button"
          aria-label="Próximo mês"
          onClick={() => trocarMes(1)}
          className="flex h-7 w-7 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <div className="grid grid-cols-7 gap-y-1" onMouseLeave={() => onHover?.(null)}>
        {DIAS.map((d, i) => (
          <div
            key={`${d}-${i}`}
            aria-hidden="true"
            className="pb-1 text-center text-[10px] font-bold uppercase tracking-widest text-muted-foreground"
          >
            {d}
          </div>
        ))}
        {dias.map((d) => {
          const foraDoMes = !isSameMonth(d, mes)
          const desabilitado = bloqueado(d)
          const ehInicio = faixaDe ? isSameDay(d, faixaDe) : false
          const ehFim = faixaAte ? isSameDay(d, faixaAte) : false
          const noMeio =
            faixaDe && faixaAte && isAfter(startOfDay(d), faixaDe) && isBefore(startOfDay(d), faixaAte)
          const marcado = ehInicio || ehFim
          const hoje = isSameDay(d, new Date())
          const temConteudo = diasMarcados.has(format(d, 'yyyy-MM-dd'))

          return (
            <button
              key={d.toISOString()}
              type="button"
              disabled={desabilitado}
              aria-pressed={marcado}
              aria-label={
                format(d, "d 'de' MMMM 'de' yyyy", { locale: ptBR }) +
                (temConteudo ? `, ${markedLabel}` : '')
              }
              onClick={() => onSelect(d)}
              onMouseEnter={() => onHover?.(d)}
              className={cn(
                'relative mx-auto flex h-8 w-8 items-center justify-center rounded-sm font-numeric text-xs tabular-nums transition-colors',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                'disabled:cursor-not-allowed disabled:opacity-30',
                foraDoMes ? 'text-muted-foreground/60' : 'text-foreground',
                noMeio && 'bg-accent text-accent-foreground',
                marcado && 'bg-primary text-primary-foreground hover:bg-brand-gold-deep',
                !marcado && !desabilitado && 'hover:bg-accent hover:text-accent-foreground',
                hoje && !marcado && 'ring-1 ring-inset ring-primary',
              )}
            >
              {format(d, 'd')}
              {temConteudo && (
                <span
                  aria-hidden="true"
                  className={cn(
                    'absolute bottom-1 left-1/2 h-1 w-1 -translate-x-1/2 rounded-full',
                    marcado ? 'bg-primary-foreground' : 'bg-primary',
                  )}
                />
              )}
            </button>
          )
        })}
      </div>
    </div>
  )
}
