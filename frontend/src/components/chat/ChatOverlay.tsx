import { X, Send, Paperclip, Smile } from 'lucide-react';
import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/Button';
import { useFinaleStore } from '../../stores/useFinaleStore';

export function ChatOverlay() {
    const isOpen = useFinaleStore((state) => state.isChatOpen);
    const closeChat = useFinaleStore((state) => state.closeChat);
    const [messages, setMessages] = useState([
        { id: 1, type: 'agent', text: 'Posso mandar o link?', time: '10:00', author: 'Martha da PK 🇧🇷' },
        { id: 2, type: 'user', text: 'PODE', time: '10:01' },
        { id: 3, type: 'agent', text: 'Link enviado. Qualquer dúvida é só chamar.', time: '10:01', author: 'Martha da PK 🇧🇷' },
        { id: 4, type: 'user', text: 'OBRIGADO POR COMPARECEREM NA AULA DE HOJE, AMANHÃ FAREMOS O LINK, FUI PRA PRAIA', time: '10:02' },
        { id: 5, type: 'agent', text: 'Certo. Te envio o link do Suporte Safegold amanhã.', time: '10:02', author: 'Martha da PK 🇧🇷' }
    ]);
    const [inputValue, setInputValue] = useState('');

    useEffect(() => {
        if (isOpen) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = '';
        }
    }, [isOpen]);

    if (!isOpen) return null;

    return (
        <div className="fixed inset-0 z-modal-backdrop flex items-center justify-center bg-brand-ink/80 backdrop-blur-sm animate-in fade-in duration-200">
            {/* O painel do chat é superfície escura fixa nos dois modos: `surface-dark`
                troca os tokens dentro do bloco, então tudo aqui usa token semântico. */}
            <div className="surface-dark w-full max-w-md bg-background border border-border rounded-lg shadow-e3 overflow-hidden flex flex-col h-[80vh] max-h-[700px]">

                {/* Header */}
                <div className="bg-card p-4 flex items-center justify-between border-b border-border">
                    <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-primary p-0.5">
                            <img src="https://github.com/shadcn.png" alt="Martha" className="w-full h-full rounded-full grayscale" />
                        </div>
                        <div>
                            <div className="flex items-center gap-2">
                                <h3 className="font-title font-bold text-foreground text-sm">Martha da PK 🇧🇷</h3>
                                <span className="w-2 h-2 rounded-full bg-success animate-pulse" />
                            </div>
                            <p className="text-xs text-muted-foreground">Especialista em Atendimentos</p>
                        </div>
                    </div>
                    <div className="flex items-center gap-2">
                        <Button variant="ghost" size="icon" onClick={closeChat} aria-label="Fechar conversa">
                            <X size={20} />
                        </Button>
                    </div>
                </div>

                {/* Messages Area */}
                <div className="flex-1 overflow-y-auto p-4 space-y-4 bg-background">
                    <div className="text-center text-xs text-muted-foreground my-4">Hoje</div>

                    {messages.map((msg) => (
                        <div key={msg.id} className={`flex ${msg.type === 'user' ? 'justify-end' : 'justify-start'}`}>
                            {msg.type === 'agent' && (
                                <div className="w-8 h-8 rounded-full bg-muted mr-2 flex-shrink-0 overflow-hidden">
                                    <img src="https://github.com/shadcn.png" alt="Martha" className="w-full h-full grayscale opacity-80" />
                                </div>
                            )}
                            <div
                                className={`max-w-[80%] p-3 rounded-lg text-sm ${msg.type === 'user'
                                        ? 'bg-primary text-primary-foreground rounded-tr-sm'
                                        : 'bg-card text-card-foreground rounded-tl-sm'
                                    }`}
                            >
                                {msg.text}
                            </div>
                        </div>
                    ))}
                </div>

                {/* Input Area */}
                <div className="p-4 bg-card border-t border-border">
                    <div className="flex items-center justify-between text-xs text-muted-foreground mb-2 px-1">
                        <span>Suporte Safegold</span>
                    </div>
                    <div className="relative flex items-center gap-2 bg-background rounded-full p-2 border border-input focus-within:border-ring transition-colors">
                        <Button variant="ghost" size="icon" className="h-9 w-9" aria-label="Anexar arquivo">
                            <Paperclip size={18} />
                        </Button>
                        <input
                            type="text"
                            className="flex-1 bg-transparent border-none outline-none text-foreground text-sm placeholder:text-muted-foreground"
                            placeholder="Digite sua mensagem..."
                            value={inputValue}
                            onChange={(e) => setInputValue(e.target.value)}
                            onKeyDown={(e) => {
                                if (e.key === 'Enter' && inputValue.trim()) {
                                    setMessages([...messages, {
                                        id: Date.now(),
                                        type: 'user',
                                        text: inputValue,
                                        time: 'Now'
                                    }]);
                                    setInputValue('');
                                }
                            }}
                        />
                        <Button variant="ghost" size="icon" className="h-9 w-9" aria-label="Inserir emoji">
                            <Smile size={18} />
                        </Button>
                        <Button
                            variant="primary"
                            size="icon"
                            className="h-9 w-9 rounded-full"
                            aria-label="Enviar mensagem"
                            onClick={() => {
                                if (inputValue.trim()) {
                                    setMessages([...messages, {
                                        id: Date.now(),
                                        type: 'user',
                                        text: inputValue,
                                        time: 'Now'
                                    }]);
                                    setInputValue('');
                                }
                            }}
                        >
                            <Send size={16} />
                        </Button>
                    </div>
                </div>

            </div>
        </div>
    );
}
