import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Ban, CheckCircle2, Lock, Pencil, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { SideDrawer } from '@/components/SideDrawer'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { SearchInput } from '@/components/ui/SearchInput'
import { Select } from '@/components/ui/Select'
import { Tooltip } from '@/components/ui/Tooltip'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { companiesApi } from '@/lib/api/projects'
// A moeda vem da CONFIGURAÇÃO do app (`APP_CURRENCY`), não de `'BRL'` cravado
// na tela: `formatMoney`/`formatPercent` são o único formatador do produto.
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import {
  listRiskControls,
  riskControlsApi,
  riskOperationTypesApi,
  type RiskControl,
} from '../api/risk'
import { LIMITE_VAZIO, RiskControlDrawer, type RiskControlFormValues } from '../components/RiskControlDrawer'

/**
 * **Limites** (FE-240..FE-249) — a tela que cadastra o teto de risco.
 *
 * Nenhuma operação de risco e nenhum recebível existem sem um limite para a
 * combinação (empresa, portador, tipo). É por isso que esta tela vem antes das
 * telas que a consomem.
 *
 * ### O que mudou em relação ao legado, e está registrado
 *
 * - **IMP-R3 — a busca passa a filtrar.** Lá o `q` era lido, recebia `""` por
 *   default e **nunca** entrava no `where`: a caixa não fazia nada, e a
 *   mensagem "Não encontramos nenhum resultado para a busca «x»" era
 *   inalcançável. Está em `improvements-log.md` para o QA não abrir bug.
 * - **O filtro de portador vem do PROJETO**, não de `Carrier.all` (FE-241).
 * - **A exclusão bloqueada diz o que está impedindo** (FE-247). No legado ela
 *   respondia 202 e a tela dizia "excluído" sem ter excluído (D-24/D-98).
 * - **Ativar não mente.** Lá o `activate!` usava `save` e o controller respondia
 *   200 mesmo quando a validação recusava.
 *
 * Todo botão de escrita tem par no **servidor** (FE-248): esconder o botão nunca
 * foi autorização.
 */
