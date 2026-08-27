import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { Plus, FolderKanban, Pencil, Trash2, Eye } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { SearchInput } from '@/components/ui/SearchInput'
import { Badge } from '@/components/ui/Badge'
import { Progress } from '@/components/ui/Progress'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { useMobile } from '@/hooks/useMobile'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useJobProgress } from '@/hooks/useJobProgress'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatAmount } from '@/lib/utils/number'
import { projectsApi, type Project } from '@/lib/api/projects'
import { ProjectForm, type ProjectFormValues, valoresIniciais, doProjeto } from './ProjectForm'

/**
 * **Projetos** (FE-080..FE-084) — a lista do tenant.
 *
 * O que muda em relação ao legado:
 *
 * - **A lista respeita a participação** (D-29). No legado bastava passar
 *   `project_id` na query string para ler qualquer projeto: a linha
 *   `Project.where(id: params[:project_id])` substituía o escopo por membership.
 *   OG e Admin enxergam todos por decisão explícita (DEC-99), não por acidente.
 * - **O progresso da criação anda sozinho** (FE-083 / D-86). No legado não havia
 *   nem polling nem push: o usuário recarregava a lista à mão para saber se o
 *   projeto tinha terminado de nascer. Aqui o `job_state`/`job_progress` chegam
 *   por Action Cable — **polling é proibido** (Princípio 10).
 * - **A falha de remoção APARECE e o projeto PERMANECE na lista** (FE-084). No
 *   legado o tratamento de erro estava comentado e o JS redirecionava dizendo
 *   "removido com sucesso" sem ter removido (D-24).
 * - **O toast distingue "cadastrado" de "atualizado"** (FE-090).
 */
