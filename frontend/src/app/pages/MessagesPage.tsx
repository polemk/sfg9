import { useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { Eye, MessageSquare, Plus, Send, Star, Trash2, UserPlus } from 'lucide-react'
import PageHeader from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { Checkbox } from '@/components/ui/Checkbox'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Select } from '@/components/ui/Select'
import { SearchInput } from '@/components/ui/SearchInput'
import { Textarea } from '@/components/ui/textarea'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { EmptyState } from '@/components/ui/States'
import { SideDrawer } from '@/components/SideDrawer'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { usePagination } from '@/hooks/usePagination'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import {
  adminMessagesApi,
  observersApi,
  type AdminMessage,
  type AdminMessageContext,
  type AdminMessageState,
  type Observer,
} from '@/lib/api/console'
import { cn } from '@/lib/utils'

/**
 * `/messages` — mensagens administrativas e observadores (FE-405, FE-528).
 *
 * ### Por que esta tela ganha item de menu
 *
 * No legado ela era **órfã**: existia, funcionava, e o `create_console_menu`
 * não a listava — só se chegava nela por URL decorada. Migrar a casca sem
 * listá-la repetiria a órfã no produto novo (decisão **DS2-1**). O item mora no
 * grupo "Admin" de `app/consoleNavigation.tsx`, gateado por OG e Admin.
 *
 * ### Duas correções observáveis, e uma NÃO-correção deliberada
 *
 * - **FE-407 — trocar filtro zera a página.** No legado o `offset` sobrevivia à
 *   troca de filtro, então filtrar estando na página 7 deixava o usuário numa
 *   página inexistente, com a lista vazia e nenhuma explicação.
 * - **BE-424 — o total respeita os filtros.** O `@total_count` do legado era
 *   `Message.all.count`: o total global, calculado antes dos filtros. A tela
 *   dizia "12 de 380".
 * - **DEC-73 — a inversão Concluído/Fechado é REPLICADA.** Pedir "Concluído"
 *   grava "Fechado"; a ação de encerrar grava "Concluído". A tela **mostra o
 *   estado que o servidor devolveu**, nunca o que ela pediu — é o que impede a
 *   interface de mentir sobre um comportamento que decidimos preservar.
 *
 * ### Cor de contexto sem cor literal
 *
 * O legado devolvia hex do servidor (`context.rb:41-47`: `#ffd4d6`, `#fdecd7`,
 * `#d9ffce`). Aqui o servidor manda a **chave** e a tela escolhe a variante do
 * `Badge` — token, que muda sozinho entre claro e escuro. Hex de servidor num
 * app de dois modos é um dos dois modos errado.
 */

const VARIANTE_DE_CONTEXTO: Record<AdminMessageContext, 'secondary' | 'negative' | 'info' | 'success'> = {
  other: 'secondary',
  problem: 'negative',
  contact: 'info',
  suggestion: 'success',
}

const VARIANTE_DE_SITUACAO: Record<AdminMessageState, 'default' | 'secondary' | 'success' | 'warning' | 'info'> = {
  unread: 'default',
  read: 'secondary',
  open: 'info',
  evaluated: 'info',
  answered: 'warning',
  done: 'success',
  closed: 'secondary',
  rejected: 'secondary',
}

const CONTEXTOS: { value: AdminMessageContext; label: string }[] = [
  { value: 'other', label: 'Outros' },
  { value: 'problem', label: 'Problema' },
  { value: 'contact', label: 'Contato' },
  { value: 'suggestion', label: 'Sugestão' },
]

const SITUACOES: { value: AdminMessageState; label: string }[] = [
  { value: 'unread', label: 'Não lido' },
  { value: 'read', label: 'Lido' },
  { value: 'open', label: 'Aberto' },
  { value: 'evaluated', label: 'Avaliado' },
  { value: 'answered', label: 'Respondido' },
  { value: 'done', label: 'Concluído' },
  { value: 'closed', label: 'Fechado' },
  { value: 'rejected', label: 'Rejeitado' },
]

