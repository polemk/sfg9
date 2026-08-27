import { useQuery } from '@tanstack/react-query'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { CategoryBarChart } from '@/components/charts/CategoryBarChart'
import { dashboardApi, valoresDaSerie, CARRIER_VOLUME_KEY } from '@/lib/api/dashboard'

/**
 * **"Onde está concentrado o risco?"** — a exposição por portador na data.
 *
 * A terceira pergunta do painel, e a única que fala de **concentração**. Dois
 * projetos com a mesma exposição total são situações completamente diferentes se
 * num deles ela está espalhada por seis portadores e no outro está em um. O
 * cartão de exposição não distingue os dois; este painel distingue.
 *
 * ## O mesmo endpoint da tela de indicadores
 *
 * `GET /api/v1/dashboard/volume_by_carrier`, que é
 * `Risk::AggregateService.volume_by_carrier_on` — o mesmo
 * `Calculator.limite_utilizado_on` da coluna "Lim. util" do console de risco. Um
 * endpoint, dois consumidores: o painel e a tela de lançamentos. Duplicar a
 * consulta é como as duas telas começam a discordar.
 *
 * ## Valor negativo aparece como está (DEC-01)
 *
 * Utilização é `Σ saldo × (−1)`, então saldo positivo produz utilização
 * negativa. Foi observado no seed — dois de três portadores. A barra vai para o
 * outro lado do eixo, com o token negativo, e o valor com sinal aparece no
 * rótulo direto e na tabela. Corrigir o sinal aqui seria mudar número de tela
 * sem ninguém ter decidido isso.
 */
export function CarrierExposurePanel({ date }: { date: string }) {
  const consulta = useQuery({
    queryKey: [...CARRIER_VOLUME_KEY, date],
    queryFn: () => dashboardApi.volumeByCarrier({ date }),
    placeholderData: (anterior) => anterior,
  })

  const dados = consulta.data
  const emExtenso = date.split('-').reverse().join('/')

  return (
    <ChartPanel
      title="Exposição por portador"
      subtitle={`Limite utilizado em ${emExtenso}`}
      loading={consulta.isLoading}
      error={consulta.isError ? consulta.error : undefined}
      onRetry={() => consulta.refetch()}
      // Lista vazia = não há limite ativo. Não é o mesmo que "todos zerados".
      hasData={(dados?.labels.length ?? 0) > 0}
      emptyTitle="Nenhum limite ativo neste projeto"
      emptyDescription="A exposição por portador sai dos limites de risco. Cadastre um limite em Projeto › Limites."
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
