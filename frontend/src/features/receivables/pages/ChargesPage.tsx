import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Lock, Pencil, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { SideDrawer } from '@/components/SideDrawer'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { DatePicker } from '@/components/ui/DatePicker'
import { Label } from '@/components/ui/Label'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { Select } from '@/components/ui/Select'
import { Tooltip } from '@/components/ui/Tooltip'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatMoney } from '@/lib/utils/number'
import { CHARGE_STATES, chargesApi, type Charge, type ChargeState } from '../api/receivables'
import { ChargeEditDrawer } from '../components/ChargeEditDrawer'

/**
 * **Cobranças** (FE-179…FE-186). Dona por **DEC-63**.
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * As tabelas `charges`, `receipts` e `remunerations` **não existem** no banco
 * de produção: as migrations que as criam estão entre as 24 que nunca subiram
 * (o dump de 31/05/2025 não tem `COPY public.charges`). Esta tela é o espelho
 * do código de 2022 (`../sfg/app/controllers/pub/charges_controller.rb`), sem
 * corrigir o que parecer errado.
 *
 * ## O que muda em relação ao legado
 *
 * - **D-20 — a paginação existe.** No legado o limite era fixo de **1000 no
 *   cliente** e não havia nenhum no servidor.
 * - **FE-180 — o filtro de ano aceita VAZIO.** Sem essa opção era impossível
 *   ver todas as cobranças de uma vez.
 * - **D-18 — "Faturado" bloqueia no SERVIDOR.** No legado o bloqueio existia só
 *   na tela (`charges/show/_body.js.erb`): a API aceitava a alteração de um
 *   pacote já emitido. Aqui o servidor recusa, e o botão escondido é
 *   conveniência — nunca a defesa.
 * - **FE-186 — a data padrão da criação é hoje + 30 dias**, e ela é decisão de
 *   INTERFACE: o servidor exige a data explicitamente.
 *
 * ## Os recibos dependem da S8, e isso aparece na tela
 *
 * O extrato por remuneração precisa de `Remuneration`, que é da **S8**.
 * Enquanto o model não existir o servidor responde **422 nomeando a fatia** — e
 * a tela mostra isso como estado, com a razão escrita. Não é erro, e não é uma
 * lista vazia fingindo que não há nada a faturar.
 */
const MESES = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
]

