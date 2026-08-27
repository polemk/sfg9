
import { useState, useEffect, useMemo } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
    Plus,
    Search,
    Eye,
    BarChart3,
    Settings as SettingsIcon,
    MessageSquare,
    GitBranch,
    Activity,
    Sparkles,
    LayoutDashboard,
    ListTree,
    Bot,
    Edit3,
    Trash2,
    CheckCircle2,
    Calendar,
    ArrowRight,
    Star,
    Zap,
    Edit,
    Layers,
    Clock,
    Loader2
} from 'lucide-react'
import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { useInView } from 'react-intersection-observer'
import { apiClient } from '@/lib/api/client'
import PageHeader from '@/components/PageHeader'
import { KpiCard } from '@/components/kpi/KpiCard'
import { FlowTypeSelectionModal } from './components/FlowTypeSelectionModal'
import { chatBuilderApi } from './api/builder'
import { useAuthStore } from '@/store/authStore'
import { Button } from '@/components/ui/Button'
import { useMobile } from '@/hooks/useMobile'
import { MobileFlowListPage } from './MobileFlowListPage'

type FlowKind = 'chatbot' | 'ai_agent';

interface AgentConfig {
    model?: string;
    system_prompt?: string;
}

interface ChatFlow {
    id: number
    name: string
    kind: FlowKind
    is_default: boolean
    keywords: string[] | null
    persona_name: string | null
    persona_avatar: string | null
    agent_config: AgentConfig
    created_at: string
    updated_at: string
}

interface FlowsResponse {
    flows: ChatFlow[];
    total: number;
    limit: number;
    offset: number;
}

type TabId = 'overview' | 'analytics' | 'settings'

