/**
 * **O autocomplete de impersonação — um só, para as três portas de entrada.**
 *
 * FE-036 / FE-037 / FE-038, DEC-18.3.
 *
 * ### Por que este arquivo voltou a existir
 *
 * Ele estava **morto**: nenhuma tela o importava, e ao lado dele o
 * `ImpersonateSelector` da barra lateral tinha uma segunda busca, escrita à mão,
 * com o mesmo debounce, o mesmo `usersApi.list` e o mesmo `ReasonDialog`. Duas
 * cópias da mesma coisa é como uma delas fica para trás — e a que estava para trás
 * era esta: os selos de papel diziam **"OG" ou "Cliente"**, e `client` não existe
 * mais desde a **DEC-41**. Quem abrisse a busca veria o Admin, o Gerente e o
 * Colaborador todos rotulados como "Cliente".
 *
 * Agora existe **um** componente, e as três portas (barra lateral, menu do usuário,
 * folha de contexto do celular) montam este mesmo.
 *
 * ### O que ele garante
 *
 *  - **Debounce de 300 ms** e mínimo de 2 caracteres — sem isso cada tecla é uma
 *    requisição e a resposta lenta sobrescreve a recente.
 *  - **Limite de 5 resultados** (BE-033). Não é estética: a lista abre dentro de um
 *    painel flutuante, e no telefone seis linhas já empurram o dedo para fora da
 *    zona do polegar.
 *  - **Selo do papel real**, com os quatro do Safegold e a cor do token semântico.
 *  - **Motivo obrigatório** antes de chamar o servidor (DEC-18.3). O backend recusa
 *    sem ele com 422, e um 422 seco depois do clique não explica nada.
 *  - **Alvo de toque de 44 px** nas linhas (§5.4.8): esta lista é usada no celular.
 *
 * A **trava de hierarquia é do servidor** (`Authorization::Hierarchy`). Aqui só se
 * decide quem vê a busca — OG e Admin. Se um Admin buscar um OG, o nome aparece
 * (ele já aparece na lista de contas) e o servidor recusa o `start` com 403: é a
 * ordem certa, porque esconder o nome da busca não protegeria nada e a lista de
 * contas já o mostra.
 */
import { useState, useRef, useEffect, useCallback } from 'react'
import { Search, UserCheck, X, Loader2 } from 'lucide-react'
import { usersApi, impersonateApi } from '@/lib/api/endpoints'
import { ReasonDialog } from '@/features/auth/ReasonDialog'
import { useAuthStore, useRole } from '@/store/authStore'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import type { User } from '@/lib/api/types'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { cn } from '@/lib/utils'

/** Teto de resultados (BE-033). Um número, num lugar. */
const LIMITE_DE_RESULTADOS = 5

/** Os quatro papéis do Safegold (DEC-41), com o tom do token semântico. */
const SELO_POR_PAPEL: Record<string, { rotulo: string; classe: string }> = {
  og: { rotulo: 'OG', classe: 'bg-success/15 text-success' },
  admin: { rotulo: 'ADMIN', classe: 'bg-primary/15 text-primary' },
  gerente: { rotulo: 'GERENTE', classe: 'bg-warning/15 text-warning' },
  colaborador: { rotulo: 'COLAB.', classe: 'bg-muted text-muted-foreground' },
}

function selo(user: User) {
  const slug = (user.user_type_slug || '').toLowerCase()
  return SELO_POR_PAPEL[slug] ?? { rotulo: (user.user_type || '—').toUpperCase(), classe: 'bg-muted text-muted-foreground' }
}

export interface ImpersonateSearchProps {
  /** Chamado depois de iniciar a impersonação, para o hospedeiro fechar o painel. */
  onStarted?: () => void
  /** Foca o campo ao montar. A barra lateral abre o painel e quer o foco lá. */
  autoFocus?: boolean
  className?: string
}

