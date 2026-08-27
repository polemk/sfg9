import { useState, useRef, useEffect } from 'react'
import { UserCheck, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { SidebarSelectorCard } from '@/components/ui/SidebarSelectorCard'
import { Tooltip } from '@/components/ui/Tooltip'
import { clearTokens } from '@/lib/api/tokenStore'
import { authService } from '@/lib/api/auth'
import { useAuthStore } from '@/store/authStore'
import { impersonateApi } from '@/lib/api/endpoints'
// FE-036/FE-037 — a busca é UMA. Este arquivo tinha a sua própria cópia (mesmo
// debounce, mesmo `usersApi.list`, mesmo `ReasonDialog`) enquanto
// `ImpersonateSearch.tsx` estava morto ao lado. Duas cópias é como uma fica para
// trás — e a de lá ainda rotulava todo mundo como "Cliente", papel que a DEC-41
// removeu.
import { ImpersonateSearch } from '@/components/ImpersonateSearch'
import { notify } from '@/lib/notify'

interface ImpersonateSelectorProps {
    collapsed?: boolean
}

export function ImpersonateSelector({ collapsed }: ImpersonateSelectorProps) {
    const [isOpen, setIsOpen] = useState(false)
    const containerRef = useRef<HTMLDivElement>(null)

    const { stopImpersonation, logout } = useAuthStore()
    const impersonating = useAuthStore((s) => s.impersonating)
    const impersonatedUser = useAuthStore((s) => s.user)
    const trueUser = useAuthStore((s) => s.trueUser)

    // Guard: detecta estado de impersonação inconsistente e reseta
    useEffect(() => {
        if (impersonating && (!trueUser || trueUser.id === impersonatedUser?.id)) {
            console.warn('[ImpersonateSelector] Estado inconsistente detectado — resetando impersonação')
            useAuthStore.setState({ impersonating: false, trueUser: null })
        }
    }, [])

    // Handle click outside to close
    useEffect(() => {
        function handleClickOutside(event: MouseEvent) {
            if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
                setIsOpen(false)
            }
        }
        document.addEventListener('mousedown', handleClickOutside)
        return () => document.removeEventListener('mousedown', handleClickOutside)
    }, [])

    const handleStopImpersonation = async () => {
        try {
            const data = await impersonateApi.stop() as unknown as {
                access_token: string
                refresh_token: string
                user: import('@/lib/api/types').User
            }
            stopImpersonation(data.access_token,
                data.user as any
            )
            notify.success('Voltando ao seu usuário')
            setTimeout(() => {
                window.location.href = '/dashboard'
            }, 300)
        } catch (err: any) {
            const status = err?.response?.status
            const code = err?.response?.data?.error

            // 422 not_impersonating = estado local desincronizado, reset forçado
            if (status === 422 || code === 'not_impersonating') {
                console.warn('[ImpersonateSelector] Backend não está impersonando — resetando estado local')
                useAuthStore.setState({ impersonating: false, trueUser: null })
                notify.info('Sessão de impersonação já encerrada. Recarregando...')
                setTimeout(() => window.location.reload(), 500)
                return
            }

            console.error('Stop impersonation error:', err)
            notify.error('Erro na API. Fazendo logout...')
            // Mesma regra do botão Sair: limpar só o estado local deixaria os
            // cookies HttpOnly vivos, e a próxima rota protegida ressuscitaria a
            // sessão. O DELETE revoga os três tokens e apaga os dois cookies.
            try {
                await authService.logout()
            } catch {
                // Rede fora ou sessão já morta: segue com a limpeza local.
            }
            clearTokens()
            logout()
            setTimeout(() => {
                window.location.href = '/login'
            }, 500)
        }
    }

    return (
        <div className="relative" ref={containerRef}>
            <div className="flex items-center gap-2">
                <SidebarSelectorCard
                    label="Vendo como"
                    value={impersonating ? (impersonatedUser?.name ?? 'Usuário') : 'Ninguém'}
                    icon={UserCheck}
                    collapsed={collapsed}
                    open={isOpen}
                    tone={impersonating ? 'warning' : 'default'}
                    onClick={() => setIsOpen(!isOpen)}
                    className="flex-1"
                />

                {/* A saída da impersonação vive ao lado do cartão, não dentro
                    dele: quem está "vendo como" outra pessoa precisa de um jeito
                    óbvio de voltar a ser quem é. Sem isto o handler existiria e
                    nada o chamaria — foi o que aconteceu quando o gatilho virou
                    o cartão padronizado. */}
                {impersonating && !collapsed && (
                    <Tooltip content="Encerrar impersonação" side="right">
                        <button
                            type="button"
                            onClick={handleStopImpersonation}
                            aria-label="Encerrar impersonação"
                            className={cn(
                                'flex h-9 w-9 shrink-0 items-center justify-center rounded-md border border-warning/30',
                                'text-warning transition-colors hover:bg-warning/10',
                                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                            )}
                        >
                            <X aria-hidden="true" className="h-4 w-4" />
                        </button>
                    </Tooltip>
                )}
            </div>

            {/* Dropdown */}
            {isOpen && !impersonating && (
                <div
                    className={cn(
                        "absolute top-full left-0 mt-2 z-modal w-64 origin-top-left",
                        "animate-in fade-in zoom-in-95 duration-200",
                        collapsed ? "left-12 top-0 mt-0" : ""
                    )}
                    style={{ minWidth: collapsed ? '16rem' : '100%' }}
                >
                    <div className="rounded-lg border border-border bg-popover text-popover-foreground shadow-e3 overflow-hidden">
                        {/* A busca é o componente compartilhado — ver a nota no
                            topo do arquivo. Ele já traz debounce, teto de 5,
                            selo do papel real, motivo obrigatório e o alvo de
                            toque de 44 px. */}
                        <div className="p-3">
                            <ImpersonateSearch autoFocus onStarted={() => setIsOpen(false)} />
                        </div>

                        {/* Faixa inferior sólida de marca — sem gradiente. */}
                        <div className="h-0.5 w-full bg-primary/40" />
                    </div>
                </div>
            )}

        </div>
    )
}
