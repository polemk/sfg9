import { useEffect, useMemo, useState } from 'react'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { Label } from '@/components/ui/Label'
import { Select } from '@/components/ui/Select'
import { DatePicker } from '@/components/ui/DatePicker'
import { MoneyInput } from '@/components/ui/NumericInput'
import { formatarReais } from '@/lib/api/projects'
import { formatDate, toIsoDate } from '@/lib/utils/date'
import type { RenegotiationInstallment, RenegotiationPayment } from '@/lib/api/renegotiations'

/**
 * **O painel de pagamento** (FE-224, FE-225, FE-226).
 *
 * ⚠ **DEC-53 — não existe aba PAGAMENTOS.** O pagamento é lançado e editado a
 * partir da PARCELA, que é como o legado realmente o expunha; a aba própria está
 * comentada lá e não é portada aqui. O backend é completo (endpoints, autorização
 * e escopo), e o QA do Phase 4 **não deve abrir defeito pela aba ausente**.
 *
 * ## D-B12 — a data do pagamento é EDITÁVEL
 *
 * No legado o campo era travado em "hoje". Duas consequências: `days_late` era
 * **sempre 0**, o que tornava o cálculo de atraso inútil, e **pagamento
 * retroativo era impossível** — o operador que recebia o comprovante três dias
 * depois não tinha como registrar a data real.
 *
 * ## O teto, que agora existe em duas camadas
 *
 * "Pago Total" é calculado e o botão fica bloqueado com zero **e** com valor
 * acima do pendente. Corrige o **D-52**: no legado não havia checagem em camada
 * nenhuma — o pendente era só rótulo do seletor de previsão. ⚠ Isso **muda o que
 * hoje é aceito** e pode barrar lançamento que o operador fazia.
 */
export interface PaymentDrawerProps {
  open: boolean
  onClose: () => void
  /** Previsões elegíveis. O seletor mostra nº, vencimento e pendente. */
  installments: RenegotiationInstallment[]
  /** Parcela pré-selecionada (o painel foi aberto pela linha dela). */
  installmentId?: string | null
  /** Preenchido = modo EDIÇÃO. */
  editando?: RenegotiationPayment | null
  onSubmit: (dados: {
    renegotiation_installment_id: string
    date: string
    installment_paid_value_with_interest_cm: number
    late_payment_value: number
  }) => void
  salvando?: boolean
}

export function PaymentDrawer({
  open,
  onClose,
  installments,
  installmentId,
  editando,
  onSubmit,
  salvando,
}: PaymentDrawerProps) {
  const [parcelaId, setParcelaId] = useState<string | null>(null)
  const [data, setData] = useState<Date | string | null>(null)
  const [valor, setValor] = useState<number | null>(null)
  const [mora, setMora] = useState<number | null>(null)

  useEffect(() => {
    if (!open) return
    if (editando) {
      setParcelaId(editando.renegotiation_installment_id)
      setData(editando.date)
      setValor(Number(editando.installment_paid_value_with_interest_cm))
      setMora(Number(editando.late_payment_value))
    } else {
      setParcelaId(installmentId ?? null)
      setData(new Date())
      setValor(null)
      setMora(null)
    }
  }, [open, editando, installmentId])

  const parcela = useMemo(
    () => installments.find((i) => i.id === parcelaId),
    [installments, parcelaId],
  )

  // O pendente que o teto usa: na edição, o próprio pagamento sai da conta —
  // salvar sem alterar o valor não pode ser recusado pelo próprio valor.
  const pendenteDisponivel = useMemo(() => {
    if (!parcela) return null
    const pendente = Number(parcela.pending_value)
    if (!editando) return pendente
    return pendente + Number(editando.installment_paid_value_with_interest_cm)
  }, [parcela, editando])

  const pagoTotal = (valor ?? 0) + (mora ?? 0)
  const acimaDoPendente = pendenteDisponivel != null && (valor ?? 0) > pendenteDisponivel
  const podeSalvar =
    !!parcelaId && !!toIsoDate(data) && (valor ?? 0) > 0 && (mora ?? 0) >= 0 && !acimaDoPendente

  return (
    <SideDrawer
      open={open}
      onClose={onClose}
      title={editando ? `Editar pagamento #${editando.payment_number ?? ''}` : 'Registrar pagamento'}
      footer={
        <div className="flex items-center justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={salvando}>
            Cancelar
          </Button>
          <Button
            loading={salvando}
            disabled={!podeSalvar}
            onClick={() =>
              onSubmit({
                renegotiation_installment_id: parcelaId!,
                date: toIsoDate(data)!,
                installment_paid_value_with_interest_cm: valor ?? 0,
                late_payment_value: mora ?? 0,
              })
            }
          >
            {editando ? 'Salvar' : 'Registrar pagamento'}
          </Button>
        </div>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="parcela">Previsão</Label>
          <Select
            id="parcela"
            options={installments.map((i) => ({
              value: i.id,
              label: `#${i.number ?? '?'} · ${formatDate(i.due_date)}`,
              description: `Pendente ${formatarReais(i.pending_value)}`,
              disabled: !editando && Number(i.pending_value) <= 0,
            }))}
            value={parcelaId}
            onChange={setParcelaId}
            placeholder="Selecione a previsão…"
            // Na edição a parcela é FIXA: o servidor recusa mudá-la pela URL
            // (BE-222), e oferecer a troca na tela seria oferecer o que o
            // servidor nega.
            disabled={!!editando}
            block
          />
          {editando && (
            <p className="text-xs text-muted-foreground">
              A previsão de um pagamento não muda. Remova e lance de novo, se for o caso.
            </p>
          )}
        </div>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="data">Data do pagamento</Label>
          {/* **Editável** (D-B12): retroativo é caso legítimo, e é o que dá
              sentido ao cálculo de dias de atraso. */}
          <DatePicker id="data" value={data} onChange={setData} />
          {parcela && (
            <p className="text-xs text-muted-foreground">
              Vencimento da previsão: {formatDate(parcela.due_date)}. O atraso é calculado a partir dele.
            </p>
          )}
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="valor">Valor pago (principal + juros + correção)</Label>
            <MoneyInput id="valor" value={valor} onChange={setValor} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="mora">Mora e juros por atraso</Label>
            <MoneyInput id="mora" value={mora} onChange={setMora} />
          </div>
        </div>

        <section className="rounded-lg border border-border bg-muted/40 p-4">
          <dl className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Pendente da previsão</dt>
              <dd className="font-numeric tabular-nums text-foreground">
                {pendenteDisponivel != null ? formatarReais(pendenteDisponivel) : '—'}
              </dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Pago total</dt>
              <dd className="font-numeric tabular-nums text-foreground">{formatarReais(pagoTotal)}</dd>
            </div>
          </dl>

          {acimaDoPendente && (
            <p role="alert" className="mt-3 text-xs text-destructive-text">
              O valor pago não pode passar do pendente da previsão. O servidor recusa pelo mesmo motivo.
            </p>
          )}

          <p className="mt-3 text-xs text-muted-foreground">
            A mora entra no total pago <strong>e</strong> no total devido da previsão — por isso ela não
            reduz o pendente. É a conta do sistema atual, preservada.
          </p>
        </section>
      </div>
    </SideDrawer>
  )
}
