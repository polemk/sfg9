
import React from 'react';
import { MessageSquare, Type, ArrowRightCircle, ExternalLink } from 'lucide-react';

export const NodesSidebar = () => {
    const onDragStart = (event: React.DragEvent, nodeType: string) => {
        event.dataTransfer.setData('application/reactflow', nodeType);
        event.dataTransfer.effectAllowed = 'move';
    };

    // Cor por tipo de nó: mensagem = info, captura = success, escolha = warning,
    // condição/transferência = brand-steel, redirecionamento = muted.
    const itemClass =
        'flex items-center gap-2 p-3 bg-muted/50 border border-border rounded-md cursor-grab hover:bg-accent hover:text-accent-foreground transition-colors';

    return (
        <aside className="w-64 bg-card text-card-foreground border-r border-border p-4 flex flex-col gap-4">
            <div className="font-title font-semibold text-lg">Blocos</div>
            <div className="font-semibold mb-4 text-xs uppercase tracking-wider text-muted-foreground">Blocos Disponíveis</div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'text')}
                draggable
            >
                <MessageSquare className="w-4 h-4 text-info" />
                <span className="text-sm">Mensagem</span>
            </div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'question')}
                draggable
            >
                <Type className="w-4 h-4 text-success" />
                <span className="text-sm">Pergunta</span>
            </div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'option')}
                draggable
            >
                <div className="flex gap-1">
                    <div className="w-4 h-2 bg-warning rounded-sm" />
                    <div className="w-4 h-2 bg-warning rounded-sm" />
                </div>
                <span className="text-sm">Botões</span>
            </div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'list')}
                draggable
            >
                <div className="flex flex-col gap-1">
                    <div className="w-4 h-1 bg-warning rounded-sm" />
                    <div className="w-4 h-1 bg-warning rounded-sm" />
                    <div className="w-4 h-1 bg-warning rounded-sm" />
                </div>
                <span className="text-sm">Lista</span>
            </div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'condition')}
                draggable
            >
                <div className="rotate-45 w-3 h-3 border-2 border-brand-steel rounded-sm" />
                <span className="text-sm">Condicional</span>
            </div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'handoff')}
                draggable
            >
                <ArrowRightCircle className="w-4 h-4 text-brand-steel" />
                <span className="text-sm">Saltar para Fluxo</span>
            </div>

            <div
                className={itemClass}
                onDragStart={(event) => onDragStart(event, 'redirect')}
                draggable
            >
                <ExternalLink className="w-4 h-4 text-muted-foreground" />
                <span className="text-sm">Redirecionar / Ação</span>
            </div>

        </aside>
    );
};
