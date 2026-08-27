import { useEffect, useMemo, useRef, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Search, Filter, Eye, Pencil, Trash2, Plus, MoreHorizontal, Mail, Phone, Upload, Check, Loader2, UserCheck, Lock, Unlock } from 'lucide-react'
import PageHeader from '@/components/PageHeader'
import { usersApi } from '@/lib/api/endpoints'
import { apiClient } from '@/lib/api/client'
import { User } from '@/lib/api/types'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { PhoneInputGroup } from '@/components/PhoneInputGroup'
import { useAuthStore } from '@/store/authStore'
import { notify } from '@/lib/notify'
import { SideDrawer } from '@/components/SideDrawer'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { ReasonDialog } from '@/features/auth/ReasonDialog'
import { impersonateApi } from '@/lib/api/endpoints'
import type { SafegoldRole, UserStats } from '@/lib/api/types'

/**
 * `/users` — contas do Safegold.
 *
 * **O DADO FALSO SAIU (FE-011 / IMP-A27 / U11).**
 *
 * Esta tela servia um array `mockUsers` hardcoded — nove pessoas inventadas, com
 * papéis `client` que nem existem mais (DEC-41) — sempre que o usuário logado fosse
 * visitante ou cliente. Num sistema de crédito isso é inaceitável: quem abrisse a tela
 * veria uma base de usuários que não é a dele, sem nenhum sinal de que era exemplo, e
 * tomaria decisão em cima. Agora a tela chama a API; quem não tem permissão recebe
 * 403 e vê um estado vazio explícito, que é a informação verdadeira.
 */

