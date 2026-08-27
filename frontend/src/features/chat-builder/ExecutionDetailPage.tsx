import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { flowExecutionsApi, FlowExecutionStep } from '@/lib/api/endpoints'
import { format } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import { timeAgo } from '@/lib/utils/date'
import {
    Activity,
    User,
    Clock,
    MessageSquare,
    HelpCircle,
    MousePointer,
    GitBranch,
    Play,
    ArrowRight,
    ArrowLeft,
    RefreshCw,
    Layers,
    Calendar,
    Hash,
    Database,
    Code,
    ChevronDown,
    Loader2,
    CheckCircle2,
    ExternalLink
} from 'lucide-react'
import PageHeader from '@/components/PageHeader'

// Cor por TIPO DE NÓ segue a tabela semântica de domínio do chat-builder:
// gatilho → ouro (primary), mensagem → info, captura → success, escolha → warning,
// condição/handoff → brand-steel, redirect → muted.
const NODE_TYPE_CONFIG: Record<string, { icon: React.ElementType; color: string; bgColor: string; borderColor: string; label: string }> = {
    trigger: { icon: Play, color: 'text-primary', bgColor: 'bg-primary/10', borderColor: 'border-primary/30', label: 'Trigger' },
    text: { icon: MessageSquare, color: 'text-info', bgColor: 'bg-info/10', borderColor: 'border-info/30', label: 'Mensagem' },
    message: { icon: MessageSquare, color: 'text-info', bgColor: 'bg-info/10', borderColor: 'border-info/30', label: 'Mensagem' },
    question: { icon: HelpCircle, color: 'text-success', bgColor: 'bg-success/10', borderColor: 'border-success/30', label: 'Pergunta' },
    input: { icon: HelpCircle, color: 'text-success', bgColor: 'bg-success/10', borderColor: 'border-success/30', label: 'Input' },
    option: { icon: MousePointer, color: 'text-warning', bgColor: 'bg-warning/10', borderColor: 'border-warning/30', label: 'Opções' },
    redirect: { icon: ArrowRight, color: 'text-muted-foreground', bgColor: 'bg-muted/50', borderColor: 'border-border', label: 'Redirect' },
    condition: { icon: GitBranch, color: 'text-brand-steel', bgColor: 'bg-brand-steel/10', borderColor: 'border-brand-steel/30', label: 'Condição' },
    handoff: { icon: RefreshCw, color: 'text-brand-steel', bgColor: 'bg-brand-steel/10', borderColor: 'border-brand-steel/30', label: 'Handoff' },
}


