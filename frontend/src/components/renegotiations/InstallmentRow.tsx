import { ChevronDown, MoreVertical, Pencil, Trash2, Receipt } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Checkbox } from '@/components/ui/Checkbox'
import { Badge } from '@/components/ui/Badge'
import { Tooltip } from '@/components/ui/Tooltip'
import { formatarReais } from '@/lib/api/projects'
import { formatDate } from '@/lib/utils/date'
import type { RenegotiationInstallment, RenegotiationPayment } from '@/lib/api/renegotiations'

/**
 * **A linha de previsão, com os pagamentos aninhados** (FE-215, FE-216, FE-219).
 *
 * ## As três regras da caixa de seleção
 *
 * 1. **Parcela com pagamento NÃO recebe caixa** (FE-219) — porque ela não pode
 *    ser removida em lote, e oferecer a seleção seria oferecer o que o servidor
 *    recusa. No lugar dela fica um ícone com a explicação, não um espaço vazio.
 * 2. **No modo seleção, o clique na linha é ignorado** (FE-215): quem está
 *    marcando dez parcelas não quer abrir uma delas por engano.
 * 3. **A expansão dos pagamentos é independente da seleção** — dá para conferir
 *    o que foi pago antes de decidir marcar.
 *
 * O `color` do lote é o mesmo do legado: parcelas criadas juntas compartilham a
 * faixa lateral, e é assim que o usuário vê o lote.
 */
export interface InstallmentRowProps {
  parcela: RenegotiationInstallment
  expandida: boolean
  onToggleExpandir: () => void
  modoSelecao: boolean
  selecionada: boolean
  onToggleSelecao: () => void
  podeEscrever: boolean
  onGerarPagamento: () => void
  onEditar: () => void
  onRemover: () => void
  onEditarPagamento: (pagamento: RenegotiationPayment) => void
  onRemoverPagamento: (pagamento: RenegotiationPayment) => void
  onAcoesMobile?: () => void
  compacto?: boolean
}

