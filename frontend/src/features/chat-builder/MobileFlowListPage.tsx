import { useNavigate } from 'react-router-dom'
import {
    Plus,
    Search,
    GitBranch,
    Activity,
    Sparkles,
    Bot,
    Edit,
    Zap,
    Clock,
    Loader2,
    MessageSquare,
    BarChart3,
    ArrowRight,
    UserPlus,
    Check,
    Image as ImageIcon,
    X,
} from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { KpiCard } from '@/components/kpi/KpiCard'
import { cn } from '@/lib/utils'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { useState, useMemo, useEffect } from 'react'
import { notify } from '@/lib/notify'

type FlowKind = 'chatbot' | 'ai_agent'

interface AgentConfig {
    model?: string
    system_prompt?: string
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

type TabId = 'overview' | 'flows' | 'personas' | 'analytics'

const PersonaFormSheet = ({
    visible,
    onClose,
    persona,
    onSave
}: {
    visible: boolean
    onClose: () => void
    persona: any
    onSave: (data: any) => void
}) => {
    return (
        <div
            className={`absolute top-0 right-0 w-full sm:w-[420px] h-full bg-popover border-l border-border flex flex-col transition-transform duration-200 will-change-transform ${visible ? 'translate-x-0' : 'translate-x-full'}`}
            data-helper
        >
            <div className="flex-1 overflow-y-auto px-6 pt-[7px] pb-6">
                <div className="space-y-5 mt-0">
                    <div className="flex items-center justify-between">
                        <h2 className="text-xl font-semibold text-foreground">
                            {persona.name ? 'Editar Persona' : 'Nova Persona'}
                        </h2>
                    </div>

                    <div className="space-y-6">
                        <div className="space-y-2">
                            <Label
                                htmlFor="persona-name"
                                className="text-sm font-medium text-foreground flex items-center gap-2"
                            >
                                <UserPlus className="h-3.5 w-3.5 text-primary" />
                                Nome da Persona <span className="text-destructive">*</span>
                            </Label>
                            <Input
                                id="persona-name"
                                placeholder="Ex: Marta do Suporte"
                                value={persona.name}
                                onChange={(e: React.ChangeEvent<HTMLInputElement>) => onSave({ ...persona, name: e.target.value })}
                                className="rounded-md"
                                required
                            />
                        </div>

                        <div className="space-y-2">
                            <Label
                                htmlFor="persona-role"
                                className="text-sm font-medium text-foreground flex items-center gap-2"
                            >
                                <Sparkles className="h-3.5 w-3.5 text-primary" />
                                Papel / Função
                            </Label>
                            <Input
                                id="persona-role"
                                placeholder="Ex: Especialista em Vendas"
                                value={persona.role}
                                onChange={(e: React.ChangeEvent<HTMLInputElement>) => onSave({ ...persona, role: e.target.value })}
                                className="rounded-md"
                            />
                        </div>

                        <div className="space-y-4 pt-2">
                            <Label className="text-sm font-medium text-foreground flex items-center gap-2">
                                <ImageIcon className="h-3.5 w-3.5 text-primary" />
                                Preview Visual
                            </Label>
                            <div className="flex items-center gap-4 p-4 rounded-lg bg-muted/30 border border-border">
                                <div className="h-16 w-16 rounded-md bg-background border border-border flex items-center justify-center overflow-hidden">
                                    {persona.name || persona.avatar ? (
                                        <img
                                            src={persona.avatar || `https://api.dicebear.com/7.x/avataaars/svg?seed=${persona.name}`}
                                            alt="Preview"
                                            className="w-full h-full object-cover"
                                        />
                                    ) : (
                                        <UserPlus className="h-6 w-6 text-muted-foreground/30" />
                                    )}
                                </div>
                                <div className="flex-1">
                                    <p className="text-[10px] font-bold text-muted-foreground leading-tight italic">
                                        O sistema gera um avatar único automaticamente baseado no nome.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <Button variant="ghost" size="icon" aria-label="Fechar" className="absolute top-4 right-4" onClick={onClose}>
                <X className="h-4 w-4" />
            </Button>
            <Button
                variant="primary"
                className="helper-fab absolute right-6 bottom-6 h-12 w-12 p-0 rounded-full shadow-e2"
                disabled={!persona.name}
                onClick={() => { notify.success('Persona salva com sucesso!'); onClose() }}
                aria-label="Salvar persona"
            >
                <Check className="h-6 w-6" />
            </Button>
        </div>
    )
}

interface MobileFlowListPageProps {
    flows: ChatFlow[]
    isLoading: boolean
    activeTab: TabId
    setActiveTab: (tab: TabId) => void
    search: string
    setSearch: (s: string) => void
    newFlowName: string
    setNewFlowName: (s: string) => void
    handleCreate: () => void
    isPending: boolean
    getTimeAgo: (date?: string | null) => string
}

export function MobileFlowListPage({
    flows,
    isLoading,
    activeTab,
    setActiveTab,
    search,
    setSearch,
    newFlowName,
    setNewFlowName,
    handleCreate,
    isPending,
    getTimeAgo
}: MobileFlowListPageProps) {
    const navigate = useNavigate()
    const [isNewPersonaOpen, setIsNewPersonaOpen] = useState(false)
    const [personaMounted, setPersonaMounted] = useState(false)
    const [personaVisible, setPersonaVisible] = useState(false)
    const [personaForm, setPersonaForm] = useState({ name: '', role: '', avatar: '' })

    useEffect(() => {
        if (isNewPersonaOpen) {
            setPersonaMounted(true); setPersonaVisible(false)
            const t = setTimeout(() => setPersonaVisible(true), 0)
            return () => clearTimeout(t)
        }
        setPersonaVisible(false)
        const t = setTimeout(() => setPersonaMounted(false), 200)
        return () => clearTimeout(t)
    }, [isNewPersonaOpen])

    const flowsArray = Array.isArray(flows) ? flows : []

    const activePersonas = useMemo(() => {
        const personasMap = new Map()

        const defaultPersonas = [
            { name: 'Marta Atendimento', role: 'Vendas e Suporte', avatar: '/images/avatars/martha.png', count: 0 },
            { name: 'Anna Assistente', role: 'Gestão de Leads', avatar: '/images/avatars/anna.png', count: 0 },
            { name: 'Maju AI', role: 'Atendimento Geral', avatar: '/images/avatars/maju.png', count: 0 }
        ]

        defaultPersonas.forEach(p => personasMap.set(p.name, p))

        flowsArray.forEach(flow => {
            if (flow.persona_name) {
                const existing = personasMap.get(flow.persona_name)
                if (existing) {
                    existing.count += 1
                } else {
                    const matchedDefault = defaultPersonas.find(dp =>
                        flow.persona_name?.toLocaleLowerCase().includes(dp.name.split(' ')[0].toLocaleLowerCase())
                    )
                    personasMap.set(flow.persona_name, {
                        name: flow.persona_name,
                        role: 'Persona Customizada',
                        avatar: flow.persona_avatar || matchedDefault?.avatar || `https://api.dicebear.com/7.x/avataaars/svg?seed=${flow.persona_name}`,
                        count: 1
                    })
                }
            }
        })

        return Array.from(personasMap.values())
    }, [flowsArray])

    const tabs = [
        { id: 'overview' as const, label: 'Início', icon: Zap },
        { id: 'flows' as const, label: 'Fluxos', icon: GitBranch },
        { id: 'personas' as const, label: 'Personas', icon: Bot },
        { id: 'analytics' as const, label: 'Dados', icon: BarChart3 },
    ]

    const flowsWithKeywords = flowsArray.filter(f => f.keywords && f.keywords.length > 0).length

    if (isLoading) {
        return (
            <div className="flex flex-col items-center justify-center h-[60vh] gap-4">
                <Loader2 className="h-8 w-8 animate-spin text-primary" />
                <p className="text-sm text-muted-foreground animate-pulse font-medium">Carregando inteligência...</p>
            </div>
        )
    }

    return (
        <div className="flex flex-col pb-24 space-y-6">
            {/* Header Mobile */}
            <div className="flex items-center justify-between px-6 pt-2">
                <div>
                    <h1 className="text-2xl font-black tracking-tighter text-foreground uppercase">Chatbot</h1>
                    <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest opacity-60">
                        Automação & IA
                    </p>
                </div>
                <Button
                    variant="primary"
                    size="sm"
                    className="flex items-center gap-2 h-10 px-4"
                    onClick={() => navigate('/admin/chat/builder')}
                >
                    <GitBranch size={16} />
                    Builder
                </Button>
            </div>

            {/* Tab Selector */}
            <div className="px-6">
                <div className="flex p-1 gap-1 bg-muted/30 backdrop-blur-md rounded-lg border border-border/50">
                    {tabs.map((tab) => {
                        const Icon = tab.icon
                        const isActive = activeTab === tab.id
                        return (
                            <button
                                key={tab.id}
                                type="button"
                                onClick={() => setActiveTab(tab.id)}
                                className={cn(
                                    "flex-1 flex flex-col items-center justify-center py-2.5 rounded-md transition-all duration-300 gap-1",
                                    "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                                    isActive
                                        ? "bg-background text-primary shadow-e2 ring-1 ring-border/20"
                                        : "text-muted-foreground hover:text-foreground hover:bg-accent hover:text-accent-foreground"
                                )}
                            >
                                <Icon size={18} className={cn(isActive && "text-primary")} />
                                <span className="text-[10px] font-black uppercase tracking-tighter">{tab.label}</span>
                            </button>
                        )
                    })}
                </div>
            </div>

            {/* Tab Content */}
            <div className="px-6 pb-4">
                {/* Overview Tab */}
                {activeTab === 'overview' && (
                    <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">
                        <div className="grid grid-cols-2 gap-3">
                            <KpiCard
                                title="Total"
                                value={String(flowsArray.length)}
                                icon={GitBranch}
                                color="hsl(var(--info))"
                                changeLabel="Fluxos ativos"
                                changeType="neutral"
                            />
                            <KpiCard
                                title="Keywords"
                                value={String(flowsWithKeywords)}
                                icon={Zap}
                                color="hsl(var(--primary))"
                                changeLabel="Gatilhos"
                                changeType="neutral"
                            />
                        </div>

                        {/* Recent Activity */}
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <h3 className="text-[11px] font-black uppercase tracking-[0.2em] text-muted-foreground/60 flex items-center gap-2">
                                    <Activity size={14} className="text-success" /> Atividades Recentes
                                </h3>
                            </div>
                            <div className="bg-card/30 backdrop-blur-xl rounded-lg p-5 border border-border/50 divide-y divide-border/20 space-y-4">
                                {flowsArray.slice(0, 3).map((flow) => (
                                    <div key={flow.id} className="pt-4 first:pt-0 flex items-center justify-between group">
                                        <div className="flex items-start gap-3">
                                            <div className="h-2 w-2 rounded-full bg-success mt-2" />
                                            <div>
                                                <p className="text-sm font-bold text-foreground leading-tight">{flow.name}</p>
                                                <p className="text-[10px] font-numeric text-muted-foreground">há {getTimeAgo(flow.updated_at)}</p>
                                            </div>
                                        </div>
                                        <Button
                                            variant="ghost"
                                            size="icon"
                                            aria-label={`Abrir ${flow.name} no builder`}
                                            onClick={() => navigate(`/admin/chat/builder?flowId=${flow.id}`)}
                                            className="h-8 w-8 rounded-md"
                                        >
                                            <ArrowRight size={14} />
                                        </Button>
                                    </div>
                                ))}
                                {flowsArray.length === 0 && (
                                    <p className="text-sm text-muted-foreground text-center py-4">Nenhuma atividade registrada</p>
                                )}
                            </div>
                        </div>

                        {/* Quick Create */}
                        <div className="bg-primary/10 p-6 rounded-lg border border-primary/20 shadow-e3 relative overflow-hidden group">
                            <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:scale-110 transition-transform">
                                <Plus size={80} />
                            </div>
                            <div className="relative z-base space-y-5">
                                <div>
                                    <h3 className="text-lg font-black text-foreground tracking-tight">Novo Fluxo Inteligente</h3>
                                    <p className="text-xs text-muted-foreground font-medium">Inicie uma nova automação agora.</p>
                                </div>
                                <div className="space-y-3">
                                    <input
                                        type="text"
                                        placeholder="Ex: Suporte de Vendas..."
                                        value={newFlowName}
                                        onChange={(e) => setNewFlowName(e.target.value)}
                                        className="w-full bg-background border border-input rounded-md px-4 h-12 text-sm font-medium text-foreground focus-visible:ring-2 focus-visible:ring-ring outline-none transition-all placeholder:text-muted-foreground"
                                    />
                                    <Button
                                        onClick={handleCreate}
                                        disabled={isPending || !newFlowName.trim()}
                                        variant="primary"
                                        className="w-full h-12 flex items-center justify-center gap-2"
                                    >
                                        {isPending ? <Loader2 size={18} className="animate-spin" /> : <Zap size={18} />}
                                        {isPending ? 'Criando...' : 'Criar Agora'}
                                    </Button>
                                </div>
                            </div>
                        </div>

                        {/* Pro Tip */}
                        <div className="p-5 bg-muted/20 rounded-lg border border-border/50 flex flex-col gap-3">
                            <div className="flex items-center gap-2">
                                <div className="h-6 w-6 rounded-full bg-info/10 flex items-center justify-center text-info">
                                    <Sparkles size={12} />
                                </div>
                                <span className="text-[10px] font-black uppercase tracking-[0.2em] text-info">Dica Pro</span>
                            </div>
                            <p className="text-xs text-muted-foreground leading-relaxed font-medium">
                                Configure <strong className="text-foreground">Keywords</strong> específicas para cada fluxo para o bot as identifique automaticamente em qualquer conversa global.
                            </p>
                        </div>
                    </div>
                )}

                {/* Flows Tab */}
                {activeTab === 'flows' && (
                    <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
                        <div className="relative group">
                            <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
                            <input
                                type="text"
                                placeholder="Buscar fluxos..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                className="w-full bg-muted/20 border border-input rounded-md pl-11 pr-4 h-12 text-sm font-medium text-foreground focus-visible:ring-2 focus-visible:ring-ring outline-none transition-all placeholder:text-muted-foreground"
                            />
                        </div>

                        <div className="space-y-3">
                            {flowsArray.filter(f => f.name.toLowerCase().includes(search.toLowerCase())).map((flow) => (
                                <div
                                    key={flow.id}
                                    className="bg-card/40 backdrop-blur-xl p-5 rounded-lg border border-border/50 shadow-e1 flex flex-col gap-4 active:scale-[0.98] transition-transform cursor-pointer"
                                    onClick={() => navigate(`/admin/chat/builder?flowId=${flow.id}`)}
                                >
                                    <div className="flex items-start justify-between">
                                        <div className="flex items-center gap-3">
                                            <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center text-primary border border-primary/20">
                                                <GitBranch size={20} />
                                            </div>
                                            <div>
                                                <h4 className="font-bold text-foreground tracking-tight flex items-center gap-2">
                                                    {flow.name}
                                                    {flow.is_default && (
                                                        <Badge variant="secondary" className="text-[8px] h-4 bg-warning/10 text-warning font-black uppercase tracking-widest">Padrão</Badge>
                                                    )}
                                                </h4>
                                                <p className="text-[10px] font-numeric text-muted-foreground">Editado há {getTimeAgo(flow.updated_at)}</p>
                                            </div>
                                        </div>
                                        <Edit size={14} className="text-muted-foreground opacity-60" />
                                    </div>

                                    <div className="flex flex-wrap gap-2">
                                        {flow.keywords?.slice(0, 3).map((kw, i) => (
                                            <span key={i} className="px-2 py-0.5 text-[9px] font-black uppercase tracking-tighter bg-primary/10 text-primary border border-primary/20 rounded-md flex items-center gap-1">
                                                <Sparkles size={8} />
                                                {kw}
                                            </span>
                                        ))}
                                        <div className="flex items-center gap-1.5 px-2 py-0.5 bg-muted/40 rounded-md">
                                            <Bot size={10} className="text-muted-foreground" />
                                            <span className="text-[9px] font-black uppercase tracking-tighter text-muted-foreground">{flow.persona_name || 'Geral'}</span>
                                        </div>
                                    </div>
                                </div>
                            ))}
                            {flowsArray.length === 0 && (
                                <div className="py-20 text-center space-y-3">
                                    <Bot size={40} className="mx-auto text-muted-foreground/20" />
                                    <p className="text-sm text-muted-foreground font-medium">Nenhum fluxo encontrado</p>
                                </div>
                            )}
                        </div>
                    </div>
                )}

                {/* Personas Tab */}
                {activeTab === 'personas' && (
                    <div className="space-y-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
                        <div
                            onClick={() => setIsNewPersonaOpen(true)}
                            className="bg-primary/5 hover:bg-primary/10 border-2 border-dashed border-primary/20 p-8 rounded-lg flex flex-col items-center justify-center text-center gap-3 active:scale-95 transition-all cursor-pointer"
                        >
                            <div className="h-14 w-14 rounded-full bg-primary flex items-center justify-center text-primary-foreground shadow-e3">
                                <Plus size={24} />
                            </div>
                            <div>
                                <h4 className="font-black text-foreground uppercase tracking-tight">Nova Persona</h4>
                                <p className="text-xs text-muted-foreground font-medium">Crie identidades personalizadas para seus assistentes.</p>
                            </div>
                        </div>

                        <div className="grid grid-cols-1 gap-4">
                            {activePersonas.map((persona, i) => (
                                <div key={i} className="bg-card/40 backdrop-blur-xl p-5 rounded-lg border border-border/50 shadow-e1 flex items-center gap-4 relative overflow-hidden group">
                                    <div className="relative">
                                        <div className="h-16 w-16 rounded-lg border-2 border-border p-1 relative z-base overflow-hidden bg-background">
                                            <img
                                                src={persona.avatar}
                                                alt={persona.name}
                                                className="h-full w-full object-cover rounded-md"
                                            />
                                        </div>
                                        {persona.count > 0 && (
                                            <div className="absolute -top-2 -right-2 h-6 w-6 rounded-full bg-primary text-[10px] font-numeric font-black flex items-center justify-center border-2 border-background text-primary-foreground z-sticky">
                                                {persona.count}
                                            </div>
                                        )}
                                    </div>

                                    <div className="flex-1 space-y-1">
                                        <h4 className="font-black text-sm tracking-tight text-foreground leading-none">{persona.name}</h4>
                                        <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">{persona.role}</p>
                                        <div className="flex items-center gap-2 pt-1">
                                            <div className="flex items-center gap-1 text-[9px] font-black uppercase text-primary bg-primary/10 px-2 py-0.5 rounded-md">
                                                <GitBranch size={8} />
                                                <span className="font-numeric">{persona.count}</span> {persona.count === 1 ? 'Fluxo' : 'Fluxos'}
                                            </div>
                                            {persona.count > 0 && (
                                                <span className="text-[9px] font-bold text-success uppercase tracking-tighter">Ativo</span>
                                            )}
                                        </div>
                                    </div>
                                    <Button
                                        variant="ghost"
                                        size="icon"
                                        aria-label={`Editar persona ${persona.name}`}
                                        onClick={() => {
                                            setPersonaForm({ name: persona.name, role: persona.role, avatar: persona.avatar })
                                            setIsNewPersonaOpen(true)
                                        }}
                                        className="h-10 w-10 shrink-0"
                                    >
                                        <Edit size={16} />
                                    </Button>
                                </div>
                            ))}
                        </div>

                        {personaMounted && (
                            <div className="fixed inset-0 z-drawer">
                                <div
                                    className={`absolute inset-0 bg-brand-ink/70 transition-opacity duration-200 ${personaVisible ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
                                    onClick={() => setIsNewPersonaOpen(false)}
                                />
                                <PersonaFormSheet
                                    visible={personaVisible}
                                    onClose={() => setIsNewPersonaOpen(false)}
                                    persona={personaForm}
                                    onSave={setPersonaForm}
                                />
                            </div>
                        )}
                    </div>
                )}

                {/* Analytics Tab */}
                {activeTab === 'analytics' && (
                    <div className="space-y-8 animate-in fade-in slide-in-from-bottom-4 duration-500">
                        <div className="grid grid-cols-2 gap-3">
                            <KpiCard
                                title="Conversas"
                                value="1.2k"
                                icon={MessageSquare}
                                color="hsl(var(--info))"
                                change="12.5%"
                                changeType="positive"
                            />
                            <KpiCard
                                title="Conclusão"
                                value="68%"
                                icon={GitBranch}
                                color="hsl(var(--success))"
                                change="5.2%"
                                changeType="positive"
                            />
                            <KpiCard
                                title="Abandono"
                                value="23%"
                                icon={Activity}
                                color="hsl(var(--warning))"
                                change="1.8%"
                                changeType="negative"
                            />
                            <KpiCard
                                title="Msgs/Sessão"
                                value="8.4"
                                icon={Sparkles}
                                color="hsl(var(--primary))"
                                change="0.5"
                                changeType="positive"
                            />
                        </div>

                        <div className="space-y-4">
                            <h3 className="text-[11px] font-black uppercase tracking-[0.2em] text-muted-foreground/60 flex items-center gap-2">
                                <Activity size={14} className="text-primary" /> Conclusão por Fluxo
                            </h3>
                            <div className="bg-card/40 backdrop-blur-xl p-6 rounded-lg border border-border/50 space-y-6">
                                {[
                                    { name: 'Onboarding Cliente', value: 85, color: 'bg-success' },
                                    { name: 'Suporte de Vendas', value: 62, color: 'bg-primary' },
                                    { name: 'Dúvidas Técnicas', value: 45, color: 'bg-info' }
                                ].map((item, i) => (
                                    <div key={i} className="space-y-2">
                                        <div className="flex justify-between items-center text-xs">
                                            <span className="font-bold tracking-tight">{item.name}</span>
                                            <span className="font-numeric font-black text-primary">{item.value}%</span>
                                        </div>
                                        <div className="h-2 w-full bg-muted/50 rounded-full overflow-hidden">
                                            <div
                                                className={cn("h-full rounded-full transition-all duration-1000", item.color)}
                                                style={{ width: `${item.value}%` }}
                                            />
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>

                        <div className="space-y-4">
                            <h3 className="text-[11px] font-black uppercase tracking-[0.2em] text-muted-foreground/60 flex items-center gap-2">
                                <Activity size={14} className="text-warning" /> Pontos de Abandono
                            </h3>
                            <div className="flex flex-wrap gap-2">
                                {[
                                    { label: 'Passo 3', val: '32% de saída', tone: 'negative' },
                                    { label: 'Passo 5', val: '18% de saída', tone: 'warning' },
                                    { label: 'Passo 2', val: '8% de saída', tone: 'muted' }
                                ].map((chip, i) => (
                                    <div key={i} className={cn(
                                        "px-4 py-2 rounded-lg border flex items-center gap-2",
                                        chip.tone === 'negative' ? "bg-negative/10 border-negative/30 text-negative" :
                                        chip.tone === 'warning' ? "bg-warning/10 border-warning/30 text-warning" :
                                        "bg-muted border-border text-muted-foreground"
                                    )}>
                                        <span className="text-[10px] font-black uppercase tracking-tighter">{chip.label}</span>
                                        <span className="text-[10px] font-numeric font-bold opacity-70">{chip.val}</span>
                                    </div>
                                ))}
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