export function ImpersonateSearch({ onStarted, autoFocus, className }: ImpersonateSearchProps) {
  const { canImpersonate } = useRole()
  const startImpersonation = useAuthStore((s) => s.startImpersonation)
  const eu = useAuthStore((s) => s.user)

  const [query, setQuery] = useState('')
  const [results, setResults] = useState<User[]>([])
  const [loading, setLoading] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [reasonTarget, setReasonTarget] = useState<User | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const buscar = useCallback(async (q: string) => {
    setLoading(true)
    setErro(null)
    try {
      const data = await usersApi.list({ q, perPage: LIMITE_DE_RESULTADOS })
      // A própria conta sai da lista: "ver como você mesmo" não é nada, e o
      // servidor recusa (não-lateral inclui não-si-mesmo).
      setResults((data.users || []).filter((u) => u.id !== eu?.id))
    } catch (e: any) {
      // **Erro visível.** Antes o `catch` zerava a lista, e "não consegui
      // perguntar" ficava idêntico a "ninguém com esse nome".
      setResults([])
      setErro(e?.response?.data?.message || 'Não foi possível buscar agora.')
    } finally {
      setLoading(false)
    }
  }, [eu?.id])

  useEffect(() => {
    if (query.trim().length < 2) {
      setResults([])
      setErro(null)
      return
    }
    const timer = setTimeout(() => buscar(query.trim()), 300)
    return () => clearTimeout(timer)
  }, [query, buscar])

  useEffect(() => {
    if (autoFocus) setTimeout(() => inputRef.current?.focus(), 50)
  }, [autoFocus])

  if (!canImpersonate) return null

  async function iniciar(alvo: User, motivo: string) {
    try {
      const data = await impersonateApi.start(alvo.id, motivo)
      startImpersonation(data.access_token, data.impersonated_user)
      setQuery('')
      setResults([])
      onStarted?.()
      notify.success(`Vendo como ${alvo.name || alvo.email}`, {
        description: 'A sessão expira em 1 hora e está na trilha de auditoria.',
      })
      // Recarregar é intencional: cada consulta em cache do React Query foi
      // respondida com o escopo do usuário anterior. Invalidar uma a uma deixaria
      // a próxima esquecida.
      window.location.href = '/dashboard'
    } catch (err: any) {
      notify.error(err?.response?.data?.message || 'Não foi possível iniciar a impersonação')
    }
  }

  const mostrarLista = query.trim().length >= 2

  return (
    <div className={cn('space-y-2', className)}>
      <div className="relative">
        <Search aria-hidden="true" className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Buscar pessoa…"
          aria-label="Buscar pessoa para ver como"
          className="h-11 w-full rounded-md border border-input bg-background pl-9 pr-9 text-sm text-foreground outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
        />
        {loading && (
          <Loader2 aria-hidden="true" className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        )}
        {!loading && query && (
          <Button
            variant="ghost"
            size="icon"
            aria-label="Limpar busca"
            onClick={() => { setQuery(''); setResults([]) }}
            className="absolute right-1 top-1/2 h-8 w-8 -translate-y-1/2"
          >
            <X className="h-3.5 w-3.5" />
          </Button>
        )}
      </div>

      {mostrarLista && (
        <div className="max-h-64 overflow-y-auto rounded-md border border-border">
          {erro ? (
            <p role="alert" className="px-3 py-4 text-center text-xs text-destructive">{erro}</p>
          ) : loading && results.length === 0 ? (
            <p className="px-3 py-4 text-center text-xs text-muted-foreground">Buscando…</p>
          ) : results.length === 0 ? (
            <p className="px-3 py-4 text-center text-xs text-muted-foreground">Ninguém com esse nome.</p>
          ) : (
            <ul>
              {results.map((u) => {
                const s = selo(u)
                return (
                  <li key={u.id}>
                    {/* Item de lista: `<button>` cru tokenizado (§5.4.3). O
                        `min-h-[3rem]` é o alvo de toque de 44 px do §5.4.8 —
                        esta lista abre na folha de contexto do celular. */}
                    <button
                      type="button"
                      onClick={() => setReasonTarget(u)}
                      className="group flex min-h-[3rem] w-full items-center gap-3 px-3 py-2 text-left transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
                    >
                      <UserAvatar name={u.name} email={u.email} src={u.avatar_url} colorKey={u.id} size={32} />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-medium text-foreground">{u.name || 'Sem nome'}</span>
                        <span className="block truncate text-xs text-muted-foreground">{u.email || u.phone}</span>
                      </span>
                      <span className={cn('shrink-0 rounded-sm px-1.5 py-0.5 text-[10px] font-semibold tracking-wide', s.classe)}>
                        {s.rotulo}
                      </span>
                      <UserCheck aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground transition-colors group-hover:text-foreground" />
                    </button>
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      )}

      <ReasonDialog
        open={!!reasonTarget}
        title={`Ver como ${reasonTarget?.name || reasonTarget?.email || 'esta pessoa'}`}
        description="O motivo fica na trilha de auditoria com o seu nome. A sessão expira em 1 hora e não personifica ninguém."
        confirmLabel="Ver como"
        onCancel={() => setReasonTarget(null)}
        onConfirm={(motivo) => {
          const alvo = reasonTarget
          setReasonTarget(null)
          if (alvo) iniciar(alvo, motivo)
        }}
      />
    </div>
  )
}
