import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { FileText, GitBranch } from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { DetailList } from '@/components/ui/DetailList'
import { useMobile } from '@/hooks/useMobile'
import { formatDate } from '@/lib/utils/date'
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { riskOperationsApi, type RiskOperation } from '../api/risk'
import { LastMovementCard } from './LastMovementCard'
import { RenewalsCard } from './RenewalsCard'

/**
 * **A aba GERAL do detalhe** (FE-265, FE-266, FE-267, FE-268).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * Fonte: `../sfg/app/views/pub/console/parts/risk_operations/detail/`.
 *
 * ## FE-265 — "Saldo Inicial" é exibido NEGATIVO, e isso é DEC-01
 *
 * O banco guarda `original_balance` com o sinal invertido
 * (`risk_operation.rb:34`) e **esta tela mostra assim**, enquanto o formulário
 * de edição mostra o valor absoluto. Os dois convivem no legado; a melhoria foi
 * **declinada pelo usuário** (D-93) e está no `improvements-log.md`. **QA não
 * deve abrir bug** para o sinal.
 *
 * ## FE-268 — os chips são `<Link>` de verdade
 *
 * "Recebível" e "Operação Original" levam ao registro. No legado eram rótulos
 * mortos, e o operador copiava o id na mão.
 */
export function OperationGeneralTab({ operacao }: { operacao: RiskOperation }) {
  const estreito = useMobile()

  const ultimo = useQuery({
    queryKey: ['risk-last-movement', operacao.id],
    queryFn: () => riskOperationsApi.lastMovement(operacao.id),
  })

  const semJanela = operacao.has_pre_faturamento || operacao.is_static

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        {operacao.is_ended && (
          <Badge variant="secondary">
            Encerrada — continua consumindo limite
          </Badge>
        )}
        {operacao.is_static && <Badge variant="secondary">Par estático do limite</Badge>}
        {operacao.is_on_variable && <Badge variant="secondary">Considerada no variável</Badge>}

        {/* FE-268 — chips como links reais. */}
        {operacao.receivable_id && (
          <Link
            to={`/receivables/${operacao.receivable_id}`}
            className="inline-flex items-center gap-1 rounded-md border border-border bg-card px-2 py-1 text-xs text-foreground hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <FileText className="h-3.5 w-3.5" aria-hidden />
            Recebível
          </Link>
        )}
        {operacao.original_id && operacao.original_id !== operacao.id && (
          <Link
            to={`/risk-operations/${operacao.original_id}`}
            className="inline-flex items-center gap-1 rounded-md border border-border bg-card px-2 py-1 text-xs text-foreground hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <GitBranch className="h-3.5 w-3.5" aria-hidden />
            Operação original
          </Link>
        )}
      </div>

      <Card className="p-4">
        <DetailList
          layout={estreito ? 'stack' : 'grid'}
          columns={2}
          items={[
            { label: 'Empresa', content: operacao.company_title },
            { label: 'Portador', content: operacao.carrier_title },
            { label: 'Tipo', content: operacao.operation_type_title },
            { label: 'Subtipo', content: operacao.operation_subtype_title },
            { label: 'Nº do contrato', content: operacao.contract_number || null },
            {
              label: 'Emissão',
              content: semJanela ? '-' : formatDate(operacao.issue_date),
            },
            {
              label: 'Vencimento',
              content: semJanela ? '-' : formatDate(operacao.due_date),
            },
            {
              label: 'Vencimento original',
              content: semJanela ? '-' : formatDate(operacao.original_due_date),
              hidden: !operacao.original_due_date,
            },
            {
              label: 'Capital da operação',
              content: formatMoney(Number(operacao.operation_value)),
              numeric: true,
            },
            {
              // **FE-265 / DEC-01** — exibido com o sinal NEGATIVO gravado.
              label: 'Saldo inicial',
              content: formatMoney(Number(operacao.original_balance)),
              numeric: true,
            },
            { label: 'Saldo atual', content: formatMoney(Number(operacao.balance)), numeric: true },
            { label: 'Taxa acordada', content: formatPercent(Number(operacao.agreed_rate)), numeric: true },
            { label: 'Prorrogações', content: String(operacao.extensions_count), numeric: true },
            { label: 'Observação', content: operacao.observation || null, full: true },
          ]}
        />
      </Card>

      <LastMovementCard dados={ultimo.data} />

      {/* FE-267 — só aparece quando a cadeia existe. */}
      <RenewalsCard operacao={operacao} />
    </div>
  )
}