export function RiskControlsPage() {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  // O grupo "Projeto" da matriz é `CRUD` para os quatro papéis: o gate é a
  // PARTICIPAÇÃO no projeto (C1), não o papel (C3).
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination()
  const [sort, setSort] = useState<SortState | null>({ key: 'title', direction: 'asc' })

  const [filtroEmpresa, setFiltroEmpresa] = useState<string | null>(null)
  const [filtroPortador, setFiltroPortador] = useState<string | null>(null)
  const [filtroTipo, setFiltroTipo] = useState<string | null>(null)

  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<RiskControl | null>(null)
  const [valores, setValores] = useState<RiskControlFormValues>(LIMITE_VAZIO)
  const [confirmando, setConfirmando] = useState<RiskControl | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  useEffect(() => {
    document.title = 'Safegold - Limites'
  }, [])

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      companyId: filtroEmpresa ?? undefined,
      carrierId: filtroPortador ?? undefined,
      riskOperationTypeId: filtroTipo ?? undefined,
      orderingKey: sort?.key,
      orderingStyle: (sort?.direction === 'desc' ? 'down' : 'up') as 'up' | 'down',
    }),
    [paginacao.page, paginacao.perPage, busca.consulta, filtroEmpresa, filtroPortador, filtroTipo, sort],
  )

  const consulta = useQuery({
    queryKey: ['risk-controls', filtros],
    queryFn: () => listRiskControls(filtros),
  })

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['risk-controls'] })
    // O console lê os mesmos limites — mudar um aqui muda o painel lá.
    queryClient.invalidateQueries({ queryKey: ['risk-summary'] })
  }

  const salvar = useMutation({
    mutationFn: (dados: RiskControlFormValues) =>
      editando
        ? riskControlsApi.update(editando.id, { limite: dados.limite, taxa: dados.taxa })
        : riskControlsApi.create({
            company_id: dados.company_id,
            carrier_id: dados.carrier_id,
            risk_operation_type_id: dados.risk_operation_type_id,
            limite: dados.limite ?? 0,
            taxa: dados.taxa ?? 0,
            original_balance: dados.original_balance ?? 0,
            original_balance_pre: dados.original_balance_pre ?? 0,
          }),
    onSuccess: () => {
      notify.success(editando ? 'Limite atualizado.' : 'Limite cadastrado.')
      fecharDrawer()
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o limite.')),
  })

  const alternar = useMutation({
    mutationFn: (limite: RiskControl) =>
      limite.is_active ? riskControlsApi.deactivate(limite.id) : riskControlsApi.activate(limite.id),
    onSuccess: (_dado, limite) => {
      notify.success(
        limite.is_active
          ? `Limite «${limite.title}» desativado. Ele sai do painel de exposição.`
          : `Limite «${limite.title}» ativado. Ele volta ao painel de exposição.`,
      )
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível mudar o estado do limite.')),
  })

  const excluir = useMutation({
    mutationFn: (limite: RiskControl) => riskControlsApi.remove(limite.id),
    onSuccess: (_dado, limite) => {
      notify.success(`Limite «${limite.title}» excluído.`)
      setConfirmando(null)
      invalidar()
    },
    onError: (erro) => {
      // A mensagem do servidor NOMEIA a dependência. Reescrevê-la aqui seria a
      // segunda implementação da mesma regra.
      notify.error(mensagemDoServidor(erro, 'Não foi possível excluir o limite.'))
      setConfirmando(null)
    },
  })

  function abrirCriacao() {
    setEditando(null)
    setValores(LIMITE_VAZIO)
    setDrawerAberto(true)
  }

  function abrirEdicao(limite: RiskControl) {
    setEditando(limite)
    setValores({
      company_id: limite.company_id,
      carrier_id: limite.carrier_id,
      risk_operation_type_id: limite.risk_operation_type_id,
      limite: Number(limite.limite),
      taxa: Number(limite.taxa),
      original_balance: Number(limite.original_balance),
      original_balance_pre: Number(limite.original_balance_pre),
    })
    setDrawerAberto(true)
  }

  function fecharDrawer() {
    setDrawerAberto(false)
    setEditando(null)
  }

  const colunas: Column<RiskControl>[] = [
    {
      key: 'title',
      header: 'Portador',
      sortable: true,
      accessor: (c) => c.carrier_title ?? '',
      cell: (c) => (
        <span className="block">
          <span className="flex items-center gap-2">
            <span className="truncate">{c.carrier_title ?? '—'}</span>
            {!c.is_active && (
              <Tooltip content="Desativado / Limite desativado, não será utilizado">
                <Badge variant="secondary" className="shrink-0">
                  Desativado
                </Badge>
              </Tooltip>
            )}
            {/* DB-240 / DEC-43 — linha do modelo pré-2022, sem tipo. Ela some
                de todos os agregados até o ETL convertê-la, e o rótulo existe
                para que isso não seja descoberto por diferença de número. */}
            {c.is_legacy_shape && (
              <Tooltip content="Limite no formato anterior a 2022, sem tipo. Ele NÃO entra no painel de exposição até ser convertido.">
                <Badge variant="secondary" className="shrink-0">
                  Legado
                </Badge>
              </Tooltip>
            )}
          </span>
          {c.carrier_group_title && (
            <span className="block text-xs text-muted-foreground">• {c.carrier_group_title}</span>
          )}
        </span>
      ),
    },
    {
      key: 'company',
      header: 'Empresa',
      accessor: (c) => c.company_title ?? '',
      cell: (c) => <span className="block truncate">{c.company_title ?? '—'}</span>,
    },
    {
      key: 'type',
      header: 'Tipo',
      accessor: (c) => c.risk_operation_type_title ?? '',
      cell: (c) => (
        <span className="flex items-center gap-1.5">
          <span className="truncate">{c.risk_operation_type_title ?? '—'}</span>
          {c.has_pre_faturamento && (
            <Tooltip content="Tipo com pré-faturamento: o limite tem o par de operações estáticas.">
              <Badge variant="secondary" className="shrink-0">
                Pré
              </Badge>
            </Tooltip>
          )}
        </span>
      ),
    },
    {
      key: 'limite',
      header: 'Lim',
      sortable: true,
      variant: 'number',
      accessor: (c) => Number(c.limite),
      cell: (c) => <span className="font-numeric tabular-nums">{formatMoney(Number(c.limite))}</span>,
    },
    {
      key: 'taxa',
      header: 'Tax',
      sortable: true,
      variant: 'number',
      accessor: (c) => Number(c.taxa),
      cell: (c) => <span className="font-numeric tabular-nums">{formatPercent(Number(c.taxa))}</span>,
    },
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      align: 'right',
      width: '10rem',
      cell: (c) => (podeEscrever ? <AcoesDoLimite limite={c} onEditar={abrirEdicao} onAlternar={alternar.mutate} onExcluir={setConfirmando} /> : null),
    },
  ]

  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0
  const escopo = projectScopeCode(consulta.error)

  // Os dois 409 de escopo são ESTADO, não erro: sem projeto escolhido não há
  // lista a mostrar, e isso não é falha do sistema nem do usuário.
  if (escopo) {
    return (
      <div className="pb-10">
        <PageHeader
          title="Limites"
          subtitle="O teto de risco por empresa, portador e tipo. Toda operação e todo recebível dependem de um limite ativo."
        />
        <ProjectScopeState code={escopo} recurso="os limites de risco" />
      </div>
    )
  }

  return (
    <div className="pb-10">
      <PageHeader
        title="Limites"
        subtitle="O teto de risco por empresa, portador e tipo. Toda operação e todo recebível dependem de um limite ativo."
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
            placeholder="Buscar por portador ou empresa…"
            aria-label="Buscar limite por portador ou empresa"
          />
        }
        rightSlot={
          podeEscrever ? (
            <Button onClick={abrirCriacao}>
              <Plus aria-hidden="true" className="h-4 w-4" />
              Novo limite
            </Button>
          ) : undefined
        }
      />

      <RiskControlFilters
        empresa={filtroEmpresa}
        portador={filtroPortador}
        tipo={filtroTipo}
        onEmpresa={(v) => {
          setFiltroEmpresa(v)
          setFiltroPortador(null)
          paginacao.reset()
        }}
        onPortador={(v) => {
          setFiltroPortador(v)
          paginacao.reset()
        }}
        onTipo={(v) => {
          setFiltroTipo(v)
          paginacao.reset()
        }}
      />

      {estreito ? (
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={consulta.data?.items}
          onRetry={() => consulta.refetch()}
          loadingLabel="Carregando limites…"
          emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum limite cadastrado'}
          emptyDescription={
            buscando
              ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
              : 'Sem limite não há operação de risco nem recebível. Cadastre o primeiro para esta empresa.'
          }
        >
          {(itens) => (
            <div>
              {itens.map((c) => (
                <MobileCard
                  key={c.id}
                  title={c.carrier_title ?? c.title}
                  subtitle={c.company_title ?? undefined}
                  status={c.is_active ? undefined : 'Desativado'}
                  statusTone={c.is_active ? undefined : 'neutral'}
                  headerAction={
                    podeEscrever ? (
                      <span onClick={(e) => e.stopPropagation()}>
                        <MobileRowActions
                          open={acoesDe === c.id}
                          onOpenChange={(aberto) => setAcoesDe(aberto ? c.id : null)}
                          title={c.carrier_title ?? c.title}
                          subtitle="Limite de risco"
                          actions={[
                            {
                              key: 'editar',
                              label: 'Editar',
                              icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
                              onSelect: () => abrirEdicao(c),
                            },
                            {
                              key: 'estado',
                              label: c.is_active ? 'Desativar' : 'Ativar',
                              icon: c.is_active ? (
                                <Ban aria-hidden="true" className="h-4 w-4" />
                              ) : (
                                <CheckCircle2 aria-hidden="true" className="h-4 w-4" />
                              ),
                              onSelect: () => alternar.mutate(c),
                            },
                            {
                              key: 'excluir',
                              label: 'Excluir',
                              icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                              destructive: true,
                              disabledReason: c.dependents_count > 0 ? motivoDoBloqueio(c) : undefined,
                              onSelect: () => setConfirmando(c),
                            },
                          ]}
                        />
                      </span>
                    ) : undefined
                  }
                >
                  <dl className="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Tipo</dt>
                      <dd className="text-foreground">{c.risk_operation_type_title ?? '—'}</dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Taxa</dt>
                      <dd className="font-numeric tabular-nums text-foreground">{formatPercent(Number(c.taxa))}</dd>
                    </div>
                    <div className="col-span-2">
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Limite</dt>
                      <dd className="font-numeric tabular-nums text-foreground">{formatMoney(Number(c.limite))}</dd>
                    </div>
                  </dl>
                </MobileCard>
              ))}
            </div>
          )}
        </AsyncSection>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-card">
          <DataTable
            columns={colunas}
            data={consulta.data?.items}
            rowKey={(c) => c.id}
            loading={consulta.isLoading}
            error={consulta.isError ? consulta.error : undefined}
            onRetry={() => consulta.refetch()}
            sortMode="server"
            sort={sort}
            onSortChange={(s) => {
              setSort(s)
              paginacao.reset()
            }}
            caption="Limites de risco"
            loadingLabel="Carregando limites…"
            emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum limite cadastrado'}
            emptyDescription={
              buscando
                ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
                : 'Sem limite não há operação de risco nem recebível. Cadastre o primeiro para esta empresa.'
            }
            emptyAction={
              buscando ? (
                <Button variant="secondary" size="sm" onClick={busca.limpar}>
                  Limpar busca
                </Button>
              ) : podeEscrever ? (
                <Button size="sm" onClick={abrirCriacao}>
                  <Plus aria-hidden="true" className="h-4 w-4" />
                  Novo limite
                </Button>
              ) : undefined
            }
          />
        </div>
      )}

      {meta && meta.total > 0 && estreito && (
        <MobilePagination
          page={meta.page}
          total={meta.total}
          perPage={meta.perPage}
          loading={consulta.isFetching}
          onPageChange={paginacao.setPage}
        />
      )}

      {meta && meta.total > 0 && !estreito && (
        <PaginationPill
          className="mt-4"
          page={meta.page}
          totalPages={meta.totalPages}
          perPage={meta.perPage}
          loading={consulta.isFetching}
          onPageChange={paginacao.setPage}
          onPerPageChange={paginacao.setPerPage}
        />
      )}

      <RiskControlDrawer
        open={drawerAberto}
        onClose={fecharDrawer}
        editing={editando}
        values={valores}
        setValue={(campo, valor) => setValores((atual) => ({ ...atual, [campo]: valor }))}
        onSubmit={() => salvar.mutate(valores)}
        saving={salvar.isPending}
      />

      <SideDrawer
        open={confirmando !== null}
        onClose={() => setConfirmando(null)}
        title="Excluir limite"
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" onClick={() => setConfirmando(null)}>
              Cancelar
            </Button>
            <Button
              variant="destructive"
              className="flex-1"
              loading={excluir.isPending}
              onClick={() => confirmando && excluir.mutate(confirmando)}
            >
              Excluir
            </Button>
          </div>
        }
      >
        <p className="text-sm text-foreground">
          Excluir o limite de <strong>«{confirmando?.carrier_title}»</strong> em{' '}
          <strong>{confirmando?.company_title}</strong>?
        </p>
        <p className="text-sm text-muted-foreground">A operação não pode ser desfeita. Tem certeza?</p>
        {confirmando && confirmando.dependents_count > 0 && (
          <p className="rounded-md border border-border bg-muted/40 p-3 text-sm text-muted-foreground">
            {motivoDoBloqueio(confirmando)} O servidor vai recusar, e nada será apagado.
          </p>
        )}
      </SideDrawer>
    </div>
  )
}

