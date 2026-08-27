
import React, { memo } from 'react';
import { Handle, Position, NodeProps, Node } from '@xyflow/react';
import { List } from 'lucide-react';
import { OptionNodeData } from '../types/nodes';

// Nó de lista de escolha: cor semântica do tipo "List" é `warning`.
const ListNode = ({ data, selected }: NodeProps<Node<OptionNodeData>>) => {
    return (
        <div className={`px-4 py-3 shadow-e1 rounded-lg border-2 bg-card min-w-[250px] ${selected ? 'border-warning ring-2 ring-warning/20' : 'border-border'}`}>
            <div className="flex items-center text-warning mb-2">
                <List className="w-4 h-4 mr-2" />
                <span className="text-xs font-bold uppercase">Lista de Opções</span>
            </div>

            <div className="text-sm text-foreground mb-3">
                {data.content}
            </div>

            <div className="space-y-2">
                <div className="bg-muted p-2 rounded-sm text-xs border border-border">
                    <div className="font-semibold mb-1 text-muted-foreground">Exemplo de lista:</div>
                    {(data.options || []).slice(0, 3).map((option, index) => (
                        <div key={index} className="pl-2 border-l-2 border-warning/50 mb-1 last:mb-0">
                            {option}
                        </div>
                    ))}
                    {(data.options || []).length > 3 && (
                        <div className="pl-2 text-muted-foreground">... mais <span className="font-numeric">{(data.options || []).length - 3}</span> itens</div>
                    )}
                    {(data.options || []).length === 0 && (
                        <div className="pl-2 text-muted-foreground italic">Nenhuma opção</div>
                    )}
                </div>
            </div>

            <Handle
                type="target"
                position={Position.Left}
                className="w-3 h-3 bg-warning border-2 border-background"
            />
            <Handle
                type="source"
                position={Position.Right}
                className="w-3 h-3 bg-warning border-2 border-background"
            />
        </div>
    );
};

export default memo(ListNode);
