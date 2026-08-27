import { useCallback, useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Pencil, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { SearchInput } from '@/components/ui/SearchInput'
import { Select } from '@/components/ui/Select'
import { Tooltip } from '@/components/ui/Tooltip'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatPercent } from '@/lib/utils/number'
import {
  REMUNERATION_CLASS_LABELS,
  listRemunerations,
  remunerationsApi,
  type Remuneration,
  type RemunerationClass,
} from '../api/structuredOperations'
import { RemunerationDrawer } from '../components/RemunerationDrawer'

/**
 * **Projeto › Remunerações** (`FE-303`…`FE-306`).
 *
 * A remuneração é **a única linha do sistema que multiplica faturamento**: é o
 * `fee` de `Receipt#fetch`, e o valor do recibo é
 * `operation_value × (fee / 100)`. Por isso esta tela **não calcula nada** — o
 * `%` na célula é rótulo, e quem multiplica é o servidor (contrato **C2**).
 *
 * ## O que muda em relação ao legado
 *
 * - **`FE-303` — ordenação e paginação passam a existir.** O
 *   `remunerations_controller#search` do legado devolve a relação **inteira**,
 *   sem `ORDER BY`, sem `LIMIT` e sem total. Com um projeto de 200 tipos, a
 *   tela carregava 200 linhas em ordem de inserção.
 * - **O `%` aparece na CÉLULA**, não só no cabeçalho da coluna. No legado a
 *   célula imprimia `2.55` e o cabeçalho dizia "Taxa (%)" — quem chegava pelo
 *   meio da tabela lia um número sem unidade.
 * - **`FE-306` — os dois defeitos do deep-link.** O `openEdit(id)` do legado
 *   gravava `taxId` enquanto o proxy lia `remuneration_id`, então pelo
 *   deep-link a URL virava `/remunerations/undefined/edit.js`; e o ERB escapado
 *   punha a **string literal** `<%= pub_console_path %>` dentro do
 *   `history.replaceState`. Aqui `/remunerations/add` e
 *   `/remunerations/:id/edit` são **rotas de verdade**, com histórico — o botão
 *   Voltar volta, em vez de sair do console (D-92).
 *
 * ## O gate é papel **e** somente-leitura
 *
 * "Cadastrar" exige `!user_is_readonly` **e** admin/og/gerente — as duas
 * condições do legado (`_body.html.erb:11-13`), aninhadas. Esconder o botão é
 * conveniência; quem recusa é o servidor.
 */
