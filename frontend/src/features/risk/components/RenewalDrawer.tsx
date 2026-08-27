import { useEffect, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { Campo } from '@/app/pages/catalogs/CatalogFields'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { DatePicker } from '@/components/ui/DatePicker'
import { LoadingState } from '@/components/ui/States'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatDate } from '@/lib/utils/date'
import { riskOperationsApi, type RiskOperation } from '../api/risk'

/**
 * **Renovar operação** (FE-275).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `create_risk_operations` está entre as 24 migrations que nunca subiram
 * (`analise-dump-producao.md` §1): nenhuma renovação existiu em produção. A
 * fonte é `../sfg/app/controllers/pub/risk_operations_controller.rb:86-113`.
 *
 * ## ⚠ A DEC-35 ANULA O IMP-R1 DO `tasks.md`
 *
 * O `tasks.md` desta fatia (Phase 2) prometia que renovar **encerraria** a
 * original, corrigindo o D-94. A **DEC-35 (25/08/2026)** decidiu depois:
 * *"Renovar NÃO encerra a original. As duas operações ficam vivas e as duas
 * consomem limite de risco ao mesmo tempo."* Por isso o aviso abaixo é
 * **informativo**, e não a descrição de um encerramento que não acontece.
 *
 * ## O que muda em relação ao legado
 *
 * - **`minDate` e `maxDate` passam a existir.** No legado os dois datepickers
 *   eram livres, e dava para escolher um vencimento anterior à emissão — que o
 *   servidor aceitava. Aqui o vencimento mínimo é o dia seguinte à emissão, e o
 *   servidor recusa o resto (`RenewalService#create`).
 * - **As datas sugeridas vêm do SERVIDOR** (`GET :id/renewal`), não de uma
 *   conta repetida no JavaScript: é o mesmo cálculo que grava (contrato C2).
 * - **Os toasts falam de renovação.** No legado eles dizem "O tipo de operação
 *   foi criado/atualizado com sucesso" — texto de outro módulo, copiado junto
 *   com a parcial.
 */
export function RenewalDrawer({
  operacao,
  onClose,
  onRenewed,
}: {
  operacao: RiskOperation
  onClose: () => void
  onRenewed: () => void
}) {
  const [emissao, setEmissao] = useState<Date | null>(null)
  const [vencimento, setVencimento] = useState<Date | null>(null)

  const previa = useQuery({
    queryKey: ['risk-operation-renewal', operacao.id],
    queryFn: () => riskOperationsApi.renewalPreview(operacao.id),
  })

  useEffect(() => {
    if (!previa.data) return
    setEmissao(new Date(`${previa.data.issue_date}T00:00:00`))
    setVencimento(new Date(`${previa.data.due_date}T00:00:00`))
  }, [previa.data])

  const iso = (d: Date | null) => (d ? d.toISOString().slice(0, 10) : '')

  const renovar = useMutation({
    mutationFn: () =>
      riskOperationsApi.createRenewal(operacao.id, {
        issue_date: iso(emissao),
        due_date: iso(vencimento),
      }),
    onSuccess: () => {
      notify.success('Operação renovada.')
      onRenewed()
      onClose()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível renovar a operação.')),
  })

  /** O dia seguinte à emissão — o `minDate` que o legado não tinha. */
  const minVencimento = emissao ? new Date(emissao.getTime() + 86_400_000) : null

  return (
    <SideDrawer
      open
      onClose={onClose}
      title="Renovar operação"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>Cancelar</Button>
          <Button
            onClick={() => renovar.mutate()}
            disabled={!emissao || !vencimento || renovar.isPending}
          >
            {renovar.isPending ? 'Renovando…' : 'Renovar'}
          </Button>
        </div>
      }
    >
      {previa.isPending ? (
        <LoadingState label="Calculando as datas…" />
      ) : (
        <div className="space-y-5">
          <div className="rounded-md border border-border bg-muted/40 p-3 text-sm">
            <p className="font-medium">{operacao.title}</p>
            <p className="text-muted-foreground">
              Vigência atual: {formatDate(operacao.issue_date)} a {formatDate(operacao.due_date)}
            </p>
            {previa.data && (
              <p className="mt-1 text-muted-foreground">
                Prazo decorrido: <span className="font-numeric">{previa.data.elapsed_days}</span> dias. A
                sugestão de vencimento preserva o prazo original.
              </p>
            )}
          </div>

          <Campo id="ren-emissao" label="Nova emissão" hint="Sugestão: hoje.">
            <DatePicker id="ren-emissao" value={emissao} onChange={setEmissao} />
          </Campo>

          <Campo
            id="ren-vencimento"
            label="Novo vencimento"
            hint="Sugestão: vencimento original + o mesmo prazo em dias."
          >
            <DatePicker id="ren-vencimento" value={vencimento} onChange={setVencimento} min={minVencimento} />
          </Campo>

          {/* **DEC-35, dito na tela.** A operação original continua aberta e
              continua consumindo limite enquanto as janelas se sobrepõem. Isso
              é o ciclo de vida do legado, replicado por decisão do usuário — e
              está aqui para que o operador não descubra por diferença de
              número no painel. */}
          <p className="rounded-md border border-border bg-card p-3 text-xs text-muted-foreground">
            A operação atual <strong>não</strong> é encerrada pela renovação. Enquanto as duas vigências
            se sobrepõem, as duas consomem o limite do portador. Para encerrar a original, edite-a e
            marque "Encerrada".
          </p>
        </div>
      )}
    </SideDrawer>
  )
}
