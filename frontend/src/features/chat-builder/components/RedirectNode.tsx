
import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { ExternalLink, Hash, KeyRound } from 'lucide-react';
import { ChatNodeData } from '../types/nodes';

// Nó de redirecionamento: cor semântica do tipo "Redirect" é `muted`.
export const RedirectNode = ({ data, selected }: NodeProps & { data: ChatNodeData }) => {
    // Cast to explicit type if needed or use optional chaining
    const action = (data as any).action || 'navigate';
    const url = (data as any).url;
    const target = (data as any).target;
    const autoAuth = (data as any).auto_auth;

    const getIcon = () => {
        switch (action) {
            case 'scroll_to': return <Hash className="w-4 h-4 text-muted-foreground" />;
            default: return <ExternalLink className="w-4 h-4 text-muted-foreground" />;
        }
    };

    const getLabel = () => {
        switch (action) {
            case 'scroll_to': return 'Rolar para Elemento';
            default: return 'Navegar para URL';
        }
    };

    return (
        <div className={`px-4 py-3 shadow-e1 rounded-md bg-card border-2 min-w-[200px] ${selected ? 'border-muted-foreground ring-2 ring-muted-foreground/20' : 'border-border'}`}>
            <Handle type="target" position={Position.Top} className="w-3 h-3 bg-muted-foreground border-2 border-background" />

            <div className="flex items-center gap-3 mb-2">
                <div className="p-2 bg-muted rounded-full">
                    {getIcon()}
                </div>
                <div className="font-bold text-sm text-card-foreground">
                    {getLabel()}
                </div>
            </div>

            <div className="text-xs text-muted-foreground bg-muted/50 p-2 rounded-sm break-all max-w-[180px] flex flex-col gap-1">
                {action === 'scroll_to' && (
                    <span className="font-mono">{target || '#selector'}</span>
                )}
                {action === 'navigate' && (
                    <span className="underline">{url || 'https://...'}</span>
                )}
                {autoAuth && (
                    <div className="flex items-center gap-1 text-success font-medium">
                        <KeyRound className="w-3 h-3" /> Auto-login
                    </div>
                )}
            </div>

            {/* Redirect node is usually terminal, but could continue if needed. 
                For now, let's allow continuing flow? 
                Actually, navigate/auth usually disrupts flow unless it's just a command.
                Let's keep source handle for flexibility.
            */}
            <Handle type="source" position={Position.Bottom} className="w-3 h-3 bg-muted-foreground border-2 border-background" />
        </div>
    );
};
