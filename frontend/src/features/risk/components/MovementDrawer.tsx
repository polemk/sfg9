import { useEffect, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Lock } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Campo } from '@/app/pages/catalogs/CatalogFields'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { DatePicker } from '@/components/ui/DatePicker'
import { LoadingState } from '@/components/ui/States'
import { Select } from '@/components/ui/Select'
import { Textarea } from '@/components/ui/textarea'
import { MoneyInput } from '@/components/ui/NumericInput'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { riskOperationsApi, type RiskMovement, type RiskOperation } from '../api/risk'

/**
 * **Lançar / editar movimento** (FE-271, FE-272).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `create_risk_movements` está entre as 24 migrations que nunca subiram. Fonte:
 * `../sfg/app/controllers/pub/risk_movements_controller.rb` e
 * `.../risk_movements/helper/_body`.
 *
 * ## Quatro coisas que mudam, e todas foram medidas no legado
 *
 * 1. **O datepicker fica ALINHADO ao servidor.** O legado abria o calendário
 *    com `issue_date + 1` e `due_date + 1` (off-by-one nas duas pontas): o
 *    primeiro dia da operação não era selecionável e o dia seguinte ao
 *    vencimento era — e aí o servidor recusava. Aqui `min`/`max` vêm de
 *    `GET :id/movements/options`, que devolve a **mesma** janela que o
 *    `BE-274` valida.
 * 2. **`movement_value > 0` vale no servidor** (decisão B-05). Valor negativo
 *    **inverte o sinal** do movimento — um crédito de −1.000 vira débito. É
 *    registro corrompido, não convenção de sinal: não cai no DEC-01.
 * 3. **Em transferência, o tipo é readonly** e a contrapartida nasce junto, na
 *    mesma transação (BE-275). No legado o par nascia no `after_create` e, sem
 *    `pair_operation`, ficava **meia transferência** gravada.
 * 4. **Os toasts falam de movimento.** No legado eles dizem "A previsão foi
 *    criada/atualizada com sucesso" — texto do módulo de renegociação.
 */
export function MovementDrawer({
  operacao,
  movimento,
  mode,
  onClose,
  onSaved,
}: {
  operacao: RiskOperation
  /** Preenchido = edição. */
  movimento?: RiskMovement | null
  mode: 'new' | 'transfer'
  onClose: () => void
  onSaved: () => void
}) {
  const editando = !!movimento
  const [tipoId, setTipoId] = useState<string>('')
  const [data, setData] = useState<Date | null>(null)
  const [valor, setValor] = useState<number | null>(null)
  const [observacao, setObservacao] = useState('')

  const opcoes = useQuery({
    queryKey: ['risk-movement-options', operacao.id, mode],
    queryFn: () => riskOperationsApi.movementOptions(operacao.id, mode),
  })

  useEffect(() => {
    if (movimento) {
      setTipoId(movimento.movement_type_id)
      setData(new Date(`${movimento.date}T00:00:00`))
      setValor(Number(movimento.movement_value))
      setObservacao(movimento.observation ?? '')
      return
    }
    if (opcoes.data) setTipoId(opcoes.data.movement_type_id ?? '')
  }, [movimento, opcoes.data])

  /**
   * A janela vem do servidor. Operação estática não tem janela (B-08) — os dois
   * campos vêm nulos e o calendário fica livre, que é o comportamento certo.
   */
  const min = opcoes.data?.min_date ? new Date(`${opcoes.data.min_date}T00:00:00`) : null
  const max = opcoes.data?.max_date ? new Date(`${opcoes.data.max_date}T00:00:00`) : null

  /** Transferência: o tipo é fixado e não se edita nem na criação nem depois. */
  const tipoTravado = (opcoes.data?.movement_type_locked ?? false) || (movimento?.is_transfer ?? false)

  const salvar = useMutation({
    mutationFn: () => {
      const payload = {
        movement_type_id: tipoId,
        date: data ? data.toISOString().slice(0, 10) : '',
        movement_value: valor ?? 0,
        observation: observacao || undefined,
      }
      return editando
        ? riskOperationsApi.updateMovement(operacao.id, movimento!.id, payload)
        : riskOperationsApi.createMovement(operacao.id, payload)
    },
    onSuccess: () => {
      notify.success(editando ? 'Movimento atualizado.' : 'Movimento lançado.')
      onSaved()
      onClose()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o movimento.')),
  })

  const titulo = mode === 'transfer'
    ? 'Transferir para a antecipação'
    : editando ? 'Editar movimento' : 'Novo movimento'

  // **B-05, espelhado na tela.** O botão só habilita com valor > 0 — e o
  // servidor recusa igual, para quem chamar a API direto.
  const podeSalvar = !!tipoId && !!data && (valor ?? 0) > 0

  return (
    <SideDrawer
      open
      onClose={onClose}
      title={titulo}
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>Cancelar</Button>
          <Button onClick={() => salvar.mutate()} disabled={!podeSalvar || salvar.isPending}>
            {salvar.isPending ? 'Salvando…' : 'Salvar'}
          </Button>
        </div>
      }
    >
      {opcoes.isPending ? (
        <LoadingState label="Carregando…" />
      ) : (
        <div className="space-y-5">
          <Campo id="mov-tipo" label="Tipo de movimentação">
            {tipoTravado ? (
              <div className="flex items-center gap-2 rounded-md border border-input bg-muted px-3 py-2 text-sm text-muted-foreground">
                <Lock className="h-3.5 w-3.5 shrink-0" aria-hidden />
                <span>
                  {(opcoes.data?.movement_types ?? []).find((t) => t.id === tipoId)?.title ??
                    movimento?.movement_type_title ??
                    'Valor Transferido'}
                </span>
              </div>
            ) : (
              <Select
                value={tipoId}
                onChange={setTipoId}
                options={[
                  { value: '', label: 'Selecione o tipo' },
                  ...(opcoes.data?.movement_types ?? []).map((t) => ({
                    value: t.id,
                    label: `${t.title} (${t.credit_type === 'C' ? 'crédito' : 'débito'})`,
                  })),
                ]}
              />
            )}
          </Campo>

          <Campo
            id="mov-data"
            label="Data"
            hint={
              min && max
                ? `Entre ${min.toLocaleDateString('pt-BR')} e ${max.toLocaleDateString('pt-BR')} — a janela da operação.`
                : undefined
            }
          >
            <DatePicker id="mov-data" value={data} onChange={setData} min={min} max={max} />
          </Campo>

          <Campo id="mov-valor" label="Valor do movimento" hint="Sempre positivo — o sinal vem do tipo.">
            <MoneyInput id="mov-valor" value={valor} onChange={setValor} />
          </Campo>

          <Campo id="mov-obs" label="Observação">
            <Textarea id="mov-obs" rows={3} value={observacao}
                      onChange={(e) => setObservacao(e.target.value)} />
          </Campo>

          {mode === 'transfer' && (
            <p className="rounded-md border border-border bg-card p-3 text-xs text-muted-foreground">
              A contrapartida "Transferência Recebida" é lançada na operação de antecipação, com a mesma
              data, o mesmo valor e a mesma observação. As duas nascem juntas: se a contrapartida não
              puder ser gravada, nada é gravado.
            </p>
          )}
        </div>
      )}
    </SideDrawer>
  )
}
