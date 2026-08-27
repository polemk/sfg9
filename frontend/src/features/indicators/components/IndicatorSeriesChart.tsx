import { useMemo } from 'react'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { SeriesLineChart } from '@/components/charts/SeriesLineChart'
import type { GridRow } from '@/lib/api/indicators'
import { nomeCurtoDoMes, paraNumero } from '../lib/periodo'

/**
 * S15 / `NEW-001` (parte 1) — **a série mensal de um indicador**.
 *
 * > **Feature NOVA (DEC-21), não paridade.** Não existe no legado: `Doughnut` é
 * > exposto como global em `../sfg/app/frontend/vendor/js/index.js.erb:31,37` e
 * > **nenhuma view o instancia** (grep em `app/views/`, `app/frontend/js/`,
 * > `*.erb`, `*.js`, `*.scss`: zero ocorrências fora de `vendor/`). O QA do
 * > Phase 4 **não deve procurar este gráfico na origem**. Isto **supera**, por
 * > decisão posterior do usuário, a nota de escopo do DEC-09 — que continua
 * > correta quanto ao legado.
 *
 * ## Não há segunda consulta, e é isso que faz o gráfico ser verdade
 *
 * Ele desenha **a grade que está na mesma tela** — o mesmo array `linhas` que a
 * `MonthlyGrid` renderiza, vindo de `GET /api/v1/indicator_entries/grid`
 * (BE-324/BE-716). Uma consulta própria criaria a chance de gráfico e tabela
 * discordarem por meio segundo de cache, e ninguém saberia qual acreditar.
 * Pelo mesmo motivo o gráfico **não tem filtro próprio** (design G3): o período
 * e o indicador são os da tela.
 *
 * ## Mês não lançado NÃO vira ponto em zero (DEC-70 / D-117)
 *
 * A célula não lançada chega como `entry: null` — que é ausência de informação,
 * não o valor zero. O gráfico de linha **não sabe desenhar buraco**: um `null` no
 * meio da série vira ponto em zero. Então a série leva **só os meses lançados**: um mês sem
 * lançamento some do eixo em vez de afirmar que o indicador valeu zero. O eixo
 * fica irregular quando há buraco, e é por isso que o subtítulo diz quantos
 * meses foram lançados — o buraco fica visível, em vez de virar um número falso.
 *
 * ## Não há série derivada
 *
 * Nada de variação mês a mês, acumulado, média ou percentual: isso continua
 * fora de escopo pela nota de `openspec/specs/indicators/spec.md`. O gráfico
 * plota **o que está lançado**, e só.
 */
export interface IndicatorSeriesChartProps {
  linhas: GridRow[]
  /** O indicador escolhido no cartão de FILTROS da tela. `null` = todos. */
  indicadorId: string | null
  ano: number
  /** `null` = os 12 meses. Com um mês só não há série a desenhar. */
  mes: number | null
}

export function IndicatorSeriesChart({ linhas, indicadorId, ano, mes }: IndicatorSeriesChartProps) {
  // Com um indicador escolhido, é ele. Sem escolha, só desenha quando **não há
  // ambiguidade** (o projeto tem um indicador só) — escolher o primeiro de uma
  // lista seria o gráfico decidir por conta própria de qual dado está falando.
  const linha = useMemo(() => {
    if (indicadorId) return linhas.find((l) => l.indicator.id === indicadorId) ?? null
    return linhas.length === 1 ? linhas[0] : null
  }, [linhas, indicadorId])

  const pontos = useMemo(() => {
    if (!linha) return { labels: [] as string[], values: [] as number[] }

    const lancados = linha.cells
      .filter((celula) => celula.entry !== null)
      .map((celula) => ({
        label: nomeCurtoDoMes(celula.month),
        value: paraNumero(celula.entry?.value) ?? 0,
      }))

    return { labels: lancados.map((p) => p.label), values: lancados.map((p) => p.value) }
  }, [linha])

  // Mês único: a grade mostra uma linha só, e uma "série" de um ponto não é uma
  // série. Dizer isso é melhor do que desenhar um ponto solto.
  if (mes !== null) {
    return (
      <ChartPanel
        title="Série mensal"
        subtitle={`Filtro em um mês só (${nomeCurtoDoMes(mes)} de ${ano})`}
        hasData={false}
        emptyTitle="A série precisa de mais de um mês"
        emptyDescription='Escolha "Todos os meses" no filtro de PERÍODO para ver a evolução do indicador.'
        labels={[]}
        values={[]}
      >
        {null}
      </ChartPanel>
    )
  }

  if (!linha) {
    return (
      <ChartPanel
        title="Série mensal"
        subtitle={`${ano}`}
        hasData={false}
        emptyTitle="Escolha um indicador"
        emptyDescription="O gráfico mostra um indicador por vez. Use POR INDICADOR no cartão de filtros — o gráfico segue o mesmo filtro da grade."
        labels={[]}
        values={[]}
      >
        {null}
      </ChartPanel>
    )
  }

  const totalDeMeses = linha.cells.length
  const lancados = pontos.labels.length

  return (
    <ChartPanel
      title={`Série mensal — ${linha.indicator.title}`}
      subtitle={
        lancados > 0
          ? `${lancados} de ${totalDeMeses} meses lançados em ${ano}. Mês não lançado não aparece na linha.`
          : `${ano}`
      }
      hasData={lancados > 0}
      emptyTitle="Sem lançamentos no período"
      emptyDescription="Nenhum mês deste ano foi lançado para este indicador. Preencha uma célula da grade e a linha aparece aqui — um mês em branco não é o mesmo que zero."
      labels={pontos.labels}
      values={pontos.values}
      valueFormat="currency"
      labelHeader="Mês"
      valueHeader="Valor lançado"
    >
      <SeriesLineChart labels={pontos.labels} values={pontos.values} measureLabel={linha.indicator.title} />
    </ChartPanel>
  )
}
