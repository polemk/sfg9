import { useEffect, useState } from 'react'
import { Key, Plus, Trash2, ShieldCheck, AlertCircle } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/Table'
import { credentialsApi } from '@/lib/api/endpoints'
import type { Credential } from '@/lib/api/types'
import { notify } from '@/lib/notify'
import { CreateCredentialModal } from '@/features/credentials/CreateCredentialModal'
import { PageHeader } from '@/components/PageHeader'
import { useMobile } from '@/hooks/useMobile'
import { MobileCredentialsList } from '@/features/credentials/components/MobileCredentialsList'

export function CredentialsPage() {
    const isMobile = useMobile()
    const [credentials, setCredentials] = useState<Credential[]>([])
    const [isLoading, setIsLoading] = useState(true)
    const [isModalOpen, setIsModalOpen] = useState(false)
    const [deletingId, setDeletingId] = useState<string | null>(null)

    const fetchCredentials = async () => {
        try {
            setIsLoading(true)
            const res = await credentialsApi.getCredentials()
            // Axios response `.data` is handled by our API client mostly,
            // but let's safely array check it if needed.
            const data = (res as any).data || res
            setCredentials(Array.isArray(data) ? data : [])
        } catch (error) {
            notify.error('Erro ao carregar credenciais')
            console.error(error)
        } finally {
            setIsLoading(false)
        }
    }

    useEffect(() => {
        fetchCredentials()
    }, [])

    if (isMobile) return <MobileCredentialsList />

    const handleDelete = async (id: string, name: string) => {
        if (!window.confirm(`Tem certeza que deseja excluir a credencial "${name}"? Agentes usando esta chave pararão de funcionar.`)) {
            return
        }

        try {
            setDeletingId(id)
            await credentialsApi.deleteCredential(id)
            notify.success('Credencial removida com sucesso')
            fetchCredentials()
        } catch (error) {
            notify.error('Erro ao remover credencial')
        } finally {
            setDeletingId(null)
        }
    }

    const getProviderLabel = (provider: string) => {
        switch (provider) {
            case 'openai': return 'OpenAI'
            case 'anthropic': return 'Anthropic'
            case 'google': return 'Google Gemini'
            case 'openai_whisper': return 'OpenAI Whisper'
            default: return provider
        }
    }

    return (
        <div className="space-y-6">
            <PageHeader
                title="Credenciais de IA"
                subtitle="Gerencie de forma segura as chaves de API para os provedores de inteligência artificial."
                rightSlot={
                    <Button onClick={() => setIsModalOpen(true)} className="gap-2" variant="primary">
                        <Plus className="w-4 h-4" />
                        Nova Credencial
                    </Button>
                }
            />

            <Card className="p-6">
                {isLoading ? (
                    <div className="space-y-4">
                        {[1, 2, 3].map(i => (
                            <div key={i} className="h-16 bg-muted/50 rounded-lg animate-pulse" />
                        ))}
                    </div>
                ) : credentials.length === 0 ? (
                    <div className="text-center py-12">
                        <div className="mx-auto w-16 h-16 rounded-full bg-muted/50 flex items-center justify-center mb-4">
                            <ShieldCheck className="w-8 h-8 text-muted-foreground" />
                        </div>
                        <h3 className="text-lg font-medium text-foreground mb-2">Nenhuma credencial cadastrada</h3>
                        <p className="text-muted-foreground max-w-sm mx-auto mb-6">
                            Adicione chaves de API da OpenAI, Anthropic ou Google para habilitar os Agentes de IA.
                        </p>
                        <Button onClick={() => setIsModalOpen(true)} variant="secondary">
                            Adicionar primeira credencial
                        </Button>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <Table>
                            <TableHeader>
                                <TableRow className="border-b border-border">
                                    <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Nome</TableHead>
                                    <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Provedor</TableHead>
                                    <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Chave (Mascarada)</TableHead>
                                    <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Data de Criação</TableHead>
                                    <TableHead className="text-xs font-bold uppercase tracking-wider text-muted-foreground text-right">Ações</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {credentials.map(credential => (
                                    <TableRow key={credential.id} className="border-t border-border hover:bg-accent/60 transition-colors">
                                        <TableCell className="font-medium">{credential.name}</TableCell>
                                        <TableCell>
                                            <div className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold bg-primary/10 text-primary">
                                                {getProviderLabel(credential.provider)}
                                            </div>
                                        </TableCell>
                                        <TableCell className="font-numeric text-sm text-muted-foreground">
                                            {credential.api_key_masked}
                                        </TableCell>
                                        <TableCell className="text-muted-foreground text-sm font-numeric">
                                            {new Date(credential.created_at).toLocaleDateString('pt-BR', {
                                                day: '2-digit', month: 'short', year: 'numeric'
                                            })}
                                        </TableCell>
                                        <TableCell className="text-right">
                                            <Button
                                                variant="destructive"
                                                size="sm"
                                                aria-label="Remover credencial"
                                                onClick={() => handleDelete(credential.id, credential.name)}
                                                disabled={deletingId === credential.id}
                                            >
                                                {deletingId === credential.id ? (
                                                    <div className="w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" />
                                                ) : (
                                                    <Trash2 className="w-4 h-4" />
                                                )}
                                            </Button>
                                        </TableCell>
                                    </TableRow>
                                ))}
                            </TableBody>
                        </Table>
                    </div>
                )}
            </Card>

            <div className="bg-info/10 border border-info/30 rounded-lg p-4 flex gap-3 text-sm text-info">
                <AlertCircle className="w-5 h-5 shrink-0" />
                <p>
                    Suas chaves de API são encriptadas de forma segura no banco de dados ({`Active Record Encryption`}) e nunca são retornadas em texto plano para o frontend. Não as compartilhe.
                </p>
            </div>

            <CreateCredentialModal
                isOpen={isModalOpen}
                onClose={() => setIsModalOpen(false)}
                onSuccess={fetchCredentials}
            />
        </div>
    )
}
