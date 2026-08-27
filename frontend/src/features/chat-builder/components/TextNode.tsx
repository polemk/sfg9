
import React, { memo } from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { MessageSquare } from 'lucide-react';
import { TextNodeData } from '../types/nodes';

// Nó de mensagem: cor semântica do tipo "Text/Message" é `info`.
const TextNode = ({ data: rawData, selected }: NodeProps) => {
    const data = rawData as TextNodeData;
    return (
        <div className={`px-4 py-3 shadow-e1 rounded-lg border-2 bg-card min-w-[200px] ${selected ? 'border-info ring-2 ring-info/20' : 'border-border'}`}>
            <div className="flex items-center text-info mb-2">
                <MessageSquare className="w-4 h-4 mr-2" />
                <span className="text-xs font-bold uppercase">Mensagem</span>
            </div>

            <div className="text-sm text-card-foreground">
                {data.content || <span className="italic text-muted-foreground">Sem conteúdo...</span>}
            </div>

            <Handle type="target" position={Position.Left} className="w-3 h-3 bg-info border-2 border-background" />
            <Handle type="source" position={Position.Right} className="w-3 h-3 bg-info border-2 border-background" />
        </div>
    );
};

export default memo(TextNode);
