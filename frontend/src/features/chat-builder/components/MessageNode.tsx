
import React, { memo } from 'react';
import { Handle, Position, NodeProps, Node } from '@xyflow/react';
import { MessageSquare, Clock } from 'lucide-react';
import { TextNodeData } from '../types/nodes';

// Nó de mensagem com vários balões dentro. Cor do tipo "Message" = `info`.
const MessageNode = ({ data, selected }: NodeProps<Node<TextNodeData>>) => {
    const blocks = (data as any).blocks || [{ type: 'text', content: data.content }];

    return (
        <div className={`shadow-e1 rounded-lg border-2 bg-card min-w-[280px] max-w-[320px] overflow-hidden ${selected ? 'border-info ring-2 ring-info/20' : 'border-border'}`}>
            {/* Cabeçalho */}
            <div className="bg-muted/30 px-3 py-2 border-b border-border flex items-center justify-between">
                <div className="flex items-center text-info">
                    <MessageSquare className="w-3.5 h-3.5 mr-2" />
                    <span className="text-xs font-bold uppercase tracking-wider">Mensagem</span>
                </div>
            </div>

            {/* Blocos de conteúdo */}
            <div className="p-2 space-y-2 relative">
                {blocks.map((block: any, idx: number) => (
                    <div key={idx} className="relative group">
                        {block.type === 'text' && (
                            <div className="bg-secondary/50 text-secondary-foreground p-3 rounded-tr-lg rounded-br-lg rounded-bl-lg text-sm leading-relaxed border border-border/50">
                                {block.content}
                            </div>
                        )}
                        {block.type === 'delay' && (
                            <div className="flex items-center justify-center gap-2 py-2 text-xs text-muted-foreground bg-muted/20 rounded-full border border-dashed border-border">
                                <Clock className="w-3 h-3" />
                                <span>Aguardando <span className="font-numeric">{block.seconds || 3}</span> segundos...</span>
                            </div>
                        )}
                    </div>
                ))}

                {/* Dica de edição */}
                {selected && <div className="text-xs text-center text-muted-foreground pt-1 opacity-50">Clique em editar para adicionar conteúdo ou botões</div>}

                {/* Opções / botões */}
                {(data as any).options && (data as any).options.length > 0 && (
                    <div className="mt-4 pt-3 border-t border-border/50 space-y-2">
                        {(data as any).options.map((option: any, index: number) => (
                            <div key={index} className="relative group">
                                <div className="flex items-center justify-between bg-secondary/30 hover:bg-secondary/50 p-2 rounded-md border border-border/50 transition-colors">
                                    <span className="text-xs font-medium text-secondary-foreground">{option}</span>
                                </div>
                                <Handle
                                    type="source"
                                    position={Position.Right}
                                    id={`option-${index}`}
                                    className="!w-2 !h-2 !bg-info !border-2 !border-background !-right-1 transition-transform group-hover:scale-125"
                                />
                            </div>
                        ))}
                    </div>
                )}
            </div>

            <Handle
                type="target"
                position={Position.Left}
                className="w-3 h-3 bg-info border-2 border-background top-8"
            />
            <Handle
                type="source"
                position={Position.Right}
                className="w-3 h-3 bg-info border-2 border-background top-8"
            />
        </div>
    );
};

export default memo(MessageNode);
