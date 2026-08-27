import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, FolderKanban, Pencil, ShieldCheck } from 'lucide-react'
import { notify } from '@/lib/notify'

import PageHeader from '@/components/PageHeader'
import { PermissionControl } from '@/components/PermissionControl'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { CopyButton } from '@/components/ui/CopyButton'
import { DetailList } from '@/components/ui/DetailList'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { usersApi, type PermissionChange } from '@/lib/api/endpoints'
import { useAuthStore } from '@/store/authStore'
import { DEFAULT_PER_PAGE } from '@/lib/api/pagination'
import { rotuloDeVerificacao } from '@/features/auth/identityLabels'
import { useIsReadonly } from '@/hooks/useMyPermissions'

/**
 * `/users/:id` — o detalhe de uma conta. FE-022, FE-023, FE-024, FE-025, FE-513.
 *
 * ## Os quatro defeitos do legado que esta tela fecha
 *
 * **1. A aba e o conteúdo eram gateados em LUGARES DIFERENTES** (FE-022). No legado,
 * `detail/_body.html.erb:14` decidia se a aba "Projetos" aparecia e a linha `:22`
 * decidia se o conteúdo dela existia — com condições **diferentes**. Resultado
 * medido: o **Gerente via a aba e ela abria vazia**.
 *
 * A correção é estrutural: **nenhuma das três abas tem condição de visibilidade
 * própria.** Quem chega nesta rota já passou pelo gate de papel do registro de
 * navegação (`consoleNavigation.tsx`, o mesmo dado que monta o menu), e as três abas
 * aparecem para todos os três papéis que chegam — o que muda entre eles é o poder de
 * **escrever**, decidido uma vez em `podeEscrever` e passado adiante. Não existe
 * lugar onde alguém possa esconder uma aba e esquecer do conteúdo, porque não existe
 * a condição.
 *
 * **2. "Editar" era gateado por `may_delete_users?`** (FE-023) — permissão de
 * **remover**. Quem podia editar e não podia remover não via o botão de editar. Aqui
 * o gate é o de escrita da matriz (DEC-18: OG e Admin), que é o mesmo que o servidor
 * aplica no `PUT`.
 *
 * **3. O painel de permissões listava 17 abilities** (FE-024), e o gate de cada uma
 * vivia na view. Sobram **7** — as que tinham call site real (DEC-108) —, e as 6 que
 * voltaram passaram a ser checadas no SERVIDOR, com 403. A tela renderiza o catálogo
 * que o servidor devolve, sem lista escrita aqui: foi assim que ela passou de 1 para
 * 7 sem que nenhuma chave fosse digitada neste arquivo. Duas delas são **teto
 * numérico**, não interruptor — ver `PermissionControl`.
 *
 * **4. A aba Projetos listava `Project.all`** (FE-025), sem paginação e sem filtro:
 * abrir o perfil de qualquer pessoa mostrava a carteira inteira do sistema. Agora é
 * `GET /api/v1/users/:id/memberships`, paginado e recortado pela **interseção** entre
 * a participação do alvo e a visibilidade de quem pergunta (C1).
 *
 * ## Uma divergência do `tasks.md`, registrada de propósito
 *
 * A tarefa 8.8 pede **"DELETE pela rota com `:id` de verdade"** — o legado tinha
 * toggles de associar/desassociar projeto aqui. **A aba não os tem, e isso é
 * deliberado.** A **DC-18** (S4) decidiu que esta aba é *informativa*: conceder e
 * revogar participação é da aba "Membros" **do projeto**, onde as três condições de
 * servidor do **DEC-18.5** valem (não-readonly, não remover o dono, não remover a si
 * mesmo). Um segundo lugar para revogar seria essas condições reimplementadas — foi
 * assim que o legado chegou ao D-34. O defeito que a tarefa cita (o backend ignorava
 * o `:id` do DELETE e usava a trinca) está fechado do lado certo: em
 * `DELETE /api/v1/memberships/:id`, com o id de verdade.
 */

type AbaId = 'geral' | 'projetos' | 'permissoes'

