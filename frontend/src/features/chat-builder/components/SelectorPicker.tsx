
import React, { useState } from 'react';
import { Target, X } from 'lucide-react';
import { Button } from '@/components/ui/Button';

const SELECTOR_CATEGORIES = [
    {
        label: 'Main Site',
        selectors: [
            { label: 'Planos', value: '#plans' },
            { label: 'Título Planos', value: '#plans-heading' },
            { label: 'Time', value: '#team-presentation' },
            { label: 'Carta', value: '#letter' },
            { label: 'Reator', value: '#reactor-area' },
        ]
    },
    {
        label: 'Admin',
        selectors: [
            { label: 'Topbar', value: '#topbar' },
            { label: 'Sidebar', value: '#sidebar' },
            { label: 'Content', value: '#content' },
            { label: 'Dashboard', value: '#dashboard' },
        ]
    },
    {
        label: 'Visitor',
        selectors: [
            { label: 'Chat Widget', value: '#chat-widget' },
            { label: 'Proposal View', value: '#proposal-view' },
            { label: 'Product List', value: '#product-list' },
        ]
    }
];

interface SelectorPickerProps {
    onSelect: (selector: string) => void;
    currentValue?: string;
}

export const SelectorPicker = ({ onSelect, currentValue }: SelectorPickerProps) => {
    const [isOpen, setIsOpen] = useState(false);

    if (!isOpen) {
        return (
            <Button
                variant="link"
                size="sm"
                onClick={() => setIsOpen(true)}
                className="mt-1 h-auto gap-1 px-0 text-xs"
            >
                <Target className="w-3 h-3" />
                Sugerir Seletor
            </Button>
        );
    }

    return (
        <div className="absolute z-drawer bg-popover text-popover-foreground border border-border rounded-lg shadow-e3 w-64 mt-1 p-0 animate-in fade-in zoom-in-95 duration-200 overflow-hidden flex flex-col">
            {/* Cabeçalho */}
            <div className="flex items-center justify-between p-2 border-b border-border bg-muted/30">
                <span className="text-xs font-semibold">Seletores CSS</span>
                <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => setIsOpen(false)}
                    className="h-6 w-6"
                    title="Fechar"
                >
                    <X className="w-3 h-3" />
                </Button>
            </div>

            {/* Conteúdo */}
            <div className="p-2 max-h-64 overflow-y-auto">
                {SELECTOR_CATEGORIES.map((category) => (
                    <div key={category.label} className="mb-3 last:mb-0">
                        <div className="text-xs font-bold uppercase text-muted-foreground mb-1 px-2">
                            {category.label}
                        </div>
                        <div className="space-y-0.5">
                            {category.selectors.map((sel) => (
                                <button
                                    key={sel.value}
                                    type="button"
                                    onClick={() => {
                                        onSelect(sel.value);
                                        setIsOpen(false);
                                    }}
                                    className={`w-full text-left px-2 py-1.5 text-xs rounded-sm hover:bg-accent hover:text-accent-foreground transition-colors flex items-center justify-between group focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${currentValue === sel.value ? 'bg-primary/10 text-primary' : ''
                                        }`}
                                >
                                    <span className="flex items-center gap-2">
                                        <span className="font-mono text-info opacity-70">#</span>
                                        <span>{sel.label}</span>
                                    </span>
                                    <span className="text-xs text-muted-foreground opacity-0 group-hover:opacity-100 font-mono">
                                        {sel.value}
                                    </span>
                                </button>
                            ))}
                        </div>
                    </div>
                ))}

                {/* Dica */}
                <div className="mt-2 p-2 bg-info/10 rounded-sm text-xs text-info">
                    <p>Você também pode digitar um seletor personalizado (ex: <code>#minha-secao</code>).</p>
                </div>
            </div>
        </div>
    );
};
