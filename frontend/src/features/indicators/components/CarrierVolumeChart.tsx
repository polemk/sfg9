import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { CategoryBarChart } from '@/components/charts/CategoryBarChart'
import { dashboardApi, valoresDaSerie, CARRIER_VOLUME_KEY } from '@/lib/api/dashboard'
import { nomeCurtoDoMes } from '../lib/periodo'

/**
 * S15 / `NEW-001` (parte 2) — **volume por portador**.
 *
 * > **Feature NOVA (DEC-21), não paridade.** Ver a nota do
 * > `IndicatorSeriesChart`: o legado carregava uma biblioteca de gráfico e
 * > nenhuma view a instanciava. O QA do Phase 4 **não deve procurar isto no
 * > legado**.
 *
 * ## De onde vem o número
 *
 * De `GET /api/v1/dashboard/volume_by_carrier`, que chama
 * `Risk::AggregateService.volume_by_carrier_on` — o **mesmo**
 * `Calculator.limite_utilizado_on` que pinta a coluna "Lim. util" do console de
 * risco (BE-249/BE-251), só que acumulado por portador em vez de por tipo.
 * Nenhum valor financeiro é agregado no cliente (contrato **C2**).
 *
 * ## A data de apuração, e por que ela é escrita na tela
 *
 * A exposição é um número **de uma data**, não de um intervalo; a tela de
 * lançamentos filtra por **período** (ano, e opcionalmente mês). A tradução é
 * uma só, e está aqui: a data é o **fim do período filtrado**, e nunca o
 * futuro — apurar exposição em 31/12 de um ano que ainda não acabou mostraria
 * um saldo que ninguém pode conferir. O subtítulo diz a data escolhida, porque
 * um número sem data neste domínio não quer dizer nada.
 *
 * O gráfico **não tem filtro próprio** (design G3): ele deriva do filtro da
 * tela. Um segundo filtro ao lado do primeiro produziria duas verdades na mesma
 * página.
 *
 * ## Cor não é o único portador de informação
 *
 * Todas as barras têm a **mesma** cor de propósito: é uma medida só (volume) em
 * categorias sem ordem natural, e colorir cada portador queimaria o único canal
 * livre para repetir o que o comprimento da barra já diz. Quem identifica o
 * portador é o **rótulo do eixo**, o **tooltip** e a **tabela de valores** —
 * três caminhos, nenhum deles a cor.
 *
 * ## Valor negativo aparece como está (DEC-01)
 *
 * `limite_utilizado_on` é `Σ saldo × (−1)`, e saldo positivo produz utilização
 * negativa. Isso acontece com dado real (foi observado no seed de demonstração:
 * dois de três portadores negativos). A barra desce abaixo do eixo, e o valor
 * vai para a tabela com o sinal — corrigi-lo aqui seria mudar número de tela
 * sem ninguém ter decidido isso.
 */
export interface CarrierVolumeChartProps {
  ano: number
  /** `null` = o ano inteiro. */
  mes: number | null
}

/** Fim do período filtrado, **nunca no futuro**. Formato ISO, que é o que a API lê. */
export function dataDeApuracao(ano: number, mes: number | null, hoje = new Date()): string {
  // `new Date(ano, mes, 0)` = último dia do mês `mes` (mês seguinte, dia zero).
  const fimDoPeriodo = mes !== null ? new Date(ano, mes, 0) : new Date(ano, 11, 31)
  const alvo = fimDoPeriodo > hoje ? hoje : fimDoPeriodo

  const mm = String(alvo.getMonth() + 1).padStart(2, '0')
  const dd = String(alvo.getDate()).padStart(2, '0')
  return `${alvo.getFullYear()}-${mm}-${dd}`
}

function porExtenso(iso: string): string {
  const [a, m, d] = iso.split('-')
  return `${d}/${m}/${a}`
}

export function CarrierVolumeChart({ ano, mes }: CarrierVolumeChartProps) {
  const data = useMemo(() => dataDeApuracao(ano, mes), [ano, mes])

  const consulta = useQuery({
    queryKey: [...CARRIER_VOLUME_KEY, data],
    queryFn: () => dashboardApi.volumeByCarrier({ date: data }),
    placeholderData: (anterior) => anterior,
  })

  const dados = consulta.data
  const periodo = mes !== null ? `${nomeCurtoDoMes(mes)} de ${ano}` : `${ano}`

  return (
    <ChartPanel
      title="Volume por portador"
      subtitle={`Limite utilizado em ${porExtenso(data)} — fim do período filtrado (${periodo})`}
      loading={consulta.isLoading}
      error={consulta.isError ? consulta.error : undefined}
      onRetry={() => consulta.refetch()}
      // Lista vazia = **não há limite ativo no projeto**. Tudo zerado é outra
      // coisa, e o servidor manda `has_data` para que as duas não se confundam.
      hasData={(dados?.labels.length ?? 0) > 0}
      emptyTitle="Nenhum limite ativo neste projeto"
      emptyDescription="O volume por portador sai dos limites de risco. Cadastre um limite em Projeto › Limites e ele aparece aqui."
      labels={dados?.labels ?? []}
      values={valoresDaSerie(dados)}
      valueFormat="currency"
      labelHeader="Portador"
      valueHeader="Limite utilizado"
    >
      <CategoryBarChart
        labels={dados?.labels ?? []}
        values={valoresDaSerie(dados)}
        measureLabel="Limite utilizado por portador"
      />
    </ChartPanel>
  )
}
