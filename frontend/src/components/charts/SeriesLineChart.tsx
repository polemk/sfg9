import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { getThemeVars } from './theme'
import { CHART_TOKENS } from './chartTokens'
import { formatExact, formatTick, yAxisWidth, type ChartFormat } from './chartFormat'

/**
 * **Série temporal de UMA medida** — a forma para "como isto evoluiu".
 *
 * ## Por que existe, ao lado de `RechartsLine`
 *
 * `RechartsLine` é da base ai9 e continua **intacto** (Princípio 6b): ele nasceu
 * para "crescimento de assinaturas", imprime o valor cru no tooltip
 * (`{val}` → `605602.54`) e usa a largura padrão de eixo do Recharts, que corta
 * o rótulo de sete dígitos. Num console financeiro em pt-BR os dois são defeito,
 * e os dois foram vistos na tela. Ele não tem gancho de formatação, então a
 * correção não cabia numa prop.
 *
 * Este componente é o **membro novo da biblioteca** que serve o app inteiro daqui
 * em diante: mesmo tema, mesma tipografia de eixo, mesmo tooltip, e o formato
 * vindo do sistema (`chartFormat`), não de cada tela.
 *
 * ## Decisões de desenho, e de onde vêm
 *
 * - **Uma série, nenhuma legenda.** O título nomeia a medida; caixa de legenda
 *   para uma linha só é ruído.
 * - **Cor:** `--info`. Medido: o ouro da marca (`--primary`) dá **1,63:1** sobre
 *   o card claro — abaixo do mínimo de 3:1 para marca de dado. O ouro continua
 *   sendo a cor de ação da marca; ele não carrega dado.
 * - **Grade sólida e discreta**, não tracejada: tracejo lê como projeção.
 * - **Marca fina** (2 px) e ponto pequeno; o realce é do ponto sob o cursor.
 * - **Sem `dataKey` numérico no eixo X**: o rótulo vem pronto do servidor.
 */
export interface SeriesLineChartProps {
  labels: string[]
  values: number[]
  format?: ChartFormat
  /** Altura em px. O padrão já inclui a faixa do eixo X. */
  height?: number
  /** Nome da medida, para o leitor de tela e para o tooltip. */
  measureLabel?: string
}

export function SeriesLineChart({
  labels,
  values,
  format = 'currency',
  height = 260,
  measureLabel,
}: SeriesLineChartProps) {
  const tema = getThemeVars()
  const dados = labels.map((label, i) => ({ label, value: Number(values[i] ?? 0) }))
  const eixo = { fill: tema.fgMuted as string, fontSize: 12 }

  return (
    <div style={{ width: '100%', height }} role="img" aria-label={`Gráfico de linha: ${measureLabel ?? 'série'}`}>
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={dados} margin={{ top: 12, right: 16, left: 0, bottom: 8 }}>
          <CartesianGrid stroke={tema.grid} vertical={false} />
          <XAxis dataKey="label" tick={eixo} tickLine={false} axisLine={{ stroke: tema.grid }} minTickGap={16} />
          <YAxis
            tick={eixo}
            tickLine={false}
            axisLine={false}
            // A largura vem do rótulo mais largo que ESTA série produz. Era isto
            // que faltava: com a largura padrão, `R$ 1,6 mi` virava `6 mi`.
            width={yAxisWidth(values, format)}
            tickFormatter={(v: number) => formatTick(v, format)}
          />
          <Tooltip
            cursor={{ stroke: tema.grid }}
            content={({ active, payload }) => {
              if (!active || !payload?.length) return null
              const ponto = payload[0]?.payload as { label: string; value: number } | undefined
              if (!ponto) return null
              return (
                <div className="rounded-lg border border-border bg-popover px-3 py-2 shadow-e3">
                  <p className="mb-0.5 text-xs text-muted-foreground">{ponto.label}</p>
                  <p className="font-numeric text-sm font-semibold text-foreground">
                    {formatExact(ponto.value, format)}
                  </p>
                </div>
              )
            }}
          />
          <Line
            type="monotone"
            dataKey="value"
            stroke={CHART_TOKENS.series}
            strokeWidth={2}
            dot={{ r: 2.5, stroke: CHART_TOKENS.series, fill: CHART_TOKENS.series }}
            activeDot={{ r: 5 }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
