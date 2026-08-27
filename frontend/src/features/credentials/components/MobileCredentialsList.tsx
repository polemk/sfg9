import React, { useState, useEffect } from 'react'
import {
    Key,
    Plus,
    Trash2,
    ShieldCheck,
    Search,
    MoreVertical,
    Calendar,
    Lock,
    Cpu,
    Loader2
} from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Badge } from '@/components/ui/Badge'
import { Drawer, DrawerContent, DrawerTitle } from '@/components/ui/drawer'
import { credentialsApi } from '@/lib/api/endpoints'
import type { Credential } from '@/lib/api/types'
import { notify } from '@/lib/notify'
import { cn } from '@/lib/utils'
import { CreateCredentialModal } from '../CreateCredentialModal'

export const MobileCredentialsList: React.FC = () => {
    const [credentials, setCredentials] = useState<Credential[]>([])
    const [isLoading, setIsLoading] = useState(true)
    const [searchTerm, setSearchTerm] = useState('')
    const [formOpen, setFormOpen] = useState(false)
    const [selectedCredential, setSelectedCredential] = useState<Credential | null>(null)
    const [deletingId, setDeletingId] = useState<string | null>(null)
    const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false)

    const fetchCredentials = async () => {
        try {
            setIsLoading(true)
            const res = await credentialsApi.getCredentials()
            const data = (res as any).data || res
            setCredentials(Array.isArray(data) ? data : [])
        } catch (error) {
            notify.error('Erro ao carregar credenciais')
            console.error(error)
        } finally {
            setIsLoading(false)
        }
    }

    useEffect(() => { fetchCredentials() }, [])

    const handleDelete = async () => {
        if (!selectedCredential) return
        try {
            setDeletingId(selectedCredential.id)
            await credentialsApi.deleteCredential(selectedCredential.id)
            notify.success('Credencial removida com sucesso')
            fetchCredentials()
            setConfirmDeleteOpen(false)
            setSelectedCredential(null)
        } catch {
            notify.error('Erro ao remover credencial')
        } finally {
            setDeletingId(null)
        }
    }

    const getProviderLabel = (provider: string) => {
        switch (provider) {
            case 'openai': return 'OpenAI'
            case 'openai_whisper': return 'OpenAI Whisper'
            case 'anthropic': return 'Anthropic'
            case 'google': return 'Google Gemini'
            default: return provider
        }
    }

    const filteredCredentials = credentials.filter(c =>
        c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        c.provider.toLowerCase().includes(searchTerm.toLowerCase())
    )

    return (
        <div className="flex flex-col min-h-full bg-background relative">
            {/* Header Sticky */}
            <div className="sticky top-0 z-sticky bg-background/80 backdrop-blur-md px-4 py-4 space-y-4 border-b border-border/40">
                <div className="flex items-center justify-between">
                    <h1 className="text-2xl font-black text-foreground tracking-tight">Credenciais</h1>
                    <Button
                        variant="primary"
                        size="icon"
                        aria-label="Nova credencial"
                        className="shrink-0"
                        onClick={() => setFormOpen(true)}
                    >
                        <Plus className="w-5 h-5" />
                    </Button>
                </div>

                <div className="relative group">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground group-focus-within:text-primary transition-colors" />
                    <Input
                        placeholder="Buscar credencial..."
                        className="pl-10 h-11 bg-muted/30 border-border/40 focus:bg-muted/50 transition-all rounded-md"
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                    />
                </div>
            </div>

            {/* Listagem */}
            <div className="flex-1 px-4 py-4 space-y-3 pb-32">
                {isLoading ? (
                    Array.from({ length: 4 }).map((_, i) => (
                        <div key={i} className="h-24 w-full bg-muted/20 animate-pulse rounded-lg border border-border/40" />
                    ))
                ) : filteredCredentials.length === 0 ? (
                    <div className="flex flex-col items-center justify-center pt-20 text-center space-y-4">
                        <div className="w-20 h-20 rounded-full bg-muted/30 flex items-center justify-center text-muted-foreground/40">
                            <Lock size={40} />
                        </div>
                        <div>
                            <h3 className="text-lg font-semibold text-foreground">Nenhuma credencial</h3>
                            <p className="text-sm text-muted-foreground max-w-[220px] mx-auto">
                                {searchTerm
                                    ? 'Não encontramos nada para sua busca.'
                                    : 'Adicione chaves de API para habilitar os recursos de IA.'}
                            </p>
                        </div>
                    </div>
                ) : (
                    filteredCredentials.map((credential) => (
                        <div
                            key={credential.id}
                            className="glass-panel p-4 rounded-lg flex items-center justify-between group active:scale-[0.98] transition-all hover:bg-accent border border-border/40"
                            onClick={() => setSelectedCredential(credential)}
                        >
                            <div className="flex items-center gap-4">
                                <div className="h-12 w-12 rounded-lg bg-primary/10 flex items-center justify-center text-primary border border-primary/20 shadow-e1">
                                    <Cpu size={24} />
                                </div>
                                <div className="space-y-1">
                                    <div className="flex items-center gap-2">
                                        <span className="font-bold text-foreground leading-tight">{credential.name}</span>
                                        <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4 border-none font-black uppercase bg-primary/10 text-primary">
                                            {getProviderLabel(credential.provider)}
                                        </Badge>
                                    </div>
                                    <div className="flex items-center gap-1.5 text-[11px] font-numeric text-muted-foreground/70">
                                        <Key size={10} className="shrink-0" />
                                        <span>{credential.api_key_masked}</span>
                                    </div>
                                </div>
                            </div>
                            <div className="text-muted-foreground/30">
                                <MoreVertical size={20} />
                            </div>
                        </div>
                    ))
                )}
            </div>

            {/* Bottom Sheet de Detalhes */}
            <Drawer open={!!selectedCredential && !formOpen} onOpenChange={(open) => !open && setSelectedCredential(null)}>
                <DrawerContent className="rounded-t-lg bg-background border-t border-border p-0 overflow-hidden max-h-[96vh] flex flex-col z-drawer outline-none">
                    <DrawerTitle className="sr-only">Detalhes da Credencial</DrawerTitle>
                    <div className="p-6 pb-4 bg-primary/5 shrink-0">
                        <div className="mx-auto w-12 h-1.5 rounded-full bg-muted mb-6" />
                        <div className="flex items-start justify-between">
                            <div className="flex items-center gap-4">
                                <div className="h-16 w-16 rounded-lg bg-primary/10 flex items-center justify-center text-primary border border-primary/20 shadow-e2">
                                    <Key size={32} />
                                </div>
                                <div className="flex flex-col">
                                    <h2 className="text-xl font-black text-foreground leading-tight">{selectedCredential?.name}</h2>
                                    <Badge className="text-[9px] px-1.5 py-0 h-4 border-none font-black uppercase mt-1 self-start bg-primary text-primary-foreground">
                                        {selectedCredential ? getProviderLabel(selectedCredential.provider) : ''}
                                    </Badge>
                                </div>
                            </div>
                            <Button
                                size="icon"
                                variant="destructive"
                                aria-label="Excluir credencial"
                                className="rounded-full h-10 w-10 shrink-0"
                                onClick={() => setConfirmDeleteOpen(true)}
                            >
                                <Trash2 size={18} />
                            </Button>
                        </div>
                    </div>

                    <div className="flex-1 overflow-y-auto px-6 pb-12 space-y-8">
                        <div className="space-y-4 pt-4">
                            <h4 className="text-[10px] font-black uppercase tracking-[0.2em] text-muted-foreground/60 flex items-center gap-2">
                                <ShieldCheck size={12} />
                                Segurança e Status
                            </h4>
                            <div className="space-y-3">
                                <div className="bg-muted/20 p-4 rounded-lg border border-border flex items-center justify-between">
                                    <div className="space-y-1">
                                        <span className="text-[9px] font-black uppercase text-muted-foreground/60 block">Status da Chave</span>
                                        <span className="text-sm text-success font-bold flex items-center gap-1.5">
                                            <div className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
                                            Encriptada e Ativa
                                        </span>
                                    </div>
                                    <Lock size={16} className="text-muted-foreground/40" />
                                </div>
                                <div className="bg-muted/20 p-4 rounded-lg border border-border flex items-center justify-between">
                                    <div className="space-y-1">
                                        <span className="text-[9px] font-black uppercase text-muted-foreground/60 block">Data de Criação</span>
                                        <span className="text-sm text-foreground font-numeric">
                                            {selectedCredential?.created_at
                                                ? new Date(selectedCredential.created_at).toLocaleDateString('pt-BR', {
                                                    day: '2-digit', month: 'long', year: 'numeric'
                                                })
                                                : '-'}
                                        </span>
                                    </div>
                                    <Calendar size={16} className="text-muted-foreground/40" />
                                </div>
                            </div>
                        </div>

                        <div className="bg-primary/5 border border-primary/10 rounded-lg p-4 flex gap-3 text-xs text-primary font-medium leading-relaxed">
                            <Lock className="w-4 h-4 shrink-0" />
                            <p>
                                Suas chaves de API são encriptadas de forma segura no servidor e nunca trafegam em texto plano.
                            </p>
                        </div>
                    </div>
                </DrawerContent>
            </Drawer>

            {/* Diálogo de Confirmação de Exclusão */}
            {confirmDeleteOpen && (
                <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
                    <div className="absolute inset-0 bg-brand-ink/70 backdrop-blur-sm" onClick={() => setConfirmDeleteOpen(false)} />
                    <div className="relative w-full max-w-sm rounded-lg border border-border bg-background p-6 shadow-e3 animate-in fade-in zoom-in-95 duration-200">
                        <div className="w-12 h-12 rounded-lg bg-destructive/10 flex items-center justify-center text-destructive mb-4">
                            <Trash2 size={24} />
                        </div>
                        <h3 className="text-xl font-black text-foreground mb-2 tracking-tight">Excluir credencial?</h3>
                        <p className="text-sm text-muted-foreground mb-6 leading-relaxed">
                            Agentes de IA vinculados a esta chave pararão de funcionar imediatamente. Esta ação não pode ser desfeita.
                        </p>
                        <div className="flex flex-col gap-2">
                            <Button
                                variant="destructive"
                                onClick={handleDelete}
                                disabled={!!deletingId}
                                className="w-full h-12"
                            >
                                {deletingId ? <Loader2 className="animate-spin h-5 w-5" /> : 'Confirmar Exclusão'}
                            </Button>
                            <Button
                                variant="ghost"
                                onClick={() => setConfirmDeleteOpen(false)}
                                className="w-full h-12"
                            >
                                Cancelar
                            </Button>
                        </div>
                    </div>
                </div>
            )}

            <CreateCredentialModal
                isOpen={formOpen}
                onClose={() => setFormOpen(false)}
                onSuccess={() => { setFormOpen(false); fetchCredentials() }}
            />
        </div>
    )
}
