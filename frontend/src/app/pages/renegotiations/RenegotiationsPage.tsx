import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, RefreshCcw, SlidersHorizontal, Trash2, Pencil, X, MoreVertical } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { SearchInput } from '@/components/ui/SearchInput'
import { Select } from '@/components/ui/Select'
import { DataTable, type SortState } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { Badge } from '@/components/ui/Badge'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileActionsSheet, MobileRowActions } from '@/components/mobile/MobileRowActions'
import {
  MobileEmptyState,
  MobileErrorState,
  MobileListSkeleton,
} from '@/components/mobile/MobileListState'
import { useMobile } from '@/hooks/useMobile'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { useSortStack } from '@/hooks/useSortStack'
import { useIsReadonly } from '@/hooks/usePermission'
import { formatDate } from '@/lib/utils/date'
import { formatarReais } from '@/lib/api/projects'
import { localizePercentLabel } from '@/lib/utils/number'
import {
  renegotiationsApi,
  type Renegotiation,
  type RenegotiationState,
  type RenegotiationStateFilter,
} from '@/lib/api/renegotiations'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'

/**
 * **Renegociações** — a lista (FE-190..FE-198).
 *
 * ## Os cinco defeitos do legado que morrem nesta tela
 *
 * - **D-29 / C1** — passar `renegotiation_id` na URL lia a renegociação de
 *   QUALQUER projeto: o controller reatribuía a relação escopada
 *   (`pub/renegotiations_controller.rb:24`). O escopo agora é do servidor.
 * - **BE-190** — a busca só casava `provider_name`, apesar de a primeira coluna
 *   se chamar "Nome" (`title`). Agora casa os dois.
 * - **D-49** — o filtro "Sem parcela cadastrada" caía no `else` do `case`, que
 *   tinha um `return` no meio da action: a tela dava **500**. Junto com a
 *   correção do D-45, os quatro estados **funcionam**.
 * - **D-20** — `l`/`o` eram calculados e nunca aplicados, e o `where!` do ramo
 *   com busca descartava a relação. A paginação é real, com envelope em
 *   cabeçalho (DEC-62).
 * - **D-24** — o `destroy` respondia `errors.any? ? :ok : :ok` com template
 *   VAZIO: a tela dizia "removido com sucesso", a lista recarregava e o registro
 *   voltava. Agora o erro real do servidor aparece.
 *
 * ## Q-B28, registrada e visível
 *
 * O legado usa `provider_name` na rota e mostra `title` na lista. Aqui a coluna
 * "Nome" mostra o título **e** o fornecedor logo abaixo, quando são diferentes —
 * assim o usuário vê os dois nomes que o sistema usa, em vez de descobrir a
 * diferença clicando.
 */
