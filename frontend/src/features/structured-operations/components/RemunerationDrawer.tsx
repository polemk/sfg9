import { useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { Label } from '@/components/ui/Label'
import { PercentInput } from '@/components/ui/NumericInput'
import { Select } from '@/components/ui/Select'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { riskOperationTypesApi } from '@/features/risk/api/risk'
import {
  REMUNERATION_CLASS_LABELS,
  REMUNERATION_CLASSES,
  remunerationsApi,
  structuredOperationTypesApi,
  type Remuneration,
  type RemunerationClass,
} from '../api/structuredOperations'

/**
 * **Painel de remuneração** (`FE-304`, `FE-305`).
 *
 * ## A gambiarra dos dois selects sobrepostos morre aqui
 *
 * O legado renderizava **dois** `f.select :operation_type_id` no mesmo lugar —
 * um com os `RiskOperationType`, outro com os `StructuredOperationType` — e
 * escondia um deles por CSS. Para o segundo não colidir no envio, o `name` era
 * trocado para `disabled_operation_type_id`; ao alternar a classe, o JavaScript
 * **trocava os dois `name`** e o `disabled` entre os elementos. Duas
 * consequências:
 *
 * 1. o campo que ficava `disabled` **não era enviado pelo navegador**, então
 *    havia caminhos em que o tipo escolhido simplesmente não chegava ao
 *    servidor;
 * 2. o valor selecionado ficava guardado no elemento errado depois de uma
 *    alternância.
 *
 * Aqui é **um** select, controlado por estado. Trocar a classe troca a lista de
 * opções e limpa o tipo — não existe elemento escondido guardando valor.
 *
 * ## `Q-R21` — na edição o select EXIBE o tipo desativado
 *
 * O cadastro oferece só tipos **ativos**. Mas uma remuneração antiga pode
 * apontar para um tipo que foi desativado depois: no legado ela aparecia com o
 * select **em branco**, e salvar limpava o vínculo. Aqui, na edição, o tipo
 * atual é injetado na lista (marcado "inativo") **sem** ser oferecido em novos
 * cadastros.
 *
 * ## Classe e tipo são imutáveis na edição — replicado
 *
 * `disabled: !r.id.nil?` nos dois selects do legado. O par (projeto, classe,
 * tipo) é único (DB-284) e é por ele que `Receipt#fetch` acha **uma** taxa;
 * trocá-lo depois moveria os recibos já emitidos. O que muda é que os campos
 * **não somem mais do envio**.
 *
 * ## `FE-305` / `T-D9` — a taxa NÃO tem limite de faixa
 *
 * Nem superior nem inferior. 250% passa hoje e continua passando. É a taxa que
 * multiplica **todo** o faturamento, então travá-la é decisão do negócio, não
 * da migração — e a P-026 perdeu o objeto: a tabela não existe em produção,
 * não há dado contra o qual medir.
 */
export function RemunerationDrawer({
  aberto,
  editando,
  onFechar,
  onSalvo,
}: {
  aberto: boolean
  editando: Remuneration | null
  onFechar: () => void
  onSalvo: () => void
}) {
  const queryClient = useQueryClient()
  const [classe, setClasse] = useState<RemunerationClass>('RiskOperationType')
  const [tipoId, setTipoId] = useState<string>('')
  const [taxa, setTaxa] = useState<number | null>(null)
  const avisado = useRef(false)

  // Recarrega o painel a cada abertura — sem isto, abrir "Editar" depois de
  // "Cadastrar" mostraria o rascunho anterior.
  useEffect(() => {
    if (!aberto) return
    if (editando) {
      setClasse(editando.operation_type_type)
      setTipoId(editando.operation_type_id)
      setTaxa(Number(editando.value))
    } else {
      setClasse('RiskOperationType')
      setTipoId('')
      setTaxa(null)
    }
    avisado.current = false
  }, [aberto, editando])

  // Só ATIVOS — é o que o legado oferecia (`.active` nos dois selects).
  const tiposLiq = useQuery({
    queryKey: ['risk-operation-types', 'ativos'],
    queryFn: () => riskOperationTypesApi.list({ perPage: 100, active: true }),
    enabled: aberto,
  })

  const tiposEst = useQuery({
    queryKey: ['structured-operation-types', 'ativos'],
    queryFn: () => structuredOperationTypesApi.list({ perPage: 100, active: true }),
    enabled: aberto,
  })

  const carregandoTipos = classe === 'RiskOperationType' ? tiposLiq.isLoading : tiposEst.isLoading

  const opcoesDeTipo = useMemo(() => {
    const lista =
      classe === 'RiskOperationType'
        ? (tiposLiq.data?.items ?? []).map((t) => ({ value: t.id, label: t.title }))
        : (tiposEst.data?.items ?? []).map((t) => ({ value: t.id, label: t.title }))

    // Q-R21 — na edição, o tipo atual entra na lista mesmo se estiver
    // desativado. Sem isto o select abriria em branco e salvar limparia o
    // vínculo, que é o que o legado fazia.
    if (editando && editando.operation_type_type === classe && !lista.some((o) => o.value === editando.operation_type_id)) {
      return [{ value: editando.operation_type_id, label: `${editando.title} (inativo)` }, ...lista]
    }
    return lista
  }, [classe, tiposLiq.data, tiposEst.data, editando])

  const salvar = useMutation({
    mutationFn: () =>
      editando
        ? // Os campos imutáveis VIAJAM no envio — no legado o `disabled` os
          // fazia sumir do formulário e o servidor recebia menos do que a tela
          // mostrava.
          remunerationsApi.update(editando.id, {
            operation_type_type: classe,
            operation_type_id: tipoId,
            value: taxa ?? 0,
          })
        : remunerationsApi.create({
            operation_type_type: classe,
            operation_type_id: tipoId,
            value: taxa ?? 0,
          }),
    onSuccess: (r) => {
      notify.success(editando ? `Remuneração «${r.title}» atualizada.` : `Remuneração «${r.title}» cadastrada.`)
      queryClient.invalidateQueries({ queryKey: ['remunerations'] })
      // Os candidatos a recibo dependem das remunerações do projeto.
      queryClient.invalidateQueries({ queryKey: ['charge-receipts'] })
      onSalvo()
    },
    onError: (erro) =>
      notify.error(mensagemDoServidor(erro, 'Não foi possível salvar a remuneração.')),
  })

  const pendencia = !tipoId ? 'Escolha o tipo de operação.' : taxa === null ? 'Informe o valor da taxa.' : null
  const podeSalvar = pendencia === null && !salvar.isPending

  return (
    <SideDrawer
      open={aberto}
      onClose={onFechar}
      title={editando ? 'Editar remuneração' : 'Cadastrar remuneração'}
      footer={
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onFechar} disabled={salvar.isPending}>
            Cancelar
          </Button>
          <Button className="flex-1" loading={salvar.isPending} disabled={!podeSalvar} onClick={() => salvar.mutate()}>
            Salvar
          </Button>
        </div>
      }
    >
      <div className="space-y-1.5">
        <Label htmlFor="operation_type_type">Remuneração para</Label>
        <Select
          id="operation_type_type"
          aria-label="Remuneração para"
          value={classe}
          disabled={!!editando}
          onChange={(v) => {
            setClasse((v as RemunerationClass) ?? 'RiskOperationType')
            // Trocar a classe limpa o tipo: um id de outra classe seria
            // recusado pelo servidor com uma mensagem que não ajuda ninguém.
            setTipoId('')
          }}
          options={REMUNERATION_CLASSES.map((c) => ({ value: c, label: REMUNERATION_CLASS_LABELS[c] }))}
        />
        {editando && (
          <p className="text-xs text-muted-foreground">
            Classe e tipo são definidos na criação: é o par que o recibo usa para achar a taxa.
          </p>
        )}
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="operation_type_id">Tipo de Operação</Label>
        <Select
          id="operation_type_id"
          aria-label="Tipo de operação"
          placeholder={carregandoTipos ? 'Carregando…' : 'clique para escolher…'}
          value={tipoId || null}
          disabled={!!editando || carregandoTipos}
          onChange={(v) => setTipoId(v ?? '')}
          options={opcoesDeTipo}
        />
        {!editando && opcoesDeTipo.length === 0 && !carregandoTipos && (
          <p className="text-xs text-muted-foreground">
            Não há tipo ativo desta classe. Cadastre um tipo antes de criar a remuneração.
          </p>
        )}
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="value">Valor da taxa (%)</Label>
        <PercentInput
          id="value"
          value={taxa}
          onChange={setTaxa}
          placeholder="Ex.: 2,55%"
          // FE-305 / T-D9 — sem `min` e sem `max`, de propósito.
          onWarningChange={(aviso) => {
            if (aviso && !avisado.current) {
              avisado.current = true
              notify.warning(aviso)
            }
            if (!aviso) avisado.current = false
          }}
        />
        <p className="text-xs text-muted-foreground">
          É o percentual sobre o capital da operação. O valor do recibo é calculado no servidor — esta tela
          não multiplica nada.
        </p>
      </div>

      {pendencia && (
        <p role="status" className="text-xs text-muted-foreground">
          {pendencia}
        </p>
      )}
    </SideDrawer>
  )
}