export function ProjectsPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = (papel === 'og' || papel === 'admin' || papel === 'gerente') && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination()
  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<Project | null>(null)
  const [valores, setValores] = useState<ProjectFormValues>(valoresIniciais())
  const [confirmando, setConfirmando] = useState<Project | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  const filtros = useMemo(
    () => ({ page: paginacao.page, perPage: paginacao.perPage, q: busca.consulta || undefined }),
    [paginacao.page, paginacao.perPage, busca.consulta],
  )

  const consulta = useQuery({
    queryKey: ['projects', filtros],
    queryFn: () => projectsApi.list(filtros),
  })

  /**
   * FE-083 / **D-86** — o progresso da criação anda sozinho.
   *
   * No legado não havia **nem polling nem push**: quem criava um projeto
   * recarregava a lista à mão para descobrir se ele tinha terminado de nascer.
   * Aqui o `ProjectProgressChannel` avisa, e o websocket é só o **gatilho** —
   * quem entrega o dado continua sendo o React Query (§5.7 das convenções).
   *
   * **`setInterval` é proibido** (Princípio 10), e o teste desta fatia reprova
   * `refetchInterval` em qualquer tela daqui.
   */
  const { current: projetoCorrente } = useCurrentProject()
  const progresso = useJobProgress({
    projectId: projetoCorrente?.id ?? null,
    invalidateKeys: [['projects']],
  })

  const invalidar = () => queryClient.invalidateQueries({ queryKey: ['projects'] })

  const salvar = useMutation({
    mutationFn: (dados: Record<string, unknown>) =>
      editando ? projectsApi.update(editando.id, dados) : projectsApi.create(dados),
    onSuccess: () => {
      // FE-090 — "cadastrado" e "atualizado" são eventos diferentes, e o
      // legado dizia a mesma frase para os dois.
      notify.success(editando ? 'Projeto atualizado.' : 'Projeto cadastrado.')
      setDrawerAberto(false)
      setEditando(null)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o projeto.')),
  })

  const excluir = useMutation({
    mutationFn: (projeto: Project) => projectsApi.remove(projeto.id),
    onSuccess: (_dado, projeto) => {
      notify.success(`Projeto «${projeto.name}» removido.`)
      setConfirmando(null)
      invalidar()
    },
    onError: (erro) => {
      // FE-084 — o erro do servidor APARECE, e a lista não muda.
      notify.error(mensagemDoServidor(erro, 'Não foi possível remover o projeto.'))
      setConfirmando(null)
    },
  })

  function abrirCriacao() {
    setEditando(null)
    setValores(valoresIniciais())
    setDrawerAberto(true)
  }

  function abrirEdicao(projeto: Project) {
    setEditando(projeto)
    setValores(doProjeto(projeto))
    setDrawerAberto(true)
  }

  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0

  function acoesDoProjeto(projeto: Project) {
    return [
      {
        key: 'abrir',
        label: 'Abrir detalhe',
        icon: <Eye aria-hidden="true" className="h-4 w-4" />,
        onSelect: () => navigate(`/projects/${projeto.id}`),
      },
      {
        key: 'editar',
        label: 'Editar',
        icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
        onSelect: () => abrirEdicao(projeto),
      },
      {
        key: 'excluir',
        label: projeto.is_sandbox ? 'Limpar dados' : 'Remover',
        icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
        destructive: true,
        // FE-094 — o projeto de treinamento oferece "limpar", não "remover".
        disabledReason: projeto.is_sandbox
          ? 'Projeto de treinamento: os dados são limpos, o projeto não é removido.'
          : undefined,
        onSelect: () => setConfirmando(projeto),
      },
    ]
  }

  return (
    <div className="pb-10">
      <PageHeader
        title="Projetos"
        subtitle="Cada projeto é um escopo fechado: empresas, limites, recebíveis e renegociações vivem dentro de um."
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
            placeholder="Buscar projeto por nome ou chave…"
            aria-label="Buscar projeto por nome ou chave"
          />
        }
        rightSlot={
          podeEscrever ? (
            <Button onClick={abrirCriacao}>
              <Plus aria-hidden="true" className="h-4 w-4" />
              Novo projeto
            </Button>
          ) : undefined
        }
      />

      <AsyncSection
        loading={consulta.isLoading}
        error={consulta.isError ? consulta.error : undefined}
        data={consulta.data?.items}
        onRetry={() => consulta.refetch()}
        loadingLabel="Carregando projetos…"
        emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum projeto ainda'}
        emptyDescription={
          buscando
            ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
            : 'O projeto é o escopo de tudo no Safegold. Cadastre o primeiro para liberar o restante do console.'
        }
      >
        {(itens) =>
          estreito ? (
            <div>
              {itens.map((p) => (
                <MobileCard
                  key={p.id}
                  title={p.name}
                  subtitle={p.integration_key}
                  onClick={() => navigate(`/projects/${p.id}`)}
                  headerAction={
                    podeEscrever ? (
                      <span onClick={(e) => e.stopPropagation()}>
                        <MobileRowActions
                          open={acoesDe === p.id}
                          onOpenChange={(aberto) => setAcoesDe(aberto ? p.id : null)}
                          title={p.name}
                          subtitle="Projeto"
                          actions={acoesDoProjeto(p)}
                        />
                      </span>
                    ) : undefined
                  }
                >
                  <SeloProjeto projeto={p} />
                  <ProgressoDoProjeto projeto={p} aoVivo={progresso} />
                </MobileCard>
              ))}
            </div>
          ) : (
            <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
              {itens.map((p) => (
                <li key={p.id}>
                  <article className="relative flex h-full flex-col gap-3 overflow-hidden rounded-lg border border-border bg-card p-4 pl-5 shadow-e1">
                    {/* A cor de identificação do projeto é **dado**, não estilo:
                        vem da coluna `color`. Ela entra como FAIXA na borda, e
                        não como fundo de um ícone — um valor arbitrário do
                        banco atrás de um glifo é contraste que ninguém pode
                        garantir, e projeto sem cor ficava com o ícone
                        invisível no modo escuro. A faixa não tem esse problema:
                        sem cor, ela cai no token da borda. */}
                    <span
                      aria-hidden="true"
                      className="absolute inset-y-0 left-0 w-1.5 bg-border"
                      style={p.color ? { backgroundColor: p.color } : undefined}
                    />
                    <div className="flex items-start gap-3">
                      <span
                        className="mt-0.5 inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-border bg-muted text-muted-foreground"
                        aria-hidden="true"
                      >
                        <FolderKanban className="h-4 w-4" />
                      </span>
                      <button
                        type="button"
                        className="min-w-0 flex-1 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        onClick={() => navigate(`/projects/${p.id}`)}
                      >
                        <span className="block truncate font-semibold text-card-foreground">{p.name}</span>
                        <code className="block truncate font-numeric text-xs text-muted-foreground">
                          {p.integration_key}
                        </code>
                      </button>

                      {podeEscrever && (
                        <div className="flex shrink-0 items-center gap-1">
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={`Editar ${p.name}`}
                            onClick={() => abrirEdicao(p)}
                          >
                            <Pencil aria-hidden="true" className="h-4 w-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={
                              p.is_sandbox ? `Limpar dados de ${p.name}` : `Remover ${p.name}`
                            }
                            onClick={() => setConfirmando(p)}
                          >
                            <Trash2 aria-hidden="true" className="h-4 w-4" />
                          </Button>
                        </div>
                      )}
                    </div>

                    <SeloProjeto projeto={p} />
                    <ProgressoDoProjeto projeto={p} aoVivo={progresso} />

                    <p className="mt-auto font-numeric text-xs text-muted-foreground">
                      {p.members_count} membro(s)
                    </p>
                  </article>
                </li>
              ))}
            </ul>
          )
        }
      </AsyncSection>

      {meta && meta.total > 0 && estreito ? (
        <MobilePagination
          page={meta.page}
          total={meta.total}
          perPage={meta.perPage}
          loading={consulta.isFetching}
          onPageChange={paginacao.setPage}
        />
      ) : null}

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

      <SideDrawer
        open={drawerAberto}
        onClose={() => setDrawerAberto(false)}
        title={editando ? 'Editar projeto' : 'Novo projeto'}
        footer={
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDrawerAberto(false)}>
              Cancelar
            </Button>
            {/* FE-089 / DC-23 — **uma** requisição por clique em "Salvar".
                O legado registrava salvamento a cada `keyup` do formulário. */}
            <Button disabled={salvar.isPending} onClick={() => salvar.mutate(paraPayload(valores, editando))}>
              Salvar
            </Button>
          </div>
        }
      >
        <ProjectForm values={valores} onChange={setValores} editing={editando} />
      </SideDrawer>

      <SideDrawer
        open={confirmando !== null}
        onClose={() => setConfirmando(null)}
        title={confirmando?.is_sandbox ? 'Limpar projeto de treinamento' : 'Remover projeto'}
        footer={
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setConfirmando(null)}>
              Cancelar
            </Button>
            <Button
              variant="destructive"
              disabled={excluir.isPending || confirmando?.is_sandbox}
              onClick={() => confirmando && excluir.mutate(confirmando)}
            >
              Remover
            </Button>
          </div>
        }
      >
        {confirmando?.is_sandbox ? (
          <p className="text-sm text-muted-foreground">
            «{confirmando.name}» é o projeto de treinamento. Ele nunca é removido — os dados são limpos e o
            projeto volta ao estado inicial. A limpeza é feita por rotina de operação, com pré-visualização.
          </p>
        ) : (
          <p className="text-sm text-muted-foreground">
            Remover «{confirmando?.name}»? Se houver empresa, limite, recebível ou renegociação vinculados, o
            servidor recusa e o projeto permanece — a mensagem dirá qual vínculo segura.
          </p>
        )}
      </SideDrawer>
    </div>
  )
}