export function RenegotiationsPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const mobile = useMobile()
  const readonly = useIsReadonly()

  const [filtrosAbertos, setFiltrosAbertos] = useState(false)
  const [estado, setEstado] = useState<RenegotiationStateFilter | null>(null)
  const [tipo, setTipo] = useState<string | null>(null)
  // FE-194 — a ordenacao EMPILHA. Ver `useSortStack`.
  const ordem = useSortStack()
  const [acoesDe, setAcoesDe] = useState<Renegotiation | null>(null)

  const busca = useDebouncedSearch({ delay: 300 })
  const paginacao = usePagination({ initialPerPage: 50 })

  // As listas de tipo e de estado vêm do SERVIDOR (DEC-102: nada de tela que
  // finge — sem lista escrita no fonte).
  const opcoes = useQuery({
    queryKey: ['renegotiation-options'],
    queryFn: () => renegotiationsApi.options(),
    staleTime: 30 * 60 * 1000,
  })

  const filtros = useMemo(
    () => ({
      q: busca.consulta || undefined,
      state: estado ?? undefined,
      kind: tipo ?? undefined,
      orderingKeys: ordem.chaves,
      orderingStyles: ordem.estilos,
      page: paginacao.page,
      perPage: paginacao.perPage,
    }),
    [busca.consulta, estado, tipo, ordem.chaves, ordem.estilos, paginacao.page, paginacao.perPage],
  )

  const lista = useQuery({
    queryKey: ['renegotiations', filtros],
    queryFn: () => renegotiationsApi.list(filtros),
    placeholderData: (anterior) => anterior,
  })

  // FE-198 — a renegociação aguardando confirmação de remoção.
  const [confirmandoRemocao, setConfirmandoRemocao] = useState<Renegotiation | null>(null)

  const remover = useMutation({
    mutationFn: (registro: Renegotiation) => renegotiationsApi.remove(registro.id),
    onSuccess: () => {
      notify.success('Renegociação removida.')
      queryClient.invalidateQueries({ queryKey: ['renegotiations'] })
      setAcoesDe(null)
      setConfirmandoRemocao(null)
    },
    // **O erro REAL do servidor aparece** — é a correção do D-24.
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover a renegociação.')),
  })

  const itens = lista.data?.items ?? []
  const meta = lista.data?.meta
  // "Escolha um projeto" e "você não participa de nenhum" são ESTADO DE TELA
  // (409), não falha. O 404 de projeto alheio continua sendo erro — e continua
  // indistinguível de id inexistente, que é a anti-enumeração do C1.
  const escopo = projectScopeCode(lista.error)
  const temFiltro = !!busca.consulta || !!estado || !!tipo

  function limparFiltros() {
    busca.limpar()
    setEstado(null)
    setTipo(null)
    paginacao.setPage(1)
  }

  const acoesDaLinha = (registro: Renegotiation) => [
    {
      key: 'abrir',
      label: 'Abrir renegociação',
      icon: <Pencil className="h-4 w-4" aria-hidden />,
      onSelect: () => navigate(`/renegotiations/${registro.id}`),
    },
    {
      key: 'remover',
      label: 'Remover',
      icon: <Trash2 className="h-4 w-4" aria-hidden />,
      destructive: true,
      // **FE-198 — pergunta antes.** Estava removendo no clique: um toque errado
      // no menu de ações apagava a renegociação sem volta. O critério de
      // habilitação (sem parcela, sem pagamento) protege o dado com histórico,
      // não protege contra o clique errado numa que ainda está vazia.
      onSelect: () => setConfirmandoRemocao(registro),
      // O critério do botão é o critério do SERVIDOR: sem parcela e sem
      // pagamento. Quando ele não vale, o motivo fica escrito.
      disabledReason: podeRemoverMotivo(registro, readonly),
    },
  ]

  /**
   * **FE-196 — a coluna de ações no DESKTOP.**
   *
   * A lista tinha o menu de ações só no cartão de telefone: no computador não
   * havia como remover uma renegociação, nem havia afordância nenhuma de que a
   * linha tivesse ações. O `MobileRowActions` já resolve os dois formatos — folha
   * no telefone, menu suspenso no desktop —, e é o critério do projeto para o
   * controle de "mais ações". Faltava a lista chamá-lo aqui.
   *
   * A coluna é montada DENTRO do componente porque as ações dependem dos
   * manipuladores (`navigate`, a confirmação de remoção); `colunas`, no topo do
   * arquivo, é estática de propósito e continua assim.
   */
  const colunasComAcoes = useMemo(
    () => [
      ...colunas,
      {
        key: 'acoes',
        header: <span className="sr-only">Ações</span>,
        align: 'right' as const,
        width: '4rem',
        // Fora do cartão do telefone: lá as ações já são a folha do cabeçalho.
        hideOnMobile: true,
        cell: (registro: Renegotiation) => (
          <span onClick={(e) => e.stopPropagation()}>
            <MobileRowActions
              open={acoesDe?.id === registro.id}
              onOpenChange={(aberto: boolean) => setAcoesDe(aberto ? registro : null)}
              title={registro.title}
              subtitle={registro.provider_name}
              actions={acoesDaLinha(registro)}
            />
          </span>
        ),
      },
    ],
    // `acoesDe` entra porque decide qual linha está com o menu aberto.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [acoesDe, readonly],
  )

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Renegociações"
        subtitle="Dívidas negociadas com fornecedores: parcelas, pagamentos e documentos."
        loading={lista.isFetching}
        searchSlot={
          <SearchInput
            value={busca.termo}
            loading={busca.pendente}
            onValueChange={(valor) => {
              busca.setTermo(valor)
              paginacao.setPage(1)
            }}
            onClear={limparFiltros}
            placeholder="Buscar pelo nome da renegociação ou do fornecedor…"
          />
        }
        rightSlot={
          <div className="flex items-center gap-2">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setFiltrosAbertos((aberto) => !aberto)}
              aria-expanded={filtrosAbertos}
            >
              <SlidersHorizontal className="mr-2 h-4 w-4" aria-hidden />
              Filtros
              {temFiltro && (
                <Badge variant="secondary" className="ml-2">
                  ativo
                </Badge>
              )}
            </Button>
            {!readonly && (
              <Button size="sm" onClick={() => navigate('/renegotiations/new')}>
                <Plus className="mr-2 h-4 w-4" aria-hidden />
                Nova renegociação
              </Button>
            )}
          </div>
        }
      />

      {filtrosAbertos && (
        <div className="flex flex-wrap items-end gap-3 rounded-lg border border-border bg-card p-4">
          <div className="flex min-w-[13rem] flex-1 flex-col gap-1.5">
            <label htmlFor="filtro-estado" className="text-xs font-medium text-muted-foreground">
              Status
            </label>
            <Select
              id="filtro-estado"
              options={(opcoes.data?.states ?? []).map((e) => ({ value: e.value, label: e.label }))}
              value={estado}
              onChange={(valor) => {
                setEstado(valor as RenegotiationStateFilter)
                paginacao.setPage(1)
              }}
              placeholder="Todos os status"
              block
            />
          </div>
          <div className="flex min-w-[13rem] flex-1 flex-col gap-1.5">
            <label htmlFor="filtro-tipo" className="text-xs font-medium text-muted-foreground">
              Tipo
            </label>
            <Select
              id="filtro-tipo"
              options={(opcoes.data?.kinds ?? []).map((k) => ({ value: k, label: k }))}
              value={tipo}
              onChange={(valor) => {
                setTipo(valor)
                paginacao.setPage(1)
              }}
              placeholder="Todos os tipos"
              block
            />
          </div>
          {temFiltro && (
            <Button variant="ghost" size="sm" onClick={limparFiltros}>
              <X className="mr-2 h-4 w-4" aria-hidden />
              Limpar
            </Button>
          )}
        </div>
      )}

      {escopo ? (
        <ProjectScopeState code={escopo} recurso="as renegociações" />
      ) : mobile ? (
        <ListaEstreita
          itens={itens}
          carregando={lista.isLoading}
          erro={lista.error}
          onRetry={() => lista.refetch()}
          filtrada={temFiltro}
          onAbrir={(registro) => navigate(`/renegotiations/${registro.id}`)}
          onAcoes={setAcoesDe}
          onLimpar={limparFiltros}
        />
      ) : (
        // A tabela tem 13 colunas (FE-190) e não cabe em 1440 px. Ela rola
        // dentro do PRÓPRIO contêiner — a PÁGINA nunca rola na horizontal
        // (§5.4.8, regra 3). É o mesmo invólucro que o `CatalogScreen` usa.
        <div className="overflow-x-auto rounded-lg border border-border bg-card">
          <DataTable<Renegotiation>
            columns={colunasComAcoes}
            data={itens}
            rowKey={(registro) => registro.id}
            loading={lista.isLoading}
            error={lista.error}
            onRetry={() => lista.refetch()}
            sortMode="server"
            sort={ordem.primeira}
            onSortChange={(novo, chave) => {
              ordem.trocar(novo, chave)
              paginacao.setPage(1)
            }}
            onRowClick={(registro) => navigate(`/renegotiations/${registro.id}`)}
            emptyTitle={temFiltro ? `Nenhum resultado para «${busca.consulta || 'os filtros'}»` : 'Nenhuma renegociação cadastrada'}
            emptyDescription={
              temFiltro
                ? 'Ajuste a busca ou limpe os filtros para ver todas as renegociações do projeto.'
                : 'A renegociação é a dívida negociada com um fornecedor: você cadastra o acordo, lança as previsões de parcela e registra os pagamentos.'
            }
            emptyAction={
              temFiltro ? (
                <Button variant="secondary" size="sm" onClick={limparFiltros}>
                  Limpar filtros
                </Button>
              ) : (
                !readonly && (
                  <Button size="sm" onClick={() => navigate('/renegotiations/new')}>
                    <Plus className="mr-2 h-4 w-4" aria-hidden />
                    Nova renegociação
                  </Button>
                )
              )
            }
            caption="Renegociações do projeto"
          />
        </div>
      )}

      {meta && meta.total > 0 && (
        <div className="flex justify-end">
          {mobile ? (
            <MobilePagination
              page={meta.page}
              perPage={meta.perPage}
              total={meta.total}
              onPageChange={paginacao.setPage}
            />
          ) : (
            <PaginationPill
              page={meta.page}
              totalPages={meta.totalPages}
              perPage={meta.perPage}
              onPageChange={paginacao.setPage}
              onPerPageChange={paginacao.setPerPage}
              loading={lista.isFetching}
            />
          )}
        </div>
      )}

      {/* **Só no telefone.** Depois do FE-196 a linha do desktop tem o próprio
          menu suspenso, e os dois compartilham o `acoesDe`: sem esta guarda, um
          clique no computador abria a folha E o menu ao mesmo tempo, com o
          "Remover" duplicado na tela. */}
      {mobile && (
        <MobileActionsSheet
          open={!!acoesDe}
          onOpenChange={(aberto) => !aberto && setAcoesDe(null)}
          title={acoesDe?.title ?? ''}
          subtitle={acoesDe?.provider_name}
          actions={acoesDe ? acoesDaLinha(acoesDe) : []}
        />
      )}

      {/* FE-198 — a confirmação que faltava. O texto NOMEIA a renegociação: uma
          caixa que só diz "tem certeza?" não ajuda quem clicou na linha errada,
          que é exatamente o caso contra o qual ela existe. */}
      <ConfirmDialog
        open={confirmandoRemocao !== null}
        onOpenChange={(aberto) => !aberto && setConfirmandoRemocao(null)}
        title="Remover esta renegociação?"
        description={
          confirmandoRemocao
            ? `A renegociação «${confirmandoRemocao.title}», de ${confirmandoRemocao.provider_name}, será removida. ` +
              'Só é possível remover acordo sem parcela e sem pagamento — se houver, o servidor recusa e diz quantos são.'
            : ''
        }
        confirmLabel="Remover renegociação"
        tone="destructive"
        loading={remover.isPending}
        onConfirm={() => confirmandoRemocao && remover.mutate(confirmandoRemocao)}
      />
    </div>
  )
}

