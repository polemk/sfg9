import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Landmark, Pencil, Trash2, UserPlus, Users2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { useProjectActions } from './ProjectActions'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { DetailList } from '@/components/ui/DetailList'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Autocomplete } from '@/components/ui/Autocomplete'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/Label'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { useMobile } from '@/hooks/useMobile'
import { useAuthStore } from '@/store/authStore'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import {
  carrierConnectionsApi,
  membershipsApi,
  projectsApi,
  MEMBERSHIP_ROLE_LABELS,
  type Membership,
  type MembershipRole,
} from '@/lib/api/projects'

/**
 * **Detalhe do projeto** (FE-091..FE-099, FE-040, FE-041).
 *
 * Cinco defeitos do legado morrem nesta tela:
 *
 * - **FE-093 — os dois interruptores tinham o MESMO id HTML**
 *   (`id="is_active_{project.id}"`). Clicar no rótulo de "BI contratado"
 *   alternava o de "Gerido pela Safegold". Aqui cada um tem id próprio, e o
 *   teste `ProjectDetailPage.test` reprova se voltarem a colidir.
 * - **FE-091 — a data de criação saía como `dd/mm/aaaa- HH:MM`**, com o hífen
 *   colado. Agora é `Intl`.
 * - **FE-095 / FE-097 — a lista de membros espelha as TRÊS condições do
 *   servidor** (não-readonly, não remove o dono, não remove a si mesmo) e a
 *   mensagem fala do **projeto**. No legado ela dizia "O membro foi removido da
 *   empresa" — texto copiado de outra tela.
 * - **FE-098 — o cartão de portadores é ordenado e o vazio é explícito.**
 * - **FE-099 — a observação some quando está vazia**, em vez de deixar um
 *   cartão com um título e nada embaixo.
 */