function ExecutionStepCard({ step, index, total }: { step: FlowExecutionStep; index: number; total: number }) {
    const config = NODE_TYPE_CONFIG[step.node_type] || {
        icon: Activity,
        color: 'text-muted-foreground',
        bgColor: 'bg-muted/50',
        borderColor: 'border-border',
        label: step.node_type
    }
    const Icon = config.icon

    return (
        <div className={`relative ${index < total - 1 ? 'pb-8' : ''}`}>
            {/* Timeline Line */}
            {index < total - 1 && (
                <div className="absolute left-6 top-14 w-0.5 h-[calc(100%-3.5rem)] bg-border" />
            )}

            <div className={`bg-card border ${config.borderColor} rounded-lg overflow-hidden shadow-e1 hover:shadow-e2 transition-shadow`}>
                {/* Header */}
                <div className={`p-4 ${config.bgColor} border-b ${config.borderColor} flex items-center justify-between`}>
                    <div className="flex items-center gap-3">
                        <div className={`h-12 w-12 rounded-lg ${config.bgColor} border ${config.borderColor} flex items-center justify-center`}>
                            <Icon className={`h-6 w-6 ${config.color}`} />
                        </div>
                        <div>
                            <div className="flex items-center gap-2">
                                <span className={`text-sm font-bold uppercase tracking-wider ${config.color}`}>
                                    {config.label}
                                </span>
                                <span className="px-2 py-0.5 text-xs bg-background/50 text-muted-foreground rounded-full font-numeric">
                                    #{index + 1}
                                </span>
                            </div>
                            <p className="text-xs text-muted-foreground mt-0.5">
                                Node ID: <span className="font-mono">{step.node_id}</span>
                            </p>
                        </div>
                    </div>
                    <div className="text-right">
                        <p className="text-xs text-muted-foreground font-numeric">
                            {format(new Date(step.created_at), "HH:mm:ss", { locale: ptBR })}
                        </p>
                        <p className="text-xs text-muted-foreground">
                            {timeAgo(step.created_at)}
                        </p>
                    </div>
                </div>

                {/* Content */}
                <div className="p-4 space-y-4">
                    {/* Summary */}
                    <div>
                        <p className="text-sm font-medium text-foreground">{step.summary}</p>
                    </div>

                    {/* Input/Output Grid */}
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {/* User Input */}
                        {step.input_data && Object.keys(step.input_data).length > 0 && (
                            <div className="space-y-2">
                                <div className="flex items-center gap-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                                    <ArrowRight className="h-3 w-3" />
                                    Input do Usuário
                                </div>
                                <div className="p-3 bg-primary/5 border border-primary/10 rounded-lg">
                                    {step.input_data.user_input ? (
                                        <p className="text-sm text-primary font-medium">"{step.input_data.user_input}"</p>
                                    ) : (
                                        <pre className="text-xs font-mono text-foreground overflow-x-auto">
                                            {JSON.stringify(step.input_data, null, 2)}
                                        </pre>
                                    )}
                                </div>
                            </div>
                        )}

                        {/* Output */}
                        {step.output_data && Object.keys(step.output_data).length > 0 && (
                            <div className="space-y-2">
                                <div className="flex items-center gap-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                                    <ArrowLeft className="h-3 w-3" />
                                    Output do Bot
                                </div>
                                <div className="p-3 bg-muted/50 border border-border rounded-lg">
                                    {step.output_data.content ? (
                                        <p className="text-sm text-foreground">{step.output_data.content}</p>
                                    ) : (
                                        <pre className="text-xs font-mono text-foreground overflow-x-auto">
                                            {JSON.stringify(step.output_data, null, 2)}
                                        </pre>
                                    )}
                                    {step.output_data.options && step.output_data.options.length > 0 && (
                                        <div className="mt-2 flex flex-wrap gap-1">
                                            {step.output_data.options.map((opt: any, i: number) => (
                                                <span key={i} className="px-2 py-1 text-xs bg-background border border-border rounded-full">
                                                    {typeof opt === 'string' ? opt : opt.label || opt.text}
                                                </span>
                                            ))}
                                        </div>
                                    )}
                                    {step.output_data.action && (
                                        <div className="mt-2 flex items-center gap-2">
                                            <span className="text-xs text-muted-foreground">Ação:</span>
                                            <span className="px-2 py-0.5 text-xs bg-muted text-muted-foreground rounded font-mono">
                                                {step.output_data.action}
                                            </span>
                                            {step.output_data.target && (
                                                <span className="text-xs text-muted-foreground">
                                                    {'\u2192'} {step.output_data.target}
                                                </span>
                                            )}
                                        </div>
                                    )}
                                </div>
                            </div>
                        )}
                    </div>

                    {/* Context Snapshot */}
                    {step.context_snapshot && Object.keys(step.context_snapshot).length > 0 && (
                        <details className="group">
                            <summary className="flex items-center gap-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider cursor-pointer hover:text-foreground">
                                <Database className="h-3 w-3" />
                                Contexto neste passo (<span className="font-numeric">{Object.keys(step.context_snapshot).length}</span> variáveis)
                                <ChevronDown className="h-3 w-3 ml-auto transition-transform group-open:rotate-180" />
                            </summary>
                            <div className="mt-2 p-3 bg-muted/30 border border-border rounded-lg">
                                <pre className="text-xs font-mono text-foreground overflow-x-auto">
                                    {JSON.stringify(step.context_snapshot, null, 2)}
                                </pre>
                            </div>
                        </details>
                    )}
                </div>
            </div>
        </div>
    )
}

