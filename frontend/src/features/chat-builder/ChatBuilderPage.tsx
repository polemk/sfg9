import React, { useCallback, useRef, useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
    ReactFlow,
    Controls,
    Background,
    useNodesState,
    useEdgesState,
    addEdge,
    Connection,
    Edge,
    BackgroundVariant,
    ReactFlowProvider,
    Node,
    MiniMap,
    useReactFlow,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { nanoid } from 'nanoid';
import { toast } from 'sonner';
import {
    Loader2,
    Save,
    ChevronDown,
    ChevronUp,
    Network,
    Activity,
    Terminal,
    Settings2,
    Play,
    FileText,
    X
} from 'lucide-react';

import { useChatFlow, ExecutionLog } from '@/hooks/useChatFlow';
import { Button } from '@/components/ui/Button';
import { Logo } from '@/components/brand/Logo';

import TextNode from './components/TextNode';
import InputNode from './components/InputNode';
import OptionNode from './components/OptionNode';
import ListNode from './components/ListNode';
import ConditionNode from './components/ConditionNode';
import MessageNode from './components/MessageNode';
import TriggerNode from './components/TriggerNode';
import { HandoffNode } from './components/HandoffNode';
import { RedirectNode } from './components/RedirectNode';
import { NodesSidebar } from './components/NodesSidebar';
import { PropertiesPanel } from './components/PropertiesPanel';
import { ChatNode } from './types/nodes';
import { chatBuilderApi, FlowKind, AgentConfig } from './api/builder';
import { FloatingToolbar } from './components/FloatingToolbar';
import { AIChatWidget } from '@/components/chat/AIChatWidget';
import { RapidLaunchMenu } from './components/RapidLaunchMenu';
import { FlowSettingsModal, FlowSettingsData } from './components/FlowSettingsModal';
import { AIAgentConfigPanel } from './components/AIAgentConfigPanel';
import { Settings } from 'lucide-react';

const nodeTypes = {
    text: MessageNode,
    message: MessageNode,
    question: InputNode,
    input: InputNode,
    option: OptionNode,
    list: ListNode,
    condition: ConditionNode,
    trigger: TriggerNode,
    handoff: HandoffNode,
    redirect: RedirectNode,
} as any;

const initialNodes: ChatNode[] = [];
const initialEdges: Edge[] = [];
function BuilderContent() {
    const reactFlowWrapper = useRef<HTMLDivElement>(null);
    const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
    const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
    const [reactFlowInstance, setReactFlowInstance] = useState<any>(null);
    const [flowId, setFlowId] = useState<string | null>(null);
    const [flowName, setFlowName] = useState<string>('');
    const [flowKind, setFlowKind] = useState<FlowKind>('chatbot');
    const [agentConfig, setAgentConfig] = useState<AgentConfig>({});
    const [keywords, setKeywords] = useState<string[]>([]);
    const [personaName, setPersonaName] = useState<string>('');
    const [personaDescription, setPersonaDescription] = useState<string>('');
    const [personaAvatar, setPersonaAvatar] = useState<string>('');
    const [mappedRoutes, setMappedRoutes] = useState<string[]>([]);
    const [overrideActiveChat, setOverrideActiveChat] = useState<boolean>(false);
    const [isSettingsOpen, setIsSettingsOpen] = useState(false);
    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [isChatOpen, setIsChatOpen] = useState(false);
    const [isConsoleMinimized, setIsConsoleMinimized] = useState(false);
    const [testKey, setTestKey] = useState(0);
    const [sessionId, setSessionId] = useState<string | null>(null);
    const [logs, setLogs] = useState<ExecutionLog[]>([]);
    const [searchParams] = useSearchParams();

    // Resizable Console State
    const [consoleHeight, setConsoleHeight] = useState(350);
    const [isResizing, setIsResizing] = useState(false);

    const logsEndRef = useRef<HTMLDivElement>(null);

    const startResizing = useCallback((e: React.MouseEvent) => {
        e.preventDefault();
        setIsResizing(true);
    }, []);

    // Auto-scroll logs
    useEffect(() => {
        if (logsEndRef.current) {
            logsEndRef.current.scrollIntoView({ behavior: 'smooth' });
        }
    }, [logs]);

    const stopResizing = useCallback(() => {
        setIsResizing(false);
    }, []);

    const resize = useCallback((e: MouseEvent) => {
        if (isResizing) {
            const newHeight = window.innerHeight - e.clientY;
            if (newHeight > 100 && newHeight < window.innerHeight - 200) {
                setConsoleHeight(newHeight);
            }
        }
    }, [isResizing]);

    useEffect(() => {
        if (isResizing) {
            window.addEventListener('mousemove', resize);
            window.addEventListener('mouseup', stopResizing);
        } else {
            window.removeEventListener('mousemove', resize);
            window.removeEventListener('mouseup', stopResizing);
        }
        return () => {
            window.removeEventListener('mousemove', resize);
            window.removeEventListener('mouseup', stopResizing);
        };
    }, [isResizing, resize, stopResizing]);

    const onTest = async () => {
        // Save first to ensure backend has latest data
        await onSave();
        // Force reset the chat widget
        setTestKey(prev => prev + 1);
        setIsChatOpen(prev => !prev); // Toggle console
    };

    // Load initial flow - check URL params first
    useEffect(() => {
        const loadFlow = async () => {
            try {
                const urlFlowId = searchParams.get('flowId');
                let flow;

                if (urlFlowId) {
                    // Load specific flow by ID
                    flow = await chatBuilderApi.getFlowById(urlFlowId);
                } else {
                    // Fall back to default flow
                    flow = await chatBuilderApi.getDefaultFlow();
                }

                setFlowId(flow.id);
                setFlowName(flow.name || 'Fluxo sem nome');
                setFlowKind(flow.kind || 'chatbot');
                setAgentConfig(flow.agent_config || {});
                setKeywords(flow.keywords || []);
                setPersonaName(flow.persona_name || '');
                setPersonaDescription(flow.persona_description || '');
                setPersonaAvatar(flow.persona_avatar || '');
                setMappedRoutes(flow.mapped_routes || []);
                setOverrideActiveChat(flow.override_active_chat || false);

                if (flow.definition) {
                    const { nodes: rawNodes = [], edges: loadedEdges = [] } = flow.definition;

                    // Sanitize nodes to prevent ReactFlow crashes
                    let loadedNodes = rawNodes.map((n: ChatNode) => ({
                        ...n,
                        position: n.position || { x: 0, y: 0 },
                        data: n.data || {}
                    }));

                    // Check if trigger node exists, if not create one
                    const hasTrigger = loadedNodes.some((n: ChatNode) => n.type === 'trigger');
                    if (!hasTrigger) {
                        const triggerNode: ChatNode = {
                            id: 'trigger-start',
                            type: 'trigger',
                            position: { x: 50, y: 200 },
                            data: {
                                flowName: flow.name || 'Novo Fluxo',
                                keywords: flow.keywords || [],
                                isDefault: flow.is_default || false,
                                personaName: flow.persona_name || '',
                                personaAvatar: flow.persona_avatar || '',
                            }
                        };
                        loadedNodes = [triggerNode, ...loadedNodes];
                    }

                    setNodes(loadedNodes);
                    setEdges(loadedEdges);
                } else {
                    // New flow - start with trigger node
                    const triggerNode: ChatNode = {
                        id: 'trigger-start',
                        type: 'trigger',
                        position: { x: 50, y: 200 },
                        data: {
                            flowName: flow.name || 'Novo Fluxo',
                            keywords: flow.keywords || [],
                            isDefault: flow.is_default || false,
                            personaName: flow.persona_name || '',
                            personaAvatar: flow.persona_avatar || '',
                        }
                    };
                    setNodes([triggerNode]);
                    setEdges([]);
                }
            } catch (error) {
                console.error('Failed to load flow', error);
                toast.error('Erro ao carregar fluxo');
            } finally {
                setIsLoading(false);
            }
        };
        loadFlow();
    }, [setNodes, setEdges, searchParams]);

    // Sync Trigger Node data -> Page State (keywords, flowName, persona)
    // This ensures that editing the Trigger node in the sidebar updates the global flow state
    // IMPORTANT: Skip for AI agents — they manage state directly via AIAgentConfigPanel,
    // not through the trigger node. Running this for agents would overwrite fresh state
    // with stale trigger node data (which holds empty keywords).
    useEffect(() => {
        if (flowKind === 'ai_agent') return;
        const triggerNode = nodes.find(n => n.type === 'trigger');
        if (triggerNode) {
            const data = triggerNode.data as any;
            if (data.flowName !== undefined && data.flowName !== flowName) setFlowName(data.flowName);
            if (data.keywords !== undefined && JSON.stringify(data.keywords) !== JSON.stringify(keywords)) setKeywords(data.keywords);
            if (data.personaName !== undefined && data.personaName !== personaName) setPersonaName(data.personaName);
            if (data.personaAvatar !== undefined && data.personaAvatar !== personaAvatar) setPersonaAvatar(data.personaAvatar);
        }
    }, [nodes, flowName, keywords, personaName, personaAvatar, flowKind]);

    const onSave = async () => {
        if (!flowId) {
            toast.error('Erro: Fluxo não carregado. Recarregue a página.');
            return;
        }

        setIsSaving(true);

        try {
            if (flowKind === 'ai_agent') {
                // Save AI Agent config
                await chatBuilderApi.saveFlow(flowId, {
                    agent_config: agentConfig,
                    name: flowName,
                    keywords: keywords,
                    persona_name: personaName,
                    persona_description: personaDescription,
                    persona_avatar: personaAvatar,
                    credential_id: agentConfig.credential_id,
                    mapped_routes: mappedRoutes,
                    override_active_chat: overrideActiveChat,
                });
            } else {
                // Save Chatbot flow
                if (!reactFlowInstance) return;
                const flow = reactFlowInstance.toObject();

                await chatBuilderApi.saveFlow(flowId, {
                    definition: {
                        nodes: flow.nodes,
                        edges: flow.edges,
                    },
                    name: flowName,
                    keywords: keywords,
                    persona_name: personaName,
                    persona_description: personaDescription,
                    persona_avatar: personaAvatar,
                    mapped_routes: mappedRoutes,
                    override_active_chat: overrideActiveChat,
                });
            }
            toast.success('Fluxo salvo com sucesso!');
        } catch (error) {
            console.error('Failed to save', error);
            toast.error('Erro ao salvar fluxo');
        } finally {
            setIsSaving(false);
        }
    };

    const handleSaveSettings = async (data: FlowSettingsData) => {
        setFlowName(data.name);
        setKeywords(data.keywords);
        setPersonaName(data.personaName || '');
        setPersonaDescription(data.personaDescription || '');
        setPersonaAvatar(data.personaAvatar || '');

        // Update the trigger node data as well
        setNodes(nds => nds.map(node => {
            if (node.type === 'trigger') {
                return {
                    ...node,
                    data: {
                        ...node.data,
                        flowName: data.name,
                        keywords: data.keywords,
                        personaName: data.personaName,
                        personaAvatar: data.personaAvatar
                    }
                };
            }
            return node;
        }));

        // We trigger a full save to backend
        if (!reactFlowInstance || !flowId) return;

        setIsSaving(true);
        const flow = reactFlowInstance.toObject();

        try {
            await chatBuilderApi.saveFlow(flowId, {
                definition: {
                    nodes: flow.nodes,
                    edges: flow.edges,
                },
                name: data.name,
                keywords: data.keywords,
                persona_name: data.personaName,
                persona_description: data.personaDescription,
                persona_avatar: data.personaAvatar,
            });
            toast.success('Configurações salvas!');
            setIsSettingsOpen(false);
        } catch (error) {
            console.error('Failed to save settings', error);
            toast.error('Erro ao salvar configurações');
            throw error; // Re-throw for modal to handle if needed
        } finally {
            setIsSaving(false);
        }
    };

    const onConnect = useCallback(
        (params: Connection) => setEdges((eds) => addEdge(params, eds)),
        [setEdges],
    );

    const onDragOver = useCallback((event: React.DragEvent) => {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    }, []);

    const onDrop = useCallback(
        (event: React.DragEvent) => {
            event.preventDefault();

            const type = event.dataTransfer.getData('application/reactflow');
            if (typeof type === 'undefined' || !type) {
                return;
            }

            const position = reactFlowInstance.screenToFlowPosition({
                x: event.clientX,
                y: event.clientY,
            });

            const newNode: ChatNode = {
                id: nanoid(),
                type,
                position,
                data: {
                    content: type === 'text' ? 'Nova mensagem...' : 'Nova pergunta...',
                    ...(type === 'question' ? { variable: 'var_name', inputType: 'text' } : {}),
                    ...(type === 'option' || type === 'list' ? { options: ['Opção 1', 'Opção 2'] } : {}),
                    ...(type === 'condition' ? { variable: 'var_name', operator: '==', value: 'valor' } : {}),
                    ...(type === 'handoff' ? { targetFlowId: '', targetFlowName: '' } : {}),
                    ...(type === 'redirect' ? { action: 'navigate', url: '', target: '', auto_auth: false } : {}),
                } as any,
            };

            setNodes((nds) => nds.concat(newNode));
        },
        [reactFlowInstance, setNodes],
    );

    const [rapidMenu, setRapidMenu] = useState<{ x: number, y: number, visible: boolean, sourceNodeId: string | null, sourceHandle: string | null }>({
        x: 0,
        y: 0,
        visible: false,
        sourceNodeId: null,
        sourceHandle: null
    });
    const connectionStartRef = useRef<{ nodeId: string | null, handleId: string | null }>({ nodeId: null, handleId: null });

    const onConnectStart = useCallback((_: any, { nodeId, handleId }: any) => {
        connectionStartRef.current = { nodeId, handleId };
    }, []);

    const onConnectEnd = useCallback(
        (event: any) => {
            if (!connectionStartRef.current.nodeId) return;

            const targetIsPane = event.target.classList.contains('react-flow__pane');

            if (targetIsPane && reactFlowInstance) {
                const { x, y } = reactFlowInstance.screenToFlowPosition({
                    x: event.clientX,
                    y: event.clientY,
                });

                setRapidMenu({
                    x: event.clientX, // Keep screen coordinates for fixed menu, or flow coordinates for absolute? 
                    // FloatingToolbar uses fixed? No, RapidLaunchMenu uses fixed styling but we want it near mouse.
                    // Let's use screen coordinates for the menu position style if it's fixed.
                    // Actually RapidLaunchMenu uses style={{ left: x, top: y }}
                    // If we pass screen coordinates, it works if the component returns valid style.
                    // The component uses fixed positioning in previous step.
                    // So we pass CLIENT coordinates.

                    // Wait, if I want to create node at FLOW coordinates, I need those too.
                    // I will calculate flow coordinates inside onRapidLaunchSelect or store them too.
                    // Let's store flow coordinates in a ref or calculate them again?
                    // Better to calculate flow coordinates for the new node based on the menu position or just reuse the event.

                    // Let's store client X/Y for menu position.
                    y: event.clientY,
                    visible: true,
                    sourceNodeId: connectionStartRef.current.nodeId,
                    sourceHandle: connectionStartRef.current.handleId
                });
            }
        },
        [reactFlowInstance]
    );

    const onRapidLaunchSelect = useCallback((type: string) => {
        if (!rapidMenu.sourceNodeId || !reactFlowInstance) return;

        // Calculate flow position from the menu screen position
        const position = reactFlowInstance.screenToFlowPosition({
            x: rapidMenu.x,
            y: rapidMenu.y,
        });

        const newNodeId = nanoid();
        const newNode: ChatNode = {
            id: newNodeId,
            type,
            position,
            data: {
                content: type === 'text' ? 'Nova mensagem...' : 'Nova pergunta...',
                ...(type === 'question' ? { variable: 'var_name', inputType: 'text' } : {}),
                ...(type === 'option' || type === 'list' ? { options: ['Opção 1', 'Opção 2'] } : {}),
                ...(type === 'condition' ? { variable: 'var_name', operator: '==', value: 'valor' } : {}),
                ...(type === 'handoff' ? { targetFlowId: '', targetFlowName: '' } : {}),
                ...(type === 'redirect' ? { action: 'navigate', url: '', target: '', auto_auth: false } : {}),
            } as any,
        };

        setNodes((nds) => nds.concat(newNode));

        // Add edge
        const newEdge: Edge = {
            id: nanoid(),
            source: rapidMenu.sourceNodeId,
            sourceHandle: rapidMenu.sourceHandle,
            target: newNodeId,
            targetHandle: null // default input handle
        };

        setEdges((eds) => eds.concat(newEdge));

        // Close menu
        setRapidMenu(prev => ({ ...prev, visible: false }));
        connectionStartRef.current = { nodeId: null, handleId: null };

    }, [rapidMenu, reactFlowInstance, setNodes, setEdges]);

    const [selectedElements, setSelectedElements] = useState<any[]>([]);

    // Track selection
    useEffect(() => {
        // We can use the onSelectionChange hook from ReactFlow, but for now accessing internal state or a simple hook might be easier.
        // Or simpler: useOnSelectionChange
    }, []);

    // Better way to track selection for the toolbar
    const onSelectionChange = useCallback(({ nodes, edges }: { nodes: Node[]; edges: Edge[] }) => {
        setSelectedElements([...nodes, ...edges]);
    }, []);

    const onDeleteSelected = useCallback(() => {
        setNodes((nds) => nds.filter((node) => !selectedElements.some((s) => s.id === node.id)));
        setEdges((eds) => eds.filter((edge) => !selectedElements.some((s) => s.id === edge.id)));
        setSelectedElements([]);
    }, [selectedElements, setNodes, setEdges]);

    // Keyboard delete is handled by ReactFlow default, but the button needs manual logic
    // ReactFlow's 'deleteKeyCode' handles the keyboard part.
    // For the button, we need to know what is selected.

    if (isLoading) {
        return (
            <div className="flex h-full w-full items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-primary" />
                <span className="ml-2 text-muted-foreground">Carregando fluxo...</span>
            </div>
        );
    }

    // Render AI Agent Config Panel if kind is ai_agent
    if (flowKind === 'ai_agent') {
        return (
            <div className="w-full relative min-h-[calc(100vh-82px)] flex flex-col">
                <AIAgentConfigPanel
                    flowId={flowId || ''}
                    flowName={flowName}
                    agentConfig={agentConfig}
                    keywords={keywords}
                    personaName={personaName}
                    personaAvatar={personaAvatar}
                    onConfigChange={setAgentConfig}
                    onNameChange={setFlowName}
                    onKeywordsChange={setKeywords}
                    onPersonaNameChange={setPersonaName}
                    onPersonaAvatarChange={setPersonaAvatar}
                    mappedRoutes={mappedRoutes}
                    overrideActiveChat={overrideActiveChat}
                    onMappedRoutesChange={setMappedRoutes}
                    onOverrideActiveChatChange={setOverrideActiveChat}
                    onSave={onSave}
                    isSaving={isSaving}
                />
            </div>
        );
    }

    // Render Chatbot Builder (React Flow)
    return (
        <div className="w-full h-[calc(100vh-64px)] bg-background flex flex-col relative overflow-hidden">
            {/* Top Section: Builder */}
            <div className="flex-grow flex relative min-h-0">
                <NodesSidebar />
                <div className="flex-grow h-full relative" ref={reactFlowWrapper}>
                    <FloatingToolbar
                        onSave={onSave}
                        onTest={onTest}
                        isSaving={isSaving}
                        onDelete={onDeleteSelected}
                        hasSelection={selectedElements.length > 0}
                        flowName={flowName}
                        onOpenSettings={() => setIsSettingsOpen(true)}
                    />

                    <ReactFlow
                        nodes={nodes}
                        edges={edges}
                        onNodesChange={onNodesChange}
                        onEdgesChange={onEdgesChange}
                        onConnect={onConnect}
                        onConnectStart={onConnectStart}
                        onConnectEnd={onConnectEnd}
                        onInit={setReactFlowInstance}
                        onDrop={onDrop}
                        onDragOver={onDragOver}
                        onSelectionChange={onSelectionChange}
                        nodeTypes={nodeTypes}
                        fitView
                        deleteKeyCode={['Backspace', 'Delete']}
                    >
                        <Background
                            variant={BackgroundVariant.Lines}
                            gap={120}
                            size={0.1}
                            color="hsl(var(--border))"
                            style={{ opacity: 0.6 }}
                        />
                        <Controls />
                        <MiniMap />
                    </ReactFlow>

                    {rapidMenu.visible && (
                        <RapidLaunchMenu
                            x={rapidMenu.x}
                            y={rapidMenu.y}
                            onSelect={onRapidLaunchSelect}
                            onClose={() => setRapidMenu(prev => ({ ...prev, visible: false }))}
                        />
                    )}
                </div>
                <PropertiesPanel />
                <FlowSettingsModal
                    isOpen={isSettingsOpen}
                    onClose={() => setIsSettingsOpen(false)}
                    initialData={{
                        name: flowName,
                        keywords: keywords,
                        personaName: personaName,
                        personaDescription: personaDescription,
                        personaAvatar: personaAvatar
                    }}
                    onSave={handleSaveSettings}
                />
            </div>

            {isChatOpen && (
                <div
                    className={`fixed inset-x-0 bottom-0 bg-card/95 backdrop-blur-xl border-t border-border shadow-e3 z-drawer flex flex-col transition-all duration-300 ease-in-out ${isConsoleMinimized ? 'translate-y-[calc(100%-40px)]' : ''}`}
                    style={{ height: isConsoleMinimized ? 40 : consoleHeight }}
                >
                    {/* Resize Handle (only visible when not minimized) */}
                    {!isConsoleMinimized && (
                        <div
                            onMouseDown={startResizing}
                            className="absolute -top-1 left-0 right-0 h-2 cursor-ns-resize hover:bg-primary/20 transition-colors z-sticky"
                        />
                    )}

                    {/* Console Header / Info Bar */}
                    <div
                        className={`h-10 px-6 flex items-center justify-between cursor-pointer hover:bg-accent transition-colors ${isConsoleMinimized ? 'bg-primary/5' : 'border-b border-border'}`}
                        onClick={() => isConsoleMinimized && setIsConsoleMinimized(false)}
                    >
                        {/* Left Side: Status & Counts */}
                        <div className="flex items-center gap-6 overflow-hidden">
                            <div className="flex items-center gap-2 text-primary shrink-0">
                                <Terminal className="w-4 h-4" />
                                <span className="text-xs font-black uppercase tracking-[0.2em]">Console de Teste</span>
                            </div>

                            <div className="h-4 w-px bg-border hidden sm:block" />

                            <div className="flex items-center gap-4 text-muted-foreground whitespace-nowrap overflow-hidden">
                                <div className="flex items-center gap-1.5">
                                    <FileText className="w-3.5 h-3.5 text-info" />
                                    <span className="text-xs font-medium uppercase tracking-wider truncate max-w-[200px]">{flowName}</span>
                                </div>

                                <div className="flex items-center gap-1.5 border-l border-border pl-4">
                                    <Network className="w-3.5 h-3.5 text-brand-steel" />
                                    <span className="text-xs font-medium uppercase tracking-wider">
                                        <span className="font-numeric">{nodes.length}</span> Blocos <span className="opacity-40">•</span> <span className="font-numeric">{edges.length}</span> Conexões
                                    </span>
                                </div>

                                <div className="hidden md:flex items-center gap-2 border-l border-border pl-4">
                                    <div className="h-2 w-2 rounded-full bg-success animate-pulse" />
                                    <span className="text-xs font-black uppercase tracking-tight text-success">Runtime Ativo</span>
                                    <span className="text-xs text-muted-foreground font-numeric ml-2">ID: {String(flowId || '').slice(0, 8)}...</span>
                                </div>
                            </div>
                        </div>

                        {/* Right Side: Controls */}
                        <div className="flex items-center gap-1 shrink-0 ml-4">
                            <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8"
                                onClick={(e) => {
                                    e.stopPropagation();
                                    setIsConsoleMinimized(!isConsoleMinimized);
                                }}
                                title={isConsoleMinimized ? "Expandir" : "Minimizar"}
                            >
                                {isConsoleMinimized ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                            </Button>
                            <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 ml-1"
                                onClick={(e) => {
                                    e.stopPropagation();
                                    setIsChatOpen(false);
                                }}
                                title="Fechar Console"
                            >
                                <X className="w-4 h-4" />
                            </Button>
                        </div>
                    </div>

                    {/* Console Content: Split Chat | Results */}
                    <div className="flex-grow flex min-h-0 overflow-hidden bg-background">
                        {/* Left: Chat */}
                        <div className="w-[480px] border-r border-border h-full relative overflow-hidden bg-background">
                            <AIChatWidget
                                key={testKey}
                                isOpen={true}
                                onClose={() => setIsChatOpen(false)}
                                mode="flow"
                                flowId={flowId || undefined}
                                sessionId={sessionId || undefined}
                                embedded={true}
                                defaultMinimized={false}
                                onLogsChange={setLogs}
                                previewPersona={{ 
                                    name: personaName, 
                                    avatar: personaAvatar, 
                                    description: personaDescription 
                                }}
                                className="w-full h-full relative !static !shadow-none !border-0"
                            />
                        </div>

                        {/* Right: Results & Logs */}
                        <div className="flex-grow h-full flex flex-col bg-muted text-foreground font-mono text-sm p-8 overflow-y-auto selection:bg-primary/30 scrollbar-thin">
                            <div className="flex items-center justify-between mb-8 border-b border-border pb-4">
                                <div className="flex items-center gap-3">
                                    <div className="p-1.5 bg-info/10 rounded-md">
                                        <Activity className="w-4 h-4 text-info" />
                                    </div>
                                    <span className="text-info font-bold tracking-tight uppercase text-xs">Trilha de Execução</span>
                                </div>
                                <div className="flex items-center gap-3">
                                    <span className="text-xs text-muted-foreground uppercase font-black tracking-[0.2em]">Session ID</span>
                                    <span className="px-2 py-0.5 bg-card rounded-sm border border-border text-xs text-muted-foreground font-medium font-numeric">{sessionId || 'SEM_SESSAO'}</span>
                                </div>
                            </div>

                            <div className="space-y-4">
                                {logs.length === 0 ? (
                                    <div className="py-20 flex flex-col items-center justify-center text-center gap-4">
                                        <Logo variant="symbol" height={22} className="opacity-40" />
                                        <div className="p-4 bg-card rounded-lg border border-border">
                                            <Settings2 className="w-8 h-8 text-muted-foreground animate-spin-slow" />
                                        </div>
                                        <div className="max-w-[280px]">
                                            <h4 className="text-foreground font-black text-xs uppercase tracking-widest mb-2">Depurador em espera</h4>
                                            <p className="text-muted-foreground text-xs leading-relaxed font-sans">
                                                Inicie uma conversa no chat à esquerda para visualizar o rastreamento síncrono dos nós e variáveis em tempo real.
                                            </p>
                                        </div>
                                    </div>
                                ) : (
                                    <>
                                        {logs.map((log) => {
                                            // Cor por tipo de log — semantico, nao decorativo
                                            const typeColors = {
                                                system: 'text-warning',
                                                engine: 'text-success',
                                                flow: 'text-info',
                                                bridge: 'text-brand-steel',
                                                error: 'text-destructive',
                                                info: 'text-muted-foreground'
                                            };
                                            const typeLabels = {
                                                system: 'SYSTEM',
                                                engine: 'ENGINE',
                                                flow: 'FLOW',
                                                bridge: 'BRIDGE',
                                                error: 'ERROR',
                                                info: 'INFO'
                                            };

                                            return (
                                                <div key={log.id} className="flex gap-4 group">
                                                    <span className="text-muted-foreground font-medium shrink-0 font-numeric w-16">
                                                        {log.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                                                    </span>
                                                    <div className="flex flex-col gap-1.5">
                                                        <div className="flex items-center gap-2">
                                                            <span className={`font-black text-xs tracking-widest ${typeColors[log.type]}`}>
                                                                {typeLabels[log.type]}
                                                            </span>
                                                            {log.data?.node?.id && (
                                                                <span className="text-xs bg-card px-1.5 py-0.5 rounded-sm border border-border text-muted-foreground font-bold font-numeric">
                                                                    #{log.data.node.id}
                                                                </span>
                                                            )}
                                                        </div>
                                                        <span className="text-foreground leading-relaxed group-hover:bg-accent transition-colors px-2 -mx-2 py-1 rounded-md">
                                                            {log.message}
                                                        </span>
                                                        {log.data?.node?.content && (
                                                            <div className="mt-1 pl-3 border-l-2 border-border py-1 text-xs text-muted-foreground italic max-w-lg">
                                                                {log.data.node.content.substring(0, 100)}
                                                                {log.data.node.content.length > 100 && '...'}
                                                            </div>
                                                        )}
                                                    </div>
                                                </div>
                                            );
                                        })}
                                        <div ref={logsEndRef} />
                                    </>
                                )}
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

export function ChatBuilderPage() {
    return (
        <ReactFlowProvider>
            <BuilderContent />
        </ReactFlowProvider>
    );
}