export function RemunerationsPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const { id: idDaRota } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ['og', 'admin', 'gerente'].includes(papel) && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination()
  const [sort, setSort] = useState<SortState | null>({ key: 'kind', direction: 'asc' })
  const [filtroClasse, setFiltroClasse] = useState<RemunerationClass | null>(null)

  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<Remuneration | null>(null)
  const [confirmando, setConfirmando] = useState<Remuneration | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  useEffect(() => {
    document.title = 'Safegold - Remunerações'
  }, [])

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      operationTypeType: filtroClasse ?? undefined,
      orderingKey: sort?.key,
      orderingStyle: (sort?.direction === 'desc' ? 'down' : 'up') as 'up' | 'down',
    }),
    [paginacao.page, paginacao.perPage, busca.consulta, filtroClasse, sort],
  )

  const consulta = useQuery({
    queryKey: ['remunerations', filtros],
    queryFn: () => listRemunerations(filtros),
    placeholderData: keepPreviousData,
  })

  const invalidar = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['remunerations'] })
    queryClient.invalidateQueries({ queryKey: ['charge-receipts'] })
  }, [queryClient])

  // --- Deep-link (FE-306) ---------------------------------------------------
  const abrirCriacao = useCallback(() => {
    setEditando(null)
    setDrawerAberto(true)
    navigate('/remunerations/add')
  }, [navigate])

  const abrirEdicao = useCallback(
    (r: Remuneration) => {
      setEditando(r)
      setDrawerAberto(true)
      navigate(`/remunerations/${r.id}/edit`)
    },
    [navigate],
  )

  const fecharDrawer = useCallback(() => {
    setDrawerAberto(false)
    setEditando(null)
    navigate('/remunerations')
  }, [navigate])

  // Entrar por URL (link colado, recarregar a página) abre o painel — é o que
  // torna o deep-link uma rota, e não um efeito colateral do clique.
  useEffect(() => {
    if (!idDaRota) return
    const alvo = consulta.data?.items.find((r) => r.id === idDaRota)
    if (alvo) {
      setEditando(alvo)
      setDrawerAberto(true)
      return
    }
    remunerationsApi
      .get(idDaRota)
      .then((r) => {
        setEditando(r)
        setDrawerAberto(true)
      })
      .catch(() => {
        notify.error('Remuneração não encontrada.')
        navigate('/remunerations')
      })
    // Só reage à troca de id na URL.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idDaRota])

  // `useLocation`, e não `window.location`: o botão Voltar muda a rota **sem**
  // remontar a tela, e sem isto o painel não reabriria em `/remunerations/add`.
  useEffect(() => {
    if (location.pathname.endsWith('/remunerations/add')) {
      setEditando(null)
      setDrawerAberto(true)
    } else if (location.pathname === '/remunerations') {
      setDrawerAberto(false)
      setEditando(null)
    }
  }, [location.pathname])

  const excluir = useMutation({
    mutationFn: (r: Remuneration) => remunerationsApi.remove(r.id),
    onSuccess: (_dado, r) => {
      notify.success(`Remuneração «${r.title}» excluída.`)
      setConfirmando(null)
      invalidar()
    },
    onError: (erro) => {
      // BE-303 — com recibo emitido o servidor recusa e NOMEIA o vínculo. No
      // legado `has_many :receipts` estava sem `dependent:`: apagar a
      // remuneração deixava recibo órfão, e qualquer save posterior daquele
      // recibo falhava.
      notify.error(mensagemDoServidor(erro, 'Não foi possível excluir a remuneração.'))
      setConfirmando(null)
    },
  })

  const escopo = projectScopeCode(consulta.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as remunerações" />

  const itens = consulta.data?.items ?? []
  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0
  const filtrando = buscando || !!filtroClasse

  const vazioTitulo = buscando
    ? `Nenhum resultado para «${busca.consulta}»`
    : filtrando
      ? 'Nenhuma remuneração nesta classe'
      : 'Nenhuma remuneração neste projeto'
  const vazioDescricao = filtrando
    ? 'Tente outro termo ou limpe os filtros para ver a lista completa.'
    : 'Sem remuneração cadastrada, nenhuma operação do projeto pode virar recibo. Cadastre a primeira taxa.'

  const acaoDeVinculo = (r: Remuneration) =>
    r.receipts_count === 1
      ? '1 recibo já foi emitido com esta taxa — não é possível excluir'
      : `${r.receipts_count} recibos já foram emitidos com esta taxa — não é possível excluir`

  const colunas: Column<Remuneration>[] = [
    {
      key: 'kind',
      header: 'Classe',
      sortable: true,
      width: '7rem',
      accessor: (r) => r.beauty_type,
      cell: (r) => (
        <Tooltip content={REMUNERATION_CLASS_LABELS[r.operation_type_type]}>
          <Badge variant={r.beauty_type === 'LIQ' ? 'secondary' : 'outline'}>{r.beauty_type}</Badge>
        </Tooltip>
      ),
    },
    {
      key: 'title',
      header: 'Operação',
      sortable: true,
      accessor: (r) => r.title,
      cell: (r) => (
        <span className="block truncate" title={r.title}>
          {r.title}
        </span>
      ),
    },
    {
      key: 'value',
      header: 'Taxa (%)',
      sortable: true,
      align: 'right',
      width: '9rem',
      accessor: (r) => Number(r.value),
      // O `%` fica na CÉLULA. No legado ele vivia só no cabeçalho.
      cell: (r) => <span className="font-numeric tabular-nums">{formatPercent(Number(r.value))}</span>,
    },
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      align: 'right',
      width: '7rem',
      cell: (r) => {
        if (!podeEscrever) return null
        return (
          <div className="flex items-center justify-end gap-1" onClick={(e) => e.stopPropagation()}>
            <Button variant="ghost" size="icon" aria-label={`Editar ${r.title}`} onClick={() => abrirEdicao(r)}>
              <Pencil aria-hidden="true" className="h-4 w-4" />
            </Button>
            {r.receipts_count > 0 ? (
              <Tooltip content={acaoDeVinculo(r)}>
                <span
                  className="inline-flex h-9 w-9 items-center justify-center text-muted-foreground"
                  aria-label={acaoDeVinculo(r)}
                >
                  <Trash2 aria-hidden="true" className="h-4 w-4 opacity-40" />
                </span>
              </Tooltip>
            ) : (
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Excluir ${r.title}`}
                onClick={() => setConfirmando(r)}
              >
                <Trash2 aria-hidden="true" className="h-4 w-4" />
              </Button>
            )}
          </div>
        )
      },
    },
  ]

  return (
    <div className="pb-10">
      <PageHeader
        title="Remunerações"
        subtitle="A taxa que o projeto cobra por tipo de operação. É ela que o recibo congela ao faturar."
        loading={consulta.isFetching && !consulta.isLoading}
        searchSlot={
          <SearchInput
            value={busca.termo}
            onValueChange={(v) => {
              busca.setTermo(v)
              paginacao.reset()
            }}
            onClear={() => {
              busca.limpar()
              paginacao.reset()
            }}
            loading={busca.pendente}
            placeholder="Buscar por operação…"
            aria-label="Buscar remuneração"
          />
        }
        rightSlot={
          podeEscrever ? (
            <Button onClick={abrirCriacao}>
              <Plus aria-hidden="true" className="h-4 w-4" />
              Nova remuneração
            </Button>
          ) : undefined
        }
      />

      <div className="mb-4 max-w-xs">
        <Select
          aria-label="Filtrar por classe"
          placeholder="Todas as classes"
          value={filtroClasse}
          onChange={(v) => {
            setFiltroClasse((v as RemunerationClass) || null)
            paginacao.reset()
          }}
          options={[
            { value: '', label: 'Todas as classes' },
            { value: 'RiskOperationType', label: 'LIQ — Operações liquidáveis' },
            { value: 'StructuredOperationType', label: 'EST — Operações estruturadas' },
          ]}
        />
      </div>

      {estreito ? (
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={itens}
          onRetry={() => consulta.refetch()}
          loadingLabel="Carregando remunerações…"
          emptyTitle={vazioTitulo}
          emptyDescription={vazioDescricao}
        >
          {(linhas) => (
            <div>
              {linhas.map((r) => (
                <MobileCard
                  key={r.id}
                  title={r.title}
                  subtitle={REMUNERATION_CLASS_LABELS[r.operation_type_type]}
                  status={r.beauty_type}
                  statusTone="neutral"
                  headerAction={
                    podeEscrever ? (
                      <span onClick={(e) => e.stopPropagation()}>
                        <MobileRowActions
                          open={acoesDe === r.id}
                          onOpenChange={(aberto) => setAcoesDe(aberto ? r.id : null)}
                          title={r.title}
                          subtitle="Remuneração"
                          actions={[
                            {
                              key: 'editar',
                              label: 'Editar',
                              icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
                              onSelect: () => abrirEdicao(r),
                            },
                            {
                              key: 'excluir',
                              label: 'Excluir',
                              icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                              destructive: true,
                              disabledReason: r.receipts_count > 0 ? acaoDeVinculo(r) : undefined,
                              onSelect: () => setConfirmando(r),
                            },
                          ]}
                        />
                      </span>
                    ) : undefined
                  }
                >
                  <dl className="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Taxa</dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatPercent(Number(r.value))}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Recibos</dt>
                      <dd className="font-numeric tabular-nums text-foreground">{r.receipts_count}</dd>
                    </div>
                  </dl>
                </MobileCard>
              ))}
            </div>
          )}
        </AsyncSection>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-card">
          <DataTable<Remuneration>
            columns={colunas}
            data={itens}
            rowKey={(r) => r.id}
            loading={consulta.isLoading}
            error={consulta.isError ? consulta.error : undefined}
            onRetry={() => consulta.refetch()}
            sortMode="server"
            sort={sort}
            onSortChange={(s) => {
              setSort(s)
              paginacao.reset()
            }}
            caption="Remunerações do projeto"
            loadingLabel="Carregando remunerações…"
            emptyTitle={vazioTitulo}
            emptyDescription={vazioDescricao}
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

      <RemunerationDrawer
        aberto={drawerAberto}
        editando={editando}
        onFechar={fecharDrawer}
        onSalvo={fecharDrawer}
      />

      <ConfirmDialog
        open={confirmando !== null}
        onOpenChange={(aberto) => !aberto && setConfirmando(null)}
        title="Excluir remuneração"
        description={
          confirmando
            ? `A remuneração «${confirmando.title}» (${confirmando.beauty_type}, ${formatPercent(Number(confirmando.value))}) será removida. Operações deste tipo deixam de poder virar recibo.`
            : ''
        }
        confirmLabel="Excluir"
        tone="destructive"
        loading={excluir.isPending}
        onConfirm={() => confirmando && excluir.mutate(confirmando)}
      />
    </div>
  )
}
