import React, { useState } from 'react'
import { X, Eye, EyeOff, Key, Bot, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { credentialsApi } from '@/lib/api/endpoints'
import { notify } from '@/lib/notify'

interface CreateCredentialModalProps {
    isOpen: boolean
    onClose: () => void
    onSuccess: () => void
}

export function CreateCredentialModal({ isOpen, onClose, onSuccess }: CreateCredentialModalProps) {
    const [name, setName] = useState('')
    const [provider, setProvider] = useState<'openai' | 'anthropic' | 'google' | 'openai_whisper' | ''>('')
    const [apiKey, setApiKey] = useState('')
    const [showKey, setShowKey] = useState(false)
    const [isLoading, setIsLoading] = useState(false)

    if (!isOpen) return null

    const handleSave = async () => {
        if (!name || !provider || !apiKey) {
            notify.error('Preencha todos os campos.')
            return
        }

        try {
            setIsLoading(true)
            await credentialsApi.createCredential({
                name,
                provider,
                api_key: apiKey
            })
            notify.success('Credencial criada com sucesso!')
            onSuccess()
            handleClose()
        } catch (error: any) {
            notify.error(error?.response?.data?.message || 'Erro ao criar credencial')
        } finally {
            setIsLoading(false)
        }
    }

    const handleSubmit = (e: React.FormEvent) => { e.preventDefault(); handleSave() }

    const handleClose = () => {
        setName('')
        setProvider('')
        setApiKey('')
        setShowKey(false)
        onClose()
    }

    return (
        <div className="fixed inset-0 z-modal flex items-center justify-center bg-brand-ink/70 backdrop-blur-sm">
            <div className="w-full max-w-md bg-popover border border-border rounded-lg shadow-e3 overflow-hidden animate-in fade-in zoom-in-95 duration-200 flex flex-col relative max-h-[90vh]">
                <div className="flex items-center justify-between p-6 border-b border-border shrink-0">
                    <div className="flex items-center gap-2">
                        <Key className="w-5 h-5 text-primary" />
                        <h2 className="text-xl font-semibold text-foreground">Nova Credencial</h2>
                    </div>
                    <Button
                        variant="ghost"
                        size="icon"
                        aria-label="Fechar"
                        onClick={handleClose}
                        className="h-9 w-9 rounded-full"
                    >
                        <X className="w-4 h-4" />
                    </Button>
                </div>

                <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 pb-20 space-y-5">
                    <div className="space-y-2">
                        <Label htmlFor="provider">Provedor IA</Label>
                        <div className="relative">
                            <div className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none">
                                <Bot className="w-4 h-4" />
                            </div>
                            <select
                                id="provider"
                                value={provider}
                                onChange={(e) => setProvider(e.target.value as any)}
                                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 pl-9 appearance-none"
                                required
                            >
                                <option value="" disabled>Selecione um provedor...</option>
                                <option value="openai">OpenAI</option>
                                <option value="anthropic">Anthropic</option>
                                <option value="google">Google Gemini</option>
                                <option value="openai_whisper">OpenAI Whisper</option>
                            </select>
                        </div>
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="name">Nome da Chave</Label>
                        <Input
                            id="name"
                            placeholder="Ex: Minha API Produção"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            required
                        />
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="api_key">
                            Chave de API (Secret Key)
                        </Label>
                            <div className="relative">
                                <Input
                                    id="api_key"
                                    type={showKey ? 'text' : 'password'}
                                    placeholder="Ex: sk-proj-..."
                                    value={apiKey}
                                    onChange={(e) => setApiKey(e.target.value)}
                                    className="pr-10"
                                    required
                                />
                                <Button
                                    variant="ghost"
                                    size="icon"
                                    aria-label={showKey ? 'Ocultar chave' : 'Mostrar chave'}
                                    onClick={() => setShowKey(!showKey)}
                                    className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8 rounded-md"
                                >
                                    {showKey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                                </Button>
                            </div>
                        <p className="text-xs text-muted-foreground">
                            A chave será encriptada no banco de dados e nunca será exibida novamente.
                        </p>
                    </div>

                </form>
                <Button
                    type="button"
                    onClick={handleSave}
                    disabled={isLoading}
                    variant="primary"
                    className="helper-fab absolute right-6 bottom-6 h-12 w-12 p-0 rounded-full shadow-e2"
                    aria-label="Salvar credencial"
                >
                    {isLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Key className="w-5 h-5" />}
                </Button>
            </div>
        </div>
    )
}
