import React, { memo } from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { GitBranch } from 'lucide-react';
import { HandoffNodeData } from '../types/nodes';

// Nó de transferência: cor semântica do tipo "Handoff" é `brand-steel`.
const HandoffNodeComponent = ({ data, selected }: NodeProps & { data: HandoffNodeData }) => {
    return (
        <div className={`px-4 py-3 shadow-e1 rounded-md bg-card border-2 min-w-[200px] ${selected ? 'border-brand-steel ring-2 ring-brand-steel/20' : 'border-border'}`}>
            <Handle type="target" position={Position.Top} className="w-3 h-3 bg-brand-steel border-2 border-background" />

            <div className="flex items-center gap-3 mb-2">
                <div className="p-2 bg-muted rounded-full">
                    <GitBranch className="w-4 h-4 text-brand-steel" />
                </div>
                <div className="font-bold text-sm text-card-foreground">
                    Transferência
                </div>
            </div>

            <div className="text-xs text-muted-foreground bg-muted/50 p-2 rounded-sm">
                <span className="font-semibold">Destino: </span>
                {data.targetFlowName || <span className="italic text-destructive">Não configurado</span>}
            </div>
        </div>
    );
};

export const HandoffNode = memo(HandoffNodeComponent);
