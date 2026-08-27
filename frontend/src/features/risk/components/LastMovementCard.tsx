import { cn } from '@/lib/utils'
import { Card } from '@/components/ui/Card'
import { formatDate } from '@/lib/utils/date'
import { formatMoney } from '@/lib/utils/number'
import type { LastMovement } from '../api/risk'

/**
 * **Cartão "última movimentação"** (FE-266).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * Fonte: `../sfg/app/controllers/pub/risk_operations_controller.rb:163-176`
 * (`geral_update_values`).
 *
 * ## O 500 que morre aqui
 *
 * O legado faz `@last_movement.date.strftime(...)` **sem checar `nil`**: abrir o
 * detalhe de qualquer operação **sem movimento** derruba a tela — e o par
 * estático do limite nasce exatamente assim. O servidor agora devolve payload
 * vazio (BE-255) e este componente mostra o estado "ainda não há movimento".
 *
 * ## Os números vêm prontos (C2)
 *
 * `movement_value_sign` (−1 crédito / +1 débito) e `total_balance` chegam do
 * `Risk::Calculator`. **Este componente não soma nada** — ele escolhe o token
 * de cor e formata.
 *
 * ## D-101 — um par de tokens, não duas paletas
 *
 * `--negative` e `--success` já são os indicadores da marca (`#7D1F1E` e
 * `#217B55`, os mesmos valores do legado, definidos em `globals.css` nos dois
 * modos). O legado tinha duas paletas concorrentes para a mesma ideia; aqui o
 * par é único, como a decisão B-10 da S5 fixou.
 */
export function LastMovementCard({ dados }: { dados: LastMovement | undefined }) {
  const vazio = !dados || Object.keys(dados).length === 0

  if (vazio) {
    return (
      <Card className="p-4">
        <h3 className="text-sm font-semibold text-foreground">Última movimentação</h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Esta operação ainda não tem movimento. O saldo continua no saldo inicial.
        </p>
      </Card>
    )
  }

  const credito = dados.movement_value_sign === -1
  const saldo = Number(dados.total_balance ?? 0)

  return (
    <Card className="p-4">
      <h3 className="text-sm font-semibold text-foreground">Última movimentação</h3>

      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-xs text-muted-foreground">Data</dt>
          <dd className="font-numeric">{formatDate(dados.movement_date)}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Tipo</dt>
          <dd>{dados.movement_type ?? '—'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Valor</dt>
          <dd className={cn('font-numeric', credito ? 'text-success' : 'text-negative')}>
            {formatMoney(Number(dados.movement_value ?? 0))}
            {credito ? 'C' : 'D'}
          </dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Saldo total</dt>
          <dd className={cn('font-numeric', saldo < 0 ? 'text-negative' : 'text-success')}>
            {formatMoney(saldo)}
          </dd>
        </div>
      </dl>
    </Card>
  )
}