/** A frase que explica o 422 — o mesmo número que o servidor usa para recusar. */
function motivoDoBloqueio(limite: RiskControl): string {
  const n = limite.dependents_count
  const base =
    n === 1
      ? '1 operação ou posição depende deste limite'
      : `${n} operações ou posições dependem deste limite`
  return limite.has_pre_faturamento
    ? `${base} — inclusive o par de operações estáticas que o próprio limite abriu.`
    : `${base}.`
}

/**
 * Ações da linha (FE-247). O botão de excluir **some** quando o servidor
 * recusaria, e o lugar dele fica ocupado pela explicação — em vez de a linha
 * perder uma ação sem dizer por quê.
 */
function AcoesDoLimite({
  limite,
  onEditar,
  onAlternar,
  onExcluir,
}: {
  limite: RiskControl
  onEditar: (l: RiskControl) => void
  onAlternar: (l: RiskControl) => void
  onExcluir: (l: RiskControl) => void
}) {
  return (
    <div className="flex items-center justify-end gap-1" onClick={(e) => e.stopPropagation()}>
      <Button variant="ghost" size="icon" aria-label={`Editar limite de ${limite.carrier_title}`} onClick={() => onEditar(limite)}>
        <Pencil aria-hidden="true" className="h-4 w-4" />
      </Button>

      <Tooltip content={limite.is_active ? 'Desativar — sai do painel de exposição' : 'Ativar — volta ao painel'}>
        <Button
          variant="ghost"
          size="icon"
          aria-label={limite.is_active ? `Desativar limite de ${limite.carrier_title}` : `Ativar limite de ${limite.carrier_title}`}
          onClick={() => onAlternar(limite)}
        >
          {limite.is_active ? (
            <Ban aria-hidden="true" className="h-4 w-4" />
          ) : (
            <CheckCircle2 aria-hidden="true" className="h-4 w-4" />
          )}
        </Button>
      </Tooltip>

      {limite.dependents_count > 0 ? (
        <Tooltip content={motivoDoBloqueio(limite)}>
          <span className="inline-flex h-9 w-9 items-center justify-center text-muted-foreground" aria-label={motivoDoBloqueio(limite)}>
            <Lock aria-hidden="true" className="h-4 w-4" />
          </span>
        </Tooltip>
      ) : (
        <Button variant="ghost" size="icon" aria-label={`Excluir limite de ${limite.carrier_title}`} onClick={() => onExcluir(limite)}>
          <Trash2 aria-hidden="true" className="h-4 w-4" />
        </Button>
      )}
    </div>
  )
}