export function MessagesPage() {
  const queryClient = useQueryClient()

  const [state, setState] = useState<AdminMessageState | ''>('')
  const [context, setContext] = useState<AdminMessageContext | ''>('')
  const { termo, consulta, setTermo, pendente } = useDebouncedSearch()
  const { page, perPage, setPage, setPerPage, reset } = usePagination()
  /**
   * 6.3.1 / IMP-A11 — **a mensagem aberta vive na URL**, não em memória.
   *
   * No legado o estado do console inteiro morava num objeto global JS
   * (`dashHolder`) e a URL era espelhada por `replaceState`, **nunca**
   * `pushState`: nenhuma tela era compartilhável por link e o botão Voltar
   * saía do console (D-92). Aqui `?message=<id>` abre a conversa carregada em
   * aba nova, e cada abertura entra no histórico do navegador.
   */
  const [searchParams, setSearchParams] = useSearchParams()
  const selecionada = searchParams.get('message') ? Number(searchParams.get('message')) : null
  const setSelecionada = (id: number | null) => {
    const proximos = new URLSearchParams(searchParams)
    if (id === null) proximos.delete('message')
    else proximos.set('message', String(id))
    setSearchParams(proximos)
  }
  const [novaAberta, setNovaAberta] = useState(false)
  const [observadorEmEdicao, setObservadorEmEdicao] = useState<Observer | 'novo' | null>(null)

  // FE-407: qualquer troca de filtro volta para a página 1.
  const trocarFiltro = (fn: () => void) => { fn(); reset() }

  const lista = useQuery({
    queryKey: ['admin-messages', { state, context, q: consulta, page, perPage }],
    queryFn: () => adminMessagesApi.list({ state, context, q: consulta, page, perPage }),
  })

  const detalhe = useQuery({
    queryKey: ['admin-message', selecionada],
    queryFn: () => adminMessagesApi.get(selecionada as number),
    enabled: selecionada !== null,
  })

  const observadores = useQuery({
    queryKey: ['observers'],
    queryFn: () => observersApi.list({ perPage: 50 }),
  })

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['admin-messages'] })
    if (selecionada) queryClient.invalidateQueries({ queryKey: ['admin-message', selecionada] })
  }

  const mudarSituacao = useMutation({
    mutationFn: ({ id, novoEstado }: { id: number; novoEstado: AdminMessageState }) =>
      adminMessagesApi.update(id, { state: novoEstado }),
    onSuccess: (m) => {
      invalidar()
      // O servidor é quem diz o estado final (DEC-73). Anunciar o que foi
      // PEDIDO faria a tela mentir sobre a inversão que preservamos.
      notify.success(`Situação: ${m.state_label}`)
    },
    onError: () => notify.error('Não foi possível mudar a situação.'),
  })

  const favoritar = useMutation({
    mutationFn: ({ id, valor }: { id: number; valor: boolean }) =>
      adminMessagesApi.update(id, { is_favorite: valor }),
    onSuccess: invalidar,
  })

  const responder = useMutation({
    mutationFn: ({ id, texto }: { id: number; texto: string }) => adminMessagesApi.addNote(id, texto),
    onSuccess: () => { invalidar(); notify.success('Resposta enviada.') },
    onError: () => notify.error('Não foi possível responder.'),
  })

  const remover = useMutation({
    mutationFn: (id: number) => adminMessagesApi.remove(id),
    onSuccess: () => { setSelecionada(null); invalidar(); notify.success('Mensagem removida.') },
  })

  const mensagens = lista.data?.items ?? []
  const meta = lista.data?.meta

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Mensagens"
        subtitle="Atendimento interno: tickets, respostas e quem é notificado."
        searchSlot={
          <SearchInput
            value={termo}
            onValueChange={(v) => trocarFiltro(() => setTermo(v))}
            loading={pendente}
            placeholder="Buscar por nome, e-mail ou texto…"
            aria-label="Buscar mensagens"
          />
        }
        rightSlot={
          <Button onClick={() => setNovaAberta(true)}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            Nova mensagem
          </Button>
        }
        loading={lista.isFetching && !lista.isPending}
      />

      <div className="grid gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        {/* ---- Coluna 1: mensagens ---------------------------------------- */}
        <section className="flex flex-col gap-4">
          <div className="flex flex-wrap items-center gap-3">
            <Select
              options={[{ value: '', label: 'Todas as situações' }, ...SITUACOES]}
              value={state}
              onChange={(v) => trocarFiltro(() => setState(v as AdminMessageState | ''))}
              block={false}
              size="sm"
              aria-label="Filtrar por situação"
              className="min-w-[12rem]"
            />
            <Select
              options={[{ value: '', label: 'Todos os contextos' }, ...CONTEXTOS]}
              value={context}
              onChange={(v) => trocarFiltro(() => setContext(v as AdminMessageContext | ''))}
              block={false}
              size="sm"
              aria-label="Filtrar por contexto"
              className="min-w-[12rem]"
            />
            {meta && (
              <span className="font-numeric text-xs text-muted-foreground">
                {meta.total} {meta.total === 1 ? 'mensagem' : 'mensagens'}
              </span>
            )}
          </div>

          <AsyncSection
            loading={lista.isPending}
            error={lista.error}
            data={mensagens}
            onRetry={() => lista.refetch()}
            loadingLabel="Carregando mensagens…"
            emptyTitle="Nenhuma mensagem"
            emptyDescription="Nada corresponde aos filtros aplicados."
          >
            {(itens) => (
              <ul className="flex flex-col gap-2">
                {itens.map((m) => (
                  <li key={m.id}>
                    <button
                      type="button"
                      onClick={() => setSelecionada(m.id === selecionada ? null : m.id)}
                      aria-expanded={m.id === selecionada}
                      className={cn(
                        'flex w-full items-start gap-3 rounded-lg border p-4 text-left transition-colors',
                        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                        m.id === selecionada
                          ? 'border-primary bg-accent'
                          : 'border-border bg-card hover:bg-accent/50',
                      )}
                    >
                      <UserAvatar name={m.sender_name} email={m.sender_email} colorKey={m.sender_email} size={36} />
                      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className={cn('truncate text-sm', m.is_read ? 'text-foreground' : 'font-semibold text-foreground')}>
                            {m.sender_name}
                          </span>
                          <Badge variant={VARIANTE_DE_CONTEXTO[m.context]}>{m.context_label}</Badge>
                          <Badge variant={VARIANTE_DE_SITUACAO[m.state]}>{m.state_label}</Badge>
                        </div>
                        <p className="line-clamp-2 text-sm text-muted-foreground">{m.message}</p>
                        <span className="font-numeric text-xs text-muted-foreground">
                          {new Date(m.created_at).toLocaleString('pt-BR')} · {m.notes_count} na conversa
                        </span>
                      </div>
                      {m.is_favorite && <Star aria-label="Favorita" className="h-4 w-4 shrink-0 text-primary" />}
                    </button>

                    {m.id === selecionada && (
                      <ThreadDaMensagem
                        mensagem={detalhe.data ?? m}
                        carregando={detalhe.isPending}
                        onSituacao={(novoEstado) => mudarSituacao.mutate({ id: m.id, novoEstado })}
                        onFavorito={() => favoritar.mutate({ id: m.id, valor: !m.is_favorite })}
                        onResponder={(texto) => responder.mutate({ id: m.id, texto })}
                        onRemover={() => remover.mutate(m.id)}
                        respondendo={responder.isPending}
                      />
                    )}
                  </li>
                ))}
              </ul>
            )}
          </AsyncSection>

          {meta && meta.totalPages > 1 && (
            <PaginationPill
              page={meta.page}
              totalPages={meta.totalPages}
              perPage={meta.perPage}
              onPageChange={setPage}
              onPerPageChange={setPerPage}
              loading={lista.isFetching}
            />
          )}
        </section>

        {/* ---- Coluna 2: observadores ------------------------------------ */}
        <section className="flex h-fit flex-col gap-3 rounded-lg border border-border bg-card p-4">
          <div className="flex items-center justify-between gap-2">
            <h2 className="flex items-center gap-2 font-title text-sm font-semibold text-foreground">
              <Eye aria-hidden="true" className="h-4 w-4 text-muted-foreground" />
              Observadores
            </h2>
            <Button variant="ghost" size="sm" onClick={() => setObservadorEmEdicao('novo')}>
              <UserPlus aria-hidden="true" className="h-4 w-4" />
              Novo
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Quem recebe e-mail quando chega mensagem nos contextos marcados.
          </p>

          <AsyncSection
            loading={observadores.isPending}
            error={observadores.error}
            data={observadores.data?.items ?? []}
            onRetry={() => observadores.refetch()}
            size="inline"
            loadingLabel="Carregando observadores…"
            emptyState={
              <EmptyState
                size="inline"
                title="Ninguém observando"
                description="Sem observador, mensagem nova não avisa ninguém por e-mail."
                action={<Button size="sm" onClick={() => setObservadorEmEdicao('novo')}>Cadastrar</Button>}
              />
            }
          >
            {(itens) => (
              <ul className="flex flex-col divide-y divide-border">
                {itens.map((o) => (
                  <li key={o.id}>
                    <button
                      type="button"
                      onClick={() => setObservadorEmEdicao(o)}
                      className="flex w-full items-center gap-3 py-3 text-left transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <UserAvatar name={o.name} email={o.email} colorKey={o.email} size={32} />
                      <div className="flex min-w-0 flex-1 flex-col">
                        <span className="truncate text-sm text-foreground">{o.name}</span>
                        <span className="truncate text-xs text-muted-foreground">{o.email}</span>
                      </div>
                      <span className="font-numeric text-xs text-muted-foreground">{o.contexts.length}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </AsyncSection>
        </section>
      </div>

      <NovaMensagemDrawer
        open={novaAberta}
        onClose={() => setNovaAberta(false)}
        onCreated={() => { setNovaAberta(false); invalidar() }}
      />

      <ObservadorDrawer
        alvo={observadorEmEdicao}
        onClose={() => setObservadorEmEdicao(null)}
        onSaved={() => { setObservadorEmEdicao(null); queryClient.invalidateQueries({ queryKey: ['observers'] }) }}
      />
    </div>
  )
}

// --- Thread ------------------------------------------------------------------

function ThreadDaMensagem({
  mensagem,
  carregando,
  onSituacao,
  onFavorito,
  onResponder,
  onRemover,
  respondendo,
}: {
  mensagem: AdminMessage
  carregando: boolean
  onSituacao: (s: AdminMessageState) => void
  onFavorito: () => void
  onResponder: (texto: string) => void
  onRemover: () => void
  respondendo: boolean
}) {
  const [texto, setTexto] = useState('')
  const notas = mensagem.notes ?? []

  return (
    <div className="mt-2 flex flex-col gap-4 rounded-lg border border-border bg-card p-4">
      <div className="flex flex-wrap items-center gap-2">
        <Select
          options={SITUACOES}
          value={mensagem.state}
          onChange={(v) => onSituacao(v as AdminMessageState)}
          block={false}
          size="sm"
          aria-label="Mudar situação"
          className="min-w-[11rem]"
        />
        <Button variant="ghost" size="sm" onClick={onFavorito}>
          <Star aria-hidden="true" className={cn('h-4 w-4', mensagem.is_favorite && 'text-primary')} />
          {mensagem.is_favorite ? 'Desfavoritar' : 'Favoritar'}
        </Button>
        <Button variant="ghost" size="sm" onClick={onRemover} className="ml-auto text-destructive">
          <Trash2 aria-hidden="true" className="h-4 w-4" />
          Remover
        </Button>
      </div>

      {(mensagem.extra1_enabled || mensagem.extra2_enabled) && (
        <dl className="grid gap-2 rounded-md bg-muted p-3 text-sm sm:grid-cols-2">
          {mensagem.extra1_enabled && (
            <div>
              <dt className="text-xs uppercase tracking-wider text-muted-foreground">{mensagem.extra1_label}</dt>
              <dd className="text-foreground">{mensagem.extra1_value}</dd>
            </div>
          )}
          {mensagem.extra2_enabled && (
            <div>
              <dt className="text-xs uppercase tracking-wider text-muted-foreground">{mensagem.extra2_label}</dt>
              <dd className="text-foreground">{mensagem.extra2_value}</dd>
            </div>
          )}
        </dl>
      )}

      <AsyncSection
        loading={carregando}
        data={notas}
        size="inline"
        loadingLabel="Carregando a conversa…"
        emptyTitle="Conversa vazia"
      >
        {(itens) => (
          <ol className="flex flex-col gap-3">
            {itens.map((n) => (
              <li
                key={n.id}
                className={cn(
                  'flex max-w-[85%] flex-col gap-1 rounded-lg border p-3 text-sm',
                  n.from_admin
                    ? 'ml-auto border-primary/40 bg-accent text-foreground'
                    : 'border-border bg-muted text-foreground',
                )}
              >
                <span className="text-xs font-semibold text-muted-foreground">{n.author_name}</span>
                <p className="whitespace-pre-wrap">{n.description}</p>
                <span className="font-numeric text-[11px] text-muted-foreground">
                  {new Date(n.created_at).toLocaleString('pt-BR')}
                </span>
              </li>
            ))}
          </ol>
        )}
      </AsyncSection>

      <form
        className="flex items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          if (!texto.trim()) return
          onResponder(texto.trim())
          setTexto('')
        }}
      >
        <div className="flex-1">
          <Label htmlFor="resposta" className="sr-only">Resposta</Label>
          <Textarea
            id="resposta"
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            maxLength={500}
            rows={2}
            placeholder="Responder…"
          />
        </div>
        <Button type="submit" loading={respondendo} disabled={!texto.trim()}>
          <Send aria-hidden="true" className="h-4 w-4" />
          Enviar
        </Button>
      </form>
    </div>
  )
}

// --- Nova mensagem -----------------------------------------------------------

function NovaMensagemDrawer({ open, onClose, onCreated }: { open: boolean; onClose: () => void; onCreated: () => void }) {
  const [mensagem, setMensagem] = useState('')
  const [context, setContext] = useState<AdminMessageContext>('other')

  const criar = useMutation({
    mutationFn: () => adminMessagesApi.create({ message: mensagem.trim(), context }),
    onSuccess: () => { setMensagem(''); setContext('other'); onCreated(); notify.success('Mensagem enviada.') },
    onError: (e: any) => notify.error(e?.response?.data?.error ?? 'Não foi possível enviar.'),
  })

  const restantes = 500 - mensagem.length

  return (
    <SideDrawer
      open={open}
      onClose={onClose}
      title="Nova mensagem"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>Cancelar</Button>
          <Button onClick={() => criar.mutate()} loading={criar.isPending} disabled={!mensagem.trim()}>
            <MessageSquare aria-hidden="true" className="h-4 w-4" />
            Enviar
          </Button>
        </div>
      }
    >
      <div className="flex flex-col gap-4">
        {/* DEC-40: o envio é autenticado. Nome e e-mail vêm da sessão — no
            legado eram campos livres num endpoint efetivamente público. */}
        <p className="text-sm text-muted-foreground">
          A mensagem sai identificada com o seu nome e o seu e-mail de acesso.
        </p>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="context">Contexto</Label>
          <Select
            id="context"
            options={CONTEXTOS}
            value={context}
            onChange={(v) => setContext(v as AdminMessageContext)}
          />
        </div>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="mensagem">Mensagem</Label>
          <Textarea
            id="mensagem"
            value={mensagem}
            onChange={(e) => setMensagem(e.target.value)}
            maxLength={500}
            rows={7}
            placeholder="Descreva o que aconteceu…"
          />
          {/* O limite é o MESMO no banco, no servidor e aqui. No legado a
              coluna era string(255) e a validação aceitava 500: tudo entre os
              dois era truncado em silêncio. */}
          <span className="font-numeric text-xs text-muted-foreground">{restantes} caracteres restantes</span>
        </div>
      </div>
    </SideDrawer>
  )
}