export function FlowListPage() {
    const isMobile = useMobile()
    const queryClient = useQueryClient()
    const navigate = useNavigate()
    const [newFlowName, setNewFlowName] = useState('')
    const [search, setSearch] = useState('')
    const [activeTab, setActiveTab] = useState<TabId>('overview')
    const [mobileTab, setMobileTab] = useState<'overview' | 'flows' | 'personas' | 'analytics'>('overview')
    const [isCreateModalOpen, setIsCreateModalOpen] = useState(false)
    const [isCreatingFlow, setIsCreatingFlow] = useState(false)

    const currentUser = useAuthStore(s => s.user)
    const isVisitor = currentUser?.user_type_slug === 'visitor' || currentUser?.user_type_slug === 'client' || (currentUser?.user_type || '').toLowerCase().includes('visitante') || (currentUser?.user_type || '').toLowerCase().includes('client')

    // Mock data para visitors/clients
    const mockFlows: ChatFlow[] = useMemo(() => [
        { id: 1, name: 'Atendente Virtual', kind: 'ai_agent' as FlowKind, is_default: true, keywords: ['ajuda', 'suporte', 'atendimento'], persona_name: 'Sofia', persona_avatar: null, agent_config: { model: 'gpt-4o', system_prompt: '' }, created_at: '2026-03-10T10:00:00Z', updated_at: '2026-03-25T15:30:00Z' },
        { id: 2, name: 'Qualificação de Leads', kind: 'chatbot' as FlowKind, is_default: false, keywords: ['preço', 'orçamento', 'plano'], persona_name: 'Carlos', persona_avatar: null, agent_config: {}, created_at: '2026-03-12T08:00:00Z', updated_at: '2026-03-24T09:00:00Z' },
        { id: 3, name: 'FAQ Automatizado', kind: 'chatbot' as FlowKind, is_default: false, keywords: ['faq', 'dúvida', 'como funciona'], persona_name: null, persona_avatar: null, agent_config: {}, created_at: '2026-03-15T14:00:00Z', updated_at: '2026-03-23T11:00:00Z' },
        { id: 4, name: 'Onboarding de Clientes', kind: 'ai_agent' as FlowKind, is_default: false, keywords: ['começar', 'primeiro passo'], persona_name: 'Ana', persona_avatar: null, agent_config: { model: 'gpt-4o', system_prompt: '' }, created_at: '2026-03-18T09:00:00Z', updated_at: '2026-03-22T16:00:00Z' },
    ], [])

    // Infinite Query for Flows
    const {
        data,
        fetchNextPage,
        hasNextPage,
        isFetchingNextPage,
        status,
    } = useInfiniteQuery({
        queryKey: ['chatFlows', search],
        queryFn: async ({ pageParam = 0 }) => {
            const res = await apiClient.get<FlowsResponse>('/api/v1/flows', {
                params: {
                    limit: 50,
                    offset: pageParam,
                    search: search.trim() !== '' ? search : undefined
                }
            })
            return res as FlowsResponse
        },
        initialPageParam: 0,
        getNextPageParam: (lastPage) => {
            const nextOffset = lastPage.offset + lastPage.limit;
            return nextOffset < lastPage.total ? nextOffset : undefined;
        },
        enabled: !isVisitor,
    });

    const flows = isVisitor ? mockFlows : (data?.pages.flatMap(page => page.flows) || []);
    const totalFlows = isVisitor ? mockFlows.length : (data?.pages[0]?.total || 0);

    // Intersection observer for infinite scroll
    const { ref, inView } = useInView({
        threshold: 0.5,
    });

    useEffect(() => {
        if (inView && hasNextPage && !isFetchingNextPage) {
            fetchNextPage();
        }
    }, [inView, hasNextPage, isFetchingNextPage, fetchNextPage]);


    // Create mutation
    const createMutation = useMutation({
        mutationFn: async (name: string) => {
            const res = await apiClient.post<ChatFlow>('/api/v1/flows', { name })
            return res as ChatFlow
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['chatFlows'] })
            setNewFlowName('')
            notify.success('Fluxo criado com sucesso!')
        },
        onError: () => {
            notify.error('Erro ao criar fluxo')
        },
    })

    // Delete mutation
    const deleteMutation = useMutation({
        mutationFn: async (id: number) => {
            await apiClient.delete(`/api/v1/flows/${id}`)
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['chatFlows'] })
            notify.success('Fluxo removido!')
        },
        onError: (err: any) => {
            notify.error(err?.response?.data?.error || 'Erro ao remover fluxo')
        },
    })

    // Set default mutation
    const setDefaultMutation = useMutation({
        mutationFn: async (id: number) => {
            await apiClient.put(`/api/v1/flows/${id}/set_default`)
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['chatFlows'] })
            notify.success('Fluxo definido como padrão!')
        },
        onError: () => {
            notify.error('Erro ao definir padrão')
        },
    })

    const handleCreateFromModal = async (kind: FlowKind, name: string) => {
        setIsCreatingFlow(true)
        try {
            const flow = await chatBuilderApi.createFlow({
                name,
                kind,
                definition: kind === 'chatbot' ? { nodes: [], edges: [] } : undefined,
                agent_config: kind === 'ai_agent' ? { model: 'gpt-4o', system_prompt: '' } : undefined,
            })
            queryClient.invalidateQueries({ queryKey: ['chatFlows'] })
            notify.success('Fluxo criado com sucesso!')
            setIsCreateModalOpen(false)
            // Navigate to the builder with the new flow
            navigate(`/admin/chat/builder?flowId=${flow.id}`)
        } catch (error) {
            console.error('Failed to create flow', error)
            notify.error('Erro ao criar fluxo')
        } finally {
            setIsCreatingFlow(false)
        }
    }

    // Stats
    const flowsWithKeywords = flows.filter(f => f.keywords && f.keywords.length > 0).length
    const flowsWithPersona = flows.filter(f => f.persona_name).length
    const defaultFlow = flows.find(f => f.is_default)

    // Time ago helper
    const getTimeAgo = (dateStr?: string | null): string => {
        if (!dateStr) return 'N/A'
        const now = new Date()
        const date = new Date(dateStr)
        const diffMs = now.getTime() - date.getTime()
        const diffMins = Math.floor(diffMs / 60000)
        const diffHours = Math.floor(diffMs / 3600000)
        const diffDays = Math.floor(diffMs / 86400000)

        if (diffMins < 1) return 'Agora'
        if (diffMins < 60) return `${diffMins}min`
        if (diffHours < 24) return `${diffHours}h`
        if (diffDays === 1) return 'Ontem'
        if (diffDays < 7) return `${diffDays}d`
        return `${Math.floor(diffDays / 7)}sem`
    }

    const tabs: { id: TabId, label: string, icon: any }[] = [
        { id: 'overview', label: 'Visão Geral & Fluxos', icon: LayoutDashboard },
        { id: 'analytics', label: 'Analytics', icon: BarChart3 },
        { id: 'settings', label: 'Configurações', icon: SettingsIcon },
    ]

    // Mock analytics data (to be replaced with real API data later)
    const mockAnalytics = {
        totalConversations: 1247,
        avgFlowCompletion: 68.5,
        dropOffRate: 23.2,
        avgMessagesPerSession: 8.4,
    }

    if (isMobile) return (
        <>
            <MobileFlowListPage
                flows={flows}
                isLoading={!isVisitor && status === 'pending'}
                activeTab={mobileTab}
                setActiveTab={setMobileTab}
                search={search}
                setSearch={setSearch}
                newFlowName={newFlowName}
                setNewFlowName={setNewFlowName}
                handleCreate={() => setIsCreateModalOpen(true)}
                isPending={isCreatingFlow}
                getTimeAgo={getTimeAgo}
            />
            <FlowTypeSelectionModal
                isOpen={isCreateModalOpen}
                onClose={() => setIsCreateModalOpen(false)}
                onSelect={handleCreateFromModal}
                isCreating={isCreatingFlow}
            />
        </>
    )

    return (
        <div className="space-y-6">
            <PageHeader
                title="Chatbot"
                subtitle="Gerencie seus fluxos de conversa e automações"
                rightSlot={
                    <div className="flex items-center gap-2">
                        <Link
                            to="/admin/chat/executions"
                            className="inline-flex items-center gap-2 h-10 px-5 rounded-md border border-input bg-background text-foreground text-sm font-medium transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <Activity className="h-4 w-4" />
                            Execuções
                        </Link>
                        <Link
                            to="/admin/chat/builder"
                            className="inline-flex items-center gap-2 h-10 px-5 rounded-md bg-primary text-primary-foreground text-sm font-medium shadow-e1 transition-colors hover:bg-brand-gold-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <GitBranch className="h-4 w-4" />
                            Abrir Builder
                        </Link>
                    </div>
                }
            />

            {/* Tabs */}
            <div className="flex gap-1 bg-secondary border border-border p-1 rounded-md w-fit">
                {tabs.map(tab => (
                    <button
                        key={tab.id}
                        type="button"
                        onClick={() => setActiveTab(tab.id)}
                        className={`px-4 py-2 rounded-sm text-sm font-medium transition flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeTab === tab.id
                            ? 'bg-card border border-border text-foreground shadow-e1'
                            : 'text-muted-foreground hover:text-foreground border border-transparent'
                            }`}
                    >
                        <tab.icon className="h-4 w-4" />
                        {tab.label}
                    </button>
                ))}
            </div>

            {/* Tab Content */}
            {activeTab === 'overview' && (
                <div className="space-y-6">
                    {/* KPI Cards */}
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                        <KpiCard
                            title="Total de Fluxos"
                            value={String(totalFlows)}
                            icon={Layers}
                            color="hsl(var(--info))"
                            change={`${totalFlows} fluxos no total`}
                            changeType="neutral"
                        />
                        <KpiCard
                            title="Com Keywords"
                            value={String(flowsWithKeywords)}
                            icon={Zap}
                            color="hsl(var(--primary))"
                            change="Gatilhos testados"
                            changeType={flowsWithKeywords > 0 ? "positive" : "neutral"}
                        />
                        <KpiCard
                            title="Com Persona"
                            value={String(flowsWithPersona)}
                            icon={Bot}
                            color="hsl(var(--success))"
                            change="Personas ativas"
                            changeType={flowsWithPersona > 0 ? "positive" : "neutral"}
                        />
                        <KpiCard
                            title="Fluxo Padrão"
                            value={defaultFlow ? "Ativo" : "Nenhum"}
                            icon={Star}
                            color="hsl(var(--warning))"
                            change={defaultFlow?.name || "Necessita atenção"}
                            changeType={defaultFlow ? "positive" : "negative"}
                        />
                    </div>

                    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                        {/* Main list: All Flows with Triggers, Search and Infinite Scroll */}
                        <div className="lg:col-span-2 space-y-4">
                            <div className="flex items-center gap-2 bg-secondary border border-border p-1 rounded-md w-full focus-within:ring-2 focus-within:ring-ring">
                                <Search className="w-4 h-4 ml-2 text-muted-foreground" />
                                <input
                                    type="text"
                                    placeholder="Buscar por nome, palavras-chaves, status..."
                                    value={search}
                                    onChange={(e) => setSearch(e.target.value)}
                                    className="bg-transparent border-none focus:ring-0 text-sm w-full py-1.5"
                                />
                            </div>

                            <div className="glass-panel rounded-lg overflow-hidden">
                                <div className="p-4 border-b border-border flex items-center justify-between">
                                    <h3 className="font-semibold flex items-center gap-2">
                                        <GitBranch className="h-4 w-4 text-primary" />
                                        Lista de Fluxos
                                    </h3>
                                    <span className="text-xs text-muted-foreground"><span className="font-numeric">{totalFlows}</span> itens encontrados</span>
                                </div>
                                <div className="divide-y divide-border max-h-[600px] overflow-y-auto scrollbar-thin">
                                    {!isVisitor && status === 'pending' ? (
                                        <div className="p-10 text-center text-muted-foreground flex flex-col items-center justify-center">
                                            <Loader2 className="h-8 w-8 animate-spin mb-2" />
                                            <p className="text-sm">Carregando fluxos...</p>
                                        </div>
                                    ) : flows.length === 0 ? (
                                        <div className="p-10 text-center text-muted-foreground">
                                            <Bot className="h-10 w-10 mx-auto mb-2 opacity-20" />
                                            <p className="text-sm">Nenhum fluxo encontrado</p>
                                        </div>
                                    ) : (
                                        <>
                                            {flows.map(flow => (
                                                <div key={flow.id} className="p-4 hover:bg-accent transition-colors group">
                                                    <div className="flex items-start justify-between gap-4">
                                                        <div className="space-y-2 flex-1">
                                                            <div className="flex items-center gap-2">
                                                                <span className="font-semibold text-foreground group-hover:text-primary transition-colors">
                                                                    {flow.name}
                                                                </span>
                                                                {flow.kind === 'ai_agent' ? (
                                                                    <span className="px-1.5 py-0.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-sm font-bold uppercase tracking-wider flex items-center gap-1">
                                                                        <Bot className="h-2.5 w-2.5" />
                                                                        Agente IA
                                                                    </span>
                                                                ) : (
                                                                    <span className="px-1.5 py-0.5 text-xs bg-info/10 text-info border border-info/20 rounded-sm font-bold uppercase tracking-wider flex items-center gap-1">
                                                                        <GitBranch className="h-2.5 w-2.5" />
                                                                        Chatbot
                                                                    </span>
                                                                )}
                                                                {flow.is_default && (
                                                                    <span className="px-1.5 py-0.5 text-xs bg-warning/10 text-warning border border-warning/20 rounded-sm font-bold uppercase tracking-wider">
                                                                        Padrão
                                                                    </span>
                                                                )}
                                                            </div>

                                                            {/* Keywords Row */}
                                                            <div className="flex flex-wrap gap-1.5">
                                                                {flow.keywords && flow.keywords.length > 0 ? (
                                                                    flow.keywords.map((kw, i) => (
                                                                        <span key={i} className="px-2 py-0.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-full flex items-center gap-1">
                                                                            <Sparkles className="h-2.5 w-2.5" />
                                                                            {kw}
                                                                        </span>
                                                                    ))
                                                                ) : (
                                                                    <span className="text-xs text-muted-foreground italic flex items-center gap-1">
                                                                        <Zap className="h-3 w-3 opacity-50" />
                                                                        Sem palavras-chave de ativação
                                                                    </span>
                                                                )}
                                                            </div>

                                                            {/* Persona Row */}
                                                            <div className="flex items-center gap-3 mt-1">
                                                                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                                                    {flow.persona_avatar ? (
                                                                        <img src={flow.persona_avatar} alt={flow.persona_name || ''} className="h-4 w-4 rounded-full object-cover border border-border" />
                                                                    ) : (
                                                                        <div className="h-4 w-4 rounded-full overflow-hidden border border-border bg-muted flex items-center justify-center">
                                                                            <Bot className="h-3 w-3" />
                                                                        </div>
                                                                    )}
                                                                    Persona: <span className="text-foreground font-medium">{flow.persona_name || 'Al Bot (Padrão)'}</span>
                                                                </div>
                                                                <span className="h-1 w-1 rounded-full bg-border" />
                                                                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                                                    <Clock className="h-3.5 w-3.5" />
                                                                    Última edição {getTimeAgo(flow.updated_at)}
                                                                </div>
                                                            </div>
                                                        </div>
                                                        <div className="flex flex-col items-end gap-2">
                                                            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                                                <Button
                                                                    variant="ghost"
                                                                    size="icon"
                                                                    className="h-8 w-8"
                                                                    onClick={() => setDefaultMutation.mutate(flow.id)}
                                                                    title={flow.is_default ? "Fluxo Padrão" : "Definir como Padrão"}
                                                                    disabled={flow.is_default}
                                                                >
                                                                    <Star className={`w-4 h-4 ${flow.is_default ? 'fill-current text-warning' : ''}`} />
                                                                </Button>
                                                                <Link
                                                                    to={`/admin/chat/builder?flowId=${flow.id}`}
                                                                    className="inline-flex items-center justify-center h-8 w-8 rounded-md text-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                                                                    title="Abrir no Builder"
                                                                >
                                                                    <Edit className="h-4 w-4" />
                                                                </Link>
                                                                <Button
                                                                    variant="ghost"
                                                                    size="icon"
                                                                    className="h-8 w-8"
                                                                    onClick={() => deleteMutation.mutate(flow.id)}
                                                                    title="Excluir Fluxo"
                                                                >
                                                                    <Trash2 className="h-4 w-4 text-destructive" />
                                                                </Button>
                                                            </div>
                                                        </div>
                                                    </div>
                                                </div>
                                            ))}
                                            <div ref={ref} className="p-4 flex justify-center">
                                                {isFetchingNextPage ? (
                                                    <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                                                ) : hasNextPage ? (
                                                    <span className="text-xs text-muted-foreground">Rolar para mais</span>
                                                ) : (
                                                    <span className="text-xs text-muted-foreground">Fim da lista</span>
                                                )}
                                            </div>
                                        </>
                                    )}
                                </div>
                            </div>
                        </div>

                        {/* Recent Activity & Create Side Column */}
                        <div className="space-y-6">
                            {/* Quick create */}
                            <div className="glass-panel rounded-lg p-5 space-y-4">
                                <div className="flex items-center gap-2">
                                    <div className="h-8 w-8 rounded-md bg-primary/10 flex items-center justify-center">
                                        <Plus className="h-4 w-4 text-primary" />
                                    </div>
                                    <h3 className="font-semibold">Novo Fluxo</h3>
                                </div>
                                <div className="space-y-3">
                                    <p className="text-xs text-muted-foreground">
                                        Escolha entre criar um Chatbot com fluxo visual ou um AI Agent com inteligência autônoma.
                                    </p>
                                    <Button
                                        variant="primary"
                                        className="w-full"
                                        onClick={() => setIsCreateModalOpen(true)}
                                    >
                                        <Plus className="h-4 w-4" />
                                        Criar Novo Fluxo
                                    </Button>
                                </div>
                            </div>

                            {/* Recent activity card */}
                            <div className="glass-panel rounded-lg overflow-hidden">
                                <div className="p-4 border-b border-border">
                                    <h3 className="font-semibold flex items-center gap-2 text-sm">
                                        <Activity className="h-4 w-4 text-success" />
                                        Alterações Recentes
                                    </h3>
                                </div>
                                <div className="p-4 space-y-4">
                                    {flows.slice(0, 4).map(flow => (
                                        <div key={flow.id} className="flex items-start gap-3">
                                            <div className="h-2 w-2 rounded-full bg-success mt-1.5" />
                                            <div className="flex-1 space-y-0.5">
                                                <p className="text-sm font-medium leading-none">{flow.name}</p>
                                                <p className="text-xs text-muted-foreground">Editado <span className="font-numeric">{getTimeAgo(flow.updated_at)}</span></p>
                                            </div>
                                        </div>
                                    ))}
                                    {flows.length === 0 && (
                                        <p className="text-xs text-muted-foreground text-center py-4">Sem atividade registrada</p>
                                    )}
                                </div>
                            </div>

                            {/* Info card */}
                            <div className="p-4 bg-primary/5 rounded-lg border border-primary/20">
                                <h4 className="text-xs font-bold text-primary uppercase mb-2">Dica Pro</h4>
                                <p className="text-xs text-muted-foreground leading-relaxed">
                                    Configure <strong>Keywords</strong> específicas para cada fluxo para que o bot as identifique automaticamente em qualquer conversa global.
                                </p>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {activeTab === 'analytics' && (
                <div className="space-y-6">
                    {/* Analytics KPIs */}
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                        <KpiCard
                            title="Conversas Totais"
                            value={mockAnalytics.totalConversations.toLocaleString()}
                            icon={MessageSquare}
                            color="hsl(var(--info))"
                            change="+12.5%"
                            changeType="positive"
                        />
                        <KpiCard
                            title="Conclusão de Fluxo"
                            value={`${mockAnalytics.avgFlowCompletion}%`}
                            icon={GitBranch}
                            color="hsl(var(--success))"
                            change="Taxa média"
                            changeType="positive"
                        />
                        <KpiCard
                            title="Taxa de Abandono"
                            value={`${mockAnalytics.dropOffRate}%`}
                            icon={Activity}
                            color="hsl(var(--warning))"
                            change="Usuários que saem"
                            changeType="negative"
                        />
                        <KpiCard
                            title="Msgs / Sessão"
                            value={String(mockAnalytics.avgMessagesPerSession)}
                            icon={Sparkles}
                            color="hsl(var(--primary))"
                            change="Engajamento"
                            changeType="positive"
                        />
                    </div>

                    {/* Placeholder for charts */}
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        <div className="glass-panel rounded-lg p-6 h-[300px] flex flex-col">
                            <h3 className="font-semibold mb-4 flex items-center gap-2">
                                <BarChart3 className="h-4 w-4 text-primary" />
                                Conversas por Dia
                            </h3>
                            <div className="flex-1 flex items-center justify-center text-muted-foreground">
                                <div className="text-center">
                                    <BarChart3 className="h-12 w-12 mx-auto mb-2 opacity-20" />
                                    <p className="text-sm">Gráfico em breve</p>
                                    <p className="text-xs">Integração com analytics</p>
                                </div>
                            </div>
                        </div>

                        <div className="glass-panel rounded-lg p-6 h-[300px] flex flex-col">
                            <h3 className="font-semibold mb-4 flex items-center gap-2">
                                <GitBranch className="h-4 w-4 text-success" />
                                Conclusão por Fluxo
                            </h3>
                            <div className="flex-1 space-y-3">
                                {flows.slice(0, 5).map((flow, idx) => {
                                    const completion = Math.floor(40 + Math.random() * 50);
                                    return (
                                        <div key={flow.id} className="space-y-1">
                                            <div className="flex items-center justify-between text-sm">
                                                <span className="truncate max-w-[200px]">{flow.name}</span>
                                                <span className="font-medium font-numeric">{completion}%</span>
                                            </div>
                                            <div className="h-2 bg-muted rounded-full overflow-hidden">
                                                <div
                                                    className="h-full bg-success rounded-full transition-all"
                                                    style={{ width: `${completion}%` }}
                                                />
                                            </div>
                                        </div>
                                    )
                                })}
                                {flows.length === 0 && (
                                    <p className="text-sm text-muted-foreground text-center py-8">Nenhum fluxo para analisar</p>
                                )}
                            </div>
                        </div>
                    </div>

                    {/* Drop-off analysis placeholder */}
                    <div className="glass-panel rounded-lg p-6">
                        <h3 className="font-semibold mb-4 flex items-center gap-2">
                            <Activity className="h-4 w-4 text-warning" />
                            Pontos de Abandono
                        </h3>
                        <p className="text-sm text-muted-foreground mb-4">
                            Identifique onde os usuários abandonam o fluxo para otimizar suas conversas.
                        </p>
                        <div className="flex items-center gap-4 text-sm">
                            <div className="flex items-center gap-2 px-3 py-1.5 bg-destructive/10 text-destructive rounded-md">
                                <span className="font-medium">Passo <span className="font-numeric">3</span></span>
                                <span className="text-xs opacity-70 font-numeric">(32% de abandono)</span>
                            </div>
                            <div className="flex items-center gap-2 px-3 py-1.5 bg-warning/10 text-warning rounded-md">
                                <span className="font-medium">Passo <span className="font-numeric">5</span></span>
                                <span className="text-xs opacity-70 font-numeric">(18% de abandono)</span>
                            </div>
                            <div className="flex items-center gap-2 px-3 py-1.5 bg-muted text-muted-foreground rounded-md">
                                <span className="font-medium">Passo <span className="font-numeric">2</span></span>
                                <span className="text-xs opacity-70 font-numeric">(8% de abandono)</span>
                            </div>
                        </div>
                    </div>
                </div>
            )}


            {activeTab === 'settings' && (
                <div className="space-y-6">
                    <div className="glass-panel rounded-lg p-6">
                        <h3 className="font-semibold mb-4 flex items-center gap-2">
                            <SettingsIcon className="h-4 w-4 text-muted-foreground" />
                            Configurações Gerais
                        </h3>
                        <p className="text-sm text-muted-foreground">
                            Configurações do chatbot em breve. Aqui você poderá ajustar comportamentos globais, integrações e preferências.
                        </p>
                    </div>
                </div>
            )}

            {/* Flow Type Selection Modal */}
            <FlowTypeSelectionModal
                isOpen={isCreateModalOpen}
                onClose={() => setIsCreateModalOpen(false)}
                onSelect={handleCreateFromModal}
                isCreating={isCreatingFlow}
            />
        </div>
    )
}
