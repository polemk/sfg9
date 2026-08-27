
import React, { memo } from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Regex, TextCursorInput } from 'lucide-react';
import { InputNodeData } from '../types/nodes';

// Nó de captura de dado: cor semântica do tipo "Input" é `success`.
const InputNode = ({ data: rawData, selected }: NodeProps) => {
    const data = rawData as InputNodeData;
    return (
        <div className={`px-4 py-3 shadow-e1 rounded-lg border-2 bg-card min-w-[250px] ${selected ? 'border-success ring-2 ring-success/20' : 'border-border'}`}>
            <div className="flex items-center text-success mb-2">
                <TextCursorInput className="w-4 h-4 mr-2" />
                <span className="text-xs font-bold uppercase">Pergunta</span>
            </div>

            <div className="text-sm text-card-foreground mb-2">
                {data.content || <span className="italic text-muted-foreground">Pergunta...</span>}
            </div>

            <div className="bg-muted p-2 rounded-sm text-xs flex items-center justify-between">
                <span className="font-mono text-muted-foreground">Variável:</span>
                <span className="font-bold font-mono text-foreground">{data.variable || '???'}</span>
            </div>

            <Handle type="target" position={Position.Left} className="w-3 h-3 bg-success border-2 border-background" />
            <Handle type="source" position={Position.Right} className="w-3 h-3 bg-success border-2 border-background" />
        </div>
    );
};

export default memo(InputNode);
