
import React, { useEffect, useState } from 'react';
import { useReactFlow } from '@xyflow/react';
import { useQuery } from '@tanstack/react-query';
import { ChatNode } from '../types/nodes';
import { VariablePicker } from './VariablePicker';
import { SelectorPicker } from './SelectorPicker';
import { chatFlowApi } from '@/lib/api/chatFlow';
import { X, Clock, Zap, Sparkles, Star, GitBranch, Plus, Trash2 } from 'lucide-react';
import { KeywordInput } from './KeywordInput';
import { Button } from '@/components/ui/Button';

export const PropertiesPanel = () => {
    const { getNodes, setNodes } = useReactFlow();
    const [selectedNode, setSelectedNode] = useState<ChatNode | null>(null);

    const { data: flows } = useQuery({
        queryKey: ['flows'],
        queryFn: chatFlowApi.getFlows,
        enabled: selectedNode?.type === 'handoff'
    });

    // Poll for selection changes (simpler than strict state management for MVP)
    // In a real app, useOnSelectionChange is better, but this works reliably for now.
    useEffect(() => {
        const interval = setInterval(() => {
            const nodes = getNodes() as ChatNode[];
            const selected = nodes.find((n) => n.selected);

            // Only update local state if ID changed to avoid input lag
            if (selected?.id !== selectedNode?.id) {
                setSelectedNode(selected || null);
            }
        }, 200);
        return () => clearInterval(interval);
    }, [getNodes, selectedNode]);

    const updateNodeData = (key: string, value: any) => {
        if (!selectedNode) return;

        setNodes((nds) =>
            nds.map((node) => {
                if (node.id === selectedNode.id) {
                    return {
                        ...node,
                        data: {
                            ...node.data,
                            [key]: value,
                        },
                    };
                }
                return node;
            })
        );

        // Update local state to reflect change immediately
        setSelectedNode((prev) => prev ? { ...prev, data: { ...prev.data, [key]: value } } : null);
    };

    // Helper to insert variable at cursor position or append
    const handleInsertVariable = (variable: string) => {
        const currentContent = (selectedNode?.data as any)?.content || '';
        // Simple append for now, could be improved with ref to textarea
        updateNodeData('content', currentContent + ' ' + variable);
    };

    if (!selectedNode) {
        return (
            <aside className="w-80 bg-card border-l border-border p-4">
                <div className="text-muted-foreground text-sm italic">
                    Selecione um bloco para editar
                </div>
            </aside>
        );
    }

    return (
        <aside className="w-80 bg-card border-l border-border p-4 flex flex-col gap-4 overflow-y-auto">
            <div className="flex items-center justify-between pb-2 border-b border-border">
                <span className="font-semibold uppercase text-xs text-muted-foreground">
                    Editando: {selectedNode.type}
                </span>
                <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8"
                    onClick={() => setSelectedNode(null)}
                    aria-label="Fechar painel"
                >
                    <X className="w-4 h-4" />
                </Button>
            </div>

            <div className="space-y-4">
                {/* Message Node Special Editor */}
                {(selectedNode.type === 'text' || selectedNode.type === 'message') && (
                    <div className="space-y-4">
                        <label className="text-sm font-medium">Conteúdo da Mensagem</label>

                        {/* Blocks Iterator */}
                        {((selectedNode.data as any).blocks || [{ type: 'text', content: (selectedNode.data as any).content }]).map((block: any, idx: number) => (
                            <div key={idx} className="relative group border border-border rounded-md p-3 bg-muted/30">
                                {block.type === 'text' && (
                                    <>
                                        <label className="text-xs uppercase font-bold text-muted-foreground mb-1 block">Texto</label>
                                        <textarea
                                            className="w-full h-20 p-2 rounded-md bg-background border border-border text-sm resize-none"
                                            value={block.content}
                                            onChange={(e) => {
                                                const newBlocks = [...((selectedNode.data as any).blocks || [{ type: 'text', content: (selectedNode.data as any).content }])];
                                                newBlocks[idx] = { ...newBlocks[idx], content: e.target.value };
                                                // Sync main content for compatibility
                                                if (idx === 0) updateNodeData('content', e.target.value);
                                                updateNodeData('blocks', newBlocks);
                                            }}
                                        />
                                        <div className="flex gap-3 relative">
                                            <VariablePicker onSelect={(v) => {
                                                const newBlocks = [...((selectedNode.data as any).blocks || [{ type: 'text', content: (selectedNode.data as any).content }])];
                                                newBlocks[idx] = { ...newBlocks[idx], content: (newBlocks[idx].content || '') + ' ' + v };
                                                updateNodeData('blocks', newBlocks);
                                            }} />
                                        </div>
                                    </>
                                )}
                                {block.type === 'delay' && (
                                    <>
                                        <label className="text-xs uppercase font-bold text-muted-foreground mb-1 block flex items-center gap-1"><Clock className="w-3 h-3" /> Atraso (Segundos)</label>
                                        <input
                                            type="number"
                                            className="w-full p-2 rounded-md bg-background border border-border text-sm font-numeric"
                                            value={block.seconds}
                                            onChange={(e) => {
                                                const newBlocks = [...((selectedNode.data as any).blocks || [])];
                                                newBlocks[idx] = { ...newBlocks[idx], seconds: parseInt(e.target.value) };
                                                updateNodeData('blocks', newBlocks);
                                            }}
                                        />
                                    </>
                                )}

                                {/* Remove Block Button */}
                                <Button
                                    variant="destructive"
                                    size="icon"
                                    aria-label="Remover bloco"
                                    onClick={() => {
                                        const newBlocks = [...((selectedNode.data as any).blocks || [])];
                                        newBlocks.splice(idx, 1);
                                        updateNodeData('blocks', newBlocks);
                                    }}
                                    className="absolute top-2 right-2 h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity"
                                >
                                    <X className="w-3 h-3" />
                                </Button>
                            </div>
                        ))}

                        {/* Add Block Buttons */}
                        <div className="flex gap-2">
                            <Button
                                variant="secondary"
                                size="sm"
                                className="flex-1"
                                onClick={() => {
                                    const newBlocks = [...((selectedNode.data as any).blocks || [{ type: 'text', content: (selectedNode.data as any).content }])];
                                    newBlocks.push({ type: 'text', content: '' });
                                    updateNodeData('blocks', newBlocks);
                                }}
                            >
                                <Plus className="w-3.5 h-3.5" /> Texto
                            </Button>
                            <Button
                                variant="secondary"
                                size="sm"
                                className="flex-1"
                                onClick={() => {
                                    const newBlocks = [...((selectedNode.data as any).blocks || [{ type: 'text', content: (selectedNode.data as any).content }])];
                                    newBlocks.push({ type: 'delay', seconds: 3 });
                                    updateNodeData('blocks', newBlocks);
                                }}
                            >
                                <Clock className="w-3.5 h-3.5" /> Atraso
                            </Button>
                        </div>
                    </div>
                )}

                {/* Shared Options Editor for Message/Option/List nodes */}
                {(selectedNode.type === 'text' || selectedNode.type === 'message' || selectedNode.type === 'option' || selectedNode.type === 'list') && (
                    <div className="space-y-4 pt-4 border-t border-border">
                        <label className="text-sm font-medium">Botões (Opções Interativas)</label>
                        <div className="space-y-2">
                            {((selectedNode.data as any).options || []).map((option: string, index: number) => (
                                <div key={index} className="flex gap-2">
                                    <input
                                        type="text"
                                        className="flex-grow p-2 rounded-md bg-background border border-border text-sm"
                                        value={option}
                                        onChange={(e) => {
                                            const newOptions = [...((selectedNode.data as any).options || [])];
                                            newOptions[index] = e.target.value;
                                            updateNodeData('options', newOptions);
                                        }}
                                    />
                                    <Button
                                        variant="destructive"
                                        size="icon"
                                        aria-label="Remover opção"
                                        className="h-9 w-9 shrink-0"
                                        onClick={() => {
                                            const newOptions = [...((selectedNode.data as any).options || [])];
                                            newOptions.splice(index, 1);
                                            updateNodeData('options', newOptions);
                                        }}
                                    >
                                        <Trash2 className="w-4 h-4" />
                                    </Button>
                                </div>
                            ))}
                            <Button
                                variant="secondary"
                                size="sm"
                                className="w-full"
                                onClick={() => {
                                    const newOptions = [...((selectedNode.data as any).options || []), 'Nova Opção'];
                                    updateNodeData('options', newOptions);
                                }}
                            >
                                <Plus className="w-3.5 h-3.5" /> Adicionar Botão
                            </Button>
                        </div>
                    </div>
                )}

                {selectedNode.type !== 'text' && selectedNode.type !== 'message' && (
                    <div className="space-y-2 relative">
                        <label className="text-sm font-medium">Conteúdo (Texto)</label>
                        <textarea
                            className="w-full h-32 p-2 rounded-md bg-background border border-border text-sm resize-none focus:ring-1 focus:ring-ring transition-all"
                            value={(selectedNode.data as any).content}
                            onChange={(e) => updateNodeData('content', e.target.value)}
                            placeholder="Digite a mensagem..."
                        />
                        <VariablePicker onSelect={handleInsertVariable} />
                    </div>
                )}
            </div>{/* Configurações de Variável (Pergunta, Lista ou Opções) */}
            {(selectedNode.type === 'question' || selectedNode.type === 'input' || selectedNode.type === 'list' || selectedNode.type === 'option') && (
                <div className="space-y-4">
                    <div className="space-y-2">
                        <label className="text-sm font-medium">Salvar na variável (Opcional)</label>
                        <input
                            type="text"
                            className="w-full p-2 rounded-md bg-background border border-border text-sm font-mono"
                            value={(selectedNode.data as any).variable || ''}
                            onChange={(e) => updateNodeData('variable', e.target.value)}
                            placeholder="ex: escolha_usuario"
                        />
                        <p className="text-xs text-muted-foreground">
                            Nome da variável para usar depois (ex: <code>{'{{escolha_usuario}}'}</code>).
                        </p>
                    </div>


                    {(selectedNode.type === 'question' || selectedNode.type === 'input') && (
                        <div className="space-y-2">
                            <label className="text-sm font-medium">Tipo de Validação</label>
                            <select
                                className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                value={(selectedNode.data as any).inputType || 'text'}
                                onChange={(e) => updateNodeData('inputType', e.target.value)}
                            >
                                <option value="text">Texto Livre</option>
                                <option value="email">E-mail</option>
                                <option value="phone">Telefone</option>
                            </select>
                        </div>
                    )}
                </div>
            )}



            {selectedNode.type === 'trigger' && (
                <div className="space-y-6">
                    {/* Flow Name */}
                    <div className="space-y-1.5">
                        <label className="text-xs font-bold uppercase text-muted-foreground flex items-center gap-2">
                            <Zap className="w-3.5 h-3.5 text-primary" />
                            Nome do Fluxo
                        </label>
                        <input
                            type="text"
                            className="w-full px-3 py-2 bg-background border border-border rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all font-medium"
                            value={(selectedNode.data as any).flowName || ''}
                            onChange={(e) => updateNodeData('flowName', e.target.value)}
                            placeholder="ex: Atendimento Inicial"
                        />
                    </div>

                    {/* Default Badge */}
                    {(selectedNode.data as any).isDefault && (
                        <div className="flex items-center gap-2 px-3 py-2 bg-warning/10 border border-warning/30 rounded-md text-warning text-xs font-bold uppercase tracking-tight">
                            <Star className="w-3.5 h-3.5 fill-current" />
                            Fluxo Padrão (Fallback)
                        </div>
                    )}

                    {/* Keywords */}
                    <div className="space-y-2">
                        <label className="text-xs font-bold uppercase text-muted-foreground flex items-center gap-2">
                            <Sparkles className="w-3.5 h-3.5 text-primary" />
                            Keywords de Ativação
                        </label>
                        <p className="text-xs text-muted-foreground leading-relaxed">
                            Palavras que ativam este fluxo automaticamente. Separe por vírgula.
                        </p>
                        <KeywordInput
                            value={(selectedNode.data as any).keywords || []}
                            onChange={(keywords) => updateNodeData('keywords', keywords)}
                            placeholder="ex: ajuda, suporte, preço"
                        />
                    </div>

                    <div className="h-px bg-border" />

                    {/* Persona Name */}
                    <div className="space-y-1.5">
                        <label className="text-xs font-bold uppercase text-muted-foreground">Nome da Persona (Opcional)</label>
                        <input
                            type="text"
                            className="w-full px-3 py-2 bg-background border border-border rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all font-medium"
                            value={(selectedNode.data as any).personaName || ''}
                            onChange={(e) => updateNodeData('personaName', e.target.value)}
                            placeholder="ex: Mariana"
                        />
                    </div>

                    {/* Persona Avatar */}
                    <div className="space-y-1.5">
                        <label className="text-xs font-bold uppercase text-muted-foreground">Avatar da Persona (URL)</label>
                        <div className="flex gap-2">
                            <input
                                type="text"
                                className="flex-grow px-3 py-2 bg-background border border-border rounded-md text-xs text-muted-foreground font-mono focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                value={(selectedNode.data as any).personaAvatar || ''}
                                onChange={(e) => updateNodeData('personaAvatar', e.target.value)}
                                placeholder="https://..."
                            />
                            <div className="w-9 h-9 border border-border bg-muted rounded-md shrink-0 flex items-center justify-center overflow-hidden">
                                {(selectedNode.data as any).personaAvatar ? (
                                    <img src={(selectedNode.data as any).personaAvatar} className="w-full h-full object-cover" alt="Avatar" />
                                ) : (
                                    <div className="text-xs text-muted-foreground font-black">?</div>
                                )}
                            </div>
                        </div>
                    </div>

                    <div className="p-3 bg-primary/5 rounded-md border border-primary/10">
                        <p className="text-xs text-primary/70 text-center leading-relaxed font-medium">
                            💡 Salve o fluxo para propagar os novos gatilhos e persona para o ambiente de produção.
                        </p>
                    </div>
                </div>
            )}

            {selectedNode.type === 'condition' && (
                <div className="space-y-4">
                    <div className="space-y-2">
                        <label className="text-sm font-medium">Se a variável:</label>
                        <input
                            type="text"
                            className="w-full p-2 rounded-md bg-background border border-border text-sm font-mono"
                            value={(selectedNode.data as any).variable || ''}
                            onChange={(e) => updateNodeData('variable', e.target.value)}
                            placeholder="ex: escolha_usuario"
                        />
                    </div>

                    <div className="flex gap-2">
                        <div className="w-1/3">
                            <label className="text-sm font-medium">For:</label>
                            <select
                                className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                value={(selectedNode.data as any).operator || '=='}
                                onChange={(e) => updateNodeData('operator', e.target.value)}
                            >
                                <option value="==">Igual (==)</option>
                                <option value="!=">Diferente (!=)</option>
                                <option value=">">Maior (&gt;)</option>
                                <option value="<">Menor (&lt;)</option>
                                <option value="contains">Contém</option>
                            </select>
                        </div>
                        <div className="flex-grow">
                            <label className="text-sm font-medium">Valor:</label>
                            <input
                                type="text"
                                className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                value={(selectedNode.data as any).value || ''}
                                onChange={(e) => updateNodeData('value', e.target.value)}
                            />
                        </div>
                    </div>
                </div>
            )}
            {
                selectedNode.type === 'handoff' && (
                    <div className="space-y-4">
                        <div className="space-y-2">
                            <label className="text-sm font-medium flex items-center gap-2">
                                <GitBranch className="w-4 h-4 text-brand-steel" />
                                Fluxo de Destino
                            </label>
                            <select
                                className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                value={(selectedNode.data as any).targetFlowId || ''}
                                onChange={(e) => {
                                    const flowId = e.target.value;
                                    const flow = flows?.find(f => f.id === flowId);
                                    updateNodeData('targetFlowId', flowId);
                                    updateNodeData('targetFlowName', flow?.name || '');
                                }}
                            >
                                <option value="">Selecione um fluxo...</option>
                                {flows?.map(flow => (
                                    <option key={flow.id} value={flow.id}>
                                        {flow.name} {flow.is_default ? '(Padrão)' : ''}
                                    </option>
                                ))}
                            </select>
                            <p className="text-xs text-muted-foreground">
                                O usuário será transferido para este fluxo imediatamente.
                                Contexto e variáveis serão mantidos.
                            </p>
                        </div>
                    </div>
                )
            }
            {
                selectedNode.type === 'redirect' && (
                    <div className="space-y-4">
                        <div className="space-y-2">
                            <label className="text-sm font-medium flex items-center gap-2">
                                <Zap className="w-4 h-4 text-muted-foreground" />
                                Tipo de Ação
                            </label>
                            <select
                                className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                value={(selectedNode.data as any).action || 'navigate'}
                                onChange={(e) => updateNodeData('action', e.target.value)}
                            >
                                <option value="navigate">Navegar para URL</option>
                                <option value="scroll_to">Rolar até Elemento</option>
                            </select>
                        </div>

                        {(selectedNode.data as any).action !== 'scroll_to' && (
                            <div className="space-y-2">
                                <label className="text-sm font-medium">
                                    URL de Destino
                                </label>
                                <input
                                    type="text"
                                    className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                    value={(selectedNode.data as any).url || ''}
                                    onChange={(e) => updateNodeData('url', e.target.value)}
                                    placeholder="https://..."
                                />
                            </div>
                        )}

                        {(selectedNode.data as any).action === 'scroll_to' && (
                            <div className="space-y-2 relative">
                                <label className="text-sm font-medium">Seletor CSS (ID)</label>
                                <input
                                    type="text"
                                    className="w-full p-2 rounded-md bg-background border border-border text-sm font-mono"
                                    value={(selectedNode.data as any).target || ''}
                                    onChange={(e) => updateNodeData('target', e.target.value)}
                                    placeholder="#section-pricing"
                                />
                                <SelectorPicker
                                    onSelect={(selector) => updateNodeData('target', selector)}
                                    currentValue={(selectedNode.data as any).target}
                                />
                            </div>
                        )}

                        {(selectedNode.data as any).action === 'navigate' && (
                            <div className="space-y-2">
                                <label className="text-sm font-medium">Alvo (Target)</label>
                                <select
                                    className="w-full p-2 rounded-md bg-background border border-border text-sm"
                                    value={(selectedNode.data as any).target || '_self'}
                                    onChange={(e) => updateNodeData('target', e.target.value)}
                                >
                                    <option value="_self">Mesma Janela (_self)</option>
                                    <option value="_blank">Nova Aba (_blank)</option>
                                </select>
                            </div>
                        )}

                        <div className="flex items-center space-x-2">
                            <input
                                type="checkbox"
                                id="auto_auth"
                                checked={!!(selectedNode.data as any).auto_auth}
                                onChange={(e) => updateNodeData('auto_auth', e.target.checked)}
                                className="w-4 h-4 rounded border-border text-primary focus:ring-primary"
                            />
                            <label
                                htmlFor="auto_auth"
                                className="text-sm font-medium cursor-pointer"
                            >
                                Criar conta e Autenticar usuário
                            </label>
                        </div>

                        <div className="bg-muted p-3 rounded-md text-xs text-muted-foreground space-y-2">
                            {!!(selectedNode.data as any).auto_auth && (
                                <p>✓ Autentica o visitante e gera tokens JWT no background.</p>
                            )}
                            {(selectedNode.data as any).action === 'navigate' && (
                                <p>Redireciona o navegador para outra página opcionalmente.</p>
                            )}
                            {(selectedNode.data as any).action === 'scroll_to' && (
                                <p>Desliza suavemente até o elemento da página atual.</p>
                            )}
                        </div>
                    </div>
                )
            }
        </aside >
    );
};
