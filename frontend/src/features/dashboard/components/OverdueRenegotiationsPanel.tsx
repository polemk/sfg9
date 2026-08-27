import { Link } from 'react-router-dom'
import { CheckCircle2 } from 'lucide-react'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { formatAmount, formatMoney } from '@/lib/utils/number'
import { numeroDe, type DashboardOverdueRenegotiations } from '@/lib/api/dashboard'

/**
 * **"Quais renegociações estão em atraso, e quanto pesa cada uma?"**
 *
 * ## Por que este bloco, e por que aqui
 *
 * Ele fica **logo abaixo da lista de limites prestes a estourar**, e a vizinhança
 * é o argumento: são as duas listas de **exposição que já virou problema**, na
 * mesma forma — o cartão conta, a lista nomeia. Um gestor que vê
 * "1 renegociação em atraso" não sabe se são duas parcelas de um acordo pequeno
 * ou doze de um grande, e é essa diferença que decide para quem ele liga hoje.
 * O painel de limites diz *onde ainda dá tempo*; este diz *o que já venceu*.
 *
 * ## Forma: tabela, e é de propósito
 *
 * Os vizinhos são medidor e barra. Aqui não há uma medida contínua a comparar —
 * há **três atributos por linha** (quantas parcelas, de quem, quanto). Tabela é
 * a forma que mostra três colunas sem inventar um eixo, e o gêmeo "Ver valores"
 * fica escondido porque o conteúdo **já é** a tabela de valores.
 *
 * ## Nada é somado aqui
 *
 * `overdue_count` é apurado na consulta (o mesmo `live_overdue_for` que a
 * listagem de renegociações usa, OPS-473/BE-207) e `total_debt` é lido da
 * coluna que o agregado da renegociação mantém — exatamente como a tela de
 * detalhe faz.
 *
 * ## Truncar sem mentir
 *
 * O painel mostra as primeiras linhas e o rodapé diz **quantas ficaram de
 * fora**, com o caminho para a lista completa. Cortar em silêncio faria o painel
 * mentir sobre o tamanho do problema, que é o oposto do que ele existe para
 * fazer.
 */
export function OverdueRenegotiationsPanel({ dados }: { dados: DashboardOverdueRenegotiations }) {
  const emExtenso = dados.date.split('-').reverse().join('/')
  const ocultas = dados.total - dados.items.length

  return (
    <ChartPanel
      title="Renegociações em atraso"
      subtitle={
        dados.has_data
          ? `${dados.total} ${dados.total === 1 ? 'renegociação com parcela vencida' : 'renegociações com parcela vencida'} em ${emExtenso}`
          : `Conferido em ${emExtenso}, sobre as renegociações do projeto`
      }
      hasData={dados.has_data}
      hideValueTable
      emptyState={
        // Como no painel de limites: nenhuma parcela vencida é **boa notícia**,
        // e o ícone de caixa vazia diria o contrário.
        <div role="status" className="flex min-h-[8rem] flex-col items-center justify-center gap-3 text-center">
          <span className="flex h-11 w-11 items-center justify-center rounded-full bg-success/10 text-success">
            <CheckCircle2 className="h-5 w-5" />
          </span>
          <div className="space-y-1">
            <p className="text-sm font-semibold text-foreground">Nenhuma parcela vencida</p>
            <p className="max-w-sm text-xs text-muted-foreground">
              Todas as renegociações do projeto estão em dia em {emExtenso}. Assim que uma parcela vencer,
              o acordo aparece aqui com quantas parcelas estão em atraso.
            </p>
          </div>
        </div>
      }
      labels={dados.items.map((i) => i.title)}
      values={dados.items.map((i) => numeroDe(i.total_debt) ?? 0)}
      valueFormat="currency"
      labelHeader="Renegociação"
      valueHeader="Dívida total"
      headerSlot={
        <Link
          to="/renegotiations"
          className="rounded-md text-xs font-medium text-primary-text underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Ver as renegociações
        </Link>
      }
    >
      {/* **Sem largura mínima, e por isso sem rolagem horizontal.** Com
          `min-w-[22rem]` a tabela ficava mais larga que o cartão em 390 px e o
          último dígito de `R$ 236.480,50` era cortado — visto na captura. As
          colunas são proporcionais e o valor cai um corpo no telefone, onde
          `R$ 236.480,50` precisa de ~94 px nos 118 px que a coluna tem. */}
      <div className="overflow-x-auto">
        <table className="w-full table-fixed text-sm">
          <caption className="sr-only">Renegociações com parcela vencida em {emExtenso}</caption>
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-wide text-muted-foreground">
              <th scope="col" className="w-[46%] py-1.5 pr-2 text-left font-semibold">
                Renegociação
              </th>
              <th scope="col" className="w-[16%] px-2 py-1.5 text-right font-semibold">
                Vencidas
              </th>
              <th scope="col" className="w-[38%] py-1.5 pl-2 text-right font-semibold">
                Dívida total
              </th>
            </tr>
          </thead>
          <tbody>
            {dados.items.map((item) => (
              <tr key={item.id} className="border-b border-border/60 last:border-0">
                <th scope="row" className="min-w-0 py-2 pr-2 text-left font-normal">
                  <span className="block truncate text-foreground">{item.title}</span>
                  <span className="block truncate text-xs text-muted-foreground">{item.provider_name}</span>
                </th>
                {/* A contagem de parcelas em atraso é o número que ordena a
                    lista, e ganha o token negativo com o rótulo junto — cor
                    nunca sozinha. */}
                <td className="whitespace-nowrap px-2 py-2 text-right font-numeric font-semibold text-destructive">
                  {formatAmount(item.overdue_count, 0)}
                  <span className="sr-only"> parcelas vencidas</span>
                </td>
                <td className="whitespace-nowrap py-2 pl-2 text-right font-numeric text-xs text-foreground sm:text-sm">
                  {formatMoney(numeroDe(item.total_debt))}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {ocultas > 0 && (
        <p className="mt-2 text-xs text-muted-foreground">
          {ocultas === 1 ? 'Mais 1 renegociação em atraso não cabe aqui.' : `Mais ${ocultas} renegociações em atraso não cabem aqui.`}{' '}
          <Link to="/renegotiations" className="text-primary-text underline-offset-2 hover:underline">
            Ver todas
          </Link>
        </p>
      )}
    </ChartPanel>
  )
}