function SeloProjeto({ projeto }: { projeto: Project }) {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {projeto.is_active ? (
        <Badge variant="success">Ativo</Badge>
      ) : (
        <Badge variant="secondary">Inativo</Badge>
      )}
      {projeto.is_sandbox && <Badge variant="warning">Treinamento</Badge>}
      {projeto.has_safegold_management && <Badge variant="info">Gerido pela Safegold</Badge>}
      {projeto.has_bi && <Badge variant="outline">BI</Badge>}
    </div>
  )
}

/**
 * FE-083 / **D-86** — o progresso da criação.
 *
 * Duas origens, e as duas necessárias: `job_state`/`job_progress` vêm da própria
 * linha (DB-460) e cobrem quem **abriu a tela com o job já rodando**; o evento
 * do Action Cable cobre quem está **com a tela aberta enquanto ele anda**. Sem
 * a primeira, recarregar a página perdia a barra; sem a segunda, seria preciso
 * recarregar para vê-la mexer — que é exatamente o D-86.
 *
 * O evento ao vivo só vale para o projeto **corrente**: o canal é por projeto.
 */
function ProgressoDoProjeto({
  projeto,
  aoVivo,
}: {
  projeto: Project
  aoVivo: { status: string; percent: number | null; message?: string; error?: string }
}) {
  const desteProjeto = aoVivo.status !== 'idle'
  const estado = desteProjeto ? aoVivo.status : projeto.job_state
  const percentual = desteProjeto ? aoVivo.percent : projeto.job_progress

  if (estado === 'failed') {
    return (
      <p className="text-xs text-destructive">
        {aoVivo.error ?? 'A preparação do projeto falhou.'} A operação foi registrada — reexecute pela fila
        de tarefas.
      </p>
    )
  }
  if (estado !== 'running') return null

  return (
    <div>
      <Progress value={percentual ?? 0} />
      <p className="mt-1 font-numeric text-xs text-muted-foreground">
        {/* `useJobProgress` faz `Number(bruto)`: 1/3 do trabalho chegava como
            `33.33333333333333%`. Percentual de barra se lê inteiro, em pt-BR. */}
        {aoVivo.message ?? 'Preparando o projeto…'} {formatAmount(percentual ?? 0, 0)}%
      </p>
    </div>
  )
}

/** Do estado do formulário para o corpo da requisição. */
function paraPayload(v: ProjectFormValues, editando: Project | null): Record<string, unknown> {
  const base: Record<string, unknown> = {
    name: v.name,
    is_active: v.is_active,
    segment_id: v.segment_id ?? undefined,
    sub_segment_id: v.sub_segment_id ?? undefined,
    address_type: v.address_type,
    address: v.address,
    address_number: v.address_number,
    address_complement: v.address_complement,
    neighborhood: v.neighborhood,
    cep: v.cep,
    address_state: v.address_state ?? undefined,
    address_city: v.address_city,
    closing_date: v.closing_date || undefined,
    availability_note: v.availability_note,
  }

  if (editando) {
    // `slug` e `integration_key` não vão: são congelados na criação (DC-17).
    if (v.responsible_user_id !== undefined) base.responsible_user_id = v.responsible_user_id ?? ''
    return base
  }

  base.responsible_mode = v.responsible_mode
  if (v.responsible_mode === 'existing') base.responsible_user_id = v.responsible_user_id ?? ''
  if (v.responsible_mode === 'new') {
    base.responsible_name = v.responsible_name
    base.responsible_email = v.responsible_email
  }
  return base
}
