import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Lock } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { Checkbox } from '@/components/ui/Checkbox'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { FormActionBar } from '@/components/ui/FormActionBar'
import { LoadingState } from '@/components/ui/States'
import { Tooltip } from '@/components/ui/Tooltip'
import { MobileCard } from '@/components/mobile/MobileCard'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useMobile } from '@/hooks/useMobile'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatDate } from '@/lib/utils/date'
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { chargesApi, type ChargeReceipt } from '../api/receivables'

/**
 * **Operações da cobrança** — a seleção de recibos (`FE-184`, `FE-185`).
 *
 * Fecha as tarefas **3.24** e **3.25** da **S6**, que estavam bloqueadas: elas
 * dependiam de `Remuneration` para existir candidato, e `Remuneration` é da
 * **S8**. Quem entregou esta tela foi a S8.
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `charges`, `receipts` e `remunerations` **não existem** no banco de produção:
 * as migrations que as criam estão entre as 24 que nunca subiram. Fonte:
 * `../sfg/app/views/pub/console/parts/charges/receipts/`.
 *
 * ## `temp_id` é a identidade — e é por isso que a tela funciona
 *
 * Um candidato ainda não é um registro: ele nasce de (projeto, classe,
 * remuneração, operação) e só vira `Receipt` ao salvar. O `temp_id`
 * (`RCP-{projeto}-{LIQ|EST}-{remuneração}-{operação}`) é o que casa **marcado ×
 * persistido** nos dois lados, antes de existir `id`.
 *
 * ## `FE-184` — recibo legado com `date` nula NÃO quebra a tela
 *
 * O widget do legado fazia `receipt.date.strftime("%d/%m/%y")` **sem guarda**.
 * A operação estática do par pré/antecipação não tem data: uma linha assim
 * derrubava a renderização da lista inteira. Aqui a célula é um traço.
 *
 * ## `FE-185` — inclusões e remoções vão num ÚNICO lote, e a falha REVERTE
 *
 * O legado mantinha duas pilhas (`candidateStack` e `existingStack`) e mandava
 * as duas num `POST`. O problema não era o formato: era que a marcação na tela
 * (`w.toggleClass(...)`) acontecia **antes** da requisição e o `error` só dava
 * um toast — a tela ficava mostrando uma seleção que o servidor nunca recebeu,
 * e o usuário só descobria ao recarregar.
 *
 * Aqui o `PUT /charges/:id/receipts` recebe a lista **final** (`temp_ids`) —
 * quem não está nela é removido, tudo numa transação — e, se falhar, a tela
 * **volta ao estado do servidor**: a seleção é reconstruída a partir do
 * refetch, não do que estava na tela.
 *
 * ## `D-18` — "Faturado" bloqueia aqui e no servidor
 *
 * Cobrança `done` não aceita alteração. No legado o bloqueio existia só na tela
 * e a API aceitava a mudança de um pacote já emitido.
 */
