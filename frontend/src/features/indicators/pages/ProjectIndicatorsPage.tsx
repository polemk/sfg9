import { useCallback, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { Plus } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { SearchInput } from '@/components/ui/SearchInput'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { Accordion } from '@/components/ui/accordion'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { useMobile } from '@/hooks/useMobile'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import {
  indicatorConnectionsApi,
  indicatorsApi,
  mensagemDoServidor,
  type IndicatorConnectionRow,
  type IndicatorInput,
} from '@/lib/api/indicators'
import { ConnectionRow } from '../components/ConnectionRow'
import { IndicatorDrawer } from '../components/IndicatorDrawer'
import { DeleteIndicatorDialog } from '../components/DeleteIndicatorDialog'

/**
 * **Projeto › Indicadores específicos** (`FE-319..FE-323`).
 *
 * Lista tudo que este projeto alcança — os **globais** (com interruptor) e os
 * **específicos dele** (com editar/ativar/excluir).
 *
 * ## O que muda em relação ao legado
 *
 * - **O projeto é o corrente, não o padrão.** No legado ele vem de
 *   `current_user.default_project` **hardcoded no `data-attribute` e na URL do
 *   proxy** (`indicator_connections/_body.html.erb:1`), sem seletor: quem não
 *   tem projeto padrão **quebra** em `default_project.id`, e quem tem vários vê
 *   sempre o mesmo. Aqui o servidor resolve pelo `current_project!`.
 * - **A busca existe.** O legado registra um listener para um campo de busca
 *   que **não existe no HTML desta tela**, e o endpoint ignora `q` de qualquer
 *   forma (os ramos `if connection_type == "Carrier"/"Project"` nunca casam com
 *   `"Indicator"`).
 * - **Excluir tem confirmação** e **os lançamentos sobrevivem** — ver
 *   `DeleteIndicatorDialog`. Esta era a tela mais perigosa do bloco.
 */
export function ProjectIndicatorsPage() {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const somenteLeitura = useIsReadonly()

  const busca = useDebouncedSearch()
  const paginacao = usePagination({ initialPerPage: 50 })

  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<IndicatorConnectionRow | null>(null)
  const [excluindo, setExcluindo] = useState<IndicatorConnectionRow | null>(null)
  const [alternandoId, setAlternandoId] = useState<string | null>(null)

  const filtros = useMemo(
    () => ({ page: paginacao.page, perPage: paginacao.perPage, q: busca.consulta || undefined }),
    [paginacao.page, paginacao.perPage, busca.consulta],
  )

  const consulta = useQuery({
    queryKey: ['indicator-connections', filtros],
    queryFn: () => indicatorConnectionsApi.list(filtros),
  })

  const invalidar = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['indicator-connections'] })
    // A grade mensal mostra exatamente os conectados: conectar ou desconectar
    // muda o que ela desenha.
    queryClient.invalidateQueries({ queryKey: ['indicator-grid'] })
  }, [queryClient])

  const alternarConexao = useMutation({
    mutationFn: (indicador: IndicatorConnectionRow) =>
      indicador.connected
        ? indicatorConnectionsApi.disconnect([indicador.id])
        : indicatorConnectionsApi.connect([indicador.id]),
    onMutate: (indicador) => setAlternandoId(indicador.id),
    onSuccess: (_dado, indicador) => {
      // Concordância certa. No legado: "a relação foi ativado".
      notify.success(
        indicador.connected
          ? `«${indicador.title}» foi desconectado deste projeto. Os lançamentos históricos continuam guardados.`
          : `«${indicador.title}» foi conectado a este projeto.`,
      )
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível atualizar a conexão.')),
    onSettled: () => setAlternandoId(null),
  })

  const alternarAtivo = useMutation({
    mutationFn: (indicador: IndicatorConnectionRow) => indicatorsApi.setActive(indicador.id, !indicador.is_active),
    onSuccess: (indicador) => {
      notify.success(`«${indicador.title}» foi ${indicador.is_active ? 'ativado' : 'desativado'}.`)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível alterar o estado do indicador.')),
  })

  const salvar = useMutation({
    mutationFn: (dados: IndicatorInput) =>
      editando
        ? indicatorsApi.update(editando.id, dados)
        : // Sem `editando`, o indicador nasce ESPECÍFICO do projeto corrente. O
          // servidor resolve qual é — nenhum `project_id` sai daqui (C1).
          indicatorsApi.create({ ...dados, scope: 'project' }),
    onSuccess: (indicador) => {
      notify.success(editando ? `«${indicador.title}» atualizado.` : `«${indicador.title}» criado neste projeto.`)
      setDrawerAberto(false)
      setEditando(null)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o indicador.')),
  })

  const remover = useMutation({
    mutationFn: (indicador: IndicatorConnectionRow) => indicatorConnectionsApi.removeSpecific(indicador.id),
    onSuccess: (resultado, indicador) => {
      const preservados = resultado?.entries_preserved ?? 0
      notify.success(
        preservados > 0
          ? `«${indicador.title}» excluído. ${preservados} ${preservados === 1 ? 'lançamento foi preservado' : 'lançamentos foram preservados'}.`
          : `«${indicador.title}» excluído.`,
      )
      setExcluindo(null)
      invalidar()
    },
    onError: (erro) => {
      notify.error(mensagemDoServidor(erro, 'Não foi possível excluir o indicador.'))
      setExcluindo(null)
    },
  })

  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0
  // Ver a nota em `IndicatorEntriesPage`: 409 de escopo é estado de tela.
  const escopo = projectScopeCode(consulta.error)

  return (
    <div className="pb-10">
      <PageHeader
        title="Indicadores específicos"
        subtitle="O que aparece na grade mensal deste projeto: os indicadores globais que você conectar, mais os criados só para ele."
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
            placeholder="Buscar indicador…"
            aria-label="Buscar indicador"
          />
        }
        rightSlot={
          !somenteLeitura ? (
            <Button
              onClick={() => {
                setEditando(null)
                setDrawerAberto(true)
              }}
            >
              <Plus aria-hidden="true" className="h-4 w-4" />
              Novo indicador do projeto
            </Button>
          ) : undefined
        }
      />

      {somenteLeitura && (
        <p className="mb-4 rounded-md border border-border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
          Seu perfil está em <strong>modo somente leitura</strong>: os controles continuam visíveis,
          mas as alterações não são salvas.
        </p>
      )}

      {escopo && <ProjectScopeState code={escopo} recurso="os indicadores específicos" />}

      {/* Acordeão exclusivo: abrir a instrução de um fecha a do anterior. */}
      {!escopo && (
      <Accordion type="single" collapsible>
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={consulta.data?.items}
          onRetry={() => consulta.refetch()}
          loadingLabel="Carregando indicadores do projeto…"
          emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum indicador disponível'}
          emptyDescription={
            buscando
              ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
              : 'Cadastre um indicador no catálogo global ou crie um específico deste projeto.'
          }
        >
          {(itens) => (
            <div className="space-y-2">
              {itens.map((indicador) => (
                <ConnectionRow
                  key={indicador.id}
                  indicador={indicador}
                  somenteLeitura={somenteLeitura}
                  alternando={alternandoId === indicador.id}
                  onToggle={(i) => alternarConexao.mutate(i)}
                  onEditar={(i) => {
                    setEditando(i)
                    setDrawerAberto(true)
                  }}
                  onAlternarAtivo={(i) => alternarAtivo.mutate(i)}
                  onExcluir={(i) => setExcluindo(i)}
                />
              ))}
            </div>
          )}
        </AsyncSection>
      </Accordion>
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

      <IndicatorDrawer
        open={drawerAberto}
        onClose={() => {
          setDrawerAberto(false)
          setEditando(null)
        }}
        // `DrawerIndicator` é o contrato mínimo do painel; a linha desta tela o
        // satisfaz sem conversão de tipo.
        editando={editando}
        escopo="project"
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