export function ExecutionDetailPage() {
    const { sessionId } = useParams<{ sessionId: string }>()
    const id = parseInt(sessionId || '0')

    const { data, isLoading, error } = useQuery({
        queryKey: ['flow-execution', id],
        queryFn: () => flowExecutionsApi.get(id),
        enabled: !!id
    })

    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-[400px]">
                <div className="text-center">
                    <Loader2 className="h-8 w-8 animate-spin text-primary mx-auto mb-3" />
                    <p className="text-sm text-muted-foreground">Carregando detalhes da execução...</p>
                </div>
            </div>
        )
    }

    if (error || !data) {
        return (
            <div className="space-y-6">
                <PageHeader
                    title="Erro"
                    subtitle="Não foi possível carregar os detalhes"
                    rightSlot={
                        <Link
                            to="/admin/chat/executions"
                            className="px-4 py-2 bg-muted text-foreground border border-border rounded-md hover:bg-muted/80 transition font-medium flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Voltar
                        </Link>
                    }
                />
                <div className="bg-destructive/10 border border-destructive/20 rounded-lg p-6 text-center">
                    <p className="text-destructive">Sessão não encontrada ou erro ao carregar dados.</p>
                </div>
            </div>
        )
    }

    const session = data.session
    const timeline = data.timeline

    return (
        <div className="space-y-6">
            <PageHeader
                title={`Execução #${session.id}`}
                subtitle={session.flow_name}
                rightSlot={
                    <div className="flex items-center gap-2">
                        <Link
                            to="/admin/chat/executions"
                            className="px-4 py-2 bg-muted text-foreground border border-border rounded-md hover:bg-muted/80 transition font-medium flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <ArrowLeft className="h-4 w-4" />
                            Voltar
                        </Link>
                        <Link
                            to={`/admin/chat/builder?flowId=${session.flow_id}`}
                            className="px-4 py-2 bg-primary text-primary-foreground rounded-md hover:bg-brand-gold-deep transition font-medium flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <GitBranch className="h-4 w-4" />
                            Ver Fluxo
                        </Link>
                    </div>
                }
            />

            {/* Info Cards */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Sessão — Bloco 6 do trim: o cartão era "Informações do Lead"
                    (AI9-006). Sem lead, sobra a identificação da própria sessão. */}
                <div className="bg-card border border-border rounded-lg overflow-hidden shadow-e1">
                    <div className="p-4 border-b border-border bg-muted/30">
                        <h3 className="font-semibold flex items-center gap-2">
                            <User className="h-4 w-4 text-primary" />
                            Sessão
                        </h3>
                    </div>
                    <div className="p-4 space-y-4">
                        <div className="space-y-2">
                            <div className="flex items-center justify-between text-sm">
                                <span className="text-muted-foreground flex items-center gap-2">
                                    <Hash className="h-3 w-3" />
                                    ID da Sessão
                                </span>
                                <span className="font-numeric text-foreground">{session.id}</span>
                            </div>
                            <div className="flex items-center justify-between text-sm">
                                <span className="text-muted-foreground flex items-center gap-2">
                                    <Calendar className="h-3 w-3" />
                                    Iniciado em
                                </span>
                                <span className="text-foreground font-numeric">
                                    {session.created_at ? format(new Date(session.created_at), "dd/MM/yyyy HH:mm", { locale: ptBR }) : 'N/A'}
                                </span>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Flow Info */}
                <div className="bg-card border border-border rounded-lg overflow-hidden shadow-e1">
                    <div className="p-4 border-b border-border bg-muted/30">
                        <h3 className="font-semibold flex items-center gap-2">
                            <GitBranch className="h-4 w-4 text-info" />
                            Informações do Fluxo
                        </h3>
                    </div>
                    <div className="p-4 space-y-4">
                        <div>
                            <p className="text-xs text-muted-foreground uppercase tracking-wider mb-1">Nome do Fluxo</p>
                            <p className="font-semibold text-lg">{session.flow_name}</p>
                        </div>
                        <div className="pt-3 border-t border-border space-y-2">
                            <div className="flex items-center justify-between text-sm">
                                <span className="text-muted-foreground flex items-center gap-2">
                                    <Hash className="h-3 w-3" />
                                    ID do Fluxo
                                </span>
                                <span className="font-numeric text-foreground">{session.flow_id}</span>
                            </div>
                            <div className="flex items-center justify-between text-sm">
                                <span className="text-muted-foreground flex items-center gap-2">
                                    <Activity className="h-3 w-3" />
                                    Passo Atual
                                </span>
                                <span className="font-mono text-foreground">{session.current_step || 'Finalizado'}</span>
                            </div>
                        </div>
                        <Link
                            to={`/admin/chat/builder?flowId=${session.flow_id}`}
                            className="flex items-center gap-2 text-sm text-primary hover:underline"
                        >
                            <ExternalLink className="h-3 w-3" />
                            Abrir no Builder
                        </Link>
                    </div>
                </div>

                {/* Execution Stats */}
                <div className="bg-card border border-border rounded-lg overflow-hidden shadow-e1">
                    <div className="p-4 border-b border-border bg-muted/30">
                        <h3 className="font-semibold flex items-center gap-2">
                            <Activity className="h-4 w-4 text-primary" />
                            Estatísticas
                        </h3>
                    </div>
                    <div className="p-4 space-y-4">
                        <div className="grid grid-cols-2 gap-4">
                            <div className="text-center p-3 bg-muted/30 rounded-lg">
                                <p className="text-2xl font-bold text-primary font-numeric">{timeline.length}</p>
                                <p className="text-xs text-muted-foreground">Passos Executados</p>
                            </div>
                            <div className="text-center p-3 bg-muted/30 rounded-lg">
                                <p className="text-2xl font-bold text-foreground font-numeric">
                                    {Object.keys(session.context || {}).length}
                                </p>
                                <p className="text-xs text-muted-foreground">Variáveis Coletadas</p>
                            </div>
                        </div>
                        <div className="pt-3 border-t border-border">
                            <div className="flex items-center gap-2 text-sm">
                                <CheckCircle2 className="h-4 w-4 text-success" />
                                <span className="text-muted-foreground">Status:</span>
                                <span className="font-medium text-success">Completo</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Context Variables */}
            {session.context && Object.keys(session.context).length > 0 && (
                <div className="bg-card border border-border rounded-lg overflow-hidden shadow-e1">
                    <div className="p-4 border-b border-border bg-muted/30 flex items-center justify-between">
                        <h3 className="font-semibold flex items-center gap-2">
                            <Layers className="h-4 w-4 text-brand-steel" />
                            Variáveis Coletadas
                        </h3>
                        <span className="text-xs text-muted-foreground">
                            <span className="font-numeric">{Object.keys(session.context).length}</span> variáveis
                        </span>
                    </div>
                    <div className="p-4">
                        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                            {Object.entries(session.context).map(([key, value]) => (
                                <div key={key} className="p-3 bg-muted/30 border border-border rounded-lg">
                                    <p className="text-xs text-muted-foreground font-mono mb-1">{`{{${key}}}`}</p>
                                    <p className="text-sm font-medium text-foreground break-all">
                                        {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                                    </p>
                                </div>
                            ))}
                        </div>
                    </div>
                </div>
            )}

            {/* Timeline */}
            <div className="bg-card border border-border rounded-lg overflow-hidden shadow-e1">
                <div className="p-4 border-b border-border bg-muted/30 flex items-center justify-between">
                    <h3 className="font-semibold flex items-center gap-2">
                        <Clock className="h-4 w-4 text-info" />
                        Timeline de Execução
                    </h3>
                    <span className="text-xs text-muted-foreground">
                        <span className="font-numeric">{timeline.length}</span> {timeline.length === 1 ? 'passo' : 'passos'}
                    </span>
                </div>
                <div className="p-6">
                    {timeline.length > 0 ? (
                        <div className="space-y-0">
                            {timeline.map((step, idx) => (
                                <ExecutionStepCard
                                    key={step.id}
                                    step={step}
                                    index={idx}
                                    total={timeline.length}
                                />
                            ))}
                        </div>
                    ) : (
                        <div className="text-center py-12">
                            <Activity className="h-12 w-12 mx-auto mb-3 text-muted-foreground opacity-20" />
                            <h3 className="font-semibold text-foreground mb-1">Nenhum passo registrado</h3>
                            <p className="text-sm text-muted-foreground">
                                Esta sessão ainda não possui passos de execução registrados.
                            </p>
                        </div>
                    )}
                </div>
            </div>

            {/* Raw Data (for debugging) */}
            <details className="bg-card border border-border rounded-lg overflow-hidden shadow-e1">
                <summary className="p-4 bg-muted/30 cursor-pointer hover:bg-muted/50 transition flex items-center justify-between">
                    <h3 className="font-semibold flex items-center gap-2">
                        <Code className="h-4 w-4 text-muted-foreground" />
                        Dados Brutos (Debug)
                    </h3>
                    <ChevronDown className="h-4 w-4 text-muted-foreground" />
                </summary>
                <div className="p-4 border-t border-border">
                    <pre className="text-xs font-mono text-foreground overflow-x-auto p-4 bg-muted/30 rounded-lg max-h-96">
                        {JSON.stringify(data, null, 2)}
                    </pre>
                </div>
            </details>
        </div>
    )
}
