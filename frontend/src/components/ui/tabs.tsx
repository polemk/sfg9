import * as React from "react"
import { cn } from "@/lib/utils"

/**
 * Tabs — abas com **overflow horizontal** e conteúdo por aba (FE-423, FE-424).
 *
 * Dois defeitos do legado que este componente fecha:
 *
 * 1. **Conteúdo escondido por `visibility:hidden; opacity:0; height:0`.** As
 *    abas inativas continuavam no DOM, com os campos ainda focáveis por Tab e
 *    ainda enviados no `submit` — o usuário tabulava para dentro de um bloco
 *    invisível e o formulário mandava dado de aba que ele nunca abriu. Aqui a
 *    aba inativa **não é renderizada** (`return null`).
 * 2. **Barra de abas que estoura a largura.** Numa tela de detalhe com sete
 *    abas, as últimas simplesmente sumiam fora do contêiner. A `TabsList` agora
 *    rola na horizontal, e o próprio scroll fica escondido — a rolagem se faz
 *    por arrastar, por roda ou pelas setas do teclado, que trazem a aba ativa
 *    para dentro da vista.
 *
 * ARIA de verdade: `role="tablist"`/`tab`/`tabpanel`, `aria-selected` e
 * roving `tabIndex`. Setas ←/→ trocam de aba, Home/End vão às pontas.
 */
const TabsContext = React.createContext<{
    value: string
    onValueChange: (value: string) => void
    baseId: string
} | null>(null)

const Tabs = React.forwardRef<
    HTMLDivElement,
    React.HTMLAttributes<HTMLDivElement> & {
        defaultValue?: string
        value?: string
        onValueChange?: (value: string) => void
    }
>(({ className, defaultValue, value, onValueChange, children, ...props }, ref) => {
    const [activeTab, setActiveTab] = React.useState(value || defaultValue || "")
    const baseId = React.useId()

    // Controlado x não controlado
    const curValue = value !== undefined ? value : activeTab
    const handleValueChange = React.useCallback((newValue: string) => {
        if (value === undefined) setActiveTab(newValue)
        onValueChange?.(newValue)
    }, [value, onValueChange])

    const ctx = React.useMemo(
        () => ({ value: curValue, onValueChange: handleValueChange, baseId }),
        [curValue, handleValueChange, baseId],
    )

    return (
        <TabsContext.Provider value={ctx}>
            <div ref={ref} className={cn("min-w-0", className)} {...props}>
                {children}
            </div>
        </TabsContext.Provider>
    )
})
Tabs.displayName = "Tabs"

const TabsList = React.forwardRef<
    HTMLDivElement,
    React.HTMLAttributes<HTMLDivElement>
>(({ className, children, ...props }, ref) => {
    const listRef = React.useRef<HTMLDivElement>(null)
    React.useImperativeHandle(ref, () => listRef.current as HTMLDivElement)

    // Setas navegam entre as abas e a aba que recebe foco entra na vista —
    // sem isso, uma aba fora do overflow é focável mas invisível.
    const onKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
        const teclas = ['ArrowRight', 'ArrowLeft', 'Home', 'End']
        if (!teclas.includes(e.key)) return
        const abas = Array.from(
            listRef.current?.querySelectorAll<HTMLButtonElement>('[role="tab"]:not(:disabled)') ?? [],
        )
        if (abas.length === 0) return
        const atual = abas.findIndex((b) => b === document.activeElement)
        e.preventDefault()
        const proximo =
            e.key === 'Home' ? 0
            : e.key === 'End' ? abas.length - 1
            : e.key === 'ArrowRight' ? (atual + 1 + abas.length) % abas.length
            : (atual - 1 + abas.length) % abas.length
        const alvo = abas[proximo]
        alvo?.focus()
        alvo?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
        alvo?.click()
    }

    return (
        <div
            ref={listRef}
            role="tablist"
            onKeyDown={onKeyDown}
            className={cn(
                "flex h-11 max-w-full items-center gap-1 rounded-md border border-border bg-muted p-1.5 text-muted-foreground shadow-e1",
                // Rola na horizontal em vez de estourar a largura. A barra some
                // (é ruído numa faixa de 44px), mas a rolagem continua existindo
                // por arrastar, roda e teclado.
                "overflow-x-auto overflow-y-hidden scroll-smooth [scrollbar-width:none] [&::-webkit-scrollbar]:hidden",
                className
            )}
            {...props}
        >
            {children}
        </div>
    )
})
TabsList.displayName = "TabsList"

const TabsTrigger = React.forwardRef<
    HTMLButtonElement,
    React.ButtonHTMLAttributes<HTMLButtonElement> & { value: string }
>(({ className, value, ...props }, ref) => {
    const context = React.useContext(TabsContext)
    const isActive = context?.value === value
    const btnRef = React.useRef<HTMLButtonElement>(null)
    React.useImperativeHandle(ref, () => btnRef.current as HTMLButtonElement)

    // A aba ativa se traz para dentro da vista. Sem isto, numa barra que rolou,
    // a aba selecionada por código (voltar de uma rota, restaurar filtro) fica
    // fora da tela e o usuário não vê qual está aberta.
    React.useEffect(() => {
        if (isActive) btnRef.current?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
    }, [isActive])

    return (
        <button
            type="button"
            role="tab"
            ref={btnRef}
            id={`${context?.baseId}-tab-${value}`}
            aria-selected={isActive}
            aria-controls={`${context?.baseId}-panel-${value}`}
            // Roving tabIndex: só a aba ativa entra na ordem de Tab; as outras
            // se alcançam pelas setas, como manda o padrão de tablist.
            tabIndex={isActive ? 0 : -1}
            className={cn(
                // 44 px de alvo no telefone (critério 1 da §5.4.8): `py-2` dava 36,
                // e a barra de abas do detalhe (portador, projeto, renegociação) é
                // a navegação interna daquelas telas — errar a aba é trocar de
                // conteúdo sem querer. No desktop volta à densidade do ponteiro.
                "inline-flex min-h-[2.75rem] shrink-0 items-center justify-center whitespace-nowrap rounded-sm px-4 py-2 text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 md:min-h-0",
                isActive
                    ? "bg-card text-foreground shadow-e1"
                    : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                className
            )}
            onClick={() => context?.onValueChange(value)}
            {...props}
        />
    )
})
TabsTrigger.displayName = "TabsTrigger"

const TabsContent = React.forwardRef<
    HTMLDivElement,
    React.HTMLAttributes<HTMLDivElement> & { value: string }
>(({ className, value, children, ...props }, ref) => {
    const context = React.useContext(TabsContext)
    // Aba inativa sai do DOM. Ver o comentário do topo: escondê-la por CSS
    // deixa campo focável e enviado no submit.
    if (context?.value !== value) return null

    return (
        <div
            ref={ref}
            role="tabpanel"
            id={`${context?.baseId}-panel-${value}`}
            aria-labelledby={`${context?.baseId}-tab-${value}`}
            tabIndex={0}
            className={cn(
                "mt-3 ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
                className
            )}
            {...props}
        >
            {children}
        </div>
    )
})
TabsContent.displayName = "TabsContent"

export { Tabs, TabsList, TabsTrigger, TabsContent }