export function UserDetailPage() {
  const { id = '' } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const eu = useAuthStore((s) => s.user)
  const papel = (eu?.user_type_slug || '').toLowerCase()
  // Matriz DEC-18: OG e Admin escrevem; Gerente lê; Colaborador nem alcança a rota
  // (o gate de papel está no registro de navegação, e é o mesmo dado do menu).
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = (papel === 'og' || papel === 'admin') && !somenteLeitura

  const [aba, setAba] = useState<AbaId>('geral')

  const conta = useQuery({
    queryKey: ['user', id],
    queryFn: () => usersApi.get(id),
    enabled: Boolean(id),
  })

  const u = conta.data

  if (conta.isLoading) return <LoadingState label="Carregando a conta…" />
  if (conta.isError || !u) {
    return (
      <ErrorState
        description={
          (conta.error as any)?.response?.status === 404
            ? 'Esta conta não existe ou não está no seu alcance.'
            : 'Não foi possível carregar a conta.'
        }
        onRetry={() => conta.refetch()}
      />
    )
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={u.name || u.email || 'Conta'}
        subtitle={u.email || u.phone || undefined}
        rightSlot={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={() => navigate('/users')}>
              <ArrowLeft aria-hidden="true" className="mr-1.5 h-4 w-4" />
              Contas
            </Button>
            {/* FE-023 — gate de EDITAR, não de remover. */}
            {podeEscrever && (
              <Button variant="primary" onClick={() => navigate(`/users/${u.id}/edit`)}>
                <Pencil aria-hidden="true" className="mr-1.5 h-4 w-4" />
                Editar
              </Button>
            )}
          </div>
        }
      />

      <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-card p-4">
        <UserAvatar name={u.name} email={u.email} src={u.avatar_url} colorKey={u.id} size={56} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-base font-medium text-card-foreground">{u.name || 'Sem nome'}</p>
          <div className="mt-1 flex flex-wrap items-center gap-1.5">
            <Badge variant={u.user_type_slug === 'og' ? 'success' : 'secondary'}>
              {(u.user_type || '—').toUpperCase()}
            </Badge>
            {u.is_blocked && <Badge variant="destructive">BLOQUEADA</Badge>}
            {u.is_default_member && <Badge variant="secondary">MEMBRO PADRÃO</Badge>}
          </div>
        </div>
      </div>

      <Tabs value={aba} onValueChange={(v) => setAba(v as AbaId)}>
        {/* A lista de abas e o conteúdo saem do MESMO lugar — ver o defeito 1 no
            cabeçalho. Nenhuma condição de visibilidade mora só aqui. */}
        <TabsList>
          <TabsTrigger value="geral">Geral</TabsTrigger>
          <TabsTrigger value="projetos">
            <FolderKanban aria-hidden="true" className="mr-1.5 h-3.5 w-3.5" />
            Projetos
          </TabsTrigger>
          <TabsTrigger value="permissoes">
            <ShieldCheck aria-hidden="true" className="mr-1.5 h-3.5 w-3.5" />
            Permissões
          </TabsTrigger>
        </TabsList>

        <TabsContent value="geral">
          <AbaGeral user={u} />
        </TabsContent>

        <TabsContent value="projetos">
          <AbaProjetos userId={u.id} />
        </TabsContent>

        <TabsContent value="permissoes">
          <AbaPermissoes
            userId={u.id}
            podeEscrever={podeEscrever}
            onChanged={() => queryClient.invalidateQueries({ queryKey: ['user', id] })}
          />
        </TabsContent>
      </Tabs>
    </div>
  )
}

// --- Geral -------------------------------------------------------------------

