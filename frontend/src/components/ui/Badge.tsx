import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { X } from "lucide-react"

import { cn } from "@/lib/utils"

/**
 * Badge — rótulo curto de estado ou de item selecionado.
 *
 * `onRemove` acrescenta o "x" e transforma o badge em **item removível**
 * (FE-425): é a peça usada para mostrar o que já foi escolhido numa seleção
 * múltipla (`Autocomplete multiple`), num filtro aplicado ou numa lista de
 * destinatários.
 *
 * Detalhe que justifica ser da biblioteca em vez de um `<span>` com um `<X>` ao
 * lado: o "x" é um `<button>` **irmão** do conteúdo, com `aria-label` próprio
 * e alvo de clique de 16px. Quando a tela improvisa, o "x" vira um ícone dentro
 * do próprio badge clicável — e aí clicar em qualquer lugar do rótulo remove,
 * que é o jeito mais fácil de o usuário apagar um filtro sem querer.
 */
const badgeVariants = cva(
    "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2",
    {
        variants: {
            variant: {
                default:
                    "border-transparent bg-primary text-primary-foreground hover:bg-primary/80",
                secondary:
                    "border-transparent bg-secondary text-secondary-foreground hover:bg-secondary/80",
                destructive:
                    "border-transparent bg-destructive text-destructive-foreground hover:bg-destructive/80",
                outline: "text-foreground",
                // Estado — os mesmos tokens semânticos dos indicadores do
                // legado (positivo #217B55, negativo #7D1F1E). Não são cor
                // literal: mudam sozinhos entre claro e escuro.
                success: "border-transparent bg-success text-success-foreground",
                warning: "border-transparent bg-warning text-warning-foreground",
                info: "border-transparent bg-info text-info-foreground",
                negative: "border-transparent bg-negative text-negative-foreground",
            },
        },
        defaultVariants: {
            variant: "default",
        },
    }
)

export interface BadgeProps
    extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {
    /** Presente = badge removível: acrescenta o botão "x" ao final. */
    onRemove?: () => void
    /** Rótulo acessível do "x". Diga *o quê* está sendo removido. */
    removeLabel?: string
    /**
     * Elemento raiz. Default `div`; use `span` quando o selo vive **dentro de
     * conteúdo de frase** — um `<p>`, um `<button>`, um `<a>`, um `<label>`.
     *
     * Por que isto existe: `<div>` dentro de `<p>` é HTML inválido, e o
     * navegador **reescreve a árvore** — ele fecha o `<p>` sozinho antes do
     * `<div>`. O que se escreveu deixa de ser o que fica no DOM, e o sintoma
     * aparece longe da causa (espaçamento estranho, estilo que não aplica).
     * Foi um aviso real do React na S12, no `ContractCard`.
     *
     * O visual é idêntico: `badgeVariants` já é `inline-flex`, então trocar a
     * tag não muda um pixel. Nenhum consumidor existente precisa mudar — o
     * default continua `div`.
     */
    as?: 'div' | 'span'
}

function Badge({ className, variant, onRemove, removeLabel = 'Remover', as: Raiz = 'div', children, ...props }: BadgeProps) {
    return (
        <Raiz className={cn(badgeVariants({ variant }), onRemove && 'pr-1', className)} {...props}>
            <span className="truncate">{children}</span>
            {onRemove && (
                <button
                    type="button"
                    aria-label={removeLabel}
                    onClick={(e) => {
                        e.stopPropagation()
                        onRemove()
                    }}
                    className="-mr-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-foreground/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                    <X aria-hidden="true" className="h-3 w-3" />
                </button>
            )}
        </Raiz>
    )
}

export { Badge, badgeVariants }