export function UsersPage() {
  const [users, setUsers] = useState<User[]>([])
  // DEC-136 — o avatar escolhido na criação, à espera do id.
  const [avatarPendente, setAvatarPendente] = useState<File | null>(null)
  const [total, setTotal] = useState(0)
  const [totalPages, setTotalPages] = useState(1)
  const [page, setPage] = useState(1)
  const [perPage, setPerPage] = useState(20)
  const [q, setQ] = useState('')
  // Termo com debounce de 300 ms (FE-012). Sem ele cada tecla vira uma requisição, e
  // a resposta mais lenta chega por último e sobrescreve o resultado mais recente.
  const [debouncedQ, setDebouncedQ] = useState('')
  const [type, setType] = useState<'all' | SafegoldRole>('all')
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [statsData, setStatsData] = useState<UserStats | null>(null)
  const [impersonateTarget, setImpersonateTarget] = useState<User | null>(null)
  const [blockTarget, setBlockTarget] = useState<User | null>(null)

  // --- FE-018 — o drawer é DERIVADO DA URL, não de um `useState` -------------
  //
  // `/users/new` e `/users/:id/edit` são rotas de verdade (registradas como filhas
  // de `/users` em `consoleNavigation.tsx`). Isso dá três coisas que o estado local
  // não dava: o endereço é copiável e recarregável, o botão Voltar fecha o drawer em
  // vez de sair do console, e o gate de papel da área vale para quem digita a URL.
  //
  // No legado o mesmo efeito era `history.replaceState` — que **substitui** a
  // entrada do histórico em vez de empilhar, e por isso Voltar saltava a lista
  // inteira (mesma família do D-92).
  const navigate = useNavigate()
  const location = useLocation()
  const { id: idDaRota } = useParams<{ id: string }>()
  const criando = location.pathname.endsWith('/users/new')
  const editando = Boolean(idDaRota) && location.pathname.endsWith('/edit')
  const sideOpen = criando || editando

  const [sideMounted, setSideMounted] = useState(false)
  const [sideVisible, setSideVisible] = useState(false)
  const [editingUser, setEditingUser] = useState<Partial<User> | null>(null)
  // Erro POR CAMPO (FE-021). Antes, toda falha virava um `toast` único com a
  // mensagem concatenada do servidor: o operador lia "Email já está em uso, CPF
  // inválido" e tinha de adivinhar onde clicar. Um `toast` some em 4 segundos; a
  // mensagem embaixo do campo fica até ele consertar.
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const currentUser = useAuthStore((s) => s.user)
  // **Os mesmos portões do servidor** (FE-016). A matriz do DEC-18: OG e Admin fazem
  // CRUD de contas, Gerente só lê, Colaborador não alcança a tela. O legado mostrava
  // "Ver como" para qualquer papel e só permitia para alguns — botão que aparece e
  // não funciona é pior que botão ausente.
  const role = (currentUser?.user_type_slug || '').toLowerCase()
  const canWrite = role === 'og' || role === 'admin'
  const canImpersonate = canWrite

  // Os 4 papéis do Safegold (DEC-41). `client`, `visitor` e `free` não existem mais.
  const badgeClassForType = (_type?: string, typeSlug?: string) => {
    switch ((typeSlug || '').toLowerCase()) {
      case 'og': return 'bg-success/10 text-success border-success/30'
      case 'admin': return 'bg-primary/15 text-primary border-primary/30'
      case 'gerente': return 'bg-warning/10 text-warning border-warning/30'
      default: return 'bg-muted text-muted-foreground border-border'
    }
  }


  const fetchUsers = async () => {
    setLoading(true)
    setLoadError(null)
    try {
      const resp = await usersApi.list({
        page,
        perPage,
        q: debouncedQ || undefined,
        type: type === 'all' ? undefined : type
      })
      setUsers(resp.users)
      setTotal(resp.total)
      setTotalPages(resp.total_pages || 1)
    } catch (error: any) {
      // **Erro visível.** Antes o `catch` zerava a lista em silêncio, e "sem
      // permissão" ficava idêntico a "nenhuma conta cadastrada".
      setUsers([])
      setTotal(0)
      setLoadError(
        error?.response?.status === 403
          ? 'Seu perfil não tem acesso à lista de contas.'
          : (error?.response?.data?.message || 'Não foi possível carregar as contas.')
      )
    } finally {
      setLoading(false)
    }
  }

  const fetchStats = async () => {
    try {
      setStatsData(await usersApi.stats())
    } catch { /* o card cai para a contagem local da página */ }
  }

  // Debounce de 300 ms + reset de página (FE-012). O reset é obrigatório: buscar
  // estando na página 4 devolvia vazio e parecia "nada encontrado".
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedQ(q)
      setPage(1)
    }, 300)
    return () => clearTimeout(timer)
  }, [q])

  useEffect(() => {
    fetchUsers()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, perPage, type, debouncedQ])

  useEffect(() => {
    fetchStats()
  }, [])

  // --- DEC-39 — bloquear / desbloquear -------------------------------------
  //
  // O motivo é pedido num diálogo do design system, não em `window.prompt`: o prompt
  // nativo ignora o tema (some no modo escuro), é bloqueado em navegador headless — o
  // que impedia conferir o fluxo pela tela — e não valida nada antes de enviar.
  const handleUnblock = async (user: User) => {
    try {
      await usersApi.unblock(user.id)
      notify.success(`${user.name} desbloqueado`)
      fetchUsers()
    } catch (error: any) {
      notify.error(error?.response?.data?.message || 'Não foi possível desbloquear')
    }
  }

  const handleBlock = async (user: User, reason: string) => {
    try {
      await usersApi.block(user.id, reason)
      notify.success(`${user.name} bloqueado — a sessão ativa dele caiu agora`)
      fetchUsers()
    } catch (error: any) {
      notify.error(error?.response?.data?.message || 'Não foi possível bloquear')
    }
  }

  const handleImpersonate = async (user: User, reason: string) => {
    try {
      const data = await impersonateApi.start(user.id, reason)
      useAuthStore.getState().startImpersonation(data.access_token, data.impersonated_user as any)
      window.location.href = '/dashboard'
    } catch (error: any) {
      notify.error(error?.response?.data?.message || 'Não foi possível iniciar a impersonação')
    }
  }

  // **`client_count` saiu do contrato.** O backend devolve `by_role` (DEC-41: os
  // papéis são OG, Admin, Gerente, Colaborador; `client` não existe mais). O alias
  // depreciado foi removido do `UsersService.stats` no MESMO passo desta tela —
  // Regra de fronteira: quem remove o campo migra o consumidor.
  const stats = useMemo(() => ({
    total: statsData?.total ?? total,
    active: statsData?.active ?? users.filter((u) => !!u.last_login_at).length,
    recent: statsData?.recent ?? users.filter((u) => {
      if (!u.created_at) return false
      const created = new Date(u.created_at).getTime()
      const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
      return created >= sevenDaysAgo
    }).length,
    og: statsData?.by_role?.og ?? statsData?.og_count ?? 0,
    admin: statsData?.by_role?.admin ?? 0,
    gerente: statsData?.by_role?.gerente ?? 0,
    colaborador: statsData?.by_role?.colaborador ?? 0
  }), [statsData, total, users])

  // Abrir e fechar = NAVEGAR. Nenhum `setSideOpen` sobrou: um segundo caminho para
  // abrir o mesmo drawer é o começo de "abriu pela URL e o formulário veio vazio".
  const openCreate = () => navigate('/users/new')
  const openEdit = (user: User) => navigate(`/users/${user.id}/edit`)
  /** "Visualizar" agora é a TELA de detalhe (FE-022), com as abas e o painel de permissões. */
  const openView = (user: User) => navigate(`/users/${user.id}`)
  const closeDrawer = () => navigate('/users')

  // Preenche o formulário a partir da rota.
  //
  // Ordem importa: a lista já carregada é a fonte preferida (abertura instantânea);
  // quem chegou por URL colada não tem lista ainda, e aí busca no servidor. Sem o
  // segundo caminho, recarregar em `/users/42/edit` abriria um formulário em branco
  // e o `PATCH` gravaria vazio por cima — falha silenciosa, a pior classe.
  useEffect(() => {
    if (criando) {
      // Nasce Colaborador — o papel de MENOS poder. Nunca Admin fixo (D-39).
      setEditingUser({ user_type: 'colaborador' })
      setFieldErrors({})
      return
    }
    if (!editando || !idDaRota) {
      setEditingUser(null)
      setFieldErrors({})
      return
    }
    setFieldErrors({})
    const daLista = users.find((u) => String(u.id) === String(idDaRota))
    if (daLista) {
      setEditingUser(daLista)
      return
    }
    let cancelado = false
    usersApi.get(idDaRota)
      .then((u) => { if (!cancelado) setEditingUser(u) })
      .catch(() => {
        if (cancelado) return
        notify.error('Não foi possível abrir esta conta.')
        navigate('/users', { replace: true })
      })
    return () => { cancelado = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [criando, editando, idDaRota, users])

  useEffect(() => {
    if (sideOpen) {
      setSideMounted(true)
      setSideVisible(false)
      const t = setTimeout(() => setSideVisible(true), 0)
      return () => clearTimeout(t)
    }
    setSideVisible(false)
    const t = setTimeout(() => setSideMounted(false), 200)
    return () => clearTimeout(t)
  }, [sideOpen])

  useEffect(() => {
    if (!sideOpen) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeDrawer()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [sideOpen])

  const [confirmOpen, setConfirmOpen] = useState(false)
  const [confirmTarget, setConfirmTarget] = useState<User | null>(null)
  const askDelete = (user: User) => { setConfirmTarget(user); setConfirmOpen(true) }
  const confirmDelete = async () => {
    if (!confirmTarget) return
    try { await usersApi.delete(confirmTarget.id) } finally { setConfirmOpen(false); setConfirmTarget(null); fetchUsers() }
  }

  const [saving, setSaving] = useState(false)

  /**
   * Validação de FORMULÁRIO, por campo (FE-021).
   *
   * O servidor continua sendo quem decide — isto só evita a ida quando o erro é
   * óbvio, e coloca a mensagem **embaixo do campo errado**. A regra que importa:
   * um campo inválido não trava os outros; o `save` reprova, aponta e o operador
   * corrige um por vez.
   */
  const validarCampos = (): Record<string, string> => {
    const erros: Record<string, string> = {}
    const nome = (editingUser?.name || '').trim()
    const email = (editingUser?.email || '').trim()
    const fone = (editingUser?.phone || '').replace(/\D/g, '')

    if (!nome) erros.name = 'Informe o nome.'
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) erros.email = 'E-mail inválido.'
    // DEC-14 — e-mail e telefone são os dois canais de entrega do código de acesso.
    // Uma conta sem nenhum dos dois é uma conta que **nunca consegue entrar**, e o
    // legado deixava criar exatamente isso.
    if (!email && !fone) {
      erros.email = 'Informe e-mail ou telefone — é por onde o código de acesso chega.'
      erros.phone = 'Informe e-mail ou telefone — é por onde o código de acesso chega.'
    }
    if (fone && (fone.length < 10 || fone.length > 15)) erros.phone = 'Telefone deve ter de 10 a 15 dígitos.'
    return erros
  }

  /**
   * Traduz a resposta de erro do servidor para o campo certo.
   *
   * O Grape devolve formas diferentes conforme a origem (validação do model, do
   * endpoint, ou `ActiveRecord::RecordInvalid`), e a versão anterior desta tela
   * concatenava tudo num `toast` só. Aqui a mensagem é lida uma vez e roteada:
   * o que casa com um campo conhecido vira erro daquele campo; o que sobra vira
   * toast — porque erro sem lugar visível é erro que o operador não vê.
   */
  const distribuirErros = (data: any): { campos: Record<string, string>; resto: string | null } => {
    const campos: Record<string, string> = {}
    const pedacos: string[] = []

    const empilhar = (v: any) => {
      if (!v) return
      if (typeof v === 'string') pedacos.push(v)
      else if (Array.isArray(v)) v.forEach(empilhar)
      else if (typeof v === 'object') {
        // `{ email: ["já está em uso"] }` — o formato do `RecordInvalid`.
        Object.entries(v).forEach(([chave, valor]) => {
          const texto = Array.isArray(valor) ? valor.join(', ') : String(valor)
          if (['name', 'email', 'phone', 'user_type'].includes(chave)) campos[chave] = texto
          else empilhar(valor)
        })
      }
    }

    empilhar(data?.errors)
    empilhar(data?.error?.message ?? (typeof data?.error === 'string' ? data.error : null))
    empilhar(data?.message)

    const resto = pedacos.filter(Boolean).join(' · ') || null
    // Heurística de último recurso: o backend costuma devolver uma frase única
    // ("Email já está em uso"). Se ela nomeia um campo, ela pertence ao campo.
    if (resto && Object.keys(campos).length === 0) {
      const baixo = resto.toLowerCase()
      if (baixo.includes('mail')) campos.email = resto
      else if (baixo.includes('telefone') || baixo.includes('phone')) campos.phone = resto
      else if (baixo.includes('nome')) campos.name = resto
    }
    return { campos, resto: Object.keys(campos).length > 0 ? null : resto }
  }

  const handleSave = async () => {
    if (!editingUser) return

    const erros = validarCampos()
    setFieldErrors(erros)
    if (Object.keys(erros).length > 0) return

    setSaving(true)
    const payload: any = {
      email: editingUser.email,
      name: editingUser.name,
      phone: editingUser.phone,
      // `avatar_url` SAIU do payload (S13/OPS-493): o avatar é anexo, e o valor
      // aqui é uma URL assinada com prazo. Gravá-la na coluna faria o avatar
      // expirar sozinho. Quem escreve é `POST /api/v1/users/:id/avatar`.
      user_type_id: editingUser.user_type_id,
      user_type: editingUser.user_type,
      user_type_slug: editingUser.user_type,
    }

    const editedId = editingUser.id
    try {
      if (editingUser.id) {
        const updated = await usersApi.update(editingUser.id, payload)
        if (currentUser && editedId && currentUser.id === editedId) {
          const { setUser } = useAuthStore.getState()
          setUser && setUser({ ...(currentUser as any), avatar_url: updated.avatar_url })
        }
        notify.success('Conta atualizada')
      } else {
        const criada = await usersApi.create(payload)
        // **DEC-136 — o segundo passo do avatar.**
        //
        // Falhar aqui NÃO desfaz o cadastro, e a mensagem é `warning`: o que
        // aconteceu foi um sucesso parcial. Dizer "erro" faria a pessoa achar
        // que precisa cadastrar de novo — que é o que produziria a conta
        // duplicada, com um convite a mais enviado.
        if (avatarPendente && criada?.id) {
          try {
            const form = new FormData()
            form.append('file', avatarPendente)
            await apiClient.post(`/api/v1/users/${criada.id}/avatar`, form, {
              headers: { 'Content-Type': 'multipart/form-data' },
            })
          } catch {
            notify.warning('A conta foi criada, mas a foto não subiu. Envie pela edição.')
          }
        }
        setAvatarPendente(null)
        // D-38 — o convite é a única porta de entrada, e ele NÃO carrega senha.
        notify.success('Conta criada. O convite com o link de primeiro acesso foi enviado.')
      }
      setFieldErrors({})
      closeDrawer()
      fetchUsers()
    } catch (error: any) {
      const { campos, resto } = distribuirErros(error?.response?.data)
      setFieldErrors(campos)
      if (resto) notify.error(resto, { duration: 5000 })
      else if (Object.keys(campos).length === 0) notify.error('Não foi possível salvar a conta.')
    } finally {
      setSaving(false)
    }
  }

  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const [, setUploading] = useState(false)
  // S13 / OPS-493 — mesmo motor de anexos do ProfilePage.
  //
  // Uma diferença de comportamento que é consequência do desenho e está aqui de
  // propósito: o anexo pertence ao registro, então **o usuário precisa existir**
  // para receber avatar. No caminho antigo o arquivo era gravado solto em
  // `public/uploads` e a URL viajava como string no payload de criação — era por
  // isso que "funcionava" antes de salvar, e é a mesma razão pela qual o arquivo
  // ficava órfão quando a criação falhava. O aviso diz o que fazer.
  //
  // O `if (file.size > 2MB)` local saiu (e ele nem avisava — dava `return` mudo).
  // O limite agora é o do servidor, que também o aplica de verdade.
  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return

    // **DEC-136 — na CRIAÇÃO o arquivo fica pendente.**
    //
    // Antes recusava com "salve o usuário antes de enviar a foto": o anexo
    // pertence ao registro e precisa de um id. O legado aceitava já no
    // cadastro, e a decisão mandou voltar a aceitar.
    //
    // A prévia é local (`URL.createObjectURL`) e nada vai à rede — não há a
    // quem anexar. O envio acontece depois que o POST devolve o id, e falhar lá
    // NÃO desfaz o cadastro.
    //
    // Isto **não** é o caminho antigo do legado, e a diferença importa: lá o
    // arquivo era gravado solto em `public/uploads` e a URL viajava como string
    // no payload — por isso ficava órfão quando a criação falhava. Aqui ele só
    // sai da máquina quando existe registro para recebê-lo.
    if (!editingUser?.id) {
      setAvatarPendente(file)
      setEditingUser({ ...(editingUser || {}), avatar_url: URL.createObjectURL(file) })
      return
    }

    setUploading(true)
    try {
      const form = new FormData()
      form.append('file', file)
      const data = await apiClient.post<{ avatar_url: string }>(
        `/api/v1/users/${editingUser.id}/avatar`,
        form,
        { headers: { 'Content-Type': 'multipart/form-data' } }
      )
      setEditingUser({ ...(editingUser || {}), avatar_url: data.avatar_url })
      if (currentUser && currentUser.id === editingUser.id) {
        const { setUser } = useAuthStore.getState()
        setUser && setUser({ ...(currentUser as any), avatar_url: data.avatar_url })
      }
      fetchUsers()
    } catch (error: any) {
      notify.error(error?.response?.data?.message || 'Erro ao enviar avatar')
    }
    setUploading(false)
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Usuários"
        subtitle="Gerencie contas e perfis"
        rightSlot={canWrite ? (
          <Button onClick={openCreate} variant="primary" className="px-3.5 py-1.5">
            <span className="inline-flex items-center gap-1">
              <Plus className="h-4 w-4" /> USUÁRIO
            </span>
          </Button>
        ) : undefined}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        <div className="p-4 bg-card border border-border rounded-lg shadow-e1"><p className="text-sm text-muted-foreground">Total</p><p className="text-2xl font-bold font-numeric text-foreground">{stats.total}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg shadow-e1"><p className="text-sm text-muted-foreground">Ativos</p><p className="text-2xl font-bold font-numeric text-foreground">{stats.active}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg shadow-e1"><p className="text-sm text-muted-foreground">Novos (7d)</p><p className="text-2xl font-bold font-numeric text-foreground">{stats.recent}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg shadow-e1"><p className="text-sm text-muted-foreground">OG</p><p className="text-2xl font-bold font-numeric text-foreground">{stats.og}</p></div>
        <div className="p-4 bg-card border border-border rounded-lg shadow-e1"><p className="text-sm text-muted-foreground">Colaboradores</p><p className="text-2xl font-bold font-numeric text-foreground">{stats.colaborador}</p></div>
      </div>

      <div className="flex gap-3 items-center">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por nome, e-mail, telefone, usuário ou código"
            className="pl-9"
          />
        </div>
        <div className="flex items-center gap-2">
          <Filter className="h-4 w-4 text-muted-foreground" />
          <Select
            className="min-w-[140px]"
            block={false}
            aria-label="Filtrar por tipo de usuário"
            value={type}
            onChange={(v) => setType(v as any)}
            options={[
              { value: 'all', label: 'Todos' },
              { value: 'og', label: 'OG' },
              { value: 'admin', label: 'Admin' },
              { value: 'gerente', label: 'Gerente' },
              { value: 'colaborador', label: 'Colaborador' },
            ]}
          />
        </div>
      </div>

      {loading && <LoadingState label="Carregando contas…" />}

      {!loading && loadError && (
        <ErrorState description={loadError} onRetry={fetchUsers} />
      )}

      {!loading && !loadError && users.length === 0 && (
        <EmptyState
          title="Nenhuma conta encontrada"
          description={debouncedQ ? `Nada casa com "${debouncedQ}".` : 'Convide alguém para começar.'}
        />
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {!loading && !loadError && users.map((u, index) => (
          <div
            key={u.id}
            style={{ zIndex: users.length - index, position: 'relative' }}
            className={`p-4 glass-panel rounded-lg flex items-center justify-between cursor-pointer transition-colors hover:border-border ${u.is_blocked ? 'opacity-70' : ''}`}
            onClick={() => (canWrite ? openEdit(u) : openView(u))}
          >
            <div className="flex items-center gap-2">
              {/* FE-427: `UserAvatar` com `colorKey` no lugar do dicebear. O
                  serviço externo sorteava a cor pelo hash do NOME — cor fora
                  da marca, e o nome do usuário saindo do domínio numa query
                  string. Aqui o tom vem do id e é estável entre renders. */}
              <UserAvatar name={u.name} email={u.email} src={u.avatar_url} colorKey={u.id} size={40} />
              <div>
                <p className="text-foreground font-medium">{u.name}</p>
                <div className="my-0.5 flex flex-wrap items-center gap-1">
                  {u.user_type && (
                    <span className={`px-2 py-0.5 text-xs rounded-md border ${badgeClassForType(u.user_type, u.user_type_slug)}`}>
                      {(u.user_type || '').toUpperCase()}
                    </span>
                  )}
                  {/* DEC-39 — sem este selo, bloquear é uma ação sem confirmação
                      visível: o operador clica e a lista continua igual. */}
                  {u.is_blocked && (
                    <span className="rounded-md border border-destructive/30 bg-destructive/10 px-2 py-0.5 text-xs text-destructive">
                      BLOQUEADA
                    </span>
                  )}
                  {u.is_default_member && (
                    <span className="rounded-md border border-border bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                      MEMBRO PADRÃO
                    </span>
                  )}
                  {u.identifier && (
                    <span className="rounded-md border border-border bg-muted px-2 py-0.5 font-mono text-xs text-muted-foreground">
                      {u.identifier}
                    </span>
                  )}
                </div>
                <p className="text-xs text-muted-foreground flex items-center gap-1 my-0.5">
                  {u.email && (
                    <span className="inline-flex items-center gap-1"><Mail className="h-3 w-3" />{u.email}</span>
                  )}
                  {u.email && u.phone && <span className="mx-1">•</span>}
                  {u.phone && (
                    <span className="inline-flex items-center gap-1"><Phone className="h-3 w-3" />{u.phone}</span>
                  )}
                </p>
                <p className="text-xs text-muted-foreground">
                  {u.last_login_at
                    ? `Último login: ${new Date(u.last_login_at).toLocaleDateString('pt-BR')}`
                    : 'Nunca logou'}
                </p>
              </div>
            </div>
            <div className="relative" onClick={(e) => e.stopPropagation()}>
              <MenuActions
                canWrite={canWrite}
                canImpersonate={canImpersonate && !u.is_blocked && u.id !== currentUser?.id}
                isBlocked={!!u.is_blocked}
                onView={() => openView(u)}
                onEdit={() => openEdit(u)}
                onImpersonate={() => setImpersonateTarget(u)}
                onToggleBlock={() => (u.is_blocked ? handleUnblock(u) : setBlockTarget(u))}
                onDelete={() => askDelete(u)}
              />
            </div>
          </div>
        ))}
      </div>
      <SideDrawer
        open={sideOpen}
        onClose={closeDrawer}
        title={editingUser?.id ? 'Editar conta' : 'Criar conta'}
        footer={
          <Button onClick={handleSave} variant="primary" className="w-full" disabled={saving}>
            {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : (editingUser?.id ? <Check className="mr-2 h-4 w-4" /> : <Plus className="mr-2 h-4 w-4" />)}
            {saving ? 'Salvando…' : (editingUser?.id ? 'Salvar alterações' : 'Criar e convidar')}
          </Button>
        }
      >
        {/* O drawer é SÓ de escrita agora. "Visualizar" virou a tela `/users/:id`,
            com as abas Geral / Projetos / Permissões (FE-022) — antes era este
            mesmo drawer em modo leitura, sem permissões e sem paginação. */}
        <div className="space-y-6">
          <div className="flex flex-col items-center gap-2">
            <div className="relative">
              <div
                className="h-24 w-24 cursor-pointer overflow-hidden rounded-full border border-border bg-muted"
                onClick={() => fileInputRef.current?.click()}
              >
                {editingUser?.avatar_url ? (
                  <img src={editingUser.avatar_url} alt="Prévia do avatar" className="h-full w-full object-cover" />
                ) : (
                  <UserAvatar
                    name={editingUser?.name}
                    email={editingUser?.email}
                    colorKey={editingUser?.id}
                    size={96}
                    className="h-full w-full border-0"
                  />
                )}
              </div>
              <Button
                variant="primary"
                size="icon"
                aria-label="Trocar foto de perfil"
                className="absolute -bottom-2 -right-2 h-8 w-8 rounded-full shadow-e2"
                onClick={(e) => { e.stopPropagation(); fileInputRef.current?.click() }}
              >
                <Upload className="h-4 w-4" />
              </Button>
              <input ref={fileInputRef} type="file" accept="image/*" onChange={handleAvatarFile} className="hidden" />
            </div>
            <p className="text-sm text-foreground">Foto de perfil</p>
            {/* O número vem do catálogo do servidor (`config/attachments.yml`,
                3 MB) e é ELE que reprova. A tela antes dizia 2 MB — número que
                não batia com limite nenhum, porque não havia limite. */}
            <p className="text-xs text-muted-foreground">JPG, PNG, WEBP ou GIF, até 3 MB</p>
          </div>

          <div className="space-y-4">
            <Campo label="Tipo de conta" erro={fieldErrors.user_type}>
              {/* FE-019 — **um** campo de papel. No legado coexistiam um `hidden`
                  com default `Admin` (linha 6) e um `select` visível (linha 13) no
                  MESMO formulário: o que a pessoa escolhia e o que era enviado
                  podiam divergir, e foi assim que o D-39 criou administradores. */}
              <Select
                aria-label="Tipo de conta"
                value={(editingUser?.user_type_slug || editingUser?.user_type || '').toLowerCase() || 'colaborador'}
                onChange={(v) => setEditingUser({ ...(editingUser || {}), user_type: v })}
                options={[
                  { value: 'colaborador', label: 'Colaborador' },
                  { value: 'gerente', label: 'Gerente' },
                  { value: 'admin', label: 'Admin' },
                  { value: 'og', label: 'OG' },
                ]}
              />
            </Campo>

            <Campo label="Nome completo" erro={fieldErrors.name}>
              <Input
                className="rounded-lg"
                value={editingUser?.name || ''}
                aria-invalid={!!fieldErrors.name}
                onChange={(e) => setEditingUser({ ...(editingUser || {}), name: e.target.value })}
              />
            </Campo>

            <Campo label="E-mail" erro={fieldErrors.email}>
              <Input
                className="rounded-lg"
                type="email"
                value={editingUser?.email || ''}
                aria-invalid={!!fieldErrors.email}
                onChange={(e) => setEditingUser({ ...(editingUser || {}), email: e.target.value })}
              />
            </Campo>

            <Campo label="Telefone (WhatsApp)" erro={fieldErrors.phone}>
              <PhoneInputGroup
                value={editingUser?.phone || ''}
                onChange={(normalized) => setEditingUser({ ...(editingUser || {}), phone: normalized })}
                className="rounded-lg"
              />
            </Campo>

            {/* DEC-14 / D-38 — **não há campo de senha, e não vai haver.** O
                legado tinha "Senha" e "Confirmar senha" aqui, e criava a conta
                com uma senha determinística (D-109). A pessoa entra por código
                ou pelo link do convite. */}
            <p className="rounded-md bg-muted px-3 py-2 text-xs text-muted-foreground">
              Não existe senha. Ao salvar, a pessoa recebe um convite com um link de primeiro acesso de uso único;
              depois disso ela entra por código de 6 dígitos no e-mail ou no WhatsApp.
            </p>
          </div>
        </div>
        </SideDrawer>
      {!loading && !loadError && totalPages > 1 && (
        <PaginationPill
          page={page}
          totalPages={totalPages}
          perPage={perPage}
          onPageChange={setPage}
          onPerPageChange={(value) => { setPerPage(value); setPage(1) }}
          loading={loading}
        />
      )}

      <ReasonDialog
        open={!!impersonateTarget}
        title={`Ver como ${impersonateTarget?.name || 'este usuário'}`}
        description="O motivo fica na trilha de auditoria com o seu nome. A sessão expira em 1 hora."
        confirmLabel="Ver como"
        onCancel={() => setImpersonateTarget(null)}
        onConfirm={(reason) => {
          const target = impersonateTarget
          setImpersonateTarget(null)
          if (target) handleImpersonate(target, reason)
        }}
      />

      <ReasonDialog
        open={!!blockTarget}
        title={`Bloquear ${blockTarget?.name || 'esta conta'}`}
        description="A sessão ativa dela cai na hora, e este texto é o que ela vê ao tentar entrar. A conta não é apagada."
        label="Motivo do bloqueio"
        placeholder="Ex.: desligamento em 01/2026"
        confirmLabel="Bloquear"
        onCancel={() => setBlockTarget(null)}
        onConfirm={(reason) => {
          const target = blockTarget
          setBlockTarget(null)
          if (target) handleBlock(target, reason)
        }}
      />

      <ConfirmDialog open={confirmOpen} onCancel={() => { setConfirmOpen(false); setConfirmTarget(null) }} onConfirm={confirmDelete} />
    </div>
  )
}

/**
 * Rótulo + campo + **mensagem de erro do próprio campo** (FE-021).
 *
 * A mensagem fica embaixo do campo, não num `toast`: o toast some em 4 segundos e
 * não diz onde clicar. `role="alert"` para que o leitor de tela anuncie sem esperar
 * o foco chegar ali, e o `aria-invalid` de cada `<Input>` fecha o par.
 */
function Campo({ label, erro, children }: { label: string; erro?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label className="text-sm font-medium text-foreground">{label}</label>
      {children}
      {erro && (
        <p role="alert" className="text-xs text-destructive">
          {erro}
        </p>
      )}
    </div>
  )
}

/**
 * Menu de ações do card — **com os mesmos gates do servidor** (FE-016).
 *
 * No legado "Ver como" aparecia para qualquer papel na lista e só funcionava para
 * alguns: o operador clicava e recebia um erro. Aqui cada item só é renderizado
 * quando a matriz do DEC-18 o permite; o que não se pode fazer não aparece.
 */
function MenuActions({
  canWrite,
  canImpersonate,
  isBlocked,
  onView,
  onEdit,
  onImpersonate,
  onToggleBlock,
  onDelete
}: {
  canWrite: boolean
  canImpersonate: boolean
  isBlocked: boolean
  onView: () => void
  onEdit: () => void
  onImpersonate: () => void
  onToggleBlock: () => void
  onDelete: () => void
}) {
  const [open, setOpen] = useState(false)
  return (
    <div className="relative">
      <Button variant="ghost" size="icon" aria-label="Ações" onClick={() => setOpen((v) => !v)}>
        <MoreHorizontal className="h-4 w-4" />
      </Button>
      {open && (
        <>
          <div className="fixed inset-0 z-drawer-backdrop" onClick={(e) => { e.stopPropagation(); setOpen(false) }} />
          <div className="absolute right-0 mt-2 w-40 rounded-lg border border-border bg-popover text-popover-foreground p-1 shadow-e3 z-drawer animate-in fade-in zoom-in-95 duration-100 origin-top-right">
            <button type="button" className="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring flex items-center gap-2" onClick={(e) => { e.stopPropagation(); setOpen(false); onView() }}><Eye className="h-4 w-4" /> Visualizar</button>
            {canWrite && (
              <button type="button" className="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring flex items-center gap-2" onClick={(e) => { e.stopPropagation(); setOpen(false); onEdit() }}><Pencil className="h-4 w-4" /> Editar</button>
            )}
            {canImpersonate && (
              <button type="button" className="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring flex items-center gap-2" onClick={(e) => { e.stopPropagation(); setOpen(false); onImpersonate() }}><UserCheck className="h-4 w-4" /> Ver como</button>
            )}
            {canWrite && (
              <button type="button" className="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring flex items-center gap-2" onClick={(e) => { e.stopPropagation(); setOpen(false); onToggleBlock() }}>
                {isBlocked ? <><Unlock className="h-4 w-4" /> Desbloquear</> : <><Lock className="h-4 w-4" /> Bloquear</>}
              </button>
            )}
            {canWrite && <div className="h-px bg-border my-1" />}
            {canWrite && (
              <button type="button" className="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring flex items-center gap-2 text-destructive" onClick={(e) => { e.stopPropagation(); setOpen(false); onDelete() }}><Trash2 className="h-4 w-4" /> Remover</button>
            )}
          </div>
        </>
      )}
    </div>
  )
}

function ConfirmDialog({ open, onConfirm, onCancel }: { open: boolean; onConfirm: () => void; onCancel: () => void }) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-modal">
      <div className="absolute inset-0 z-modal-backdrop bg-brand-ink/60" onClick={onCancel} />
      <div className="absolute z-modal left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[90%] max-w-sm rounded-lg border border-border bg-popover text-popover-foreground p-6 shadow-e3">
        <h3 className="text-lg font-semibold text-foreground mb-2">Remover usuário?</h3>
        <p className="text-sm text-muted-foreground mb-4">Esta ação não pode ser desfeita. Deseja confirmar a remoção?</p>
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onCancel}>Não</Button>
          <Button variant="destructive" onClick={onConfirm}>Sim, remover</Button>
        </div>
      </div>
    </div>
  )
}

