
import React from 'react';
import { Save, Trash2, Loader2, ArrowLeft, GitBranch, Play, Settings } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/Button';

interface FloatingToolbarProps {
    onSave: () => void;
    onDelete: () => void;
    onTest: () => void;
    isSaving: boolean;
    hasSelection: boolean;
    flowName?: string;
    onOpenSettings: () => void;
}

export const FloatingToolbar = ({ onSave, onDelete, onTest, isSaving, hasSelection, flowName, onOpenSettings }: FloatingToolbarProps) => {
    return (
        <div className="absolute top-4 left-4 right-4 z-fab flex justify-between items-center">
            {/* Esquerda: voltar + nome do fluxo */}
            <div className="flex items-center gap-3 bg-card/80 text-card-foreground backdrop-blur shadow-e2 border border-border px-3 py-2 rounded-lg">
                <Link
                    to="/admin/chat/flows"
                    className="p-1.5 rounded-md hover:bg-accent text-muted-foreground hover:text-accent-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    title="Voltar para Fluxos"
                >
                    <ArrowLeft className="w-4 h-4" />
                </Link>
                <div className="h-6 w-px bg-border" />
                <div className="flex items-center gap-2">
                    <GitBranch className="w-4 h-4 text-primary" />
                    <span className="text-sm font-medium">{flowName || 'Carregando...'}</span>
                </div>
            </div>

            {/* Direita: ações */}
            <div className="flex gap-2 bg-card/80 text-card-foreground backdrop-blur shadow-e2 border border-border p-2 rounded-lg">
                {hasSelection && (
                    <Button
                        variant="destructive"
                        size="sm"
                        onClick={onDelete}
                        title="Deletar selecionado (Delete/Backspace)"
                    >
                        <Trash2 className="w-4 h-4" />
                        <span className="text-sm font-medium">Deletar</span>
                    </Button>
                )}

                {hasSelection && <div className="h-8 w-px bg-border mx-1" />}

                <Button
                    variant="ghost"
                    size="sm"
                    onClick={onOpenSettings}
                    title="Configurações do Fluxo"
                >
                    <Settings className="w-4 h-4" />
                    <span className="text-sm font-medium hidden sm:inline">Config</span>
                </Button>

                <Button
                    variant="secondary"
                    size="sm"
                    onClick={onTest}
                    title="Testar Fluxo"
                >
                    <Play className="w-4 h-4 fill-current" />
                    <span className="text-sm font-medium">Testar</span>
                </Button>

                <Button
                    variant="primary"
                    size="sm"
                    onClick={onSave}
                    disabled={isSaving}
                    title="Salvar Fluxo"
                >
                    {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                    <span className="text-sm font-medium">{isSaving ? 'Salvando...' : 'Salvar'}</span>
                </Button>
            </div>
        </div>
    );
};
