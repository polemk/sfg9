import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, Pencil, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { DatePicker } from '@/components/ui/DatePicker'
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
import { useSortStack } from '@/hooks/useSortStack'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { carrierConnectionsApi } from '@/lib/api/projects'
// `formatMoney` distingue **nulo de zero** (D-117): nulo rende travessão, zero
// rende `R$ 0,00`. No legado os dois viravam `R$ 0,00` — num sistema de crédito
// isso confunde "não informado" com "zero".
import { formatAmount, formatMoney, formatPercent } from '@/lib/utils/number'
import {
  receivablesApi,
  walletsApi,
  type ReceivableEntry,
  type ReceivableOrderingKey,
} from '../api/receivables'

/**
 * **Recebíveis** (FE-150…FE-164) — a lista de borderôs.
 *
 * É a maior lista do sistema: **28.131 linhas em produção**, de 27/02/2022 a
 * 30/05/2025. Foi para ela que a paginação de verdade e os índices desta fatia
 * foram feitos.
 *
 * ## O que muda em relação ao legado
 *
 * - **A paginação funciona** (D-20). No legado `limit`/`offset` eram lidos e
 *   **descartados**: o servidor mandava a lista inteira, a UI de paginação era
 *   decorativa e a última página ia para o lugar errado.
 * - **A ordenação acontece no servidor**, por uma allowlist (`Sfg::Sortable`).
 *   No legado uma chave desconhecida na barra de endereço derrubava o request
 *   com 500 — `get_ordering_key` devolvia `nil` e a linha seguinte fazia
 *   `nil + " "`.
 * - **A busca filtra de verdade e é literal.** O legado interpolava fragmento
 *   SQL na string do `where`: `%` do usuário virava curinga.
 * - **O CET é formatado em pt-BR** (FE-162). No legado saía cru na tela.
 * - **O portador do filtro vem do PROJETO** (FE-158) — `ProjectToCarrierConnection`,
 *   o mesmo e único critério que o servidor usa. Ter dois critérios foi o que
 *   fez a tela do legado oferecer portador que o servidor recusava.
 * - **Falha aparece.** O quarto estado (erro, com "tentar de novo") vem do
 *   `AsyncSection`; no legado o callback de erro era vazio e a tela ficava em
 *   branco, indistinguível de "não há nada".
 *
 * ## O rodapé soma a CONSULTA, não a página
 *
 * `GET /receivables/summary` agrega no banco com os mesmos filtros. Somar no
 * cliente exigiria trazer as 28 mil linhas para contar — que é literalmente o
 * que o legado fazia.
 */