// --- Peças -----------------------------------------------------------------

/** Motivo pelo qual a remoção está indisponível, ou `undefined` se está. */
function podeRemoverMotivo(registro: Renegotiation, readonly: boolean): string | undefined {
  if (readonly) return 'Modo Somente Leitura: seu perfil não permite alterações.'
  if (registro.installments_count > 0) {
    return `Esta renegociação tem ${registro.installments_count} parcela(s). Remova as parcelas antes.`
  }
  return undefined
}

const TOM_DO_ESTADO: Record<RenegotiationState, 'success' | 'warning' | 'destructive' | 'info' | 'neutral'> = {
  Liquidado: 'success',
  Pago: 'info',
  Inconsistente: 'warning',
  'Sem parcela cadastrada': 'neutral',
}

/**
 * O rótulo composto do estado, **escrito em pt-BR**.
 *
 * `beauty_state` chega do servidor como `"66.87% Pago"` — `paid_percent.to_s`
 * concatenado (`Renegotiation#beauty_state`, réplica de `../sfg/app/models/
 * renegotiation.rb:129`). Ponto decimal de JavaScript/Ruby no meio de uma tela em
 * português; visto renderizando em `/renegotiations`, `66.87% Pago` e
 * `38.97% Pago` na mesma lista. É a **terceira** vez que este descuido aparece no
 * projeto (a S8 achou `2.55%`, a S15 achou `51.76%` ao lado de `109,0%`).
 *
 * A troca é só do separador, pelo motivo que `localizePercentLabel` documenta: os
 * dígitos — inclusive o arredondamento — são do domínio e a DEC-01 manda
 * preservá-los. Aqui não há aritmética, é ortografia.
 */
