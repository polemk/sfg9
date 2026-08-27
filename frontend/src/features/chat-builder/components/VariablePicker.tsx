
import React, { useState } from 'react';
import { Sparkles, X, Plus, Trash2, Info } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { useAuthStore } from '@/store/authStore';
import { usersApi, authApi } from '@/lib/api/endpoints';
import { toast } from 'sonner';

const SYSTEM_VARIABLES = [
    { label: 'Primeiro Nome', value: '{{first_name}}' },
    { label: 'Sobrenome', value: '{{last_name}}' },
    { label: 'Nome Completo', value: '{{full_name}}' },
    { label: 'E-mail', value: '{{email}}' },
    { label: 'Telefone', value: '{{phone}}' },
    { label: 'ID do Contato', value: '{{id}}' },
];

interface VariablePickerProps {
    onSelect: (variable: string) => void;
}

export const VariablePicker = ({ onSelect }: VariablePickerProps) => {
    const [isOpen, setIsOpen] = useState(false);
    const [activeTab, setActiveTab] = useState<'system' | 'custom'>('system');
    const [newVariable, setNewVariable] = useState('');
    const [isCreating, setIsCreating] = useState(false);

    // Get user from store and actions
    const { user, updateMe } = useAuthStore();

    // Derived custom variables from user object
    const customVariables = React.useMemo(() => {
        if (!user?.custom_variables) return [];
        return Object.keys(user.custom_variables).map(key => ({
            label: key,
            value: `{{${key}}}`
        }));
    }, [user?.custom_variables]);

    const handleCreateVariable = async () => {
        if (!newVariable.trim()) return;

        // Auto-format: lowercase, snake_case
        const formattedName = newVariable.trim().toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '');

        if (!formattedName) {
            toast.error('Nome de variável inválido');
            return;
        }

        try {
            setIsCreating(true);
            const currentVars = user?.custom_variables || {};

            // Check if already exists
            if (currentVars[formattedName]) {
                toast.error('Variável já existe');
                return;
            }

            const updatedVars = { ...currentVars, [formattedName]: formattedName }; // Store label as value for now

            // Update user in backend
            if (user?.id) {
                const updatedUser = await usersApi.update(user.id, { custom_variables: updatedVars });
                // Update local store immediately
                updateMe({ custom_variables: updatedVars });

                // Auto-select the newly created variable
                onSelect(`{{${formattedName}}}`);
                setIsOpen(false);

                setNewVariable('');
                toast.success('Variável criada e inserida!');
            }
        } catch (error) {
            console.error(error);
            toast.error('Erro ao criar variável');
        } finally {
            setIsCreating(false);
        }
    };

    const handleDeleteVariable = async (key: string, e: React.MouseEvent) => {
        e.stopPropagation();
        if (!confirm(`Excluir variável "${key}"?`)) return;

        try {
            const currentVars = { ...(user?.custom_variables || {}) };
            delete currentVars[key];

            if (user?.id) {
                await usersApi.update(user.id, { custom_variables: currentVars });
                updateMe({ custom_variables: currentVars });
                toast.success('Variável removida');
            }
        } catch (error) {
            console.error(error);
            toast.error('Erro ao remover variável');
        }
    };

    if (!isOpen) {
        return (
            <Button
                variant="link"
                size="sm"
                onClick={() => setIsOpen(true)}
                className="mt-1 h-auto gap-1 px-0 text-xs"
            >
                <Sparkles className="w-3 h-3" />
                Inserir Variável
            </Button>
        );
    }

    return (
        <div className="absolute z-drawer bg-popover text-popover-foreground border border-border rounded-lg shadow-e3 w-72 mt-1 p-0 animate-in fade-in zoom-in-95 duration-200 overflow-hidden flex flex-col">
            {/* Header */}
            <div className="flex items-center justify-between p-2 border-b border-border bg-muted/30">
                <span className="text-xs font-semibold">Variáveis</span>
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

            {/* Tabs */}
            <div className="flex p-1 gap-1 border-b border-border">
                <button
                    type="button"
                    onClick={() => setActiveTab('system')}
                    className={`flex-1 text-xs py-1.5 px-2 rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeTab === 'system' ? 'bg-primary/10 text-primary font-medium' : 'hover:bg-accent hover:text-accent-foreground text-muted-foreground'
                        }`}
                >
                    Sistema
                </button>
                <button
                    type="button"
                    onClick={() => setActiveTab('custom')}
                    className={`flex-1 text-xs py-1.5 px-2 rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeTab === 'custom' ? 'bg-primary/10 text-primary font-medium' : 'hover:bg-accent hover:text-accent-foreground text-muted-foreground'
                        }`}
                >
                    Customizadas
                </button>
            </div>

            {/* Content */}
            <div className="p-2 max-h-64 overflow-y-auto min-h-[150px]">
                {activeTab === 'system' ? (
                    <div className="space-y-1">
                        {SYSTEM_VARIABLES.map((v) => (
                            <button
                                key={v.value}
                                type="button"
                                onClick={() => {
                                    onSelect(v.value);
                                    setIsOpen(false);
                                }}
                                className="w-full text-left px-2 py-1.5 text-xs rounded-sm hover:bg-accent hover:text-accent-foreground transition-colors flex items-center gap-2 group focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            >
                                <span className="font-mono text-primary opacity-70">{'{}'}</span>
                                <span className="flex-1">{v.label}</span>
                                <span className="text-xs text-muted-foreground opacity-0 group-hover:opacity-100">{v.value}</span>
                            </button>
                        ))}
                    </div>
                ) : (
                    <div className="space-y-2">
                        {/* Creator */}
                        <div className="flex gap-1 items-center mb-2">
                            <input
                                type="text"
                                value={newVariable}
                                onChange={(e) => setNewVariable(e.target.value)}
                                placeholder="Nova variável (ex: score)"
                                className="flex-1 px-2 py-1 text-xs border border-input rounded-sm bg-transparent focus:outline-none focus:ring-2 focus:ring-ring"
                                onKeyDown={(e) => e.key === 'Enter' && handleCreateVariable()}
                            />
                            <Button
                                variant="primary"
                                size="icon"
                                onClick={handleCreateVariable}
                                disabled={isCreating || !newVariable}
                                className="h-7 w-7 shrink-0"
                                title="Criar variável"
                            >
                                <Plus className="w-3 h-3" />
                            </Button>
                        </div>

                        {/* Info */}
                        <div className="flex gap-2 p-2 bg-info/10 rounded-sm text-xs text-info items-start">
                            <Info className="w-3 h-3 mt-0.5 shrink-0" />
                            <p>Use variáveis para salvar respostas do usuário. Ex: Pergunta "Qual seu time?" salva em <code>time_futebol</code>.</p>
                        </div>

                        {/* List */}
                        <div className="space-y-1 mt-2">
                            {customVariables.length === 0 ? (
                                <p className="text-xs text-muted-foreground text-center py-4">Nenhuma variável criada.</p>
                            ) : (
                                customVariables.map((v) => (
                                    <div
                                        key={v.value}
                                        className="w-full flex items-center gap-1 group"
                                    >
                                        <button
                                            type="button"
                                            onClick={() => {
                                                onSelect(v.value);
                                                setIsOpen(false);
                                            }}
                                            className="flex-1 text-left px-2 py-1.5 text-xs rounded-sm hover:bg-accent hover:text-accent-foreground transition-colors flex items-center gap-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                                        >
                                            <span className="font-mono text-warning opacity-70">{'{}'}</span>
                                            <span className="flex-1">{v.label}</span>
                                        </button>
                                        <Button
                                            variant="ghost"
                                            size="icon"
                                            onClick={(e) => handleDeleteVariable(v.label, e)}
                                            className="h-7 w-7 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
                                            title="Remover variável"
                                        >
                                            <Trash2 className="w-3 h-3 text-destructive" />
                                        </Button>
                                    </div>
                                ))
                            )}
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};
