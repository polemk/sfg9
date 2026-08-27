// Gráfico de pizza/rosca — o equivalente ai9 do `vendor/doughnut` do legado
// (DEC-10: usar as libs do ai9, não portar a lib proprietária).
import * as React from 'react'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import { vibrantPalette } from './theme'
import { EmptyState } from '@/components/ui/States'
import { formatAmount, formatMoney, formatPercent } from '@/lib/utils/number'

/**
 * RechartsPie — distribuição por categoria, com rótulo, legenda e total.
 *
 * **Nota de escopo (achado #1 do `migration-map.md`):** o legado declara o
 * `vendor/doughnut` mas **não instancia nenhum gráfico** em view nenhuma. Isto
 * aqui é o componente ficando disponível para as fatias que vierem — não é uma
 * tela portada.
 *
 * Duas coisas mudaram em relação à versão que estava na base ai9:
 *
 * 1. **Some o dado falso.** Quando o total era zero, a versão anterior
 *    desenhava cinco fatias iguais rotuladas `Chat/Facebook/Instagram/Site/
 *    WhatsApp` — categorias de outro produto, inventadas na tela. Um gráfico
 *    que mostra dado que não existe é pior que um espaço vazio: o usuário lê e
 *    acredita. Agora o vazio é o `EmptyState` da biblioteca.
 * 2. **O valor é formatado em pt-BR** e a unidade é do consumidor (`unidade`
 *    ou `variant="money"`), em vez do literal `"leads"` cravado no tooltip.
 *
 * Cor vem de `vibrantPalette()`, que é token — muda sozinha entre claro e
 * escuro. Nunca acrescente hex aqui.
 */
export interface PieItem {
  label: string
  value: number
}

export interface RechartsPieProps {
  items: PieItem[]
  /** `donut` (padrão) abre o miolo e mostra o total no centro. */
  shape?: 'donut' | 'pie'
  /** Formatação do valor no tooltip e no centro. */
  variant?: 'number' | 'money' | 'percent'
  /** Sufixo do valor quando `variant="number"` (ex.: "contratos"). */
  unidade?: string
  height?: number
  emptyMessage?: string
  /** Rótulo acessível — descreva **o que** o gráfico divide. */
  ariaLabel?: string
}

function formatar(valor: number, variant: RechartsPieProps['variant'], unidade?: string): string {
  if (variant === 'money') return formatMoney(valor)
  if (variant === 'percent') return formatPercent(valor)
  return unidade ? `${formatAmount(valor, 0)} ${unidade}` : formatAmount(valor, 0)
}

export function RechartsPie({
  items,
  shape = 'donut',
  variant = 'number',
  unidade,
  height = 320,
  emptyMessage = 'Sem dados para o período selecionado.',
  ariaLabel = 'Gráfico de distribuição',
}: RechartsPieProps) {
  const data = React.useMemo(
    () => (items || []).map((d) => ({ name: d.label, value: Number(d.value || 0) })).filter((d) => d.value > 0),
    [items],
  )
  const total = data.reduce((a, b) => a + b.value, 0)
  const COLORS = vibrantPalette()

  if (total <= 0) {
    return <EmptyState size="inline" title="Nada para exibir" description={emptyMessage} />
  }

  return (
    <div style={{ width: '100%', height }} role="img" aria-label={ariaLabel}>
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={data}
            dataKey="value"
            nameKey="name"
            innerRadius={shape === 'donut' ? 80 : 0}
            outerRadius={120}
            stroke="hsl(var(--card))"
            strokeWidth={4}
            isAnimationActive={false}
          >
            {data.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip
            content={({ payload }) => {
              if (!payload || !payload.length) return null
              const p: any = payload[0]
              const valor = Number(p?.value || 0)
              const percentual = total > 0 ? (valor / total) * 100 : 0
              return (
                <div className="rounded-md border border-border bg-popover px-3 py-2.5 text-popover-foreground shadow-e3">
                  <p className="mb-0.5 text-xs text-muted-foreground">{p?.name ?? ''}</p>
                  <p className="font-numeric text-sm font-semibold tabular-nums text-foreground">
                    {formatar(valor, variant, unidade)}
                  </p>
                  <p className="font-numeric text-xs tabular-nums text-muted-foreground">
                    {formatPercent(percentual, 1)}
                  </p>
                </div>
              )
            }}
          />
          <Legend
            verticalAlign="bottom"
            height={24}
            formatter={(value) => <span style={{ color: 'hsl(var(--muted-foreground))' }}>{value}</span>}
          />
        </PieChart>
      </ResponsiveContainer>
    </div>
  )
}