export function InstallmentRow({
  parcela,
  expandida,
  onToggleExpandir,
  modoSelecao,
  selecionada,
  onToggleSelecao,
  podeEscrever,
  onGerarPagamento,
  onEditar,
  onRemover,
  onEditarPagamento,
  onRemoverPagamento,
  onAcoesMobile,
  compacto,
}: InstallmentRowProps) {
  const temPagamento = parcela.has_payments || parcela.payments.length > 0
  const vencida = !parcela.is_paid && new Date(`${parcela.due_date}T12:00:00`) < new Date()

  return (
    <li className="overflow-hidden rounded-lg border border-border bg-card">
      <div className="flex items-stretch">
        {/* Faixa da cor do LOTE — a identidade visual do grupo de criação. */}
        <span
          aria-hidden
          className="w-1 shrink-0"
          style={{ backgroundColor: parcela.color ?? 'transparent' }}
        />

        <div className="flex min-w-0 flex-1 flex-col gap-2 p-3 sm:flex-row sm:items-center sm:gap-4">
          <div className="flex min-w-0 flex-1 items-center gap-3">
            {modoSelecao &&
              (temPagamento ? (
                // FE-219 — sem caixa, COM explicação.
                <Tooltip content="Esta previsão tem pagamento lançado e não pode ser removida em lote.">
                  <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center">
                    <Receipt className="h-4 w-4 text-muted-foreground" aria-hidden />
                  </span>
                </Tooltip>
              ) : (
                <Checkbox
                  checked={selecionada}
                  onChange={onToggleSelecao}
                  aria-label={`Selecionar previsão ${parcela.number ?? ''}`}
                />
              ))}

            <button
              type="button"
              // No modo seleção o clique na linha é IGNORADO.
              onClick={modoSelecao ? undefined : onToggleExpandir}
              aria-expanded={expandida}
              disabled={modoSelecao}
              className="flex min-w-0 flex-1 items-center gap-2 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-default"
            >
              <ChevronDown
                aria-hidden
                className={`h-4 w-4 shrink-0 text-muted-foreground transition-transform ${expandida ? 'rotate-180' : ''} ${modoSelecao ? 'opacity-30' : ''}`}
              />
              <span className="min-w-0">
                <span className="block font-numeric text-sm font-medium tabular-nums text-foreground">
                  #{parcela.number ?? '—'} · {formatDate(parcela.due_date)}
                </span>
                <span className="block text-xs text-muted-foreground">
                  {temPagamento
                    ? `${parcela.payments.length} pagamento(s)`
                    : 'Sem pagamento'}
                </span>
              </span>
            </button>
          </div>

          <dl
            // Nove colunas cabem em três faixas de três no desktop largo, e
            // encolhem para cinco e depois quatro antes de virar as duas do
            // telefone. As larguras foram escolhidas para o valor NÃO truncar:
            // `formatarReais` de sete dígitos é o pior caso desta base.
            className={`grid flex-1 gap-x-4 gap-y-1 text-sm ${
              compacto ? 'grid-cols-2' : 'grid-cols-3 lg:grid-cols-5 xl:grid-cols-9'
            }`}
          >
            {/*
              **FE-213 — as NOVE colunas de valor do legado.**
              (`renegotiation_installments/list/_widget.html.erb:9-27`.)

              A migração trazia quatro — Principal, Total, Pago e Pendente — e
              as cinco do meio tinham sumido: **Juros, P+J, CM, P+J+CM e Mora**.
              Não é detalhe de exibição: elas são a DECOMPOSIÇÃO do total, e sem
              elas o usuário vê o resultado sem ver a conta. Numa renegociação
              com correção monetária, "por que o total é este?" deixa de ter
              resposta na tela. O dado já vinha do servidor inteiro.

              **Quatro no telefone, nove no computador.** As cinco do meio são
              derivadas, e nove colunas de dinheiro a 375 px viram uma coluna de
              números ilegível — a régua do projeto é que o telefone é onde se
              CONFERE, e conferir mal é pior que não conferir. Quem precisa da
              decomposição no telefone abre a linha: ela aparece completa lá.
            */}
            <Celula rotulo="Principal" valor={parcela.main_value} />
            {!compacto && <Celula rotulo="Juros" valor={parcela.interest_value} />}
            {!compacto && <Celula rotulo="P+J" valor={parcela.main_value_with_interest} />}
            {!compacto && <Celula rotulo="CM" valor={parcela.monetary_correction_value} />}
            {!compacto && <Celula rotulo="P+J+CM" valor={parcela.main_value_with_interest_cm} />}
            {!compacto && <Celula rotulo="Mora" valor={parcela.late_payment_value} />}
            <Celula rotulo="Total" valor={parcela.installment_total_value} />
            <Celula rotulo="Pago" valor={parcela.paid_value} />
            <Celula rotulo="Pendente" valor={parcela.pending_value} />
          </dl>

          <div className="flex shrink-0 items-center gap-2">
            {parcela.is_paid ? (
              <Badge variant="success">Quitada</Badge>
            ) : vencida ? (
              <Badge variant="destructive">Vencida</Badge>
            ) : (
              <Badge variant="secondary">Em aberto</Badge>
            )}

            {podeEscrever && !modoSelecao && (
              <>
                <span className="hidden items-center gap-1 sm:flex">
                  <Button variant="ghost" size="sm" onClick={onGerarPagamento} disabled={parcela.is_paid}>
                    Pagar
                  </Button>
                  <Button variant="ghost" size="icon" aria-label="Editar previsão" onClick={onEditar}>
                    <Pencil className="h-4 w-4" aria-hidden />
                  </Button>
                  {/* Remover só sem pagamento — o mesmo critério do servidor. */}
                  {temPagamento ? (
                    <Tooltip content="Remova os pagamentos antes de excluir a previsão.">
                      <span className="inline-flex h-10 w-10 items-center justify-center">
                        <Trash2 className="h-4 w-4 text-muted-foreground/50" aria-hidden />
                      </span>
                    </Tooltip>
                  ) : (
                    <Button variant="ghost" size="icon" aria-label="Remover previsão" onClick={onRemover}>
                      <Trash2 className="h-4 w-4 text-destructive-text" aria-hidden />
                    </Button>
                  )}
                </span>

                {onAcoesMobile && (
                  <Button
                    variant="ghost"
                    size="icon"
                    className="sm:hidden"
                    aria-label={`Ações da previsão ${parcela.number ?? ''}`}
                    onClick={onAcoesMobile}
                  >
                    <MoreVertical className="h-4 w-4" aria-hidden />
                  </Button>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      {expandida && (
        <div className="border-t border-border bg-muted/30 px-3 py-2 sm:pl-12">
          {/*
            **FE-213 no telefone.** As cinco colunas do meio não cabem na linha
            compacta, e some-las de vez tiraria a decomposição do total de quem
            usa o celular. Aqui elas aparecem inteiras, com a conta na ordem em
            que ela é feita: principal, juros, soma, correção, soma, mora.
          */}
          {compacto && (
            <dl className="grid grid-cols-2 gap-x-4 gap-y-1 border-b border-border pb-2 text-sm">
              <Celula rotulo="Juros" valor={parcela.interest_value} />
              <Celula rotulo="P+J" valor={parcela.main_value_with_interest} />
              <Celula rotulo="CM" valor={parcela.monetary_correction_value} />
              <Celula rotulo="P+J+CM" valor={parcela.main_value_with_interest_cm} />
              <Celula rotulo="Mora" valor={parcela.late_payment_value} />
            </dl>
          )}

          {parcela.payments.length === 0 ? (
            <p className="py-2 text-sm text-muted-foreground">Nenhum pagamento lançado nesta previsão.</p>
          ) : (
            <ul className="divide-y divide-border">
              {parcela.payments.map((pagamento) => (
                <li
                  key={pagamento.id}
                  className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm"
                >
                  <span className="font-numeric tabular-nums text-foreground">
                    #{pagamento.payment_number ?? '—'} · {formatDate(pagamento.date)}
                    {pagamento.days_late > 0 && (
                      <span className="ml-2 text-xs text-warning">{pagamento.days_late} dia(s) de atraso</span>
                    )}
                  </span>
                  <span className="flex items-center gap-3">
                    <span className="font-numeric tabular-nums text-muted-foreground">
                      {formatarReais(pagamento.installment_paid_value_with_interest_cm)}
                      {Number(pagamento.late_payment_value) > 0 && (
                        <span className="ml-1 text-xs">
                          + {formatarReais(pagamento.late_payment_value)} de mora
                        </span>
                      )}
                    </span>
                    <span className="font-numeric font-medium tabular-nums text-foreground">
                      {formatarReais(pagamento.total_paid_value)}
                    </span>
                    {podeEscrever && (
                      <span className="flex items-center gap-1">
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label="Editar pagamento"
                          onClick={() => onEditarPagamento(pagamento)}
                        >
                          <Pencil className="h-3.5 w-3.5" aria-hidden />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label="Excluir pagamento"
                          onClick={() => onRemoverPagamento(pagamento)}
                        >
                          <Trash2 className="h-3.5 w-3.5 text-destructive-text" aria-hidden />
                        </Button>
                      </span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </li>
  )
}

function Celula({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="min-w-0">
      <dt className="text-[0.65rem] uppercase tracking-[0.05em] text-muted-foreground">{rotulo}</dt>
      <dd className="truncate font-numeric text-sm tabular-nums text-foreground">{formatarReais(valor)}</dd>
    </div>
  )
}
