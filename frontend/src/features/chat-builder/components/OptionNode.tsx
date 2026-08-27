
import React, { memo } from 'react';
import { Handle, Position, NodeProps, Node } from '@xyflow/react';
import { MousePointerClick } from 'lucide-react';
import { OptionNodeData } from '../types/nodes';

// Nó de escolha (botões): cor semântica do tipo "Option" é `warning`.
const OptionNode = ({ data, selected }: NodeProps<Node<OptionNodeData>>) => {
    return (
        <div className={`px-4 py-3 shadow-e1 rounded-lg border-2 bg-card min-w-[250px] ${selected ? 'border-warning ring-2 ring-warning/20' : 'border-border'}`}>
            <div className="flex items-center text-warning mb-2">
                <MousePointerClick className="w-4 h-4 mr-2" />
                <span className="text-xs font-bold uppercase">Botões (Opções)</span>
            </div>

            <div className="text-sm text-foreground mb-3">
                {data.content}
            </div>

            <div className="space-y-2">
                {(data.options || []).map((option, index) => (
                    <div key={index} className="relative group">
                        <div className="flex items-center justify-between bg-muted hover:bg-accent p-2 rounded-md border border-border transition-colors">
                            <span className="text-xs font-medium">{option}</span>
                        </div>
                        <Handle
                            type="source"
                            position={Position.Right}
                            id={`option-${index}`}
                            className="!w-3 !h-3 !bg-warning !border-2 !border-background !-right-1.5 transition-transform group-hover:scale-125"
                        />
                    </div>
                ))}
                {(data.options || []).length === 0 && (
                    <div className="text-xs text-muted-foreground italic text-center py-2 bg-muted/20 rounded-sm">
                        + Adicione opções no menu lateral
                    </div>
                )}
            </div>

            <Handle
                type="target"
                position={Position.Left}
                className="w-3 h-3 bg-warning border-2 border-background"
            />
        </div>
    );
};

export default memo(OptionNode);