/**
 * **Filtros da tela de Limites** (FE-241).
 *
 * Os três selects. O de portador vem de `GET /risk_controls/filters` — os
 * portadores que **têm limite** no projeto —, não de `Carrier.all`: filtrar por
 * um portador sem limite nenhum devolveria lista vazia e pareceria erro.
 */
function RiskControlFilters({
  empresa,
  portador,
  tipo,
  onEmpresa,
  onPortador,
  onTipo,
}: {
  empresa: string | null
  portador: string | null
  tipo: string | null
  onEmpresa: (v: string | null) => void
  onPortador: (v: string | null) => void
  onTipo: (v: string | null) => void
}) {
  const empresas = useQuery({
    queryKey: ['risk-filter-companies'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  const portadores = useQuery({
    queryKey: ['risk-filter-carriers', empresa],
    queryFn: () => riskControlsApi.carriersWithActiveControl(empresa ?? undefined),
  })

  const tipos = useQuery({
    queryKey: ['risk-operation-types', 'ativos'],
    queryFn: () => riskOperationTypesApi.list({ active: true, perPage: 100 }),
  })

  return (
    <div className="mb-4 grid gap-2 sm:grid-cols-3">
      {/* A opção "todos" é uma OPÇÃO nomeada, como o `include_blank` do legado —
          linha vazia sem rótulo é lida como "escolha alguma coisa". */}
      <Select
        aria-label="Filtrar por empresa"
        options={[
          { value: '', label: 'Todas as empresas' },
          ...(empresas.data?.items ?? []).map((e) => ({ value: e.id, label: e.title })),
        ]}
        value={empresa ?? ''}
        onChange={(v) => onEmpresa(v || null)}
      />
      <Select
        aria-label="Filtrar por portador"
        options={[
          { value: '', label: 'Todos os portadores' },
          ...(portadores.data ?? []).map((c) => ({
            value: c.id,
            label: c.title,
            description: c.group_title ?? undefined,
          })),
        ]}
        value={portador ?? ''}
        onChange={(v) => onPortador(v || null)}
      />
      <Select
        aria-label="Filtrar por tipo de limite"
        options={[
          { value: '', label: 'Todos os tipos' },
          ...(tipos.data?.items ?? []).map((t) => ({ value: t.id, label: t.title })),
        ]}
        value={tipo ?? ''}
        onChange={(v) => onTipo(v || null)}
      />
    </div>
  )
}
