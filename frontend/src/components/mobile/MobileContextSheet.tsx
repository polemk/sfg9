import { useState, useEffect } from 'react'
import { User, Palette, LogOut, UserCheck, X, Loader2, Search } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'
import { cn } from '@/lib/utils'
import { useAuthStore, useRole } from '@/store/authStore'
import { useTheme } from '@/hooks/useTheme'
import { authService } from '@/lib/api/auth'
import { usersApi, impersonateApi } from '@/lib/api/endpoints'
import { notify } from '@/lib/notify'
import type { User as ApiUser } from '@/lib/api/types'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { ReasonDialog } from '@/features/auth/ReasonDialog'

interface MobileContextSheetProps {
    onClose: () => void
}

export function MobileContextSheet({ onClose }: MobileContextSheetProps) {
    const navigate = useNavigate()
    const { user, logout, impersonating, startImpersonation, stopImpersonation } = useAuthStore()
    const { canImpersonate } = useRole()
    const { theme, setTheme } = useTheme()

    const [impSearch, setImpSearch] = useState('')
    const [impResults, setImpResults] = useState<ApiUser[]>([])
    const [impLoading, setImpLoading] = useState(false)
    const [activeView, setActiveView] = useState<'main' | 'impersonate'>('main')

    useEffect(() => {
        const timer = setTimeout(async () => {
            if (impSearch.length < 2) { setImpResults([]); return }
            setImpLoading(true)
            try {
                const data = await usersApi.list({ q: impSearch, perPage: 5 }) as any
                setImpResults(data.users || [])
            } catch { /* noop */ } finally { setImpLoading(false) }
        }, 300)
        return () => clearTimeout(timer)
    }, [impSearch])

    const handleLogout = async () => {
        // Ver Sidebar: sem o DELETE, o cookie HttpOnly sobrevive ao "logout".
        try {
            await authService.logout()
        } catch {
            // Rede fora ou sessão já morta: segue com a limpeza local.
        }
        logout()
        onClose()
        navigate('/login')
    }

    const handleStopImpersonation = async () => {
        try {
            const data = await impersonateApi.stop() as any
            stopImpersonation(data.access_token, data.user)
            notify.success('Sessão original restaurada')
            window.location.href = '/dashboard'
        } catch { notify.error('Erro ao parar impersonação') }
    }

    // DEC-18.3 — motivo obrigatório. No mobile o diálogo é o mesmo do desktop.
    const [reasonTarget, setReasonTarget] = useState<ApiUser | null>(null)

    const handleStartImpersonation = async (target: ApiUser, reason: string) => {
        try {
            const data = await impersonateApi.start(target.id, reason) as any
            startImpersonation(data.access_token, data.impersonated_user)
            notify.success(`Impersonando ${target.name}`)
            window.location.reload()
        } catch { notify.error('Erro ao iniciar impersonação') }
    }

    if (activeView === 'impersonate') {
        return (
            <div className="flex flex-col h-full animate-in slide-in-from-right duration-300">
                <div className="flex items-center gap-3 p-4 border-b border-border bg-secondary/20">
                    <Button variant="ghost" size="icon" onClick={() => setActiveView('main')} className="rounded-full">
                        <X className="w-4 h-4" />
                    </Button>
                    <span className="font-bold">Impersonar Usuário</span>
                </div>
                <div className="p-4">
                    <div className="relative mb-4">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                        <Input
                            placeholder="Nome ou e-mail..."
                            value={impSearch}
                            onChange={e => setImpSearch(e.target.value)}
                            className="pl-9"
                        />
                        {impLoading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-primary" />}
                    </div>
                    <div className="space-y-2">
                        {impResults.map(u => (
                            <button
                                key={u.id}
                                type="button"
                                onClick={() => setReasonTarget(u)}
                                className="w-full flex items-center gap-3 p-3 rounded-md bg-secondary text-secondary-foreground border border-border hover:bg-accent hover:text-accent-foreground transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            >
                                <div className="w-10 h-10 rounded-full bg-muted flex items-center justify-center text-sm font-bold shrink-0 overflow-hidden">
                                    {u.avatar_url
                                        ? <img src={u.avatar_url} className="w-full h-full object-cover" />
                                        : u.name?.substring(0, 2).toUpperCase()
                                    }
                                </div>
                                <div className="flex-1 text-left">
                                    <div className="text-sm font-bold">{u.name}</div>
                                    <div className="text-xs text-muted-foreground">{u.email}</div>
                                </div>
                                <UserCheck className="w-4 h-4 text-primary" />
                            </button>
                        ))}
                        {impSearch.length >= 2 && !impLoading && impResults.length === 0 && (
                            <div className="p-8 text-center text-muted-foreground text-sm">
                                Nenhum usuário encontrado
                            </div>
                        )}
                    </div>

                    <ReasonDialog
                        open={!!reasonTarget}
                        title={`Ver como ${reasonTarget?.name || 'este usuário'}`}
                description="O motivo fica na trilha de auditoria com o seu nome. A sessão expira em 1 hora."
                confirmLabel="Ver como"
                        onCancel={() => setReasonTarget(null)}
                        onConfirm={(reason) => {
                            const target = reasonTarget
                            setReasonTarget(null)
                            if (target) handleStartImpersonation(target, reason)
                        }}
                    />
                </div>
            </div>
        )
    }

    return (
        <div className="flex flex-col h-full">
            {/* Cabeçalho do perfil */}
            <div className="p-6 flex flex-col items-center border-b border-border">
                <div className="relative w-20 h-20 mb-3">
                    <div className="w-full h-full rounded-full border-2 border-primary/20 shadow-e2 bg-muted flex items-center justify-center text-2xl font-bold overflow-hidden">
                        {user?.avatar_url
                            ? <img src={user.avatar_url} className="w-full h-full object-cover" alt="Avatar" />
                            : <span>{user?.name?.substring(0, 2).toUpperCase() || user?.email?.substring(0, 2).toUpperCase() || 'U'}</span>
                        }
                    </div>
                    {impersonating && (
                        <div className="absolute -bottom-1 -right-1 bg-warning p-1.5 rounded-full border-2 border-background animate-pulse">
                            <UserCheck className="w-3 h-3 text-warning-foreground" />
                        </div>
                    )}
                </div>
                <h3 className="text-lg font-bold truncate max-w-full">{user?.name}</h3>
                <p className="text-xs text-muted-foreground truncate max-w-full mb-4">{user?.email}</p>
                {impersonating && (
                    <Button variant="destructive" size="sm" onClick={handleStopImpersonation}
                        className="px-4 h-8 text-xs uppercase font-bold">
                        Parar Impersonação
                    </Button>
                )}
            </div>

            {/* Opções */}
            <div className="flex-1 overflow-y-auto p-4 space-y-2">
                <div className="space-y-1">
                    <div className="px-2 text-[10px] font-bold uppercase tracking-wider text-muted-foreground opacity-50 mb-2">
                        Conta
                    </div>

                    <Link
                        to="/profile"
                        onClick={onClose}
                        className="flex items-center gap-3 p-4 rounded-md hover:bg-accent hover:text-accent-foreground transition-all"
                    >
                        <User className="w-5 h-5 text-muted-foreground" />
                        <span className="text-sm font-medium">Meu Perfil</span>
                    </Link>

                    <button
                        type="button"
                        onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                        className="w-full flex items-center gap-3 p-4 rounded-md hover:bg-accent hover:text-accent-foreground transition-all text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                        <Palette className="w-5 h-5 text-muted-foreground" />
                        <span className="text-sm font-medium">
                            {theme === 'dark' ? 'Mudar para Modo Claro' : 'Mudar para Modo Escuro'}
                        </span>
                    </button>
                </div>

                {canImpersonate && !impersonating && (
                    <div className="space-y-1 pt-2">
                        <div className="px-2 text-[10px] font-bold uppercase tracking-wider text-muted-foreground opacity-50 mb-2">
                            Admin
                        </div>
                        <button
                            type="button"
                            onClick={() => setActiveView('impersonate')}
                            className="w-full flex items-center justify-between p-4 rounded-md bg-secondary text-secondary-foreground border border-border active:scale-95 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <div className="flex items-center gap-3">
                                <div className="p-2 rounded-lg bg-primary/10 text-primary">
                                    <UserCheck className="w-5 h-5" />
                                </div>
                                <div className="flex flex-col items-start">
                                    <span className="text-[10px] font-bold uppercase text-muted-foreground">
                                        Impersonar
                                    </span>
                                    <span className="text-sm font-bold">Ver como outro usuário</span>
                                </div>
                            </div>
                        </button>
                    </div>
                )}
            </div>

            {/* Logout */}
            <div className="p-4 border-t border-border">
                <Button variant="destructive" onClick={handleLogout} className="w-full">
                    <LogOut className="w-5 h-5" />
                    Sair do aplicativo
                </Button>
            </div>
        </div>
    )
}