export function ProjectDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()

  const projeto = useQuery({
    queryKey: ['project', id],
    queryFn: () => projectsApi.get(id),
    enabled: Boolean(id),
  })

  // **FE-094 — as acoes rapidas do detalhe.** Editar e remover existiam so na
  // LISTA: quem abrisse o projeto para conferir tinha de voltar para agir, e a
  // lista (com filtro e paginacao) podia nem estar mostrando aquele projeto.
  // Mesma gaveta e mesma confirmacao da lista — inclusive a regra do projeto de
  // treinamento, que nunca e removido.
  const acoes = useProjectActions({ onRemovido: () => navigate('/projects') })

  return (
    <div className="pb-10">
      <Button variant="ghost" size="sm" className="mb-2" onClick={() => navigate('/projects')}>
        <ArrowLeft aria-hidden="true" className="h-4 w-4" />
        Projetos
      </Button>

      <AsyncSection
        loading={projeto.isLoading}
        error={projeto.isError ? projeto.error : undefined}
        data={projeto.data ? [projeto.data] : undefined}
        onRetry={() => projeto.refetch()}
        loadingLabel="Carregando projeto…"
        emptyTitle="Projeto não encontrado"
        emptyDescription="Ele pode ter sido removido, ou você pode não participar dele — o sistema responde igual nos dois casos, de propósito."
      >
        {([p]) => (
          <>
            <PageHeader
              title={p.name}
              subtitle={p.integration_key}
              rightSlot={
                <div className="flex flex-wrap items-center gap-1.5">
                  {p.is_active ? <Badge variant="success">Ativo</Badge> : <Badge variant="secondary">Inativo</Badge>}
                  {p.is_sandbox && <Badge variant="warning">Treinamento</Badge>}
                  <Button variant="secondary" size="sm" onClick={() => acoes.abrirEdicao(p)}>
                    <Pencil aria-hidden="true" className="h-4 w-4" />
                    Editar
                  </Button>
                  {/* O de treinamento e LIMPO, nao removido — o rotulo diz o que
                      acontece, e a propria confirmacao explica a diferenca. */}
                  <Button variant="ghost" size="sm" onClick={() => acoes.confirmarRemocao(p)}>
                    <Trash2 aria-hidden="true" className="h-4 w-4" />
                    {p.is_sandbox ? 'Limpar dados' : 'Remover'}
                  </Button>
                </div>
              }
            />

            {acoes.superficies}

            <Tabs defaultValue="resumo">
              <TabsList>
                <TabsTrigger value="resumo">Resumo</TabsTrigger>
                <TabsTrigger value="membros">Membros</TabsTrigger>
                <TabsTrigger value="portadores">Portadores</TabsTrigger>
              </TabsList>

              <TabsContent value="resumo">
                <div className="grid gap-4 lg:grid-cols-2">
                  <Card className="p-4">
                    <h2 className="mb-3 text-sm font-semibold text-card-foreground">Cadastro</h2>
                    <DetailList
                      items={[
                        { label: 'Segmento', content: p.segment_title ?? '—' },
                        { label: 'Subsegmento', content: p.sub_segment_title ?? '—' },
                        { label: 'Responsável', content: p.responsible_name ?? '—' },
                        { label: 'E-mail do responsável', content: p.responsible_email ?? '—' },
                        { label: 'Dono', content: p.owner_name ?? '—' },
                        { label: 'Membros', content: p.members_count, numeric: true },
                        {
                          label: 'Data de baixa',
                          content: p.closing_date ? formatarData(p.closing_date) : '—',
                        },
                        {
                          label: 'Criado em',
                          // FE-091 — o legado exibia `dd/mm/aaaa- HH:MM`.
                          content: formatarDataHora(p.created_at),
                        },
                        {
                          label: 'Endereço',
                          // O servidor devolve as linhas separadas por `\n`;
                          // quem decide como quebrar é a tela. O legado montava
                          // `<br/>` dentro do model.
                          content: (
                            <span className="whitespace-pre-line">{p.formatted_address || '—'}</span>
                          ),
                          full: true,
                        },
                      ]}
                    />
                  </Card>

                  <Card className="p-4">
                    <h2 className="mb-3 text-sm font-semibold text-card-foreground">Marcas</h2>
                    <MarcasDoProjeto projeto={p} />
                  </Card>

                  {/* FE-099 — some quando vazia.

                      O `?? ''` não é decoração: a entity devolvia `nil` aqui
                      enquanto o campo irmão `_html` devolvia `""`, e o tipo do
                      cliente dizia `string` para os dois. A tela caiu inteira
                      com `Cannot read properties of null (reading 'trim')`, com
                      `tsc` verde. A causa foi corrigida no servidor; isto aqui
                      protege de resposta em cache e de qualquer outro produtor
                      do mesmo campo. */}
                  {(p.availability_note_text ?? '').trim().length > 0 && (
                    <Card className="p-4 lg:col-span-2">
                      <h2 className="mb-3 text-sm font-semibold text-card-foreground">
                        Observação · Disponibilidade
                      </h2>
                      <div
                        className="prose-safegold text-sm text-card-foreground"
                        // O HTML vem do ActionText, que **recusa anexo no
                        // servidor** — não é conteúdo arbitrário de terceiro.
                        dangerouslySetInnerHTML={{ __html: p.availability_note_html }}
                      />
                    </Card>
                  )}
                </div>
              </TabsContent>

              <TabsContent value="membros">
                <AbaMembros projetoId={p.id} donoId={p.owner_id} />
              </TabsContent>

              <TabsContent value="portadores">
                <AbaPortadores />
              </TabsContent>
            </Tabs>
          </>
        )}
      </AsyncSection>
    </div>
  )
}

/**
 * FE-092, FE-093 — os dois interruptores, com **ids distintos**.
 *
 * ⚠ A marca de gestão é gravada **só em `projects`**. A cópia nas 6 tabelas
 * filhas depende da Q-02 e não foi criada: `Company` lê a marca derivada do
 * projeto, e por isso não existe coluna para divergir.
 */