export function ChargeReceiptsPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  /** `null` = ainda não sincronizado com o servidor. */
  const [selecao, setSelecao] = useState<Set<string> | null>(null)

  const cobranca = useQuery({
    queryKey: ['charge', id],
    queryFn: () => chargesApi.get(id),
    enabled: !!id,
  })

  const candidatos = useQuery({
    queryKey: ['charge-receipts', id],
    queryFn: () => chargesApi.receipts(id),
    enabled: !!id,
  })

  useEffect(() => {
    document.title = 'Safegold - Operações da cobrança'
  }, [])

  /** O estado do SERVIDOR: os `temp_id` que já estão persistidos no pacote. */
  const persistidos = useMemo(
    () => new Set((candidatos.data ?? []).filter((c) => c.persisted).map((c) => c.temp_id)),
    [candidatos.data],
  )

  // A seleção nasce do servidor — e volta a nascer dele a cada refetch. É o
  // que faz a reversão do FE-185 ser um efeito, e não um caminho especial.
  useEffect(() => {
    if (!candidatos.data) return
    setSelecao(new Set(persistidos))
  }, [candidatos.data, persistidos])

  const salvar = useMutation({
    mutationFn: (tempIds: string[]) => chargesApi.setReceipts(id, tempIds),
    onSuccess: () => {
      notify.success('Operações da cobrança atualizadas.')
      queryClient.invalidateQueries({ queryKey: ['charge-receipts', id] })
      queryClient.invalidateQueries({ queryKey: ['charge', id] })
      queryClient.invalidateQueries({ queryKey: ['charge-statement', id] })
      queryClient.invalidateQueries({ queryKey: ['charges'] })
      // A operação faturada sai de `available_for_receipt`.
      queryClient.invalidateQueries({ queryKey: ['structured-operations'] })
      queryClient.invalidateQueries({ queryKey: ['risk-operations'] })
    },
    onError: (erro) => {
      notify.error(mensagemDoServidor(erro, 'Não foi possível salvar a seleção. Nada foi alterado.'))
      // **A reversão.** O lote é transacional no servidor: se falhou, nada
      // mudou lá. Recarregar é o que garante que a tela pare de mostrar uma
      // seleção que não existe — que era o defeito do legado.
      candidatos.refetch()
    },
  })

  const escopo = projectScopeCode(cobranca.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as cobranças" />

  if (cobranca.isPending) return <LoadingState label="Carregando a cobrança…" />

  const charge = cobranca.data
  const bloqueada = charge?.done === true
  const podeSelecionar = podeEscrever && !bloqueada

  const linhas = candidatos.data ?? []
  const marcados = selecao ?? persistidos

  const alterou =
    marcados.size !== persistidos.size || [...marcados].some((t) => !persistidos.has(t))

  const totalMarcado = linhas
    .filter((c) => marcados.has(c.temp_id))
    .reduce((soma, c) => soma + (Number(c.value) || 0), 0)

  function alternar(candidato: ChargeReceipt) {
    if (!podeSelecionar) return
    setSelecao((atual) => {
      const proximo = new Set(atual ?? persistidos)
      if (proximo.has(candidato.temp_id)) proximo.delete(candidato.temp_id)
      else proximo.add(candidato.temp_id)
      return proximo
    })
  }

  const colunas: Column<ChargeReceipt>[] = [
    {
      key: 'selecao',
      header: <span className="sr-only">Selecionado</span>,
      width: '3rem',
      cell: (c) => (
        <span onClick={(e) => e.stopPropagation()}>
          <Checkbox
            checked={marcados.has(c.temp_id)}
            disabled={!podeSelecionar}
            onChange={() => alternar(c)}
            aria-label={`Incluir ${c.title} na cobrança`}
          />
        </span>
      ),
    },
    {
      key: 'kind',
      header: 'Classe',
      width: '6rem',
      accessor: (c) => c.kind,
      cell: (c) => (
        <Tooltip content={c.kind === 'LIQ' ? 'Operação de risco' : 'Operação estruturada'}>
          <Badge variant={c.kind === 'LIQ' ? 'secondary' : 'outline'}>{c.kind}</Badge>
        </Tooltip>
      ),
    },
    {
      key: 'date',
      header: 'Data',
      width: '7rem',
      align: 'center',
      accessor: (c) => c.date,
      // FE-184 — data nula é um traço. No legado `nil.strftime` derrubava a lista.
      cell: (c) => <span className="font-numeric tabular-nums">{formatDate(c.date, '-')}</span>,
    },
    {
      key: 'title',
      header: 'Tipo',
      accessor: (c) => c.title,
      cell: (c) => (
        <span className="min-w-0">
          <span className="block truncate text-foreground" title={c.title}>
            {c.title}
          </span>
          {c.operation_title && (
            <span className="block truncate text-xs text-muted-foreground" title={c.operation_title}>
              {c.operation_title}
            </span>
          )}
        </span>
      ),
    },
    {
      key: 'operation_value',
      header: 'Valor da operação',
      align: 'right',
      accessor: (c) => Number(c.operation_value),
      cell: (c) => (
        <span className="font-numeric tabular-nums">{formatMoney(Number(c.operation_value))}</span>
      ),
    },
    {
      key: 'value',
      header: 'Valor da remuneração',
      align: 'right',
      accessor: (c) => Number(c.value),
      // O valor vem PRONTO do servidor (contrato C2). Esta tela não multiplica
      // capital por taxa — a `fee` aparece como rótulo, e só.
      cell: (c) => (
        <span className="font-numeric tabular-nums text-foreground">
          {formatMoney(Number(c.value))}
          {/* A taxa é RÓTULO, e é formatada em pt-BR como todo número do app
              (OPS-289). Saía `2.55%` — ponto decimal de JavaScript no meio de
              uma coluna em reais. Visto renderizando; `tsc` não pega isto.
              Quatro casas porque `remunerations.value` é `decimal(7,4)`: com
              duas, `0,6255%` viraria `0,63%` na tela e o usuário não bateria a
              conta do valor ao lado. */}
          <span className="ml-1 text-xs text-muted-foreground">
            ({formatPercent(Number(c.fee), 4)})
          </span>
        </span>
      ),
    },
  ]

  return (
    // A barra de ações subiu 4.25rem no telefone (fica ACIMA da
    // `MobileBottomBar`), então o respiro do rodapé acompanha.
    <div className={alterou ? 'pb-44 md:pb-28' : 'pb-10'}>
      <PageHeader
        title="Operações da cobrança"
        subtitle="Selecione as operações que devem ser consideradas na cobrança."
        loading={candidatos.isFetching && !candidatos.isLoading}
        rightSlot={
          <Button variant="ghost" onClick={() => navigate('/charges')}>
            <ArrowLeft aria-hidden="true" className="h-4 w-4" />
            Voltar para a lista
          </Button>
        }
      />

      {bloqueada && (
        <Card className="mb-4 flex items-start gap-3 border-border bg-muted/40 p-4">
          <Lock aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Esta cobrança está <strong>faturada</strong>. A seleção fica somente leitura — e o servidor
            recusa qualquer alteração, mesmo fora desta tela.
          </p>
        </Card>
      )}

      {estreito ? (
        <AsyncSection
          loading={candidatos.isLoading}
          error={candidatos.isError ? candidatos.error : undefined}
          data={linhas}
          onRetry={() => candidatos.refetch()}
          loadingLabel="Carregando operações…"
          emptyTitle="Nenhuma operação a faturar"
          emptyDescription="Só entra aqui a operação SEM recibo cujo tipo tem remuneração cadastrada no projeto."
        >
          {(itens) => (
            <div>
              {itens.map((c) => (
                <MobileCard
                  key={c.temp_id}
                  title={c.title}
                  subtitle={c.operation_title ?? undefined}
                  status={c.kind}
                  statusTone="neutral"
                  onClick={() => alternar(c)}
                  headerAction={
                    <span onClick={(e) => e.stopPropagation()}>
                      <Checkbox
                        checked={marcados.has(c.temp_id)}
                        disabled={!podeSelecionar}
                        onChange={() => alternar(c)}
                        aria-label={`Incluir ${c.title} na cobrança`}
                      />
                    </span>
                  }
                >
                  <dl className="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Data</dt>
                      <dd className="font-numeric tabular-nums text-foreground">{formatDate(c.date, '-')}</dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">
                        Valor da operação
                      </dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatMoney(Number(c.operation_value))}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">
                        Valor da remuneração
                      </dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatMoney(Number(c.value))}
                      </dd>
                    </div>
                  </dl>
                </MobileCard>
              ))}
            </div>
          )}
        </AsyncSection>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-card">
          <DataTable<ChargeReceipt>
            columns={colunas}
            data={linhas}
            rowKey={(c) => c.temp_id}
            loading={candidatos.isLoading}
            // O 422 que nomeia a fatia que falta chega AQUI, como estado. Uma
            // lista vazia faria parecer que não há nada a faturar.
            error={candidatos.isError ? candidatos.error : undefined}
            onRetry={() => candidatos.refetch()}
            onRowClick={podeSelecionar ? (c) => alternar(c) : undefined}
            caption="Operações candidatas a recibo desta cobrança"
            loadingLabel="Carregando operações…"
            emptyTitle="Nenhuma operação a faturar"
            emptyDescription="Só entra aqui a operação SEM recibo cujo tipo tem remuneração cadastrada no projeto."
          />
        </div>
      )}

      {/* FE-185 — um lote só, e o botão só aparece quando há o que salvar. */}
      {alterou && (
        <FormActionBar
          pendencias={[]}
          label="Ações da seleção de recibos"
          resumo={
            <span>
              <span className="text-muted-foreground">{marcados.size} operação(ões) selecionada(s) · </span>
              <span className="font-numeric tabular-nums font-semibold text-foreground">
                {formatMoney(totalMarcado)}
              </span>
            </span>
          }
        >
          <Button
            variant="ghost"
            onClick={() => setSelecao(new Set(persistidos))}
            disabled={salvar.isPending}
          >
            Descartar mudanças
          </Button>
          <Button onClick={() => salvar.mutate([...marcados])} loading={salvar.isPending}>
            Salvar seleção
          </Button>
        </FormActionBar>
      )}
    </div>
  )
}
