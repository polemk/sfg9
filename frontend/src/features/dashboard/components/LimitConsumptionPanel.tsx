import { Link } from 'react-router-dom'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { LimitMeters } from '@/components/charts/LimitMeters'
import { localizePercentLabel } from '@/lib/utils/number'
import { numeroDe, type DashboardLimits } from '@/lib/api/dashboard'

/**
 * **"Ainda cabe operação?"** — o consumo de cada tipo de limite contra o teto.
 *
 * É a pergunta que o gestor faz antes de aprovar a próxima entrada, e é
 * diferente das outras duas do painel: o cartão de exposição diz **quanto foi
 * usado**, o ranking por portador diz **onde está concentrado**, e este diz
 * **quanto ainda cabe**. Sem ele o painel mostra o tamanho do risco e esconde a
 * folga, que é o número que decide.
 *
 * ## Nada nasce aqui
 *
 * O payload é `Risk::AggregateService.total_limits_on` — **o mesmo** que desenha
 * a tabela do console de risco (BE-251). O percentual chega como texto pronto do
 * servidor e é impresso como chegou; o estado do semáforo (`at_ceiling`) também
 * é decidido onde o número nasce, para que o painel e o detalhe nunca usem dois
 * critérios para a mesma cor.
 *
 * ## Ordem
 *
 * Do mais consumido para o menos, definida no servidor. Ordenar no cliente daria
 * duas ordens possíveis para a mesma lista conforme quem a desenha.
 */
export function LimitConsumptionPanel({ limites }: { limites: DashboardLimits }) {
  const itens = limites.items.map((item) => ({
    id: item.label,
    label: item.label,
    used: numeroDe(item.used) ?? 0,
    total: numeroDe(item.total) ?? 0,
    available: numeroDe(item.available) ?? 0,
    // Os dígitos são do domínio; o separador decimal é da tela. Sem isto o
    // painel escrevia `51.76%` ao lado de `109,0%` do painel vizinho.
    percentLabel: localizePercentLabel(item.percent_label),
    tone: item.at_ceiling ? ('danger' as const) : ('ok' as const),
  }))

  const estourados = itens.filter((i) => i.tone === 'danger').length

  return (
    <ChartPanel
      title="Consumo de limite por tipo"
      subtitle={
        estourados > 0
          ? `${estourados} ${estourados === 1 ? 'tipo está' : 'tipos estão'} com disponível negativo em ${limites.date.split('-').reverse().join('/')}`
          : `Utilizado sobre o teto em ${limites.date.split('-').reverse().join('/')}`
      }
      hasData={limites.has_data}
      emptyTitle="Nenhum limite ativo neste projeto"
      emptyDescription="Cadastre um limite em Projeto › Limites e o consumo aparece aqui."
      labels={itens.map((i) => i.label)}
      values={itens.map((i) => i.used)}
      valueFormat="currency"
      labelHeader="Tipo de limite"
      valueHeader="Utilizado"
      headerSlot={
        <Link
          to="/risk"
          className="rounded-md text-xs font-medium text-primary-text underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Abrir o console de risco
        </Link>
      }
    >
      <LimitMeters items={itens} />
    </ChartPanel>
  )
}