export function ChargesPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  const paginacao = usePagination()
  const [sort, setSort] = useState<SortState | null>({ key: 'date', direction: 'desc' })
  const [filtroEstado, setFiltroEstado] = useState<string | null>(null)
  const [filtroMes, setFiltroMes] = useState<string | null>(null)
  const [filtroAno, setFiltroAno] = useState<string | null>(null)

  const [criando, setCriando] = useState(false)
  const [novaData, setNovaData] = useState<Date | null>(null)
  const [confirmando, setConfirmando] = useState<Charge | null>(null)

  // FE-181 — a cobrança sendo editada. O rascunho dos campos vive dentro do
  // `ChargeEditDrawer`, que é o mesmo componente usado pelo detalhe.
  const [editando, setEditando] = useState<Charge | null>(null)

  useEffect(() => {
    document.title = 'Safegold - Cobranças'
  }, [])

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      state: (filtroEstado || undefined) as ChargeState | undefined,
      month: filtroMes ? Number(filtroMes) : undefined,
      // Ano vazio = TODAS as cobranças (FE-180).
      year: filtroAno ? Number(filtroAno) : undefined,
      orderingKey: (sort?.key ?? 'date') as 'date' | 'state' | 'value' | 'created_at',
      orderingStyle: (sort?.direction === 'desc' ? 'down' : 'up') as 'up' | 'down',
    }),
    [paginacao.page, paginacao.perPage, filtroEstado, filtroMes, filtroAno, sort],
  )

  const consulta = useQuery({ queryKey: ['charges', filtros], queryFn: () => chargesApi.list(filtros) })

  const invalidar = () => queryClient.invalidateQueries({ queryKey: ['charges'] })

  /**
   * **O detalhe é PÁGINA, não gaveta** (26/08/2026). Palavras do usuário: *"o
   * detalhe de cobrança ficou muito ruim assim, ou fazemos em diálogo ou em uma
   * página separada"*. A razão é medida: o detalhe abre o extrato por
   * remuneração e leva à seleção de recibos, que numa cobrança real desta base
   * tem **214 candidatos** e **9 persistidos**. Isso é tabela, e tabela não cabe
   * numa gaveta de 480 px — ela brigaria com a rolagem horizontal, a coluna
   * congelada e os cartões de telefone do `DataTable`.
   *
   * A criação continua gaveta, e continua certa: uma data e uma explicação é
   * formulário curto.
   */
  const abrirDetalhe = (charge: Charge) => navigate(`/charges/${charge.id}`)

  const criar = useMutation({
    mutationFn: (data: Date) => chargesApi.create({ date: iso(data) }),
    onSuccess: () => {
      notify.success('Cobrança criada em Edição.')
      setCriando(false)
      setNovaData(null)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível criar a cobrança.')),
  })

  const excluir = useMutation({
    mutationFn: (charge: Charge) => chargesApi.remove(charge.id),
    onSuccess: () => {
      notify.success('Cobrança excluída.')
      setConfirmando(null)
      invalidar()
    },
    onError: (erro) => {
      notify.error(mensagemDoServidor(erro, 'Não foi possível excluir a cobrança.'))
      setConfirmando(null)
    },
  })

  function abrirCriacao() {
    // FE-186 — hoje + 30 dias. Decisão de INTERFACE: o servidor exige a data.
    const daqui = new Date()
    daqui.setDate(daqui.getDate() + 30)
    setNovaData(daqui)
    setCriando(true)
  }

  const anoAtual = new Date().getFullYear()
  const anos = Array.from({ length: 8 }, (_, i) => String(anoAtual - i))

  const colunas: Column<Charge>[] = [
    {
      key: 'date',
      header: 'Data',
      sortable: true,
      accessor: (c) => c.date,
      cell: (c) => <span className="font-numeric tabular-nums">{dataBr(c.date)}</span>,
    },
    {
      key: 'state',
      header: 'Situação',
      sortable: true,
      accessor: (c) => c.state,
      cell: (c) =>
        c.done ? (
          <Tooltip content="Pacote faturado. Não aceita mais alteração — nem pela tela, nem pela API.">
            <Badge variant="secondary">
              <Lock aria-hidden="true" className="mr-1 h-3 w-3" />
              {c.state_label}
            </Badge>
          </Tooltip>
        ) : (
          <span>{c.state_label}</span>
        ),
    },
    {
      key: 'value',
      header: 'Valor',
      sortable: true,
      variant: 'number',
      accessor: (c) => Number(c.value),
      cell: (c) => <span className="font-numeric tabular-nums">{formatMoney(num(c.value))}</span>,
    },
    {
      key: 'receipts_count',
      header: 'Operações',
      variant: 'number',
      accessor: (c) => c.receipts_count,
      cell: (c) => (
        <span className="font-numeric tabular-nums">
          {c.risk_operations_count} liq. · {c.structured_operations_count} est.
        </span>
      ),
    },
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      align: 'right',
      width: '8rem',
      cell: (c) =>
        // As ações somem para o pacote faturado — e o servidor recusa de
        // qualquer forma (D-18). Esconder nunca foi a defesa.
        podeEscrever && !c.done ? (
          <div className="flex justify-end gap-1">
            <Button
              variant="ghost"
              size="icon"
              aria-label="Editar cobrança"
              onClick={(e) => {
                e.stopPropagation()
                setEditando(c)
              }}
            >
              <Pencil aria-hidden="true" className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              aria-label="Excluir cobrança"
              onClick={(e) => {
                e.stopPropagation()
                setConfirmando(c)
              }}
            >
              <Trash2 aria-hidden="true" className="h-4 w-4" />
            </Button>
          </div>
        ) : null,
    },
  ]

  const meta = consulta.data?.meta
  const escopo = projectScopeCode(consulta.error)

  const cabecalho = (
    <PageHeader
      title="Cobranças"
      subtitle="O pacote de recibos que vai ao cliente. Um pacote faturado não aceita mais alteração."
      loading={consulta.isFetching && !consulta.isLoading}
      rightSlot={
        podeEscrever ? (
          <Button onClick={abrirCriacao}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            Nova cobrança
          </Button>
        ) : undefined
      }
    />
  )

  if (escopo) {
    return (
      <div className="pb-10">
        {cabecalho}
        <ProjectScopeState code={escopo} recurso="as cobranças" />
      </div>
    )
  }

  return (
    <div className="pb-10">
      {cabecalho}

      <div className="mb-4 grid gap-3 sm:grid-cols-3">
        <Select
          aria-label="Filtrar por situação"
          placeholder="Todas as situações"
          value={filtroEstado}
          onChange={(v) => {
            setFiltroEstado(v || null)
            paginacao.reset()
          }}
          options={[{ value: '', label: 'Todas as situações' }, ...CHARGE_STATES]}
        />
        <Select
          aria-label="Filtrar por mês"
          placeholder="Todos os meses"
          value={filtroMes}
          onChange={(v) => {
            setFiltroMes(v || null)
            paginacao.reset()
          }}
          options={[
            { value: '', label: 'Todos os meses' },
            ...MESES.map((m, i) => ({ value: String(i + 1), label: m })),
          ]}
        />
        {/* **A opção em branco existe** (FE-180): no legado não havia, e ver
            todas as cobranças de uma vez era impossível. */}
        <Select
          aria-label="Filtrar por ano"
          placeholder="Todos os anos"
          value={filtroAno}
          onChange={(v) => {
            setFiltroAno(v || null)
            paginacao.reset()
          }}
          options={[{ value: '', label: 'Todos os anos' }, ...anos.map((a) => ({ value: a, label: a }))]}
        />
      </div>

      {estreito ? (
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={consulta.data?.items}
          onRetry={() => consulta.refetch()}
          loadingLabel="Carregando cobranças…"
          emptyTitle="Nenhuma cobrança neste filtro"
          emptyDescription="A cobrança agrupa os recibos das operações do período. Crie a primeira para começar."
        >
          {(itens) => (
            <div>
              {itens.map((c) => (
                <MobileCard
                  key={c.id}
                  title={dataBr(c.date)}
                  subtitle={`${c.receipts_count} recibo(s)`}
                  status={c.state_label}
                  statusTone={c.done ? 'neutral' : undefined}
                  onClick={() => abrirDetalhe(c)}
                >
                  <dl className="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Valor</dt>
                      <dd className="font-numeric tabular-nums text-foreground">{formatMoney(num(c.value))}</dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Operações</dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatMoney(num(c.total_operations_value))}
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
          <DataTable<Charge>
            columns={colunas}
            data={consulta.data?.items ?? []}
            rowKey={(c) => c.id}
            sortMode="server"
            loading={consulta.isLoading}
            error={consulta.isError ? consulta.error : undefined}
            onRetry={() => consulta.refetch()}
            loadingLabel="Carregando cobranças…"
            emptyTitle="Nenhuma cobrança neste filtro"
            emptyDescription="A cobrança agrupa os recibos das operações do período. Crie a primeira para começar."
            sort={sort}
            onSortChange={(s) => {
              setSort(s)
              paginacao.reset()
            }}
            onRowClick={abrirDetalhe}
          />
        </div>
      )}

      {meta && meta.total > 0 && (
        <div className="mt-4">
          {estreito ? (
            <MobilePagination
              page={meta.page}
              total={meta.total}
              perPage={meta.perPage}
              onPageChange={paginacao.setPage}
              loading={consulta.isFetching}
            />
          ) : (
            <PaginationPill
              page={meta.page}
              totalPages={meta.totalPages}
              perPage={meta.perPage}
              onPageChange={paginacao.setPage}
              onPerPageChange={paginacao.setPerPage}
              loading={consulta.isFetching}
            />
          )}
        </div>
      )}

      <SideDrawer
        open={criando}
        onClose={() => setCriando(false)}
        title="Nova cobrança"
        footer={
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setCriando(false)} disabled={criar.isPending}>
              Cancelar
            </Button>
            <Button onClick={() => novaData && criar.mutate(novaData)} disabled={!novaData || criar.isPending}>
              {criar.isPending ? 'Criando…' : 'Criar cobrança'}
            </Button>
          </div>
        }
      >
        <div className="space-y-1.5">
          <p className="text-sm text-muted-foreground">
            O pacote nasce em <strong>Edição</strong>. A data padrão é hoje + 30 dias.
          </p>
          <Label htmlFor="nova_data">Data da cobrança</Label>
          <DatePicker id="nova_data" value={novaData} onChange={setNovaData} />
          <p className="text-xs text-muted-foreground">
            A situação "Faturado" não é escolhida aqui: um pacote nasce aberto e só é fechado depois de conferido.
          </p>
        </div>
      </SideDrawer>

      <ChargeEditDrawer charge={editando} onClose={() => setEditando(null)} />

      <ConfirmDialog
        open={confirmando !== null}
        onOpenChange={(aberto) => !aberto && setConfirmando(null)}
        title="Excluir esta cobrança?"
        description={
          confirmando
            ? `A cobrança de ${dataBr(confirmando.date)}, no valor de ${formatMoney(num(confirmando.value))}, ` +
              'será removida. Se houver recibo vinculado, o servidor recusa e diz quantos são.'
            : ''
        }
        confirmLabel="Excluir cobrança"
        tone="destructive"
        loading={excluir.isPending}
        onConfirm={() => {
          if (confirmando) excluir.mutate(confirmando)
        }}
      />
    </div>
  )
}

function num(v: string | number | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : null
}

function dataBr(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [a, m, d] = iso.slice(0, 10).split('-')
  return d && m && a ? `${d}/${m}/${a}` : '—'
}

function iso(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}
