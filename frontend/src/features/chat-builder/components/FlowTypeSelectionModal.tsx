import React, { useState } from 'react';
import { X, GitBranch, Bot, ArrowRight } from 'lucide-react';
import { FlowKind } from '../api/builder';
import { Button } from '@/components/ui/Button';

interface FlowTypeSelectionModalProps {
    isOpen: boolean;
    onClose: () => void;
    onSelect: (kind: FlowKind, name: string) => void;
    isCreating?: boolean;
}

export function FlowTypeSelectionModal({ isOpen, onClose, onSelect, isCreating }: FlowTypeSelectionModalProps) {
    const [selectedKind, setSelectedKind] = useState<FlowKind | null>(null);
    const [flowName, setFlowName] = useState('');

    const handleContinue = () => {
        if (!selectedKind || !flowName.trim()) return;
        onSelect(selectedKind, flowName.trim());
    };

    const handleClose = () => {
        setSelectedKind(null);
        setFlowName('');
        onClose();
    };

    if (!isOpen) return null;

    // Card de tipo de fluxo: gatilho/agente de IA usam o ouro (primary).
    const cardClass = (active: boolean) =>
        `group relative flex flex-col items-center p-6 rounded-lg border-2 transition-all text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${
            active
                ? 'border-primary bg-primary/5 shadow-e2'
                : 'border-border hover:border-primary/50 hover:bg-muted/30'
        }`;

    const cardIconClass = (active: boolean) =>
        `p-3 rounded-lg mb-4 transition-colors ${active ? 'bg-primary/10' : 'bg-muted group-hover:bg-primary/5'}`;

    return (
        <div className="fixed inset-0 z-modal flex items-center justify-center bg-brand-ink/70 backdrop-blur-sm p-4">
            <div className="bg-card text-card-foreground w-full max-w-lg rounded-lg border border-border shadow-e3 flex flex-col">

                {/* Cabeçalho */}
                <div className="flex items-center justify-between p-4 border-b border-border">
                    <h2 className="font-title text-base font-semibold text-foreground">Criar Novo Fluxo</h2>
                    <Button
                        variant="ghost"
                        size="icon"
                        onClick={handleClose}
                        className="h-8 w-8"
                        title="Fechar"
                    >
                        <X className="w-5 h-5" />
                    </Button>
                </div>

                {/* Corpo */}
                <div className="p-6 space-y-6">
                    {/* Nome do fluxo */}
                    <div className="space-y-2">
                        <label className="text-sm font-medium text-muted-foreground">Nome do Fluxo</label>
                        <input
                            type="text"
                            value={flowName}
                            onChange={(e) => setFlowName(e.target.value)}
                            className="w-full px-3 py-2.5 bg-muted/30 border border-input rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:border-primary transition-all"
                            placeholder="Ex: Atendimento ao Cliente"
                            autoFocus
                        />
                    </div>

                    {/* Escolha do tipo */}
                    <div className="space-y-3">
                        <label className="text-sm font-medium text-muted-foreground">Escolha o Tipo</label>

                        <div className="grid grid-cols-2 gap-4">
                            {/* Card Chatbot */}
                            <button
                                type="button"
                                onClick={() => setSelectedKind('chatbot')}
                                className={cardClass(selectedKind === 'chatbot')}
                            >
                                <div className={cardIconClass(selectedKind === 'chatbot')}>
                                    <GitBranch className={`w-6 h-6 ${
                                        selectedKind === 'chatbot' ? 'text-primary' : 'text-muted-foreground'
                                    }`} />
                                </div>
                                <h3 className="text-sm font-semibold text-foreground mb-1">Chatbot</h3>
                                <p className="text-xs text-muted-foreground text-center leading-relaxed">
                                    Fluxo visual com arrastar e soltar. Regras fixas e estruturadas.
                                </p>
                                {selectedKind === 'chatbot' && (
                                    <div className="absolute top-2 right-2 w-3 h-3 rounded-full bg-primary" />
                                )}
                            </button>

                            {/* Card Agente de IA */}
                            <button
                                type="button"
                                onClick={() => setSelectedKind('ai_agent')}
                                className={cardClass(selectedKind === 'ai_agent')}
                            >
                                <div className={cardIconClass(selectedKind === 'ai_agent')}>
                                    <Bot className={`w-6 h-6 ${
                                        selectedKind === 'ai_agent' ? 'text-primary' : 'text-muted-foreground'
                                    }`} />
                                </div>
                                <h3 className="text-sm font-semibold text-foreground mb-1">Agente de IA</h3>
                                <p className="text-xs text-muted-foreground text-center leading-relaxed">
                                    Inteligência autônoma baseada em prompt e modelo.
                                </p>
                                {selectedKind === 'ai_agent' && (
                                    <div className="absolute top-2 right-2 w-3 h-3 rounded-full bg-primary" />
                                )}
                            </button>
                        </div>
                    </div>
                </div>

                {/* Rodapé */}
                <div className="p-4 border-t border-border flex justify-end gap-3">
                    <Button
                        variant="secondary"
                        onClick={handleClose}
                    >
                        Cancelar
                    </Button>
                    <Button
                        variant="primary"
                        onClick={handleContinue}
                        disabled={!selectedKind || !flowName.trim() || isCreating}
                    >
                        {isCreating ? 'Criando...' : (
                            <>
                                Continuar
                                <ArrowRight className="w-4 h-4" />
                            </>
                        )}
                    </Button>
                </div>
            </div>
        </div>
    );
}
