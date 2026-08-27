import { useCallback, useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { Pencil, Plus, Power, Trash2 } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { SearchInput } from '@/components/ui/SearchInput'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { RichTextView } from '@/components/ui/RichTextField'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { useMobile } from '@/hooks/useMobile'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import {
  indicatorsApi,
  mensagemDoServidor,
  type Indicator,
  type IndicatorInput,
} from '@/lib/api/indicators'
import { IndicatorDrawer } from '../components/IndicatorDrawer'
import { DeleteIndicatorDialog } from '../components/DeleteIndicatorDialog'

/**
 * **Cadastro › Indicadores** — o catálogo GLOBAL (`FE-310..FE-318`, `FE-322`).
 *
 * ## O que o usuário vai notar em relação ao legado
 *
 * - **A lista pagina de verdade.** O front do legado manda `l=50, o=0` fixos e
 *   **nunca incrementa o offset**: a partir do 51º indicador a lista
 *   simplesmente **trunca, sem aviso nenhum** — não há total, não há controle de
 *   página, e nada na tela sugere que falta coisa.
 * - **Ordenar por "Chave" funciona.** No legado `get_ordering_key("key")`
 *   devolvia `"integration_key"`, coluna que não existe em `indicators`:
 *   `PG::UndefinedColumn`, 500. Só "Título" era clicável, o que escondia o
 *   defeito (achado A-5 do DEC-85).
 * - **Ativo/inativo aparece aqui.** `is_active` sempre valeu para todos os
 *   indicadores, e o estado só era mostrado na tela de específicos (`FE-322`).
 * - **A falha aparece.** O callback de erro do proxy do legado é literalmente
 *   vazio: a lista ficava em branco, indistinguível de "não há nada".
 * - **A confirmação de exclusão diz o que será afetado** — ver
 *   `DeleteIndicatorDialog`, que é o D-66 na copy.
 *
 * ## Deep-link (`FE-317`)
 *
 * `/indicators/new` e `/indicators/:id/edit` são **rotas de verdade**, com
 * histórico. No legado o mesmo efeito existia por `history.replaceState`, e por
 * isso o botão Voltar do navegador saía do console inteiro (D-92).
 */
export function IndicatorsPage() {
  const navigate = useNavigate()
  const { id: idDaRota } = useParams<{ id: string }>()
  const location = useLocation()
  const [params, setParams] = useSearchParams()
  const queryClient = useQueryClient()
  const estreito = useMobile()

  const papel = useRoleSlug()
  const somenteLeitura = useIsReadonly()
  // Grupo "Cadastro" do legado: `current_user.admin? || og? || manager?`.
  const papelDeEscrita = papel !== null && ['og', 'admin', 'gerente'].includes(papel)
  const podeEscrever = papelDeEscrita && !somenteLeitura

  // A ordenação vive na URL (`FE-312`): compartilhar a tela ordenada por chave
  // tem de reabrir ordenada por chave.
  const sort: SortState = useMemo(() => {
    const key = params.get('ordering') ?? 'title'
    const direction = params.get('dir') === 'desc' ? 'desc' : 'asc'
    return { key, direction }
  }, [params])

  const busca = useDebouncedSearch({ initial: params.get('q') ?? '' })
  const paginacao = usePagination()

  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<Indicator | null>(null)
  const [excluindo, setExcluindo] = useState<Indicator | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      orderingKey: sort.key,
      orderingStyle: (sort.direction === 'desc' ? 'down' : 'up') as 'up' | 'down',
    }),
    [paginacao.page, paginacao.perPage, busca.consulta, sort],
  )

  const consulta = useQuery({
    queryKey: ['indicators', filtros],
    queryFn: () => indicatorsApi.list(filtros),
  })

  const invalidar = useCallback(
    () => queryClient.invalidateQueries({ queryKey: ['indicators'] }),
    [queryClient],
  )

  // --- Deep-link -----------------------------------------------------------
  const abrirCriacao = useCallback(() => {
    setEditando(null)
    setDrawerAberto(true)
    navigate('/indicators/new')
  }, [navigate])

  const abrirEdicao = useCallback(
    (indicador: Indicator) => {
      setEditando(indicador)
      setDrawerAberto(true)
      navigate(`/indicators/${indicador.id}/edit`)
    },
    [navigate],
  )

  const fecharDrawer = useCallback(() => {
    setDrawerAberto(false)
    setEditando(null)
    navigate('/indicators')
  }, [navigate])

  // Entrar por URL (link colado, recarregar a página) abre o painel. É o que
  // torna o deep-link uma rota de verdade, e não só um efeito colateral.
  useEffect(() => {
    if (!idDaRota) return
    const alvo = consulta.data?.items.find((i) => i.id === idDaRota)
    if (alvo) {
      setEditando(alvo)
      setDrawerAberto(true)
      return
    }
    // O indicador pode estar em outra página da lista.
    indicatorsApi
      .get(idDaRota)
      .then((i) => {
        setEditando(i)
        setDrawerAberto(true)
      })
      .catch(() => {
        notify.error('Indicador não encontrado.')
        navigate('/indicators')
      })
    // Só reage à troca de id na URL.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idDaRota])

  // `useLocation`, e não `window.location` com dependência vazia: o botão Voltar
  // do navegador muda a rota **sem** remontar a tela, e com `[]` o painel não
  // reabriria ao voltar para `/indicators/new`. É justamente o que o `FE-317`
  // existe para consertar (no legado o deep-link era `history.replaceState`, e o
  // Voltar saía do console inteiro — D-92).
  useEffect(() => {
    if (location.pathname.endsWith('/indicators/new')) {
      setEditando(null)
      setDrawerAberto(true)
    } else if (location.pathname === '/indicators') {
      setDrawerAberto(false)
      setEditando(null)
    }
  }, [location.pathname])

  // --- Mutações ------------------------------------------------------------
  const salvar = useMutation({
    mutationFn: (dados: IndicatorInput) =>
      editando ? indicatorsApi.update(editando.id, dados) : indicatorsApi.create(dados),
    onSuccess: (indicador) => {
      notify.success(editando ? `Indicador «${indicador.title}» atualizado.` : `Indicador «${indicador.title}» criado.`)
      fecharDrawer()
      invalidar()
      // A grade de lançamentos mostra título e instrução do indicador; se
      // estiver montada em outra aba do cache, ela recarrega.
      queryClient.invalidateQueries({ queryKey: ['indicator-grid'] })
      queryClient.invalidateQueries({ queryKey: ['indicator-connections'] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o indicador.')),
  })

  const alternarAtivo = useMutation({
    mutationFn: (indicador: Indicator) => indicatorsApi.setActive(indicador.id, !indicador.is_active),
    onSuccess: (indicador) => {
      notify.success(`Indicador «${indicador.title}» ${indicador.is_active ? 'ativado' : 'desativado'}.`)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível alterar o estado do indicador.')),
  })

  const remover = useMutation({
    mutationFn: (indicador: Indicator) => indicatorsApi.remove(indicador.id),
    onSuccess: (resultado, indicador) => {
      const preservados = resultado?.entries_preserved ?? 0
      notify.success(
        preservados > 0
          ? `Indicador «${indicador.title}» excluído. ${preservados} ${preservados === 1 ? 'lançamento foi preservado' : 'lançamentos foram preservados'}.`
          : `Indicador «${indicador.title}» excluído.`,
      )
      setExcluindo(null)
      invalidar()
    },
    onError: (erro) => {
      notify.error(mensagemDoServidor(erro, 'Não foi possível excluir o indicador.'))
      setExcluindo(null)
    },
  })

  // --- Tabela --------------------------------------------------------------
  const colunas: Column<Indicator>[] = [
    {
      key: 'title',
      header: 'Título',
      sortable: true,
      accessor: (i) => i.title,
      // `FE-313` — o acordeão é do Radix e serve **como está**: teclado, ARIA e
      // `data-state` de graça. O chevron só aparece quando há instrução, como no
      // legado (`_widget.html.erb:4`).
      cell: (i) =>
        i.description_html ? (
          <AccordionItem value={i.id} className="border-0">
            <AccordionTrigger className="py-0 text-left font-medium hover:no-underline">
              <span className="truncate">{i.title}</span>
            </AccordionTrigger>
            <AccordionContent className="pb-0 pt-3">
              <RichTextView html={i.description_html} />
            </AccordionContent>
          </AccordionItem>
        ) : (
          <span className="font-medium text-foreground">{i.title}</span>
        ),
    },
    {
      key: 'key',
      header: 'Chave de integração',
      sortable: true,
      accessor: (i) => i.key,
      cell: (i) => <code className="font-numeric text-xs text-muted-foreground">{i.key}</code>,
    },
    {
      key: 'is_active',
      header: 'Estado',
      accessor: (i) => i.is_active,
      cell: (i) => (
        <Badge variant={i.is_active ? 'success' : 'secondary'}>{i.is_active ? 'Ativo' : 'Inativo'}</Badge>
      ),
    },
    {
      key: 'entries_count',
      header: 'Lançamentos',
      variant: 'number',
      accessor: (i) => i.entries_count,
    },
    {
      key: 'projects_count',
      header: 'Projetos',
      variant: 'number',
      accessor: (i) => i.projects_count,
    },
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      align: 'right',
      width: '9rem',
      cell: (i) => {
        if (!podeEscrever) return null
        return (
          <div className="flex items-center justify-end gap-1" onClick={(e) => e.stopPropagation()}>
            <Button variant="ghost" size="icon" aria-label={`Editar ${i.title}`} onClick={() => abrirEdicao(i)}>
              <Pencil aria-hidden="true" className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              aria-label={`${i.is_active ? 'Desativar' : 'Ativar'} ${i.title}`}
              loading={alternarAtivo.isPending && alternarAtivo.variables?.id === i.id}
              onClick={() => alternarAtivo.mutate(i)}
            >
              <Power aria-hidden="true" className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="icon" aria-label={`Excluir ${i.title}`} onClick={() => setExcluindo(i)}>
              <Trash2 aria-hidden="true" className="h-4 w-4" />
            </Button>
          </div>
        )
      },
    },
  ]

  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0

  function aplicarOrdenacao(novo: SortState | null) {
    const proximo = new URLSearchParams(params)
    if (novo) {
      proximo.set('ordering', novo.key)
      proximo.set('dir', novo.direction)
    } else {
      proximo.delete('ordering')
      proximo.delete('dir')
    }
    setParams(proximo, { replace: true })
    paginacao.reset()
  }

  function aplicarBusca(valor: string) {
    busca.setTermo(valor)
    const proximo = new URLSearchParams(params)
    if (valor.trim()) proximo.set('q', valor.trim())
    else proximo.delete('q')
    setParams(proximo, { replace: true })
    paginacao.reset()
  }

  return (
    <div className="pb-10">
      <PageHeader
        title="Indicadores"
        subtitle="Catálogo compartilhado por todos os projetos. É daqui que sai a grade mensal de lançamentos."
        loading={consulta.isFetching && !consulta.isLoading}
        searchSlot={
          <SearchInput
            value={busca.termo}
            onValueChange={aplicarBusca}
            onClear={() => aplicarBusca('')}
            loading={busca.pendente}
            placeholder="Buscar indicador por título ou chave…"
            aria-label="Buscar indicador por título ou chave"
          />
        }
        rightSlot={
          podeEscrever ? (
            <Button onClick={abrirCriacao}>
              <Plus aria-hidden="true" className="h-4 w-4" />
              Novo indicador
            </Button>
          ) : undefined
        }
      />

      {/* `FE-323` generalizado: quando o controle some por perfil, a tela DIZ
          por quê em vez de deixar um espaço vazio inexplicado. */}
      {papelDeEscrita && somenteLeitura && (
        <p className="mb-4 rounded-md border border-border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
          Seu perfil está em <strong>modo somente leitura</strong>: você consulta o catálogo, mas não
          cadastra nem altera indicadores.
        </p>
      )}

      {/* Acordeão EXCLUSIVO (`type="single"`): abrir uma instrução fecha a
          anterior, como no legado. O `Root` envolve a lista inteira porque é ele
          que guarda qual item está aberto. */}
      <Accordion type="single" collapsible>
        {estreito ? (
          <AsyncSection
            loading={consulta.isLoading}
            error={consulta.isError ? consulta.error : undefined}
            data={consulta.data?.items}
            onRetry={() => consulta.refetch()}
            loadingLabel="Carregando indicadores…"
            emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum indicador cadastrado'}
            emptyDescription={
              buscando
                ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
                : 'Os indicadores alimentam a grade mensal dos projetos. Cadastre o primeiro para começar.'
            }
          >
            {(itens) => (
              <div>
                {itens.map((i) => (
                  <MobileCard
                    key={i.id}
                    title={i.title}
                    status={i.is_active ? 'Ativo' : 'Inativo'}
                    statusTone={i.is_active ? 'success' : 'neutral'}
                    headerAction={
                      podeEscrever ? (
                        <span onClick={(e) => e.stopPropagation()}>
                          <MobileRowActions
                            open={acoesDe === i.id}
                            onOpenChange={(aberto) => setAcoesDe(aberto ? i.id : null)}
                            title={i.title}
                            subtitle="Indicador"
                            actions={[
                              {
                                key: 'editar',
                                label: 'Editar',
                                icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
                                onSelect: () => abrirEdicao(i),
                              },
                              {
                                key: 'ativar',
                                label: i.is_active ? 'Desativar' : 'Ativar',
                                icon: <Power aria-hidden="true" className="h-4 w-4" />,
                                onSelect: () => alternarAtivo.mutate(i),
                              },
                              {
                                key: 'excluir',
                                label: 'Excluir',
                                icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                                destructive: true,
                                onSelect: () => setExcluindo(i),
                              },
                            ]}
                          />
                        </span>
                      ) : undefined
                    }
                  >
                    {/* A chave ocupa a linha inteira: ela é monoespaçada e longa
                        (`inadimplencia_da_carteira`), e numa grade de duas colunas de
                        390 px ela invadia a coluna do lado. Achado RENDERIZANDO em
                        390×844 — `tsc` e `vitest` passavam. */}
                    <dl className="grid grid-cols-2 gap-2 text-sm">
                      <div className="col-span-2 min-w-0">
                        <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Chave</dt>
                        <dd>
                          <code className="break-all font-numeric text-xs">{i.key}</code>
                        </dd>
                      </div>
                      <div className="min-w-0">
                        <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Lançamentos</dt>
                        <dd className="font-numeric tabular-nums text-foreground">{i.entries_count}</dd>
                      </div>
                      <div className="min-w-0">
                        <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Projetos</dt>
                        <dd className="font-numeric tabular-nums text-foreground">{i.projects_count}</dd>
                      </div>
                    </dl>
                    {i.description_html && (
                      <AccordionItem value={`m-${i.id}`} className="mt-2 border-0">
                        <AccordionTrigger className="min-h-[3rem] py-0 text-sm hover:no-underline">
                          Instrução
                        </AccordionTrigger>
                        <AccordionContent className="pb-0 pt-2">
                          <RichTextView html={i.description_html} />
                        </AccordionContent>
                      </AccordionItem>
                    )}
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
              rowKey={(i) => i.id}
              loading={consulta.isLoading}
              error={consulta.isError ? consulta.error : undefined}
              onRetry={() => consulta.refetch()}
              sortMode="server"
              sort={sort}
              onSortChange={aplicarOrdenacao}
              caption="Indicadores"
              loadingLabel="Carregando indicadores…"
              emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum indicador cadastrado'}
              emptyDescription={
                buscando
                  ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
                  : 'Os indicadores alimentam a grade mensal dos projetos. Cadastre o primeiro para começar.'
              }
              emptyAction={
                buscando ? (
                  <Button variant="secondary" size="sm" onClick={() => aplicarBusca('')}>
                    Limpar busca
                  </Button>
                ) : podeEscrever ? (
                  <Button size="sm" onClick={abrirCriacao}>
                    <Plus aria-hidden="true" className="h-4 w-4" />
                    Novo indicador
                  </Button>
                ) : undefined
              }
            />
          </div>
        )}
      </Accordion>

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

      <IndicatorDrawer
        open={drawerAberto}
        onClose={fecharDrawer}
        editando={editando}
        salvando={salvar.isPending}
        onSubmit={(dados) => salvar.mutate(dados)}
      />

      <DeleteIndicatorDialog
        indicadorId={excluindo?.id ?? null}
        titulo={excluindo?.title ?? ''}
        excluindo={remover.isPending}
        onCancel={() => setExcluindo(null)}
        onConfirm={() => excluindo && remover.mutate(excluindo)}
      />
    </div>
  )
}
