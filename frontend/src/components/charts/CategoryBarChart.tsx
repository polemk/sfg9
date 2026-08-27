import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, LabelList, ResponsiveContainer, Cell } from 'recharts'
import { useMobile } from '@/hooks/useMobile'
import { getThemeVars } from './theme'
import { CHART_TOKENS } from './chartTokens'
import { formatExact, formatTick, type ChartFormat } from './chartFormat'

/**
 * **Ranking de uma medida por categoria** — a forma para "onde isto está
 * concentrado".
 *
 * Barras **horizontais** de propósito: o rótulo da categoria é um nome próprio
 * ("FIDC Aurora Crédito"), e nome próprio em eixo vertical vira texto inclinado
 * ou cortado. Deitado, cada nome tem uma linha inteira.
 *
 * ## Cor
 *
 * **Uma medida, uma cor** — `--info`, a mesma da linha. Colorir cada categoria
 * queimaria o único canal livre para repetir o que o comprimento da barra já
 * diz, e é o anti-padrão da rampa sobre categoria nominal. Quem identifica a
 * categoria é o rótulo do eixo, o rótulo direto no fim da barra e a tabela.
 *
 * **Valor negativo troca para `--negative`** — aqui a cor SIGNIFICA estado, não
 * identidade, e é o mesmo par de tokens do semáforo da tela de risco (FE-238).
 * O sinal também vai no rótulo, então a cor nunca é o único portador.
 *
 * Medido: o ouro da marca dá 1,63:1 sobre o card claro e não pode carregar
 * dado; `--info`, `--negative` e `--success` passam nos dois modos.
 */
export interface CategoryBarChartProps {
  labels: string[]
  values: number[]
  format?: ChartFormat
  /** Altura por barra, em px. A altura total cresce com a quantidade. */
  rowHeight?: number
  measureLabel?: string
}

export function CategoryBarChart({
  labels,
  values,
  format = 'currency',
  rowHeight = 34,
  measureLabel,
}: CategoryBarChartProps) {
  // **A largura útil no telefone é ~310 px**, e o eixo de categorias comia
  // metade dela: as barras ficavam com um toco e o rótulo do valor caía por
  // cima do eixo. Visto renderizando em 390×844. O nome inteiro continua no
  // tooltip e na tabela de valores, então encurtar o eixo não esconde nada.
  const estreito = useMobile()
  const tema = getThemeVars()
  const dados = labels.map((label, i) => ({ label, value: Number(values[i] ?? 0) }))
  const eixo = { fill: tema.fgMuted as string, fontSize: 12 }

  // A largura do eixo de categorias sai do nome mais longo, com teto: nome muito
  // comprido não pode comer a área do desenho. O que não couber é truncado pelo
  // Recharts e continua inteiro no tooltip e na tabela de valores.
  const larguraCategoria = Math.min(
    estreito ? 96 : 170,
    Math.max(estreito ? 72 : 80, labels.reduce((m, l) => Math.max(m, l.length), 0) * 6.6 + 8),
  )

  const altura = Math.max(140, dados.length * rowHeight + 44)
  // Há valor negativo? Então o eixo cruza o zero e a barra cresce para a
  // ESQUERDA — a margem daquele lado precisa caber o rótulo direto, senão ele
  // sai por cima do nome do portador. Visto na tela: `-R$ 1,3 mil` colado em
  // "FIDC Solaris Recebíveis".
  const temNegativo = dados.some((d) => d.value < 0)

  return (
    <div
      style={{ width: '100%', height: altura }}
      role="img"
      aria-label={`Gráfico de barras: ${measureLabel ?? 'valores por categoria'}`}
    >
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={dados}
          layout="vertical"
          margin={{ top: 4, right: estreito ? 56 : 76, left: temNegativo ? (estreito ? 44 : 60) : 0, bottom: 8 }}
        >
          <CartesianGrid stroke={tema.grid} horizontal={false} />
          <XAxis
            type="number"
            tick={eixo}
            tickLine={false}
            axisLine={{ stroke: tema.grid }}
            tickFormatter={(v: number) => formatTick(v, format)}
          />
          <YAxis
            type="category"
            dataKey="label"
            tick={eixo}
            tickLine={false}
            axisLine={false}
            width={larguraCategoria}
          />
          <Tooltip
            cursor={{ fill: 'transparent' }}
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
          <Bar dataKey="value" radius={[0, 4, 4, 0]} isAnimationActive={false} barSize={16}>
            {dados.map((d, i) => (
              <Cell key={i} fill={d.value < 0 ? CHART_TOKENS.negative : CHART_TOKENS.series} />
            ))}
            {/* Rótulo direto no fim da barra: é ele que faz o valor existir sem
                depender do tooltip, que não existe no teclado nem no toque.

                **Dois `LabelList`, e não um.** Numa barra deitada, `right` é a
                ponta direita da barra — que para valor NEGATIVO é a linha do
                zero, ou seja, em cima do nome da categoria. Cada sinal ganha o
                lado que é a ponta LIVRE da sua barra, e o do outro sinal
                devolve texto vazio. */}
            <LabelList
              dataKey="value"
              position="right"
              className="font-numeric"
              style={{ fill: tema.fgMuted as string, fontSize: 11 }}
              // O tipo do Recharts admite texto vazio aqui; a guarda existe
              // para o rótulo não virar `NaN` numa barra sem valor.
              formatter={(v) => (typeof v === 'number' && v >= 0 ? formatTick(v, format) : '')}
            />
            <LabelList
              dataKey="value"
              position="left"
              className="font-numeric"
              style={{ fill: tema.fgMuted as string, fontSize: 11 }}
              formatter={(v) => (typeof v === 'number' && v < 0 ? formatTick(v, format) : '')}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