function estadoLegivel(registro: Renegotiation): string {
  return localizePercentLabel(registro.beauty_state, registro.state)
}

function EstadoBadge({ registro }: { registro: Renegotiation }) {
  const tom = TOM_DO_ESTADO[registro.state] ?? 'neutral'
  const variante =
    tom === 'success' ? 'success' : tom === 'warning' ? 'warning' : tom === 'info' ? 'info' : 'secondary'
  return <Badge variant={variante as any}>{estadoLegivel(registro)}</Badge>
}

const dinheiro = (valor: string | number | null | undefined) => (
  <span className="font-numeric tabular-nums">{formatarReais(valor)}</span>
)

/** As 13 colunas de resumo (FE-190). "Data próxima" vazia mostra `—`. */
const colunas = [
  {
    key: 'title',
    header: 'Nome',
    sortable: true,
    accessor: (r: Renegotiation) => r.title,
    cell: (r: Renegotiation) => (
      <span className="block">
        <span className="block truncate font-medium">{r.title}</span>
        {/* Q-B28: o legado usa o fornecedor na rota e o título na lista. Os dois
            aparecem, para que a diferença não seja descoberta clicando. */}
        {r.provider_name !== r.title && (
          <span className="block truncate text-xs text-muted-foreground">{r.provider_name}</span>
        )}
      </span>
    ),
  },
  {
    key: 'provider',
    header: 'Fornecedor',
    sortable: true,
    accessor: (r: Renegotiation) => r.provider_name,
    cell: (r: Renegotiation) => <span className="block truncate">{r.provider_name}</span>,
  },
  { key: 'kind', header: 'Tipo', sortable: true, accessor: (r: Renegotiation) => r.kind },
  {
    key: 'state',
    header: 'Status',
    sortable: true,
    accessor: (r: Renegotiation) => r.state,
    cell: (r: Renegotiation) => <EstadoBadge registro={r} />,
  },
  {
    key: 'total_debt',
    header: 'Dívida total',
    sortable: true,
    variant: 'money' as const,
    accessor: (r: Renegotiation) => Number(r.total_debt),
    cell: (r: Renegotiation) => dinheiro(r.total_debt),
  },
  {
    key: 'main_value',
    header: 'Lançado',
    variant: 'money' as const,
    accessor: (r: Renegotiation) => Number(r.main_value),
    cell: (r: Renegotiation) => dinheiro(r.main_value),
  },
  {
    key: 'paid_value',
    header: 'R$ Pago',
    variant: 'money' as const,
    accessor: (r: Renegotiation) => Number(r.paid_value),
    cell: (r: Renegotiation) => dinheiro(r.paid_value),
  },
  {
    key: 'remaining_value',
    header: 'R$ A Pagar',
    sortable: true,
    variant: 'money' as const,
    accessor: (r: Renegotiation) => Number(r.remaining_value),
    cell: (r: Renegotiation) => dinheiro(r.remaining_value),
  },
  {
    key: 'installments_count',
    header: 'Parcelas',
    variant: 'number' as const,
    accessor: (r: Renegotiation) => r.installments_count,
    cell: (r: Renegotiation) => (
      <span className="font-numeric tabular-nums">
        {r.paid_installments}/{r.installments_count}
      </span>
    ),
  },
  {
    key: 'overdue_installments',
    header: 'Vencidas',
    variant: 'number' as const,
    accessor: (r: Renegotiation) => r.overdue_installments,
    cell: (r: Renegotiation) => (
      <span
        className={`font-numeric tabular-nums ${r.overdue_installments > 0 ? 'font-semibold text-destructive-text' : ''}`}
      >
        {r.overdue_installments}
      </span>
    ),
  },
  {
    key: 'current_installment_value',
    header: 'Valor parcela',
    variant: 'money' as const,
    accessor: (r: Renegotiation) => Number(r.current_installment_value),
    cell: (r: Renegotiation) => dinheiro(r.current_installment_value),
  },
  {
    key: 'current_value',
    header: 'VP',
    variant: 'money' as const,
    accessor: (r: Renegotiation) => Number(r.current_value),
    cell: (r: Renegotiation) => dinheiro(r.current_value),
  },
  {
    key: 'next_due_date',
    header: 'Data próxima',
    variant: 'date' as const,
    accessor: (r: Renegotiation) => r.next_due_date,
    // Vazia mostra `—` (FE-190). `formatDate` já devolve o traço para nulo.
    cell: (r: Renegotiation) => <span className="font-numeric tabular-nums">{formatDate(r.next_due_date)}</span>,
  },
]

