import { DatePicker } from '@/components/ui/DatePicker'
import { Select } from '@/components/ui/Select'

/**
 * **O filtro de tempo do painel — uma POSIÇÃO e uma JANELA, nunca duas datas.**
 *
 * O painel mistura duas naturezas de tempo: exposição, limites no teto e
 * renegociações em atraso são **ponto no tempo** ("em 26/08/2026"); total
 * operado e a série são **período** ("09/2025 a 08/2026"). Um filtro que
 * ignorasse essa diferença produziria número errado ou selo mentiroso.
 *
 * A decisão (design G7): **há exatamente um ponto no tempo na página.** A data
 * define a posição; o período **não é uma segunda data**, é uma **janela**
 * ancorada nessa mesma posição — "os N meses que terminam no mês da data".
 *
 * Por que isso não é detalhe de interface: dois seletores de **data** na mesma
 * tela deixam o usuário comparar números apurados em dias diferentes sem
 * perceber. Com uma posição e uma janela isso é impossível por construção —
 * mexer na janela não move a data de apuração de cartão nenhum, e mexer na data
 * move tudo junto.
 *
 * ## Reuso
 *
 * `DatePicker` e `Select` são os da biblioteca compartilhada, os mesmos que o
 * resto do console usa. Nenhum controle novo nasce aqui: um terceiro jeito de
 * escolher data seria o começo de três comportamentos de teclado diferentes.
 *
 * ## Sem polling
 *
 * Trocar a data ou a janela muda a chave da consulta e o React Query revalida.
 * Nenhum temporizador é ligado (Princípio 10).
 */
export interface DashboardFiltersProps {
  /** ISO `YYYY-MM-DD`. A posição — o "hoje" do painel. */
  date: string
  months: number
  onDateChange: (iso: string) => void
  onMonthsChange: (months: number) => void
  /** Some enquanto o resumo ainda não chegou, para não sugerir controle morto. */
  disabled?: boolean
}

/**
 * As janelas oferecidas. Não é uma escala arbitrária: 6 é o semestre, 12 é o
 * exercício e 24 é o que o seed de demonstração cobre (`demo-seed-design.md`
 * §8) — é com ela que a série mostra a virada de ano.
 */
const JANELAS = [
  { value: '6', label: '6 meses' },
  { value: '12', label: '12 meses' },
  { value: '24', label: '24 meses' },
]

function paraIso(data: Date | null): string | null {
  if (!data) return null
  const mm = String(data.getMonth() + 1).padStart(2, '0')
  const dd = String(data.getDate()).padStart(2, '0')
  return `${data.getFullYear()}-${mm}-${dd}`
}

export function DashboardFilters({
  date,
  months,
  onDateChange,
  onMonthsChange,
  disabled,
}: DashboardFiltersProps) {
  return (
    <div className="flex flex-wrap items-end gap-3">
      <div className="min-w-0">
        <label
          htmlFor="dashboard-data"
          className="mb-1 block text-[10px] font-bold uppercase tracking-[0.14em] text-muted-foreground"
        >
          Posição em
        </label>
        <DatePicker
          id="dashboard-data"
          value={date}
          // **Não limpável.** Painel sem data de apuração não é um estado: todo
          // número desta tela é "de uma data", e um campo vazio produziria
          // requisição sem posição.
          clearable={false}
          disabled={disabled}
          aria-label="Data de apuração do painel"
          onChange={(nova) => {
            const iso = paraIso(nova)
            if (iso) onDateChange(iso)
          }}
          className="w-[10.5rem]"
        />
      </div>

      <div className="min-w-0">
        <label
          htmlFor="dashboard-janela"
          className="mb-1 block text-[10px] font-bold uppercase tracking-[0.14em] text-muted-foreground"
        >
          Janela
        </label>
        <Select
          id="dashboard-janela"
          options={JANELAS}
          value={String(months)}
          block={false}
          disabled={disabled}
          aria-label="Janela do total operado, em meses"
          onChange={(valor) => onMonthsChange(Number(valor))}
          className="w-[8.5rem]"
        />
      </div>
    </div>
  )
}