function AbaGeral({ user }: { user: any }) {
  const data = (v?: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR') : null)

  return (
    <div className="rounded-lg border border-border bg-card p-5">
      <DetailList
        columns={2}
        items={[
          { label: 'Nome', content: user.name },
          { label: 'Tipo', content: user.user_type },
          { label: 'CPF/CNPJ', content: user.cpf_cnpj },
          { label: 'E-mail', content: user.email },
          // `identifier` é o código curto que a pessoa dita por telefone (BE-048).
          // `font-numeric` porque é código, e código desalinhado numa coluna é
          // código que ninguém confere.
          // **FE-017 — com botão de copiar.** O código é ditado por telefone ao
          // suporte; só a conta PRÓPRIA tinha o botão (FE-034), e é aqui, no
          // detalhe de outra conta, que o administrador precisa dele.
          {
            label: 'Código',
            content: user.identifier ? (
              <span className="flex items-center gap-1">
                <span className="font-numeric">{user.identifier}</span>
                <CopyButton value={user.identifier} label="Código" />
              </span>
            ) : null,
          },
          { label: 'Usuário', content: user.username },
          { label: 'Telefone', content: user.phone },
          { label: 'Criada em', content: data(user.created_at) },
          {
            label: 'Último acesso',
            // "Nunca logou" é informação, não ausência de informação — e no legado
            // os dois apareciam iguais (um traço).
            content: user.last_login_at ? data(user.last_login_at) : 'Nunca acessou',
          },
          // DEC-74 — o RÓTULO, não o valor cru. A primeira versão desta tela mostrava
          // `media`, direto do banco, enquanto `/profile` mostrava "Média" — a tabela
          // vivia só na outra tela. Agora ela é de `features/auth/identityLabels`.
          { label: 'Verificação', content: rotuloDeVerificacao(user.confiability_level) },
          {
            label: 'Bloqueio',
            full: true,
            content: user.is_blocked
              ? `Bloqueada em ${data(user.blocked_at)}${user.blocked_reason ? ` — ${user.blocked_reason}` : ''}`
              : null,
            hidden: !user.is_blocked,
          },
        ]}
      />
    </div>
  )
}

// --- Projetos ----------------------------------------------------------------

function AbaProjetos({ userId }: { userId: string }) {
  const [page, setPage] = useState(1)
  const [perPage, setPerPage] = useState(DEFAULT_PER_PAGE)

  const projetos = useQuery({
    queryKey: ['user-memberships', userId, page, perPage],
    queryFn: () => usersApi.memberships(userId, { page, perPage }),
    // Mantém a página anterior enquanto a próxima carrega: sem isto a lista
    // pisca para vazio a cada clique e parece que acabou o dado.
    placeholderData: (anterior) => anterior,
  })

  if (projetos.isLoading) return <LoadingState label="Carregando projetos…" />
  if (projetos.isError) {
    return (
      <ErrorState
        description="Não foi possível carregar os projetos desta conta."
        onRetry={() => projetos.refetch()}
      />
    )
  }

  const { items = [], meta } = projetos.data ?? {}

  return (
    <div className="space-y-3">
      {items.length === 0 ? (
        <EmptyState
          title="Não participa de nenhum projeto"
          description="A participação é concedida na aba «Membros» do projeto."
        />
      ) : (
        <ul className="divide-y divide-border rounded-lg border border-border bg-card">
          {items.map((p) => (
            <li key={p.id} className="flex items-center gap-3 px-4 py-3">
              <FolderKanban aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="min-w-0 flex-1 truncate text-sm text-card-foreground">{p.name}</span>
              <Badge variant={p.is_active ? 'success' : 'secondary'}>{p.is_active ? 'Ativo' : 'Inativo'}</Badge>
            </li>
          ))}
        </ul>
      )}

      {meta && meta.totalPages > 1 && (
        <PaginationPill
          page={meta.page}
          totalPages={meta.totalPages}
          perPage={meta.perPage}
          onPageChange={setPage}
          onPerPageChange={(v) => { setPerPage(v); setPage(1) }}
          loading={projetos.isFetching}
        />
      )}

      {/* Ver a "divergência registrada" no cabeçalho: esta aba MOSTRA, não
          gerencia (DC-18). O texto existe para quem procura o botão de remover
          não concluir que ele foi esquecido. */}
      <p className="text-xs text-muted-foreground">
        Somente leitura. Para conceder ou revogar participação, use a aba «Membros» do projeto —
        é lá que valem as três condições de servidor (DEC-18.5).
      </p>
    </div>
  )
}

// --- Permissões ---------------------------------------------------------------

function AbaPermissoes({
  userId,
  podeEscrever,
  onChanged,
}: {
  userId: string
  podeEscrever: boolean
  onChanged: () => void
}) {
  const queryClient = useQueryClient()
  const chave = useMemo(() => ['user-permissions', userId], [userId])

  const permissoes = useQuery({
    queryKey: chave,
    queryFn: () => usersApi.permissions(userId),
    retry: false,
  })

  // **Este painel NÃO assina o `PermissionsChannel`, e é de propósito.**
  //
  // A primeira versão assinava com `{ user_id: userId }` — o id do ALVO. O canal
  // (corrigido nesta mesma fatia, flag U2) só entrega o fluxo do usuário da CONEXÃO e
  // rejeita qualquer outro: a assinatura seria recusada em silêncio, e ficaria aqui um
  // recurso que parece existir e nunca dispara. Foi exatamente o tipo de defeito que
  // esta migração passou o tempo todo desenterrando do legado.
  //
  // O que resta é suficiente para o caso real: depois da própria mutação o painel
  // invalida a consulta e relê. O caso de dois administradores mexendo na MESMA pessoa
  // ao mesmo tempo não é coberto — se um dia precisar ser, a saída é o canal aceitar
  // uma assinatura de terceiro sob a mesma trava de hierarquia do endpoint, e isso é
  // decisão de plataforma, não uma linha nesta tela.
  //
  // A tela `/permissions` (por PAPEL) assina normalmente: lá o fluxo é o do próprio
  // operador.

  const alterar = useMutation({
    mutationFn: ({ key, mudanca }: { key: string; mudanca: PermissionChange }) =>
      usersApi.setPermission(userId, key, mudanca),
    onSuccess: (_dado, { mudanca }) => {
      // FE-042/FE-043 — toast de sucesso **e** de erro. Na tela do legado o ramo
      // `else` era vazio: quando dava certo, nada acontecia visivelmente.
      //
      // DEC-108 — num teto, esvaziar o campo **remove a exceção desta pessoa** e
      // faz voltar a valer o do papel. Não é "sem limite": é "sem exceção".
      notify.success(
        'limit_value' in mudanca
          ? mudanca.limit_value === null || mudanca.limit_value === undefined
            ? 'Exceção de teto removida — volta a valer o do papel'
            : `Teto individual definido em ${mudanca.limit_value}`
          : mudanca.granted
            ? 'Permissão concedida'
            : 'Permissão revogada',
      )
      queryClient.invalidateQueries({ queryKey: chave })
      onChanged()
    },
    onError: (erro: any) => {
      const code = erro?.response?.data?.details?.code
      notify.error(
        code === 'HIERARCHY_LOCKED'
          ? 'Esta conta está acima do seu alcance de hierarquia.'
          : erro?.response?.data?.message || 'Não foi possível alterar a permissão.',
      )
    },
  })

  const status = (permissoes.error as any)?.response?.status
  const travadoPorHierarquia =
    status === 403 && (permissoes.error as any)?.response?.data?.details?.code === 'HIERARCHY_LOCKED'

  if (permissoes.isLoading) return <LoadingState label="Carregando permissões…" />

  if (travadoPorHierarquia) {
    // "Existe e você não pode mexer" é diferente de "não existe". Mostrar erro
    // genérico aqui faria o operador achar que a tela quebrou.
    return (
      <EmptyState
        title="Fora do seu alcance de hierarquia"
        description="Esta conta tem papel igual ou superior ao seu. Só quem está acima dela edita as permissões dela (DEC-18.2)."
      />
    )
  }

  if (permissoes.isError) {
    return <ErrorState description="Não foi possível carregar as permissões." onRetry={() => permissoes.refetch()} />
  }

  const lista = permissoes.data?.permissions ?? []

  return (
    <div className="space-y-3">
      <ul className="divide-y divide-border rounded-lg border border-border bg-card">
        {lista.map((p) => (
          <li key={p.key} className="flex items-start gap-4 px-4 py-3">
            <div className="min-w-0 flex-1">
              <label htmlFor={`perm-${p.key}`} className="block text-sm font-medium text-card-foreground">
                {p.title}
              </label>
              {p.description && <p className="mt-0.5 text-xs text-muted-foreground">{p.description}</p>}
            </div>
            {/* Toggle ou campo numérico conforme o `kind` do servidor (DEC-108). */}
            <PermissionControl
              row={p}
              idPrefix="perm"
              disabled={!podeEscrever || alterar.isPending}
              onChange={(mudanca) => alterar.mutate({ key: p.key, mudanca })}
            />
          </li>
        ))}
      </ul>

      {!podeEscrever && (
        <p className="text-xs text-muted-foreground">
          Seu perfil lê as permissões desta conta, mas não as altera (DEC-18.2).
        </p>
      )}

      {/* FE-513 — o que SUMIU, dito na tela para quem vem do legado procurar.
          Sem esta linha, "onde foram parar as outras dezesseis?" vira chamado. */}
      <p className="text-xs text-muted-foreground">
        Das 17 permissões do sistema antigo sobraram <span className="font-medium">sete</span> — as que de fato
        controlavam alguma coisa. As outras dez falavam de «Projetos» e «Módulos» genéricos e não eram consultadas
        em lugar nenhum. Quem decide o que cada pessoa alcança continua sendo o{' '}
        <span className="font-medium">papel</span> dela e a participação no projeto; o que está aqui é a{' '}
        <span className="font-medium">exceção</span> individual.
      </p>
    </div>
  )
}