interface ListaEstreitaProps {
  itens: Renegotiation[]
  carregando: boolean
  erro: unknown
  onRetry: () => void
  filtrada: boolean
  onAbrir: (registro: Renegotiation) => void
  onAcoes: (registro: Renegotiation) => void
  onLimpar: () => void
}

/**
 * A versão de telefone (DEC-100, §5.4.8): **view própria**, não tabela com
 * rolagem horizontal. Coluna fora da tela é coluna que o usuário nunca descobre —
 * e aqui a coluna escondida seria o valor ou o vencimento.
 */
function ListaEstreita({
  itens,
  carregando,
  erro,
  onRetry,
  filtrada,
  onAbrir,
  onAcoes,
  onLimpar,
}: ListaEstreitaProps) {
  if (carregando) return <MobileListSkeleton rows={5} />
  if (erro) {
    return (
      <MobileErrorState
        title="Não foi possível carregar as renegociações"
        detail={mensagemDoServidor(erro, 'Erro desconhecido.')}
        onRetry={onRetry}
      />
    )
  }
  if (itens.length === 0) {
    return (
      <MobileEmptyState
        title={filtrada ? 'Nenhum resultado' : 'Nenhuma renegociação cadastrada'}
        description={
          filtrada
            ? 'Ajuste a busca ou limpe os filtros.'
            : 'Cadastre o acordo com o fornecedor para começar a lançar as previsões de parcela.'
        }
        icon={<RefreshCcw className="h-6 w-6" aria-hidden />}
        filtered={filtrada}
        action={filtrada ? { label: 'Limpar filtros', onClick: onLimpar } : undefined}
      />
    )
  }

  return (
    <div className="flex flex-col gap-3">
      {itens.map((registro) => (
        <MobileCard
          key={registro.id}
          title={registro.title}
          subtitle={registro.provider_name}
          status={estadoLegivel(registro)}
          statusTone={TOM_DO_ESTADO[registro.state] ?? 'neutral'}
          onClick={() => onAbrir(registro)}
          headerAction={
            <span onClick={(evento) => evento.stopPropagation()}>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Ações de ${registro.title}`}
                onClick={() => onAcoes(registro)}
              >
                <MoreVertical className="h-4 w-4" aria-hidden />
              </Button>
            </span>
          }
        >
          <dl className="grid grid-cols-2 gap-2 text-sm">
            {[
              { label: 'A pagar', value: formatarReais(registro.remaining_value) },
              { label: 'Pago', value: formatarReais(registro.paid_value) },
              { label: 'Parcelas', value: `${registro.paid_installments}/${registro.installments_count}` },
              { label: 'Próxima', value: formatDate(registro.next_due_date) },
            ].map((campo) => (
              <div key={campo.label}>
                <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{campo.label}</dt>
                <dd className="font-numeric tabular-nums text-foreground">{campo.value}</dd>
              </div>
            ))}
          </dl>
        </MobileCard>
      ))}
    </div>
  )
}
