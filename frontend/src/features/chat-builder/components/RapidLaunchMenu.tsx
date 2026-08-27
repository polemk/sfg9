import React, { useEffect, useRef } from 'react';
import { Type, MessageSquare, List, GitBranch, HelpCircle } from 'lucide-react';

interface RapidLaunchMenuProps {
    x: number;
    y: number;
    onSelect: (type: string) => void;
    onClose: () => void;
}

// Mesma cor por tipo de nó usada no canvas e na paleta de blocos.
const MENU_ITEMS = [
    { type: 'text', label: 'Texto', icon: MessageSquare, color: 'text-info' },
    { type: 'question', label: 'Pergunta', icon: HelpCircle, color: 'text-success' },
    { type: 'option', label: 'Opções', icon: List, color: 'text-warning' },
    { type: 'condition', label: 'Condição', icon: GitBranch, color: 'text-brand-steel' },
];

export function RapidLaunchMenu({ x, y, onSelect, onClose }: RapidLaunchMenuProps) {
    const menuRef = useRef<HTMLDivElement>(null);

    // Close on click outside
    useEffect(() => {
        const handleClickOutside = (event: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
                onClose();
            }
        };

        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, [onClose]);

    return (
        <div
            ref={menuRef}
            className="fixed z-fab bg-popover text-popover-foreground border border-border rounded-lg shadow-e3 p-2 w-48 animate-in fade-in zoom-in-95 duration-200"
            style={{ left: x, top: y }}
        >
            <div className="text-xs font-medium text-muted-foreground px-2 py-1.5 mb-1">
                Adicionar Próximo Passo
            </div>
            <div className="flex flex-col gap-1">
                {MENU_ITEMS.map((item) => (
                    <button
                        key={item.type}
                        type="button"
                        onClick={() => onSelect(item.type)}
                        className="flex items-center gap-3 px-2 py-2 text-sm text-popover-foreground hover:bg-accent hover:text-accent-foreground rounded-md transition-colors text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                        <item.icon className={`w-4 h-4 ${item.color}`} />
                        <span>{item.label}</span>
                    </button>
                ))}
            </div>
        </div>
    );
}
