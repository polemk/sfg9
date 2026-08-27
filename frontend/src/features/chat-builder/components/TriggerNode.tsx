
import React, { memo } from 'react';
import { Handle, Position, NodeProps, Node } from '@xyflow/react';
import { Zap, Play, Sparkles } from 'lucide-react';
import { TriggerNodeData } from '../types/nodes';

/**
 * TriggerNode — ponto de entrada de um fluxo.
 * Guarda as palavras-chave, condições de início ou disparo manual.
 * Cor semântica do tipo "Trigger" é `primary` (ouro Safegold).
 */
const TriggerNode = ({ data, selected }: NodeProps<Node<TriggerNodeData>>) => {
    const flowName = (data as any).flowName || 'Novo Fluxo';
    const keywords = ((data as any).keywords || []) as string[];
    const isDefault = (data as any).isDefault || false;

    return (
        <div className={`shadow-e2 rounded-lg border-2 min-w-[260px] max-w-[300px] overflow-hidden bg-card ${selected
            ? 'border-primary ring-2 ring-primary/30'
            : isDefault ? 'border-warning/50' : 'border-primary/30'
            }`}>

            {/* Cabeçalho */}
            <div className="bg-primary/10 px-3 py-2 border-b border-primary/20 flex items-center justify-between">
                <div className="flex items-center text-primary">
                    <Zap className="w-4 h-4 mr-2" />
                    <span className="text-xs font-bold uppercase tracking-wider">Gatilho</span>
                </div>
                {isDefault && (
                    <span className="text-xs px-1.5 py-0.5 bg-warning/20 text-warning rounded-sm font-medium">
                        PADRÃO
                    </span>
                )}
            </div>

            {/* Conteúdo */}
            <div className="p-3 space-y-3">
                {/* Nome do fluxo */}
                <div className="flex items-center gap-2">
                    <Play className="w-4 h-4 text-primary" />
                    <span className="font-semibold text-foreground">{flowName}</span>
                </div>

                {/* Palavras-chave */}
                <div className="space-y-1.5">
                    <span className="text-xs uppercase text-muted-foreground tracking-wider">Ativa quando:</span>
                    {keywords.length > 0 ? (
                        <div className="flex flex-wrap gap-1">
                            {keywords.map((kw: string, i: number) => (
                                <span
                                    key={i}
                                    className="px-2 py-0.5 text-xs bg-primary/10 text-primary rounded-full flex items-center gap-1"
                                >
                                    <Sparkles className="w-2.5 h-2.5" />
                                    {kw}
                                </span>
                            ))}
                        </div>
                    ) : isDefault ? (
                        <div className="text-xs text-muted-foreground italic">
                            Qualquer mensagem (fluxo padrão)
                        </div>
                    ) : (
                        <div className="text-xs text-muted-foreground italic">
                            Sem palavras-chave definidas
                        </div>
                    )}
                </div>

                {/* Dica */}
                {selected && (
                    <div className="text-xs text-center text-primary/70 pt-1 border-t border-border/30">
                        Edite as palavras-chave no painel lateral →
                    </div>
                )}
            </div>

            {/* Só saída — este é o INÍCIO */}
            <Handle
                type="source"
                position={Position.Right}
                className="w-3 h-3 bg-primary border-2 border-background"
                style={{ top: '50%' }}
            />
        </div>
    );
};

export default memo(TriggerNode);