function MarcasDoProjeto({ projeto }: { projeto: { id: string; has_safegold_management: boolean; has_bi: boolean } }) {
  const queryClient = useQueryClient()
  const papel = useRoleSlug()
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = (papel === 'og' || papel === 'admin' || papel === 'gerente') && !somenteLeitura

  const gestao = useMutation({
    mutationFn: (valor: boolean) => projectsApi.setSafegoldManagement(projeto.id, valor),
    onSuccess: () => {
      notify.success('Marca de gestão atualizada.')
      queryClient.invalidateQueries({ queryKey: ['project', projeto.id] })
      queryClient.invalidateQueries({ queryKey: ['companies'] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível alterar a marca de gestão.')),
  })

  const bi = useMutation({
    mutationFn: (valor: boolean) => projectsApi.setBi(projeto.id, valor),
    onSuccess: () => {
      notify.success('Marca de BI atualizada.')
      queryClient.invalidateQueries({ queryKey: ['project', projeto.id] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível alterar a marca de BI.')),
  })

  return (
    <div className="space-y-3">
      <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
        <div>
          <Label htmlFor="has_safegold_management">Gerido pela Safegold</Label>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Marca operacional. As empresas do projeto a herdam por leitura — não há cópia carimbada que possa
            divergir.
          </p>
        </div>
        <Switch
          id="has_safegold_management"
          checked={projeto.has_safegold_management}
          disabled={!podeEscrever || gestao.isPending}
          onCheckedChange={(v) => gestao.mutate(v)}
        />
      </div>

      <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
        <div>
          {/* FE-093 — id PRÓPRIO. No legado os dois eram
              `id="is_active_{project.id}"` e o rótulo de um alternava o outro. */}
          <Label htmlFor="has_bi">BI contratado</Label>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Marca comercial. Pode ter consumidor externo, por isso é preservada como está.
          </p>
        </div>
        <Switch
          id="has_bi"
          checked={projeto.has_bi}
          disabled={!podeEscrever || bi.isPending}
          onCheckedChange={(v) => bi.mutate(v)}
        />
      </div>

      {!podeEscrever && (
        <p className="text-xs text-muted-foreground">
          Seu perfil não altera as marcas do projeto — o mesmo critério vale no servidor.
        </p>
      )}
    </div>
  )
}

/** FE-040, FE-041, FE-095..FE-097 — a aba de membros. */
function AbaMembros({ projetoId, donoId }: { projetoId: string; donoId: string }) {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  const usuario = useAuthStore((s) => s.user)
  const podeGerir = papel === 'og' || papel === 'admin' || papel === 'gerente'

  const [termo, setTermo] = useState('')
  const [escolhido, setEscolhido] = useState<string | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  const membros = useQuery({
    queryKey: ['memberships', projetoId],
    queryFn: () => membershipsApi.list({ perPage: 100 }),
  })

  const candidatos = useQuery({
    queryKey: ['membership-candidates', termo],
    queryFn: () => membershipsApi.candidates(termo || undefined),
    enabled: podeGerir,
  })

  const adicionar = useMutation({
    mutationFn: (userId: string) => membershipsApi.create(userId, 'participante' as MembershipRole),
    onSuccess: () => {
      notify.success('Participação criada.')
      setEscolhido(null)
      setTermo('')
      queryClient.invalidateQueries({ queryKey: ['memberships', projetoId] })
      queryClient.invalidateQueries({ queryKey: ['membership-candidates'] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível adicionar o membro.')),
  })

  const remover = useMutation({
    mutationFn: (m: Membership) => membershipsApi.remove(m.id),
    onSuccess: (_dado, m) => {
      // FE-097 — a mensagem fala do PROJETO. No legado dizia "removido da empresa".
      notify.success(`${m.user.name} saiu deste projeto.`)
      queryClient.invalidateQueries({ queryKey: ['memberships', projetoId] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover a participação.')),
  })

  /**
   * As TRÊS condições do servidor, espelhadas. A tela não as implementa — ela
   * as **recebe**: o servidor recusa igual se alguém forçar pela API.
   */
  function motivoDeNaoRemover(m: Membership): string | undefined {
    if (!podeGerir) return 'Seu perfil não gerencia participações neste projeto.'
    if (m.user.id === donoId) return 'É o dono do projeto — a participação dele não é removível.'
    if (m.user.id === usuario?.id) return 'Você não remove a própria participação.'
    return undefined
  }

  return (
    <div className="space-y-4">
      {/* FE-096 — o campo SOME para quem não pode adicionar. */}
      {podeGerir && (
        <Card className="p-4">
          <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-card-foreground">
            <UserPlus aria-hidden="true" className="h-4 w-4" />
            Adicionar membro
          </h2>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div className="flex-1">
              <Autocomplete
                aria-label="Buscar pessoa para adicionar ao projeto"
                options={(candidatos.data?.candidates ?? []).map((c) => ({
                  id: c.id,
                  label: c.name,
                  subtitle: c.email ?? c.phone ?? undefined,
                }))}
                value={escolhido}
                onChange={setEscolhido}
                onSearch={setTermo}
                loading={candidatos.isFetching}
                placeholder="Buscar por nome, e-mail ou telefone…"
                emptyMessage="Ninguém encontrado — quem já participa não aparece nesta lista."
              />
            </div>
            <Button
              disabled={!escolhido || adicionar.isPending}
              onClick={() => escolhido && adicionar.mutate(escolhido)}
            >
              Adicionar
            </Button>
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            A lista já exclui quem participa e respeita a sua hierarquia. Ninguém se adiciona a um projeto — nem
            você.
          </p>
        </Card>
      )}

      <AsyncSection
        loading={membros.isLoading}
        error={membros.isError ? membros.error : undefined}
        data={membros.data?.memberships}
        onRetry={() => membros.refetch()}
        loadingLabel="Carregando membros…"
        emptyTitle="Nenhum membro"
        emptyDescription="Todo projeto tem ao menos o dono. Se esta lista está vazia, algo saiu do lugar."
      >
        {(lista) =>
          estreito ? (
            <div>
              {lista.map((m) => (
                <MobileCard
                  key={m.id}
                  title={m.user.name}
                  subtitle={m.user.email ?? undefined}
                  headerAction={
                    <MobileRowActions
                      open={acoesDe === m.id}
                      onOpenChange={(aberto) => setAcoesDe(aberto ? m.id : null)}
                      title={m.user.name}
                      subtitle="Participação"
                      actions={[
                        {
                          key: 'remover',
                          label: 'Remover do projeto',
                          icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                          destructive: true,
                          disabledReason: motivoDeNaoRemover(m),
                          onSelect: () => remover.mutate(m),
                        },
                      ]}
                    />
                  }
                >
                  <div className="flex flex-wrap items-center gap-1.5">
                    <Badge variant="outline">
                      {MEMBERSHIP_ROLE_LABELS[m.role as MembershipRole] ?? m.role}
                    </Badge>
                    {m.is_project_owner && <Badge variant="info">Dono</Badge>}
                  </div>
                </MobileCard>
              ))}
            </div>
          ) : (
            <ul className="divide-y divide-border rounded-lg border border-border bg-card">
              {lista.map((m) => {
                const motivo = motivoDeNaoRemover(m)
                return (
                  <li key={m.id} className="flex items-center gap-3 px-4 py-3">
                    <Users2 aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-card-foreground">{m.user.name}</span>
                      <span className="block truncate text-xs text-muted-foreground">{m.user.email ?? '—'}</span>
                    </span>
                    <Badge variant="outline">
                      {MEMBERSHIP_ROLE_LABELS[m.role as MembershipRole] ?? m.role}
                    </Badge>
                    {m.is_project_owner && <Badge variant="info">Dono</Badge>}
                    {motivo ? (
                      // O lugar da ação fica OCUPADO pela explicação, em vez de
                      // a linha simplesmente perder um botão sem dizer por quê.
                      <span className="max-w-[16rem] text-right text-xs text-muted-foreground">{motivo}</span>
                    ) : (
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={`Remover ${m.user.name} do projeto`}
                        onClick={() => remover.mutate(m)}
                      >
                        <Trash2 aria-hidden="true" className="h-4 w-4" />
                      </Button>
                    )}
                  </li>
                )
              })}
            </ul>
          )
        }
      </AsyncSection>
    </div>
  )
}

/** FE-098 — ordem alfabética, com grupo; vazio explícito. */
function AbaPortadores() {
  const navigate = useNavigate()
  const conexoes = useQuery({
    queryKey: ['carrier-connections', 'list'],
    queryFn: () => carrierConnectionsApi.list({ perPage: 100 }),
  })

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Button variant="secondary" size="sm" onClick={() => navigate('/project-carrier-connections')}>
          Gerenciar conexões
        </Button>
      </div>

      <AsyncSection
        loading={conexoes.isLoading}
        error={conexoes.isError ? conexoes.error : undefined}
        data={conexoes.data?.items}
        onRetry={() => conexoes.refetch()}
        loadingLabel="Carregando portadores…"
        emptyTitle="Nenhum portador conectado"
        emptyDescription="Sem portador conectado não há garantia nem limite de risco neste projeto. Conecte o primeiro em «Gerenciar conexões»."
      >
        {(lista) => (
          <ul className="divide-y divide-border rounded-lg border border-border bg-card">
            {lista.map((c) => (
              <li key={c.id} className="flex items-center gap-3 px-4 py-3">
                <Landmark aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-card-foreground">{c.carrier_title ?? '—'}</span>
                  {c.carrier_group_title && (
                    <span className="block truncate text-xs text-muted-foreground">{c.carrier_group_title}</span>
                  )}
                </span>
                {c.carrier_is_active === false && <Badge variant="secondary">Inativo</Badge>}
              </li>
            ))}
          </ul>
        )}
      </AsyncSection>
    </div>
  )
}

function formatarData(iso: string): string {
  const d = new Date(`${iso}T00:00:00`)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString('pt-BR')
}

function formatarDataHora(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return `${d.toLocaleDateString('pt-BR')} às ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
}
