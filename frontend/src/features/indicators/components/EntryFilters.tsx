import { Select, type SelectOption } from '@/components/ui/Select'
import { Label } from '@/components/ui/Label'
import { anosDisponiveis, MESES, nomeDoMes } from '../lib/periodo'
import type { Indicator } from '@/lib/api/indicators'

/**
 * `FE-325` — o cartão **FILTROS** da grade.
 *
 * Os três controles são os do legado
 * (`indicator_entries/_body.html.erb:12-28`), com o mesmo conteúdo:
 *
 * - **POR INDICADOR** — só os **ativos** do projeto, com a opção "Todos". No
 *   legado a lista vem de
 *   `current_user.default_project.indicators.where(is_active: 1)`; aqui vem do
 *   projeto **corrente**.
 * - **POR PERÍODO** — mês (os 12, com "Todos") e ano (**atual −5 a +5**, sem
 *   opção em branco, começando no ano atual). O helper do legado se chama
 *   `ten_years_array` e devolve **onze** anos; replicado.
 *
 * O que muda: **os filtros ficam na URL**. No legado eles se perdem entre
 * visitas e não dá para mandar a tela pronta para alguém. É deep-link, não
 * feature nova.
 */
export interface EntryFiltersProps {
  indicadores: Indicator[]
  indicadorId: string | null
  mes: number | null
  ano: number
  onIndicadorChange: (id: string | null) => void
  onMesChange: (mes: number | null) => void
  onAnoChange: (ano: number) => void
}

const TODOS = '__todos__'

export function EntryFilters({
  indicadores,
  indicadorId,
  mes,
  ano,
  onIndicadorChange,
  onMesChange,
  onAnoChange,
}: EntryFiltersProps) {
  const opcoesIndicador: SelectOption[] = [
    { value: TODOS, label: 'Todos', text: 'Todos' },
    ...indicadores.map((i) => ({ value: i.id, label: i.title, text: i.title })),
  ]

  const opcoesMes: SelectOption[] = [
    { value: TODOS, label: 'Todos', text: 'Todos' },
    ...MESES.map((m) => ({ value: String(m), label: nomeDoMes(m), text: nomeDoMes(m) })),
  ]

  const opcoesAno: SelectOption[] = anosDisponiveis().map((a) => ({
    value: String(a),
    label: String(a),
    text: String(a),
  }))

  return (
    <aside className="rounded-lg border border-border bg-card p-4">
      <h2 className="font-title text-xs font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        Filtros
      </h2>

      <div className="mt-4 space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="filtro-indicador" className="text-xs uppercase tracking-[0.05em] text-muted-foreground">
            Por indicador
          </Label>
          <Select
            id="filtro-indicador"
            aria-label="Filtrar por indicador"
            options={opcoesIndicador}
            value={indicadorId ?? TODOS}
            onChange={(v) => onIndicadorChange(v === TODOS ? null : v)}
          />
        </div>

        <div className="space-y-1.5">
          <Label className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Por período</Label>
          <div className="grid grid-cols-2 gap-2">
            <Select
              id="filtro-mes"
              aria-label="Filtrar por mês"
              options={opcoesMes}
              value={mes === null ? TODOS : String(mes)}
              onChange={(v) => onMesChange(v === TODOS ? null : Number(v))}
            />
            <Select
              id="filtro-ano"
              aria-label="Filtrar por ano"
              options={opcoesAno}
              value={String(ano)}
              onChange={(v) => onAnoChange(Number(v))}
            />
          </div>
        </div>
      </div>
    </aside>
  )
}
