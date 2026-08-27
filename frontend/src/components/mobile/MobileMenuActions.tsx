import React from 'react'
import { MoreHorizontal, Eye, Pencil, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/utils'

/**
 * @deprecated **Não use em tela nova. Use `MobileRowActions`.** — DEC-100.
 *
 * Duas coisas o condenam para as fatias S5..S11:
 *
 * 1. **A lista de ações é FIXA** — ver, editar, excluir. Borderô tem "liquidar" e
 *    "reenviar remessa"; renegociação tem "aprovar"; operação estruturada tem "encerrar".
 *    Nenhuma cabe aqui, então cada tela acabaria escrevendo o próprio menu — que é
 *    exatamente o que a biblioteca compartilhada existe para impedir.
 * 2. **O painel é `absolute` dentro da linha.** Preso ao contexto de empilhamento do
 *    ancestral (§5.4.4) e colado na borda direita, com alvo espremido. O
 *    `MobileRowActions` renderiza em portal, como folha de rodapé, na zona do polegar.
 *
 * **Não há mais o caso de uso que o mantinha.** A justificativa antiga era "o padrão de
 * menu ancorado ainda serve a caso de desktop estreito" — e desde 26/08/2026 o menu
 * ancorado é o `MobileRowActions`/`MobileActionsSheet` acima de 768 px, montado sobre o
 * `FloatingPanel` (portal no `body`, virada quando não cabe, fechar por clique fora). Este
 * arquivo fica só porque é da base do ai9 e não tem consumidor; **nada novo deve usá-lo**,
 * e ele não é o menu de desktop deste app.
 */

interface MobileMenuActionsProps {
    isOpen: boolean
    onOpenChange: (open: boolean) => void
    onView: () => void
    onEdit: () => void
    onDelete: () => void
    className?: string
}

export function MobileMenuActions({
    isOpen,
    onOpenChange,
    onView,
    onEdit,
    onDelete,
    className,
}: MobileMenuActionsProps) {
    return (
        <div className={cn('relative', className)}>
            <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 active:scale-90 transition-all"
                onClick={(e: React.MouseEvent) => {
                    e.stopPropagation()
                    onOpenChange(!isOpen)
                }}
            >
                <MoreHorizontal className="h-4 w-4" />
            </Button>

            {isOpen && (
                <>
                    <div
                        className="fixed inset-0 z-drawer-backdrop"
                        onClick={(e: React.MouseEvent) => {
                            e.stopPropagation()
                            onOpenChange(false)
                        }}
                    />
                    <div className="absolute right-0 mt-2 w-44 rounded-md border border-border bg-popover text-popover-foreground shadow-e3 z-drawer py-2 overflow-hidden animate-in fade-in zoom-in-95 duration-200">
                        <button
                            type="button"
                            className="w-full text-left px-4 py-3 text-[10px] font-black uppercase tracking-widest hover:bg-accent hover:text-accent-foreground flex items-center gap-3 text-muted-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            onClick={(e: React.MouseEvent) => {
                                e.stopPropagation()
                                onOpenChange(false)
                                onView()
                            }}
                        >
                            <Eye className="h-4 w-4 text-primary" /> Visualizar
                        </button>

                        <button
                            type="button"
                            className="w-full text-left px-4 py-3 text-[10px] font-black uppercase tracking-widest hover:bg-accent hover:text-accent-foreground flex items-center gap-3 text-muted-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            onClick={(e: React.MouseEvent) => {
                                e.stopPropagation()
                                onOpenChange(false)
                                onEdit()
                            }}
                        >
                            <Pencil className="h-4 w-4 text-primary" /> Editar
                        </button>

                        <div className="h-px w-full bg-border my-1.5" />

                        <button
                            type="button"
                            className="w-full text-left px-4 py-3 text-[10px] font-black uppercase tracking-widest hover:bg-destructive/10 flex items-center gap-3 text-destructive transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            onClick={(e: React.MouseEvent) => {
                                e.stopPropagation()
                                onOpenChange(false)
                                onDelete()
                            }}
                        >
                            <Trash2 className="h-4 w-4" /> Excluir
                        </button>
                    </div>
                </>
            )}
        </div>
    )
}