// --- Observador --------------------------------------------------------------

function ObservadorDrawer({
  alvo,
  onClose,
  onSaved,
}: {
  alvo: Observer | 'novo' | null
  onClose: () => void
  onSaved: () => void
}) {
  const editando = alvo && alvo !== 'novo' ? alvo : null
  const chave = editando?.id ?? 'novo'

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [isInternal, setIsInternal] = useState(true)
  const [contexts, setContexts] = useState<AdminMessageContext[]>([])
  const [carregado, setCarregado] = useState<string | number | null>(null)

  // Sincroniza o formulário quando o alvo muda. `useState` + comparação de
  // chave em vez de `useEffect`: evita o piscar do valor antigo no primeiro
  // render do drawer.
  if (alvo && carregado !== chave) {
    setCarregado(chave)
    setName(editando?.name ?? '')
    setEmail(editando?.email ?? '')
    setIsInternal(editando?.is_internal ?? true)
    setContexts(editando?.contexts ?? [])
  }

  const salvar = useMutation({
    mutationFn: () =>
      editando
        ? observersApi.update(editando.id, { name, email, is_internal: isInternal, contexts })
        : observersApi.create({ name, email, is_internal: isInternal, contexts }),
    onSuccess: () => { setCarregado(null); onSaved(); notify.success('Observador salvo.') },
    onError: (e: any) => notify.error(e?.response?.data?.error ?? 'Não foi possível salvar.'),
  })

  const remover = useMutation({
    mutationFn: () => observersApi.remove((editando as Observer).id),
    onSuccess: () => { setCarregado(null); onSaved(); notify.success('Observador removido.') },
  })

  const alternar = (c: AdminMessageContext) =>
    setContexts((atual) => (atual.includes(c) ? atual.filter((x) => x !== c) : [...atual, c]))

  const podeSalvar = useMemo(
    () => name.trim().length > 0 && email.trim().length > 0 && contexts.length > 0,
    [name, email, contexts],
  )

  return (
    <SideDrawer
      open={alvo !== null}
      onClose={() => { setCarregado(null); onClose() }}
      title={editando ? 'Editar observador' : 'Novo observador'}
      footer={
        <div className="flex items-center justify-between gap-2">
          {editando ? (
            <Button variant="ghost" onClick={() => remover.mutate()} loading={remover.isPending} className="text-destructive">
              <Trash2 aria-hidden="true" className="h-4 w-4" />
              Remover
            </Button>
          ) : <span />}
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => { setCarregado(null); onClose() }}>Cancelar</Button>
            <Button onClick={() => salvar.mutate()} loading={salvar.isPending} disabled={!podeSalvar}>Salvar</Button>
          </div>
        </div>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="obs-nome">Nome</Label>
          <Input id="obs-nome" value={name} onChange={(e) => setName(e.target.value)} placeholder="Nome do observador" />
        </div>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="obs-email">E-mail</Label>
          <Input id="obs-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nome@empresa.com.br" />
        </div>

        <Checkbox
          checked={isInternal}
          onChange={(e) => setIsInternal(e.target.checked)}
          label="Recebe também mensagens internas"
          description="Desmarcado, o observador só é avisado de mensagens vindas de fora."
        />

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-sm font-medium text-foreground">Contextos observados</legend>
          {/* No legado o rótulo deste bloco era um copy-paste do campo de cima
              ("Seu nome"), e nada dizia que a escolha era obrigatória. */}
          <p className="mb-1 text-xs text-muted-foreground">
            Ao menos um. Sem contexto marcado, o observador nunca é notificado.
          </p>
          {CONTEXTOS.map((c) => (
            <Checkbox
              key={c.value}
              checked={contexts.includes(c.value)}
              onChange={() => alternar(c.value)}
              label={c.label}
            />
          ))}
        </fieldset>
      </div>
    </SideDrawer>
  )
}
