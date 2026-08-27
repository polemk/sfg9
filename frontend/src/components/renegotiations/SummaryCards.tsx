import { CircleDollarSign, Wallet, Receipt, AlertTriangle, WifiOff, type LucideIcon } from 'lucide-react'
import { Tooltip } from '@/components/ui/Tooltip'
import { MobileKPI } from '@/components/mobile/MobileKPI'
import { useMobile } from '@/hooks/useMobile'
import { formatarReais } from '@/lib/api/projects'
import type { Renegotiation, RenegotiationGeneralValues } from '@/lib/api/renegotiations'

/**
 * **Os quatro cartões de resumo financeiro** (FE-206) — e o aviso de consistência.
 *
 * ## O defeito do legado que morre aqui
 *
 * O legado montava o objeto de valores em JavaScript e escrevia campo a campo no
 * DOM. **Um campo ausente na resposta levantava `TypeError` e parava a
 * atualização dos demais**: o usuário via três cartões novos e um velho, sem
 * nenhum aviso. Aqui cada cartão lê o seu campo com o traço como padrão, e
 * nenhum derruba outro.
 *
 * ## Os dois números que NÃO fecham entre si, e é assim mesmo
 *
 * **"R$ Pago" conta a mora; "R$ A Pagar" a ignora.** No legado
 * `paid_value = late_payment_value + paid_value_with_interest_cm`, enquanto
 * `remaining_value` é a soma de `pending_value` das parcelas — e no `pending_value`
 * a mora entra dos dois lados da conta e **se cancela** (Q-B26). Replicado por
 * DEC-30/DEC-02, com o tooltip dizendo isso na tela em vez de deixar o usuário
 * descobrir somando.
 *
 * **Sem polling** (Princípio 10): a atualização chega por Action Cable
 * (`useRenegotiationChannel`). Quando o canal cai, o cartão avisa em vez de
 * mostrar número velho como se fosse novo.
 */
export interface SummaryCardsProps {
  renegotiation: Renegotiation | undefined
  generalValues?: RenegotiationGeneralValues
  /** `false` = o canal caiu; a tela avisa em vez de mentir. */
  connected?: boolean
  loading?: boolean
}

export function SummaryCards({ renegotiation, generalValues, connected = true, loading }: SummaryCardsProps) {
  const mobile = useMobile()
  const r = renegotiation

  const cartoes = [
    {
      chave: 'total_debt',
      titulo: 'Dívida total',
      valor: r?.total_debt,
      icone: CircleDollarSign,
      dica: 'Valor total da dívida com juros projetados — o que foi contratado.',
    },
    {
      chave: 'paid_value',
      titulo: 'R$ Pago',
      valor: r?.paid_value,
      icone: Receipt,
      dica: 'Soma dos pagamentos, INCLUINDO a mora paga por atraso. Por isso ele e "R$ A Pagar" não somam a dívida total.',
    },
    {
      chave: 'remaining_value',
      titulo: 'R$ A Pagar',
      valor: r?.remaining_value,
      icone: Wallet,
      dica: 'Soma do que falta em cada parcela, com piso em zero — e SEM contar a mora.',
    },
    {
      chave: 'current_value',
      titulo: 'Valor presente (VP)',
      valor: r?.current_value,
      icone: CircleDollarSign,
      dica: 'Valor presente da dívida pela taxa acordada. Quando há juros e saldo em aberto, ele também passa a ser mostrado como "Valor Parcela".',
    },
  ]

  if (mobile) {
    return (
      <div className="flex flex-col gap-3">
        {!connected && <AvisoCanal />}
        <div className="grid grid-cols-2 gap-3">
          {cartoes.map((c) => (
            <MobileKPI
              key={c.chave}
              title={c.titulo}
              value={c.valor != null ? Number(c.valor) : 0}
              icon={c.icone}
              format="currency"
              loading={loading || c.valor == null}
            />
          ))}
        </div>
        <StatusLancamento renegotiation={r} generalValues={generalValues} />
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3">
      {!connected && <AvisoCanal />}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {cartoes.map((c) => (
          <Cartao key={c.chave} titulo={c.titulo} valor={c.valor} Icone={c.icone} dica={c.dica} carregando={loading} />
        ))}
      </div>
      <StatusLancamento renegotiation={r} generalValues={generalValues} />
    </div>
  )
}

function Cartao({
  titulo,
  valor,
  Icone,
  dica,
  carregando,
}: {
  titulo: string
  valor: string | undefined
  Icone: LucideIcon
  dica: string
  carregando?: boolean
}) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-border bg-card p-4 shadow-e1">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted-foreground">{titulo}</span>
        <Tooltip content={dica}>
          <span className="inline-flex">
            <Icone className="h-4 w-4 text-muted-foreground" aria-hidden />
          </span>
        </Tooltip>
      </div>
      {/* Campo ausente vira traço — nunca derruba os outros cartões. */}
      <span className="font-numeric text-2xl font-semibold tabular-nums text-foreground">
        {carregando || valor == null ? '—' : formatarReais(valor)}
      </span>
    </div>
  )
}

function AvisoCanal() {
  return (
    <div
      role="status"
      className="flex items-center gap-2 rounded-md border border-warning/30 bg-warning/10 px-3 py-2 text-sm text-warning"
    >
      <WifiOff className="h-4 w-4 shrink-0" aria-hidden />
      <span>
        Atualização em tempo real indisponível. Os valores abaixo são do último carregamento — recarregue a
        página para conferir.
      </span>
    </div>
  )
}

/**
 * "Status" — a consistência do LANÇAMENTO (BE-210). Antes da resposta mostra `—`,
 * não um valor otimista.
 */
function StatusLancamento({
  renegotiation,
  generalValues,
}: {
  renegotiation: Renegotiation | undefined
  generalValues?: RenegotiationGeneralValues
}) {
  const status = generalValues?.installment_status ?? renegotiation?.installment_status
  const naoLancado = generalValues?.unposted_value ?? renegotiation?.unposted_value

  if (!status) {
    return (
      <div className="rounded-lg border border-border bg-muted/40 px-4 py-3 text-sm text-muted-foreground">
        Status: <span className="font-numeric">—</span>
      </div>
    )
  }

  const inconsistente = status === 'Inconsistente'

  return (
    <div
      className={`flex flex-wrap items-center gap-x-4 gap-y-1 rounded-lg border px-4 py-3 text-sm ${
        inconsistente ? 'border-warning/30 bg-warning/10' : 'border-border bg-muted/40'
      }`}
    >
      {inconsistente && <AlertTriangle className="h-4 w-4 shrink-0 text-warning" aria-hidden />}
      <span className={inconsistente ? 'font-medium text-warning' : 'text-muted-foreground'}>
        Lançamento: <strong>{status}</strong>
      </span>
      <span className="text-muted-foreground">
        Falta lançar:{' '}
        <span className="font-numeric tabular-nums text-foreground">{formatarReais(naoLancado)}</span>
      </span>
      {inconsistente && (
        <span className="text-xs text-muted-foreground">
          O total das parcelas (principal + juros) não bate com a dívida contratada.
        </span>
      )}
    </div>
  )
}
