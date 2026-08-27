import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/utils'

/**
 * **Paginação no telefone** — DEC-100.
 *
 * Anterior/Próxima com o contador no meio, e não a régua de números do desktop: no 390 de
 * largura a régua vira dez alvos de 20 px grudados, e o polegar erra.
 *
 * O `pb-8` fixo saiu: quem reserva o espaço do rodapé é o `MobilePageLayout`, que soma a
 * altura da barra de abas com `env(safe-area-inset-bottom)`. Somar folga nos dois lugares
 * deixava um vão morto no fim de toda lista.
 */
interface MobilePaginationProps {
    page: number
    total: number
    perPage: number
    onPageChange: (newPage: number) => void
    loading?: boolean
    className?: string
}

export function MobilePagination({
    page,
    total,
    perPage,
    onPageChange,
    loading,
    className,
}: MobilePaginationProps) {
    const totalPages = Math.ceil(total / perPage)

    if (totalPages <= 1) return null

    return (
        <nav
            aria-label="Paginação"
            className={cn('flex items-center justify-between gap-2 px-1 mt-4', className)}
        >
            {/* `aria-live`: quem usa leitor de tela precisa ouvir que a página mudou —
                o conteúdo troca sem navegação, então nada mais anuncia. */}
            <p
                aria-live="polite"
                className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground font-numeric"
            >
                Página {page} de {totalPages}
            </p>
            <div className="flex items-center gap-2">
                <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onPageChange(Math.max(1, page - 1))}
                    disabled={page <= 1 || loading}
                    aria-label="Página anterior"
                    className="min-h-[2.75rem] px-4 text-[10px] font-bold uppercase tracking-widest"
                >
                    <ChevronLeft aria-hidden="true" className="w-4 h-4 mr-1" /> Anterior
                </Button>
                <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onPageChange(Math.min(totalPages, page + 1))}
                    disabled={page >= totalPages || loading}
                    aria-label="Próxima página"
                    className="min-h-[2.75rem] px-4 text-[10px] font-bold uppercase tracking-widest"
                >
                    Próxima <ChevronRight aria-hidden="true" className="w-4 h-4 ml-1" />
                </Button>
            </div>
        </nav>
    )
}
