import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { CalendarClock, Eye, MoreVertical, Pencil, Plus, RefreshCw, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { DateRangePicker } from '@/components/ui/DatePicker'
import { EmptyState } from '@/components/ui/States'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { SearchInput } from '@/components/ui/SearchInput'
import { Select } from '@/components/ui/Select'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { useSortStack } from '@/hooks/useSortStack'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { companiesApi } from '@/lib/api/projects'
import { formatDate } from '@/lib/utils/date'
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import {
  listRiskOperations,
  riskOperationTypesApi,
  riskOperationsApi,
  type RiskOperation,
} from '../api/risk'
import { CamposDoCartao } from '../components/CamposDoCartao'
import { RiskOperationDrawer } from '../components/RiskOperationDrawer'
import { RenewalDrawer } from '../components/RenewalDrawer'
import { ExtensionDrawer } from '../components/ExtensionDrawer'

/**
 * **Operações de risco** — a lista (FE-250..FE-257).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * As seis migrations desta família estão entre as **24 que nunca subiram**
 * (`analise-dump-producao.md` §1): em três anos de uso real **nenhuma operação
 * de risco tipada existiu**. O que esta tela replica vem do fonte de 2022
 * (`../sfg/app/views/pub/console/parts/risk_operations/`), não de comportamento
 * observado.
 *
 * ## O que muda em relação ao legado, e está registrado
 *
 * - **Um campo de busca, não dois.** O legado tem dois `<input>` com a mesma
 *   classe no mesmo formulário (FE-251); o segundo nunca fez nada.
 * - **A paginação funciona**, porque o total agora é real (FE-255): lá
 *   `@total_count` era contado **depois** do `limit!/offset!`, então a lista
 *   nunca passava de uma página.
 * - **`risk_operation_id` não vaza mais projeto** (D-100) — a correção é do
 *   servidor, e esta tela é o consumidor.
 * - **Decisão B-04 — a divergência de filtro é REPLICADA:** o filtro de tipo
 *   usa `.all` (inclui tipo inativo) enquanto o formulário usa `.active`. Não é
 *   engano do porte: é o que permite achar operação histórica de um tipo que
 *   foi desativado depois.
 */
export function RiskOperationsPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  // O grupo é `CRUD` para os quatro papéis: o gate é a PARTICIPAÇÃO no projeto
  // (C1), não o papel (C3). O botão some para quem não pode, e o servidor
  // recusa de novo — esconder botão nunca foi autorização.
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination({ initialPerPage: 50 })
  // FE-254 — a ordenacao EMPILHA. Ver `useSortStack`.
  const ordem = useSortStack([{ key: 'issue_date', direction: 'desc' }])

  const [filtroEmpresa, setFiltroEmpresa] = useState<string | null>(null)
  const [filtroPortador, setFiltroPortador] = useState<string | null>(null)
  const [filtroTipo, setFiltroTipo] = useState<string | null>(null)
  const [periodo, setPeriodo] = useState<{ from: Date | null; to: Date | null }>({ from: null, to: null })

  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<RiskOperation | null>(null)
  const [renovando, setRenovando] = useState<RiskOperation | null>(null)
  const [prorrogando, setProrrogando] = useState<RiskOperation | null>(null)
  const [confirmando, setConfirmando] = useState<RiskOperation | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  useEffect(() => {
    document.title = 'Safegold - Operações de Risco'
  }, [])

  const iso = (d: Date | null) => (d ? d.toISOString().slice(0, 10) : undefined)

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      companyId: filtroEmpresa ?? undefined,
      carrierId: filtroPortador ?? undefined,
      operationTypeId: filtroTipo ?? undefined,
      // FE-253 — escolhendo só a inicial, `from = to`: é a janela de um dia.
      from: iso(periodo.from),
      to: iso(periodo.to ?? periodo.from),
      orderingKeys: ordem.chaves,
      orderingStyles: ordem.estilos,
    }),
    [paginacao.page, paginacao.perPage, busca.consulta, filtroEmpresa, filtroPortador, filtroTipo,
     periodo, ordem.chaves, ordem.estilos],
  )

  const consulta = useQuery({
    queryKey: ['risk-operations', filtros],
    queryFn: () => listRiskOperations(filtros),
  })

  const empresas = useQuery({
    queryKey: ['companies', 'para-operacoes'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  // **B-04** — o filtro usa `.all`, o formulário usa `.active`. Replicado.
  const tipos = useQuery({
    queryKey: ['risk-operation-types', 'todos'],
    queryFn: () => riskOperationTypesApi.list({ perPage: 100 }),
  })

  /**
   * **FE-257** — as duas guardas do botão "Cadastrar", vindas do servidor.
   * No legado elas eram calculadas na view e despejadas em `data-` para o
   * JavaScript decidir (`_body.html.erb:19`); a mensagem é a mesma.
   */
  const guardas = useQuery({
    queryKey: ['risk-operations', 'availability'],
    queryFn: () => riskOperationsApi.availability(),
  })

  const portadores = useQuery({
    queryKey: ['risk-operations', 'portadores', filtroEmpresa],
    queryFn: () => riskOperationsApi.carriersForCompany(filtroEmpresa as string),
    enabled: !!filtroEmpresa,
  })

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['risk-operations'] })
    // A exposição muda junto: a operação consome limite.
    queryClient.invalidateQueries({ queryKey: ['risk-summary'] })
  }

  const excluir = useMutation({
    mutationFn: (operacao: RiskOperation) => riskOperationsApi.remove(operacao.id),
    onSuccess: () => {
      notify.success('Operação removida.')
      setConfirmando(null)
      invalidar()
    },
    // **D-98** — a mensagem de recusa agora chega. No legado a resposta era
    // `errors.any? ? :ok : :ok` e a tela dizia "removida com sucesso!" mesmo
    // quando o recibo barrava.
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover a operação.')),
  })

  const escopo = projectScopeCode(consulta.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as operações de risco" />

  const operacoes = consulta.data?.items ?? []
  const meta = consulta.data?.meta

  const semEmpresa = !empresas.isLoading && (empresas.data?.items?.length ?? 0) === 0
  // Só bloqueia depois de a resposta chegar: `undefined` não é "não tem".
  const semLimiteManual =
    guardas.isSuccess && !(guardas.data.carrier_available && guardas.data.manual_control)

  const abrirNova = () => {
    setEditando(null)
    setDrawerAberto(true)
  }

  /** Tipo com pré-faturamento não tem janela de datas — a lista mostra "-". */
  const dataOuTraco = (operacao: RiskOperation, valor: string | null) =>
    operacao.has_pre_faturamento || !valor ? '-' : formatDate(valor)

  const colunas: Column<RiskOperation>[] = [
    // As larguras são declaradas porque a tela tem **dez** colunas (as mesmas
    // do legado). Sem elas, "Título" quebra em cinco linhas e a linha da tabela
    // fica com 130 px de altura — medido renderizando.
    {
      key: 'carrier',
      header: 'Portador',
      sortable: true,
      width: '13rem',
      accessor: (o) => o.carrier_title,
      cell: (o) => (
        <span className="block truncate font-medium" title={o.carrier_title ?? undefined}>
          {o.carrier_title ?? '—'}
        </span>
      ),
    },
    {
      key: 'operation_type',
      header: 'Tipo',
      sortable: true,
      width: '11rem',
      // FE-250 — a coluna "Tipo" mostra o **subtipo**: é ele que decide o
      // bucket (liquidável × pré) somado no painel.
      cell: (o) => {
        const rotulo = o.operation_subtype_title ?? o.operation_type_title ?? '—'
        return <span className="block truncate" title={rotulo}>{rotulo}</span>
      },
    },
    {
      key: 'title',
      header: 'Título',
      sortable: true,
      width: '16rem',
      accessor: (o) => o.title,
      cell: (o) => <span className="block truncate" title={o.title}>{o.title}</span>,
    },
    {
      key: 'issue_date',
      header: 'Emissão',
      sortable: true,
      align: 'center',
      width: '7rem',
      cell: (o) => <span className="font-numeric">{dataOuTraco(o, o.issue_date)}</span>,
    },
    {
      key: 'operation_value',
      header: 'Capital',
      sortable: true,
      align: 'right',
      cell: (o) => <span className="font-numeric">{formatMoney(Number(o.operation_value))}</span>,
    },
    {
      key: 'balance',
      header: 'Saldo',
      sortable: true,
      align: 'right',
      cell: (o) => <span className="font-numeric">{formatMoney(Number(o.balance))}</span>,
    },
    {
      key: 'due_date',
      header: 'Vencimento',
      sortable: true,
      align: 'center',
      width: '7.5rem',
      cell: (o) => <span className="font-numeric">{dataOuTraco(o, o.due_date)}</span>,
    },
    {
      key: 'extensions',
      header: 'Prorr.',
      align: 'center',
      width: '5rem',
      cell: (o) => <span className="font-numeric">{o.extensions_count}</span>,
    },
    {
      key: 'agreed_rate',
      header: 'Tx acordada',
      sortable: true,
      align: 'right',
      cell: (o) => <span className="font-numeric">{formatPercent(Number(o.agreed_rate))}</span>,
    },
    {
      key: 'acoes',
      header: '',
      // Cinco gatilhos de 40 px + os vãos. Com 11rem os dois últimos ficavam
      // cortados fora da célula — visto renderizando, e `tsc` não pega isso.
      width: '15rem',
      align: 'right',
      cell: (o) => (
        <div className="flex justify-end gap-1">
          <Button variant="ghost" size="icon" aria-label="Ver mais"
                  onClick={(e) => { e.stopPropagation(); navigate(`/risk-operations/${o.id}`) }}>
            <Eye className="h-4 w-4" />
          </Button>
          {podeEscrever && (
            <>
              <Button variant="ghost" size="icon" aria-label="Editar"
                      onClick={(e) => { e.stopPropagation(); setEditando(o); setDrawerAberto(true) }}>
                <Pencil className="h-4 w-4" />
              </Button>
              {/* FE-256 — Renovar e Prorrogar só para tipo SEM pré-faturamento:
                  o par estático não tem janela de datas para renovar. */}
              {!o.has_pre_faturamento && (
                <>
                  <Button variant="ghost" size="icon" aria-label="Renovar"
                          onClick={(e) => { e.stopPropagation(); setRenovando(o) }}>
                    <RefreshCw className="h-4 w-4" />
                  </Button>
                  <Button variant="ghost" size="icon" aria-label="Prorrogar"
                          onClick={(e) => { e.stopPropagation(); setProrrogando(o) }}>
                    <CalendarClock className="h-4 w-4" />
                  </Button>
                </>
              )}
              <Button variant="ghost" size="icon" aria-label="Remover"
                      onClick={(e) => { e.stopPropagation(); setConfirmando(o) }}>
                <Trash2 className="h-4 w-4" />
              </Button>
            </>
          )}
        </div>
      ),
    },
  ]

  return (
    <div className="space-y-6">
      <PageHeader
        title="Operações de Risco"
        subtitle="As operações que consomem o limite de cada portador."
        rightSlot={
          podeEscrever && !semEmpresa && !semLimiteManual ? (
            <Button onClick={abrirNova}>
              <Plus className="mr-2 h-4 w-4" />
              Nova operação
            </Button>
          ) : undefined
        }
      />

      {/* FE-263 — o bloqueio de "não há empresa" vem ANTES da lista: sem
          empresa não existe limite, e sem limite não existe operação. */}
      {semEmpresa ? (
        <EmptyState
          title="Nenhuma empresa neste projeto"
          description="A operação de risco consome o limite de uma empresa. Cadastre a empresa primeiro."
          action={<Button variant="secondary" onClick={() => navigate('/companies')}>Cadastrar empresa</Button>}
        />
      ) : semLimiteManual ? (
        // **FE-257, a segunda guarda.** A mensagem é a mesma do legado
        // (`_body.js.erb:452`), com a diferença de que o predicado vem do
        // servidor e a tela oferece o caminho em vez de só reclamar.
        <EmptyState
          title="Ainda não dá para abrir operação neste projeto"
          description="É necessário ter um portador no projeto e ao menos um limite ativo com lançamento manual associado a ele."
          action={<Button variant="secondary" onClick={() => navigate('/risk-controls')}>Cadastrar limite</Button>}
        />
      ) : (
        <>
          <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
            <div className="flex flex-1 flex-col gap-3 md:flex-row">
              {/* FE-251 — UM campo, com debounce de 300 ms. */}
              <SearchInput
                value={busca.termo}
                onValueChange={busca.setTermo}
                placeholder="Buscar por portador ou título da operação"
                className="md:max-w-sm"
              />
              <Select
                value={filtroEmpresa ?? ''}
                onChange={(v) => { setFiltroEmpresa(v || null); setFiltroPortador(null); paginacao.setPage(1) }}
                options={[
                  { value: '', label: 'Todas as empresas' },
                  ...(empresas.data?.items ?? []).map((c) => ({ value: c.id, label: c.title })),
                ]}
              />
              <Select
                value={filtroPortador ?? ''}
                onChange={(v) => { setFiltroPortador(v || null); paginacao.setPage(1) }}
                disabled={!filtroEmpresa}
                options={[
                  { value: '', label: 'Todos os portadores' },
                  ...(portadores.data ?? []).map((c) => ({ value: c.id, label: c.title })),
                ]}
              />
              <Select
                value={filtroTipo ?? ''}
                onChange={(v) => { setFiltroTipo(v || null); paginacao.setPage(1) }}
                options={[
                  { value: '', label: 'Todos os tipos' },
                  ...(tipos.data?.items ?? []).map((t) => ({
                    value: t.id,
                    // B-04 — o inativo aparece AQUI e não no formulário.
                    label: t.is_active ? t.title : `${t.title} (inativo)`,
                  })),
                ]}
              />
            </div>
            {/* FE-253 — modo range. Escolhendo só a inicial, o filtro manda
                `from = to`: é a janela de um dia, e não uma faixa aberta que
                traria a base inteira. */}
            <DateRangePicker
              from={periodo.from}
              to={periodo.to}
              onChange={(r) => { setPeriodo(r); paginacao.setPage(1) }}
              labelFrom="Vigência de"
              labelTo="até"
            />
          </div>

          {estreito ? (
            <AsyncSection
              loading={consulta.isPending}
              error={consulta.error}
              data={operacoes}
              onRetry={() => consulta.refetch()}
              emptyTitle="Nenhuma operação de risco"
              emptyDescription="Nenhuma operação para os filtros escolhidos."
            >
              {(itens) => (
                <div className="space-y-3">
                  {itens.map((o) => (
                    <MobileCard
                      key={o.id}
                      title={o.title || o.carrier_title || 'Operação'}
                      subtitle={o.operation_subtype_title ?? o.operation_type_title ?? undefined}
                      onClick={() => navigate(`/risk-operations/${o.id}`)}
                      status={o.is_ended ? 'Encerrada' : undefined}
                      statusTone={o.is_ended ? 'neutral' : undefined}
                      headerAction={
                        podeEscrever ? (
                          <Button variant="ghost" size="icon" aria-label="Ações"
                                  onClick={(e) => { e.stopPropagation(); setAcoesDe(o.id) }}>
                            <MoreVertical className="h-4 w-4" />
                          </Button>
                        ) : undefined
                      }
                    >
                      <CamposDoCartao
                        itens={[
                          ['Capital', formatMoney(Number(o.operation_value))],
                          ['Saldo', formatMoney(Number(o.balance))],
                          ['Emissão', dataOuTraco(o, o.issue_date)],
                          ['Vencimento', dataOuTraco(o, o.due_date)],
                          ['Tx acordada', formatPercent(Number(o.agreed_rate))],
                          ['Prorrogações', String(o.extensions_count)],
                        ]}
                      />
                    </MobileCard>
                  ))}
                </div>
              )}
            </AsyncSection>
          ) : (
            <DataTable
              columns={colunas}
              data={operacoes}
              rowKey={(o) => o.id}
              loading={consulta.isPending}
              error={consulta.error}
              onRetry={() => consulta.refetch()}
              sortMode="server"
              sort={ordem.primeira}
              onSortChange={ordem.trocar}
              onRowClick={(o) => navigate(`/risk-operations/${o.id}`)}
              caption="Operações de risco do projeto"
              emptyTitle="Nenhuma operação de risco"
              emptyDescription="Nenhuma operação para os filtros escolhidos."
            />
          )}

          {meta && meta.total > 0 &&
            (estreito ? (
              <MobilePagination
                page={meta.page}
                perPage={meta.perPage}
                total={meta.total}
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
            ))}
        </>
      )}

      {acoesDe && (() => {
        const alvo = operacoes.find((o) => o.id === acoesDe)
        if (!alvo) return null
        return (
          <MobileRowActions
            open
            onOpenChange={(aberto) => !aberto && setAcoesDe(null)}
            title={alvo.title || 'Operação'}
            actions={[
              { key: 'ver', label: 'Ver mais', icon: <Eye className="h-4 w-4" />, onSelect: () => navigate(`/risk-operations/${alvo.id}`) },
              { key: 'editar', label: 'Editar', icon: <Pencil className="h-4 w-4" />, onSelect: () => { setEditando(alvo); setDrawerAberto(true) } },
              ...(alvo.has_pre_faturamento
                ? []
                : [
                    { key: 'renovar', label: 'Renovar', icon: <RefreshCw className="h-4 w-4" />, onSelect: () => setRenovando(alvo) },
                    { key: 'prorrogar', label: 'Prorrogar', icon: <CalendarClock className="h-4 w-4" />, onSelect: () => setProrrogando(alvo) },
                  ]),
              { key: 'remover', label: 'Remover', icon: <Trash2 className="h-4 w-4" />, destructive: true, onSelect: () => setConfirmando(alvo) },
            ]}
          />
        )
      })()}

      <RiskOperationDrawer
        open={drawerAberto}
        operacao={editando}
        onClose={() => { setDrawerAberto(false); setEditando(null) }}
        onSaved={invalidar}
      />

      {renovando && (
        <RenewalDrawer
          operacao={renovando}
          onClose={() => setRenovando(null)}
          onRenewed={invalidar}
        />
      )}

      {prorrogando && (
        <ExtensionDrawer
          operacao={prorrogando}
          onClose={() => setProrrogando(null)}
          onExtended={invalidar}
        />
      )}

      <ConfirmDialog
        open={!!confirmando}
        onOpenChange={(aberto) => !aberto && setConfirmando(null)}
        // O legado abria um modal com o título "Excluir renegociação" — rótulo
        // de outro módulo, copiado junto com a parcial.
        title="Excluir operação de risco"
        description={
          confirmando
            ? `A operação «${confirmando.title}» e todos os seus movimentos serão removidos. Não dá para desfazer.`
            : ''
        }
        confirmLabel="Excluir"
        loading={excluir.isPending}
        onConfirm={() => confirmando && excluir.mutate(confirmando)}
      />
    </div>
  )
}
