import { useEffect, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { Campo } from '@/app/pages/catalogs/CatalogFields'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { DatePicker } from '@/components/ui/DatePicker'
import { LoadingState } from '@/components/ui/States'
import { Textarea } from '@/components/ui/textarea'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatDate } from '@/lib/utils/date'
import { riskOperationsApi, type RiskOperation } from '../api/risk'

/**
 * **Prorrogar vencimento** (FE-274).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `create_risk_operation_extensions` está entre as 24 migrations que nunca
 * subiram. Fonte:
 * `../sfg/app/controllers/pub/risk_operation_extensions_controller.rb:18-39`.
 *
 * ## O `minDate` deixou de ser a única trava
 *
 * No legado a data mínima (`due_date + 1`) existia **só no datepicker**: por
 * requisição direta dava para **encurtar** o vencimento, e o `after_create`
 * aplicava a data menor sem reclamar, deixando movimentos legítimos fora da
 * janela. Aqui o `min` vem do servidor (`GET :id/extensions/new`) **e** o
 * servidor recusa (`BE-277`). Os dois lados dizem a mesma coisa porque leem o
 * mesmo número.
 *
 * A prorrogação é **log imutável**: não há editar nem excluir, nem aqui nem no
 * legado. Corrigir é lançar outra.
 */
export function ExtensionDrawer({
  operacao,
  onClose,
  onExtended,
}: {
  operacao: RiskOperation
  onClose: () => void
  onExtended: () => void
}) {
  const [novaData, setNovaData] = useState<Date | null>(null)
  const [observacao, setObservacao] = useState('')

  const previa = useQuery({
    queryKey: ['risk-operation-extension-preview', operacao.id],
    queryFn: () => riskOperationsApi.extensionPreview(operacao.id),
  })

  useEffect(() => {
    if (!previa.data) return
    setNovaData(new Date(`${previa.data.new_due_date}T00:00:00`))
  }, [previa.data])

  const minima = previa.data ? new Date(`${previa.data.min_due_date}T00:00:00`) : null

  const prorrogar = useMutation({
    mutationFn: () =>
      riskOperationsApi.createExtension(operacao.id, {
        new_due_date: novaData ? novaData.toISOString().slice(0, 10) : '',
        observation: observacao || undefined,
      }),
    onSuccess: () => {
      notify.success('Vencimento prorrogado.')
      onExtended()
      onClose()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível prorrogar o vencimento.')),
  })

  return (
    <SideDrawer
      open
      onClose={onClose}
      title="Prorrogar vencimento"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>Cancelar</Button>
          <Button onClick={() => prorrogar.mutate()} disabled={!novaData || prorrogar.isPending}>
            {prorrogar.isPending ? 'Prorrogando…' : 'Prorrogar'}
          </Button>
        </div>
      }
    >
      {previa.isPending ? (
        <LoadingState label="Carregando…" />
      ) : (
        <div className="space-y-5">
          <div className="rounded-md border border-border bg-muted/40 p-3 text-sm">
            <p className="font-medium">{operacao.title}</p>
            <p className="text-muted-foreground">
              Vencimento atual: {formatDate(previa.data?.original_due_date ?? operacao.due_date)}
            </p>
          </div>

          <Campo
            id="ext-data"
            label="Nova data de vencimento"
            hint="Prorrogação só anda para a frente — o servidor recusa data igual ou anterior."
          >
            <DatePicker id="ext-data" value={novaData} onChange={setNovaData} min={minima} />
          </Campo>

          <Campo id="ext-obs" label="Observação">
            <Textarea id="ext-obs" rows={3} value={observacao}
                      onChange={(e) => setObservacao(e.target.value)} />
          </Campo>

          <p className="rounded-md border border-border bg-card p-3 text-xs text-muted-foreground">
            O registro da prorrogação é <strong>imutável</strong>: fica no histórico com a data anterior,
            a nova e quem prorrogou. Para corrigir, lance outra prorrogação.
          </p>
        </div>
      )}
    </SideDrawer>
  )
}
