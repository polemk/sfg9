import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { flowExecutionsApi } from '@/lib/api/endpoints'
import { timeAgo } from '@/lib/utils/date'
import {
    Activity,
    User,
    Clock,
    ChevronRight,
    GitBranch,
    ArrowLeft,
    RefreshCw,
    Users,
    Layers,
    Eye,
    Loader2
} from 'lucide-react'
import PageHeader from '@/components/PageHeader'
import { KpiCard } from '@/components/kpi/KpiCard'
import { Button } from '@/components/ui/Button'

export function ExecutionViewerPage() {
    const [page, setPage] = useState(1)

    const { data, isLoading, refetch, isFetching } = useQuery({
        queryKey: ['flow-executions', page],
        queryFn: () => flowExecutionsApi.list({ page, per_page: 20 })
    })

    // Stats
    const totalSessions = data?.meta.total || 0
    const uniqueFlows = data?.sessions ? [...new Set(data.sessions.map(s => s.flow_id))].length : 0

    // FE-430 — tempo relativo é UM utilitário (`lib/utils/date.ts`). Esta
    // página tinha a sua cópia, e a de detalhe tinha outra.
    const getTimeAgo = (dateStr?: string | null): string => timeAgo(dateStr, 'N/A')

    return (
        <div className="space-y-6">
            <PageHeader
                title="Histórico de Execuções"
                subtitle="Visualize o histórico de conversas e fluxos executados"
                rightSlot={
                    <div className="flex items-center gap-2">
                        <Link
                            to="/admin/chat"
                            className="px-4 py-2 bg-muted text-foreground border border-border rounded-md hover:bg-muted/80 transition font-medium flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Voltar
                        </Link>
                        <Button
                            onClick={() => refetch()}
                            disabled={isFetching}
                            variant="primary"
                        >
                            {isFetching ? (
                                <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                                <RefreshCw className="h-4 w-4" />
                            )}
                            Atualizar
                        </Button>
                    </div>
                }
            />

            {/* KPI Cards — cor vem de token semântico, nunca de hex literal */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <KpiCard
                    title="Total de Sessões"
                    value={String(totalSessions)}
                    icon={Users}
                    color="hsl(var(--info))"
                    change="Conversas registradas"
                    changeType="neutral"
                />
                <KpiCard
                    title="Fluxos Utilizados"
                    value={String(uniqueFlows)}
                    icon={GitBranch}
                    color="hsl(var(--success))"
                    change="Fluxos diferentes"
                    changeType="neutral"
                />
                <KpiCard
                    title="Página Atual"
                    value={`${page}/${data?.meta.total_pages || 1}`}
                    icon={Layers}
                    color="hsl(var(--primary))"
                    change={`${data?.meta.per_page || 20} por página`}
                    changeType="neutral"
                />
                <KpiCard
                    title="Status"
                    value={isLoading ? "Carregando" : "Atualizado"}
                    icon={Activity}
                    color="hsl(var(--warning))"
                    change={isFetching ? "Buscando..." : "Dados em dia"}
                    changeType={isLoading ? "neutral" : "positive"}
                />
            </div>

            {/* Sessions Table */}
            <div className="glass-panel rounded-lg overflow-hidden">
                <div className="p-4 border-b border-border/50 flex items-center justify-between">
                    <h3 className="font-semibold flex items-center gap-2">
                        <Activity className="h-4 w-4 text-primary" />
                        Sessões de Execução
                    </h3>
                    <span className="text-xs text-muted-foreground">
                        <span className="font-numeric">{totalSessions}</span> {totalSessions === 1 ? 'sessão encontrada' : 'sessões encontradas'}
                    </span>
                </div>

                {isLoading ? (
                    <div className="p-10 text-center">
                        <Loader2 className="h-8 w-8 mx-auto mb-2 animate-spin text-muted-foreground" />
                        <p className="text-sm text-muted-foreground">Carregando sessões...</p>
                    </div>
                ) : data?.sessions && data.sessions.length > 0 ? (
                    <>
                        <div className="divide-y divide-border/50">
                            {data.sessions.map(session => (
                                <Link
                                    key={session.id}
                                    to={`/admin/chat/executions/${session.id}`}
                                    className="p-4 hover:bg-muted/30 transition-colors cursor-pointer group block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                                >
                                    <div className="flex items-start justify-between gap-4">
                                        <div className="flex items-center gap-3 flex-1">
                                            <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                                                <User className="h-5 w-5 text-primary" />
                                            </div>
                                            <div className="space-y-1 flex-1 min-w-0">
                                                <div className="flex items-center gap-2">
                                                    <span className="font-semibold text-foreground group-hover:text-primary transition-colors">
                                                        Sessão <span className="font-numeric">#{session.id}</span>
                                                    </span>
                                                    <span className="px-2 py-0.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-full font-medium">
                                                        {session.flow_name}
                                                    </span>
                                                </div>
                                                <div className="flex items-center gap-3 text-xs text-muted-foreground">
                                                    <span className="flex items-center gap-1">
                                                        <Activity className="h-3 w-3" />
                                                        <span className="font-numeric">{session.steps_count}</span> passos
                                                    </span>
                                                    <span className="h-1 w-1 rounded-full bg-border" />
                                                    <span className="flex items-center gap-1">
                                                        <Clock className="h-3 w-3" />
                                                        {getTimeAgo(session.started_at)}
                                                    </span>
                                                </div>
                                            </div>
                                        </div>
                                        <div className="p-2 text-muted-foreground group-hover:text-primary group-hover:bg-primary/10 rounded-md transition-all opacity-0 group-hover:opacity-100">
                                            <Eye className="h-4 w-4" />
                                        </div>
                                    </div>
                                </Link>
                            ))}
                        </div>

                        {/* Pagination */}
                        {data.meta.total_pages > 1 && (
                            <div className="p-4 border-t border-border/50 flex items-center justify-between">
                                <Button
                                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                                    disabled={page === 1}
                                    variant="secondary"
                                    size="sm"
                                >
                                    <ChevronRight className="h-4 w-4 rotate-180" />
                                    Anterior
                                </Button>
                                <span className="text-sm text-muted-foreground">
                                    Página <span className="font-semibold text-foreground font-numeric">{page}</span> de <span className="font-semibold text-foreground font-numeric">{data.meta.total_pages}</span>
                                </span>
                                <Button
                                    onClick={() => setPage((p) => Math.min(data.meta.total_pages, p + 1))}
                                    disabled={page === data.meta.total_pages}
                                    variant="secondary"
                                    size="sm"
                                >
                                    Próxima
                                    <ChevronRight className="h-4 w-4" />
                                </Button>
                            </div>
                        )}
                    </>
                ) : (
                    <div className="p-12 text-center">
                        <Activity className="h-12 w-12 mx-auto mb-3 text-muted-foreground opacity-20" />
                        <h3 className="font-semibold text-foreground mb-1">Nenhuma execução encontrada</h3>
                        <p className="text-sm text-muted-foreground max-w-sm mx-auto">
                            As execuções aparecerão aqui quando usuários interagirem com os fluxos no chat.
                        </p>
                    </div>
                )}
            </div>
        </div>
    )
}
