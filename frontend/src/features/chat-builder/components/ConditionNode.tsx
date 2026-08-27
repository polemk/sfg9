
import React, { memo } from 'react';
import { Handle, Position, NodeProps, Node } from '@xyflow/react';
import { GitFork } from 'lucide-react';
import { ConditionNodeData } from '../types/nodes';

// Nó de condição: cor semântica do tipo "Condition" é `brand-steel`.
// As saídas Sim/Não são estado de execução — seguem success/destructive.
const ConditionNode = ({ data, selected }: NodeProps<Node<ConditionNodeData>>) => {
    const variable = (data as any).variable || 'var';
    const operator = (data as any).operator || '==';
    const value = (data as any).value || 'valor';

    return (
        <div className={`px-4 py-3 shadow-e1 rounded-lg border-2 bg-card min-w-[200px] ${selected ? 'border-brand-steel ring-2 ring-brand-steel/20' : 'border-border'}`}>
            <div className="flex items-center text-brand-steel mb-2">
                <GitFork className="w-4 h-4 mr-2" />
                <span className="text-xs font-bold uppercase">Condição</span>
            </div>

            <div className="text-sm text-foreground mb-3 font-mono bg-muted/50 p-2 rounded-sm text-center">
                <span className="text-brand-steel">{variable}</span>
                <span className="mx-1 text-muted-foreground">{operator}</span>
                <span className="text-success">"{value}"</span>
            </div>

            <Handle
                type="target"
                position={Position.Left}
                className="w-3 h-3 bg-brand-steel border-2 border-background"
            />

            {/* Caminho verdadeiro */}
            <div className="absolute -right-3 top-4 flex items-center">
                <span className="mr-4 text-xs font-bold text-success uppercase">Sim</span>
                <Handle
                    type="source"
                    position={Position.Right}
                    id="true"
                    className="w-3 h-3 bg-success border-2 border-background"
                />
            </div>

            {/* Caminho falso */}
            <div className="absolute -right-3 bottom-4 flex items-center">
                <span className="mr-4 text-xs font-bold text-destructive uppercase">Não</span>
                <Handle
                    type="source"
                    position={Position.Right}
                    id="false"
                    className="w-3 h-3 bg-destructive border-2 border-background"
                />
            </div>
        </div>
    );
};

export default memo(ConditionNode);