export function ReceivablesPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  // O grupo "Projeto" da matriz é `CRUD` para os quatro papéis: o gate é a
  // PARTICIPAÇÃO no projeto (C1), não o papel (C3). O servidor decide de novo.
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination()
  // FE-159 — a ordenacao EMPILHA. Ver `useSortStack`.
  const ordem = useSortStack([{ key: 'date', direction: 'desc' }])

  const [filtroCarteira, setFiltroCarteira] = useState<string | null>(null)
  const [filtroPortador, setFiltroPortador] = useState<string | null>(null)
  const [de, setDe] = useState<Date | null>(null)
  const [ate, setAte] = useState<Date | null>(null)

  const [confirmando, setConfirmando] = useState<ReceivableEntry | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  useEffect(() => {
    document.title = 'Safegold - Recebíveis'
  }, [])

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      walletId: filtroCarteira ?? undefined,
      carrierId: filtroPortador ?? undefined,
      // Data ausente **omite** a cláusula no servidor. No legado o que faltava
      // virava `DateTime.dinosaurs` (ano −2000) ou `.mars` (ano +2000): um
      // intervalo de 4000 anos que o banco tinha de percorrer (OPS-158).
      dateFrom: de ? iso(de) : undefined,
      dateTo: ate ? iso(ate) : undefined,
      orderingKeys: (ordem.chaves ?? ['date']) as ReceivableOrderingKey[],
      orderingStyles: ordem.estilos,
    }),
    [paginacao.page, paginacao.perPage, busca.consulta, filtroCarteira, filtroPortador, de, ate,
     ordem.chaves, ordem.estilos],
  )

  const consulta = useQuery({
    queryKey: ['receivables', filtros],
    queryFn: () => receivablesApi.list(filtros),
  })

  // O rodapé. Consulta separada de propósito: ela não muda com a página, então
  // trocar de página não a refaz.
  const semPagina = useMemo(() => {
    const { page, perPage, ...resto } = filtros
    return resto
  }, [filtros])

  const totais = useQuery({
    queryKey: ['receivables-summary', semPagina],
    queryFn: () => receivablesApi.summary(semPagina),
    enabled: !consulta.isError,
  })

  const carteiras = useQuery({
    queryKey: ['wallets', 'todas'],
    queryFn: () => walletsApi.list({ perPage: 100 }),
  })

  // **Os portadores do PROJETO** — um critério só, o mesmo do servidor.
  const portadores = useQuery({
    queryKey: ['carrier-connections', 'todos'],
    queryFn: () => carrierConnectionsApi.list({ perPage: 100 }),
  })

  const excluir = useMutation({
    mutationFn: (entry: ReceivableEntry) => receivablesApi.remove(entry.id),
    onSuccess: (_dado, entry) => {
      notify.success(`Borderô ${rotulo(entry)} excluído.`)
      setConfirmando(null)
      queryClient.invalidateQueries({ queryKey: ['receivables'] })
      queryClient.invalidateQueries({ queryKey: ['receivables-summary'] })
    },
    onError: (erro) => {
      // A mensagem do servidor nomeia o motivo. Reescrevê-la aqui seria a
      // segunda implementação da mesma regra.
      notify.error(mensagemDoServidor(erro, 'Não foi possível excluir o borderô.'))
      setConfirmando(null)
    },
  })

  const colunas: Column<ReceivableEntry>[] = [
    {
      key: 'date',
      header: 'Data',
      sortable: true,
      accessor: (r) => r.date,
      cell: (r) => <span className="font-numeric tabular-nums">{dataBr(r.date)}</span>,
    },
    {
      key: 'carrier',
      header: 'Portador',
      sortable: true,
      accessor: (r) => r.carrier_title ?? '',
      cell: (r) => (
        <span className="block">
          <span className="block truncate">{r.carrier_title ?? '—'}</span>
          {/* O tooltip do legado abria vazio quando não havia descrição. */}
          {r.description && (
            <Tooltip content={r.description}>
              <span className="block truncate text-xs text-muted-foreground">{r.description}</span>
            </Tooltip>
          )}
        </span>
      ),
    },
    {
      key: 'wallet',
      header: 'Carteira',
      sortable: true,
      accessor: (r) => r.wallet_title ?? '',
      cell: (r) => <span className="block truncate">{r.wallet_title ?? '—'}</span>,
    },
    {
      key: 'titulos',
      header: 'Títulos',
      sortable: true,
      variant: 'number',
      accessor: (r) => r.qtd_titulos,
      cell: (r) => <span className="font-numeric tabular-nums">{r.qtd_titulos}</span>,
    },
    {
      key: 'bruto',
      header: 'Bruto',
      sortable: true,
      variant: 'number',
      accessor: (r) => Number(r.valor_bruto),
      cell: (r) => <span className="font-numeric tabular-nums">{formatMoney(numero(r.valor_bruto))}</span>,
    },
    {
      key: 'tarifas',
      header: 'Tarifas',
      sortable: true,
      variant: 'number',
      accessor: (r) => Number(r.derived.valor_total_tarifas ?? 0),
      // **DEC-120** — o aviso fica NA CÉLULA DE TARIFAS, e não numa coluna
      // nova, por dois motivos: é ali que o número é parcial, e a tabela já
      // corta a coluna "Situação" em 1440 px (uma coluna a mais pioraria o que
      // já está apertado).
      cell: (r) => (
        <span className="inline-flex items-center justify-end gap-1.5">
          <span className="font-numeric tabular-nums">{formatMoney(numero(r.derived.valor_total_tarifas))}</span>
          {r.has_unknown_tax && (
            <Tooltip content="Este borderô tem tarifa de valor DESCONHECIDO: o legado gravou um valor inválido e a carga não afirmou que era zero. O total mostrado é o do que se sabe.">
              <AlertTriangle
                aria-label="Tem tarifa de valor desconhecido — total parcial"
                className="h-3.5 w-3.5 shrink-0 text-warning"
              />
            </Tooltip>
          )}
        </span>
      ),
    },
    {
      key: 'liquido',
      header: 'Líquido',
      sortable: true,
      variant: 'number',
      accessor: (r) => Number(r.derived.valor_liquido ?? 0),
      cell: (r) => (
        <span className="font-numeric tabular-nums">{formatMoney(numero(r.derived.valor_liquido))}</span>
      ),
    },
    {
      key: 'pmr',
      header: 'PMR',
      sortable: true,
      variant: 'number',
      accessor: (r) => Number(r.prz_med_pond_bco),
      cell: (r) => (
        <span className="font-numeric tabular-nums">{formatAmount(numero(r.prz_med_pond_bco), 2)}</span>
      ),
    },
    {
      key: 'cet',
      header: 'CET',
      sortable: true,
      variant: 'number',
      accessor: (r) => Number(r.derived.custo_efetivo_pz_med_emp ?? 0),
      // **Formatado em pt-BR** (FE-162). No legado o CET saía cru.
      cell: (r) => (
        <span className="font-numeric tabular-nums">
          {formatPercent(numero(r.derived.custo_efetivo_pz_med_emp), 4)}
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Situação',
      accessor: (r) => r.derived.status ?? '',
      cell: (r) =>
        r.derived.status === 'difference' ? (
          <Tooltip content="O líquido ficou abaixo do líquido esperado pela taxa acordada.">
            <Badge variant="secondary">{r.derived.status_label ?? 'Diferença'}</Badge>
          </Tooltip>
        ) : (
          <span className="text-muted-foreground">{r.derived.status_label ?? 'OK'}</span>
        ),
    },
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      align: 'right',
      width: '8rem',
      cell: (r) =>
        podeEscrever ? (
          <div className="flex items-center justify-end gap-1">
            <Button
              variant="ghost"
              size="icon"
              aria-label={`Editar borderô ${rotulo(r)}`}
              onClick={(e) => {
                e.stopPropagation()
                navigate(`/receivables/${r.id}`)
              }}
            >
              <Pencil aria-hidden="true" className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              aria-label={`Excluir borderô ${rotulo(r)}`}
              onClick={(e) => {
                e.stopPropagation()
                setConfirmando(r)
              }}
            >
              <Trash2 aria-hidden="true" className="h-4 w-4" />
            </Button>
          </div>
        ) : null,
    },
  ]

  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0
  const escopo = projectScopeCode(consulta.error)

  const cabecalho = (
    <PageHeader
      title="Recebíveis"
      subtitle="O borderô: onde o dinheiro entra no sistema. Cada linha traz o líquido e o custo efetivo já calculados pelo servidor."
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
          placeholder="Buscar por portador, nº do borderô ou descrição…"
          aria-label="Buscar borderô por portador, número ou descrição"
        />
      }
      rightSlot={
        podeEscrever ? (
          <Button onClick={() => navigate('/receivables/novo')}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            Novo borderô
          </Button>
        ) : undefined
      }
    />
  )

  // Os dois 409 de escopo são ESTADO, não erro: sem projeto escolhido não há
  // lista a mostrar, e isso não é falha do sistema nem do usuário.
  if (escopo) {
    return (
      <div className="pb-10">
        {cabecalho}
        <ProjectScopeState code={escopo} recurso="os recebíveis" />
      </div>
    )
  }

  return (
    <div className="pb-10">
      {cabecalho}

      <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Select
          aria-label="Filtrar por carteira"
          placeholder="Todas as carteiras"
          value={filtroCarteira}
          onChange={(v) => {
            setFiltroCarteira(v || null)
            paginacao.reset()
          }}
          options={[
            { value: '', label: 'Todas as carteiras' },
            ...(carteiras.data?.items ?? []).map((w) => ({ value: w.id, label: w.title })),
          ]}
        />
        <Select
          aria-label="Filtrar por portador"
          placeholder="Todos os portadores"
          value={filtroPortador}
          onChange={(v) => {
            setFiltroPortador(v || null)
            paginacao.reset()
          }}
          options={[
            { value: '', label: 'Todos os portadores' },
            ...(portadores.data?.items ?? []).map((c) => ({
              value: c.carrier_id,
              label: c.carrier_title ?? c.carrier_id,
            })),
          ]}
        />
        <DatePicker
          aria-label="Data inicial"
          placeholder="De…"
          value={de}
          clearable
          onChange={(d) => {
            setDe(d)
            paginacao.reset()
          }}
        />
        <DatePicker
          aria-label="Data final"
          placeholder="Até…"
          value={ate}
          clearable
          onChange={(d) => {
            setAte(d)
            paginacao.reset()
          }}
        />
      </div>

      {estreito ? (
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={consulta.data?.items}
          onRetry={() => consulta.refetch()}
          loadingLabel="Carregando borderôs…"
          emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum borderô lançado'}
          emptyDescription={
            buscando
              ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
              : 'O borderô é onde o dinheiro entra no sistema. Lance o primeiro para começar.'
          }
        >
          {(itens) => (
            <div>
              {itens.map((r) => (
                <MobileCard
                  key={r.id}
                  title={r.carrier_title ?? '—'}
                  subtitle={`${dataBr(r.date)} · ${r.wallet_title ?? '—'}`}
                  status={r.derived.status === 'difference' ? (r.derived.status_label ?? 'Diferença') : undefined}
                  statusTone={r.derived.status === 'difference' ? 'neutral' : undefined}
                  onClick={() => navigate(`/receivables/${r.id}`)}
                  headerAction={
                    podeEscrever ? (
                      <span onClick={(e) => e.stopPropagation()}>
                        <MobileRowActions
                          open={acoesDe === r.id}
                          onOpenChange={(aberto) => setAcoesDe(aberto ? r.id : null)}
                          title={r.carrier_title ?? 'Borderô'}
                          subtitle={`Borderô ${rotulo(r)}`}
                          actions={[
                            {
                              key: 'editar',
                              label: 'Editar',
                              icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
                              onSelect: () => navigate(`/receivables/${r.id}`),
                            },
                            {
                              key: 'excluir',
                              label: 'Excluir',
                              icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                              destructive: true,
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
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Bruto</dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatMoney(numero(r.valor_bruto))}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Líquido</dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatMoney(numero(r.derived.valor_liquido))}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Tarifas</dt>
                      <dd className="flex items-center gap-1.5 font-numeric tabular-nums text-foreground">
                        {formatMoney(numero(r.derived.valor_total_tarifas))}
                        {/* DEC-120 — no telefone não há tooltip por hover: o
                            aviso vira texto curto, senão o ícone sozinho não
                            comunica nada. */}
                        {r.has_unknown_tax && (
                          <span className="inline-flex items-center gap-1 text-xs font-normal text-warning">
                            <AlertTriangle aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />
                            parcial
                          </span>
                        )}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">CET</dt>
                      <dd className="font-numeric tabular-nums text-foreground">
                        {formatPercent(numero(r.derived.custo_efetivo_pz_med_emp), 4)}
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
          <DataTable<ReceivableEntry>
            columns={colunas}
            data={consulta.data?.items ?? []}
            rowKey={(r) => r.id}
            sortMode="server"
            loading={consulta.isLoading}
            error={consulta.isError ? consulta.error : undefined}
            onRetry={() => consulta.refetch()}
            loadingLabel="Carregando borderôs…"
            emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum borderô lançado'}
            emptyDescription={
              buscando
                ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
                : 'O borderô é onde o dinheiro entra no sistema. Lance o primeiro para começar.'
            }
            sort={ordem.primeira}
            onSortChange={(s, chave) => {
              ordem.trocar(s, chave)
              paginacao.reset()
            }}
            onRowClick={(r) => navigate(`/receivables/${r.id}`)}
          />
        </div>
      )}

      {/* O rodapé soma a CONSULTA inteira, não a página. */}
      {totais.data && (
        <div className="mt-3 flex flex-wrap items-center gap-x-6 gap-y-1 rounded-lg border border-border bg-muted/40 px-4 py-3 text-sm">
          <span className="text-muted-foreground">
            {totais.data.count === 1 ? '1 borderô' : `${totais.data.count} borderôs`} nesta consulta
          </span>
          <span>
            <span className="text-muted-foreground">Bruto </span>
            <span className="font-numeric tabular-nums">{formatMoney(numero(totais.data.valor_bruto))}</span>
          </span>
          <span>
            <span className="text-muted-foreground">Tarifas </span>
            <span className="font-numeric tabular-nums">
              {formatMoney(numero(totais.data.valor_total_tarifas))}
            </span>
          </span>
          <span>
            <span className="text-muted-foreground">Líquido </span>
            <span className="font-numeric tabular-nums">{formatMoney(numero(totais.data.valor_liquido))}</span>
          </span>
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

      <ConfirmDialog
        open={confirmando !== null}
        onOpenChange={(aberto) => !aberto && setConfirmando(null)}
        title="Excluir este borderô?"
        description={
          confirmando
            ? `O borderô ${rotulo(confirmando)} de ${confirmando.carrier_title ?? 'portador não informado'}, ` +
              `no valor líquido de ${formatMoney(numero(confirmando.derived.valor_liquido))}, será removido ` +
              'junto com as tarifas dele. Esta ação não pode ser desfeita.'
            : ''
        }
        confirmLabel="Excluir borderô"
        tone="destructive"
        loading={excluir.isPending}
        onConfirm={() => {
          if (confirmando) excluir.mutate(confirmando)
        }}
      />
    </div>
  )
}

/** `decimal` do Postgres chega como string. `null` continua `null` (D-117). */
function numero(v: string | number | null | undefined): number | null {
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

/** O número do borderô é **texto** e pode vir vazio — 669 linhas de produção têm. */
function rotulo(r: ReceivableEntry): string {
  return r.nro_bordero?.trim() ? `nº ${r.nro_bordero}` : `de ${dataBr(r.date)}`
}
