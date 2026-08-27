import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { formatDate } from '@/lib/utils/date'
import { formatMoney } from '@/lib/utils/number'
import { riskOperationsApi, type RiskOperation } from '../api/risk'

/**
 * **A cadeia de renovações** (FE-267).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `create_risk_operations` está entre as 24 migrations que nunca subiram.
 * Fonte: `../sfg/app/models/risk_operation.rb:113-139`.
 *
 * ## O que este cartão mostra, e por que o estado de cada elo importa
 *
 * A cadeia é montada por `original_id`, que aponta **sempre para a raiz** —
 * nunca para o elo anterior (`:117`). Por isso o cartão lista a cadeia inteira,
 * e não só o vizinho.
 *
 * **DEC-35:** renovar **não** encerra a original. Os elos anteriores continuam
 * abertos e continuam consumindo limite enquanto as vigências se sobrepõem. A
 * coluna de estado existe justamente para que isso seja visível: sem ela, "por
 * que o limite está no teto?" vira uma investigação.
 *
 * O `tasks.md` desta fatia prometia o contrário (IMP-R1, encerrar a original).
 * A DEC-35 veio depois e mandou replicar o legado; o cartão reflete a DEC.
 */
export function RenewalsCard({ operacao }: { operacao: RiskOperation }) {
  const consulta = useQuery({
    queryKey: ['risk-renewals', operacao.id],
    queryFn: () => riskOperationsApi.renewals(operacao.id),
  })

  const elos = consulta.data ?? []
  // Só existe cadeia quando há mais de um elo. Cartão de uma linha só é ruído.
  if (elos.length < 2) return null

  const abertos = elos.filter((e) => !e.is_ended).length

  return (
    <Card className="p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold text-foreground">Cadeia de renovações</h3>
        <span className="text-xs text-muted-foreground">
          {elos.length} operações · <span className="font-numeric">{abertos}</span> em aberto
        </span>
      </div>

      <div className="mt-3 overflow-x-auto">
        <table className="w-full min-w-[34rem] text-sm">
          <caption className="sr-only">Elos da cadeia de renovação desta operação</caption>
          <thead>
            <tr className="border-b border-border text-left text-xs text-muted-foreground">
              <th scope="col" className="pb-2 pr-3 font-medium">Operação</th>
              <th scope="col" className="pb-2 pr-3 font-medium">Emissão</th>
              <th scope="col" className="pb-2 pr-3 font-medium">Vencimento</th>
              <th scope="col" className="pb-2 pr-3 text-right font-medium">Capital</th>
              <th scope="col" className="pb-2 font-medium">Estado</th>
            </tr>
          </thead>
          <tbody>
            {elos.map((elo) => (
              <tr key={elo.id} className="border-b border-border/60 last:border-0">
                <td className="py-2 pr-3">
                  {elo.id === operacao.id ? (
                    <span className="font-medium">{elo.title} (esta)</span>
                  ) : (
                    <Link
                      to={`/risk-operations/${elo.id}`}
                      className="text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      {elo.title}
                    </Link>
                  )}
                </td>
                <td className="py-2 pr-3 font-numeric">{formatDate(elo.issue_date)}</td>
                <td className="py-2 pr-3 font-numeric">{formatDate(elo.due_date)}</td>
                <td className="py-2 pr-3 text-right font-numeric">
                  {formatMoney(Number(elo.operation_value))}
                </td>
                <td className="py-2">
                  <Badge variant={elo.is_ended ? 'secondary' : 'default'}>
                    {elo.is_ended ? 'Encerrada' : 'Em aberto'}
                  </Badge>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {abertos > 1 && (
        <p className="mt-3 text-xs text-muted-foreground">
          Mais de um elo em aberto: enquanto as vigências se sobrepõem, todos consomem o limite do
          portador. É o comportamento do produto (DEC-35), não uma inconsistência.
        </p>
      )}
    </Card>
  )
}
