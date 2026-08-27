
import React, { useState, useEffect } from 'react';
import { X, Save, MessageSquare, VenetianMask, Image as ImageIcon, Upload, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/Button';
import { KeywordInput } from './KeywordInput';
import { apiClient } from '@/lib/api/client';

interface FlowSettingsModalProps {
    isOpen: boolean;
    onClose: () => void;
    onSave: (data: FlowSettingsData) => Promise<void>;
    initialData: FlowSettingsData;
}

export interface FlowSettingsData {
    name: string;
    keywords: string[];
    personaName?: string;
    personaDescription?: string;
    personaAvatar?: string;
}

export function FlowSettingsModal({ isOpen, onClose, onSave, initialData }: FlowSettingsModalProps) {
    const [name, setName] = useState(initialData.name);
    const [keywords, setKeywords] = useState<string[]>(initialData.keywords);
    const [personaName, setPersonaName] = useState(initialData.personaName || '');
    const [personaDescription, setPersonaDescription] = useState(initialData.personaDescription || '');
    const [personaAvatar, setPersonaAvatar] = useState(initialData.personaAvatar || '');
    const [isSaving, setIsSaving] = useState(false);
    const [uploadingAvatar, setUploadingAvatar] = useState(false);
    const fileInputRef = React.useRef<HTMLInputElement | null>(null);

    useEffect(() => {
        if (isOpen) {
            setName(initialData.name);
            setKeywords(initialData.keywords || []);
            setPersonaName(initialData.personaName || '');
            setPersonaDescription(initialData.personaDescription || '');
            setPersonaAvatar(initialData.personaAvatar || '');
        }
    }, [isOpen, initialData]);

    const performSave = async () => {
        setIsSaving(true);
        try {
            await onSave({ name, keywords, personaName, personaDescription, personaAvatar });
            onClose();
        } catch (error) {
            console.error(error);
            toast.error('Erro ao salvar configurações');
        } finally {
            setIsSaving(false);
        }
    };

    const handleSave = (e: React.FormEvent) => { e.preventDefault(); performSave(); };

    const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;
        if (file.size > 2 * 1024 * 1024) {
            toast.error('Arquivo muito grande (máx. 2MB)');
            if (fileInputRef.current) fileInputRef.current.value = "";
            return;
        }
        setUploadingAvatar(true);
        try {
            const form = new FormData();
            form.append('file', file);
            const data: any = await apiClient.post(
                '/api/v1/uploads/avatar',
                form,
                { headers: { 'Content-Type': 'multipart/form-data' } }
            );
            console.log("[Avatar Upload Flow] API Response:", data);
            
            const url = data?.data?.url || data?.url;
            if (url) {
                setPersonaAvatar(url);
                toast.success('Avatar do fluxo enviado com sucesso!');
            } else {
                throw new Error("Invalid response format: missing url");
            }
        } catch (err: any) {
            console.error("[Avatar Upload Flow] Error:", err);
            toast.error(err?.response?.data?.message || err?.message || 'Erro ao enviar avatar');
        } finally {
            if (fileInputRef.current) fileInputRef.current.value = "";
            setUploadingAvatar(false);
        }
    };

    if (!isOpen) return null;

    return (
        <div className="fixed inset-0 z-modal flex items-center justify-center bg-brand-ink/70 backdrop-blur-sm p-4">
            <div className="bg-popover w-full max-w-md rounded-lg border border-border shadow-e3 flex flex-col max-h-[90vh] relative">

                {/* Header */}
                <div className="flex items-center justify-between p-4 border-b border-border shrink-0">
                    <div className="flex items-center gap-2 text-primary">
                        <SettingsHeaderIcon className="w-5 h-5" />
                        <h2 className="text-sm font-bold uppercase tracking-wider text-foreground">Configurações do Fluxo</h2>
                    </div>
                    <Button variant="ghost" size="icon" onClick={onClose} aria-label="Fechar">
                        <X className="w-5 h-5" />
                    </Button>
                </div>

                {/* Body */}
                <form onSubmit={handleSave} className="flex-1 overflow-y-auto p-6 pb-20 space-y-6">

                    {/* Flow Identifiers */}
                    <div className="space-y-4">
                        <div className="flex items-center gap-2 mb-2">
                            <div className="p-1.5 bg-info/10 rounded-md">
                                <MessageSquare className="w-4 h-4 text-info" />
                            </div>
                            <span className="text-xs font-bold uppercase text-muted-foreground">Identificação</span>
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-xs font-medium text-muted-foreground block">Nome do Fluxo</label>
                            <input
                                type="text"
                                value={name}
                                onChange={(e) => setName(e.target.value)}
                                className="w-full px-3 py-2 bg-secondary/30 border border-border rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                placeholder="Ex: Onboarding Vendas"
                                required
                            />
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-xs font-medium text-muted-foreground block">Gatilhos (Keywords)</label>
                            <KeywordInput
                                value={keywords}
                                onChange={setKeywords}
                                placeholder="Ex: olá, comprar, preço, start"
                            />
                        </div>
                    </div>

                    <div className="h-px bg-border" />

                    {/* Persona Settings */}
                    <div className="space-y-4">
                        <div className="flex items-center gap-2 mb-2">
                            <div className="p-1.5 bg-primary/10 rounded-md">
                                <VenetianMask className="w-4 h-4 text-primary" />
                            </div>
                            <span className="text-xs font-bold uppercase text-muted-foreground">Persona do Agente</span>
                        </div>

                        <div className="flex gap-4">
                            <div className="space-y-1.5 flex-1">
                                <label className="text-xs font-medium text-muted-foreground block">Nome do Atendente</label>
                                <input
                                    type="text"
                                    value={personaName}
                                    onChange={(e) => setPersonaName(e.target.value)}
                                    className="w-full px-3 py-2 bg-secondary/30 border border-border rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all font-medium"
                                    placeholder="Ex: Ana da Silva"
                                />
                            </div>
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-xs font-medium text-muted-foreground block">Subtítulo / Descrição</label>
                            <input
                                type="text"
                                value={personaDescription}
                                onChange={(e) => setPersonaDescription(e.target.value)}
                                className="w-full px-3 py-2 bg-secondary/30 border border-border rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                placeholder="Ex: Guia interativa do Safegold"
                            />
                            <p className="text-xs text-muted-foreground/60 mt-1">
                                Aparece abaixo do nome no cabeçalho do chat.
                            </p>
                        </div>

                        <div className="space-y-1.5">
                            <label className="text-xs font-medium text-muted-foreground block">Avatar URL</label>
                            <div className="flex gap-3">
                                <div className="relative flex-grow">
                                    <ImageIcon className="absolute left-3 top-2.5 w-4 h-4 text-muted-foreground" />
                                    <input
                                        type="url"
                                        value={personaAvatar}
                                        onChange={(e) => setPersonaAvatar(e.target.value)}
                                        className="w-full pl-9 pr-3 py-2 bg-secondary/30 border border-border rounded-md text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                        placeholder="https://..."
                                    />
                                </div>
                                <div className="relative group shrink-0">
                                    <button
                                        type="button"
                                        aria-label="Enviar avatar da persona"
                                        className="relative w-10 h-10 rounded-full bg-secondary/30 border border-border overflow-hidden flex items-center justify-center cursor-pointer transition-all hover:ring-2 hover:ring-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                                        onClick={() => fileInputRef.current?.click()}
                                    >
                                        {uploadingAvatar ? (
                                            <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
                                        ) : personaAvatar ? (
                                            <img src={personaAvatar} alt="Preview" className="w-full h-full object-cover" />
                                        ) : (
                                            <VenetianMask className="w-5 h-5 text-muted-foreground/30" />
                                        )}

                                        {!uploadingAvatar && (
                                            <div className="absolute inset-0 bg-brand-ink/60 text-brand-ink-foreground opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity rounded-full">
                                                <Upload className="w-4 h-4 text-background" />
                                            </div>
                                        )}
                                    </button>
                                    <input ref={fileInputRef} type="file" accept="image/*" onChange={handleAvatarFile} className="hidden" />
                                </div>
                            </div>
                        </div>
                    </div>

                </form>

                <Button
                    type="button"
                    onClick={performSave}
                    disabled={isSaving}
                    variant="primary"
                    className="helper-fab absolute right-6 bottom-6 h-12 w-12 p-0 rounded-full shadow-e2"
                    aria-label="Salvar configurações"
                >
                    {isSaving ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
                </Button>
            </div>
        </div>
    );
}

function SettingsHeaderIcon({ className }: { className?: string }) {
    return (
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
            <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.1a2 2 0 0 1-1-1.72v-.51a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
            <circle cx="12" cy="12" r="3" />
        </svg>
    )
}
