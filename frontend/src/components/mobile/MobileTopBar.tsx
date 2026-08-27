import { useState, useRef, useEffect } from 'react'
import { createPortal } from 'react-dom'
import { ChevronDown, Check, LayoutGrid, Briefcase, Film, Settings } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAuthStore, useRole } from '@/store/authStore'
import { MODE_ENTRIES, modeEntryFor } from '@/lib/sidebarModes'
import { useSidebarMode, type SidebarMode } from '@/store/sidebarModeStore'
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/Sheet'
import { Button } from '@/components/ui/Button'
import { Logo } from '@/components/brand/Logo'
import { MobileContextSheet } from './MobileContextSheet'

// Cada modo ganha um token diferente só para o olho separar um do outro —
// nenhum deles é cor literal, e todos viram sozinhos entre claro e escuro.
// **A lista de modos vem de `@/lib/sidebarModes`, não daqui.**
//
// Até 26/08 este arquivo tinha a PRÓPRIA lista, escrita à mão, com os modos
// antigos do ai9: `negocio`, `conteudo`, `plataforma`. Quando os modos do
// Safegold entraram — `results_group`, `project_group`, `management`,
// `admin_settings`, `platform` — o seletor do desktop acompanhou sozinho,
// porque deriva dos grupos de navegação. O do telefone ficou para trás.
//
// O usuário viu os dois sintomas ao mesmo tempo: **o menu mostrava quatro
// opções erradas** e **escolher qualquer uma não fazia nada**, porque o id
// gravado não existe mais em `VALID_MODES` e o store o descartava.
//
// É o defeito que o comentário do `SidebarModeToggle` já nomeava: duas listas
// para a mesma coisa é como um grupo novo aparece no menu e some do seletor.

export function MobileTopBar() {
    const { mode, setMode } = useSidebarMode()
    const { user } = useAuthStore()
    const { isOg } = useRole()
    const impersonating = useAuthStore(s => s.impersonating)
    const [isModeOpen, setIsModeOpen] = useState(false)
    const [isProfileOpen, setIsProfileOpen] = useState(false)
    const modeRef = useRef<HTMLDivElement>(null)
    const modePanelRef = useRef<HTMLDivElement>(null)

    const currentMode = modeEntryFor(mode)
    const ModeIcon = currentMode.icon

    // `pointerdown` e não `mousedown`: no telefone o `mousedown` sintético só chega
    // DEPOIS do `touchend`, então fechar por toque fora ficava com um atraso visível.
    // O painel é irmão do gatilho no portal, então o teste de "clicou fora" precisa
    // considerar os dois nós — senão tocar no próprio painel o fecha.
    useEffect(() => {
        if (!isModeOpen) return
        function aoApontarFora(e: PointerEvent) {
            const alvo = e.target as Node
            if (modeRef.current?.contains(alvo)) return
            if (modePanelRef.current?.contains(alvo)) return
            setIsModeOpen(false)
        }
        function aoTeclar(e: KeyboardEvent) {
            if (e.key === 'Escape') setIsModeOpen(false)
        }
        document.addEventListener('pointerdown', aoApontarFora)
        document.addEventListener('keydown', aoTeclar)
        return () => {
            document.removeEventListener('pointerdown', aoApontarFora)
            document.removeEventListener('keydown', aoTeclar)
        }
    }, [isModeOpen])

    const getInitials = (name?: string | null, email?: string | null) => {
        if (name) return name.substring(0, 2).toUpperCase()
        if (email) return email.substring(0, 2).toUpperCase()
        return 'U'
    }

    // **Opaca, não `glass-panel`.** O conteúdo rola POR BAIXO desta barra, e o
    // `glass-panel` é 88% de opacidade com desfoque: o texto que passa embaixo
    // aparece através dela. O usuário reportou como "o conteúdo fica por cima da
    // topbar" — não fica, ele é visto ATRAVÉS. A `MobileBottomBar` já era
    // `bg-background` opaca; a assimetria entre as duas barras era o defeito.
    // Vidro serve a painel que flutua sobre conteúdo parado, não a barra de
    // navegação sob a qual a página inteira desliza.
    //
    // `pt-[env(safe-area-inset-top)]` sobre altura mínima: instalado como PWA
    // (`display: standalone`, NEW-003) não há barra do navegador, e sem isto o conteúdo
    // do cabeçalho fica DEBAIXO do relógio/entalhe do aparelho. Só aparece no telefone
    // real — o DevTools não simula a inset.
    return (
        <header className="fixed top-0 left-0 right-0 flex min-h-[4rem] items-center justify-between z-appbar border-b border-border bg-background shadow-e2 px-4 pt-[env(safe-area-inset-top)] md:hidden">
            {/* Esquerda: seletor de modo (OG) ou logo (outros) */}
            {isOg ? (
                <div className="relative" ref={modeRef}>
                    <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setIsModeOpen(!isModeOpen)}
                        // 44 px de altura: o `size="sm"` do Button dá 36, que e alvo de
                        // mouse. Criterio 1 da §5.4.8 — e este gatilho e a unica porta do
                        // seletor de modo no telefone.
                        className="min-h-[2.75rem] rounded-full px-3"
                        aria-haspopup="menu"
                        aria-expanded={isModeOpen}
                        aria-label={`Modo do menu: ${currentMode.label}`}
                    >
                        {/* Ouro Safegold e peso do texto distinguem o selecionado —
                            nao cinco matizes decorativas. Mesma decisao do
                            `SidebarModeToggle`, que ja tinha abandonado o COLOR_MAP. */}
                        <span className="p-1 rounded-sm border border-primary/20 bg-primary/10 text-primary">
                            <ModeIcon aria-hidden="true" className="w-4 h-4" />
                        </span>
                        <span className="text-sm font-bold">{currentMode.label}</span>
                        <ChevronDown aria-hidden="true" className={cn('w-4 h-4 text-muted-foreground transition-transform', isModeOpen && 'rotate-180')} />
                    </Button>

                    {/* Painel em PORTAL, no `body` — §5.4.4 das convenções. O cabeçalho é
                        `fixed` com z próprio, e isso já cria contexto de empilhamento: todo
                        descendente fica PRESO no z do header, por mais alto que seja o z do
                        painel. (O motivo original era o `backdrop-filter` do `glass-panel`,
                        que saiu quando a barra ficou opaca — mas o portal continua sendo
                        necessário, agora pelo `fixed` + z.) Era o mesmo defeito do
                        `SidebarModeToggle`. Como o cabeçalho tem altura conhecida, o painel
                        se ancora por `fixed`, respeitando a inset do topo. */}
                    {isModeOpen && createPortal(
                        <div
                            ref={modePanelRef}
                            role="menu"
                            aria-label="Modo do menu"
                            className="fixed left-4 top-[calc(4rem+env(safe-area-inset-top))] w-64 rounded-md border border-border bg-popover text-popover-foreground shadow-e3 p-1.5 z-popover animate-in fade-in zoom-in-95 duration-200"
                        >
                            {MODE_ENTRIES.map((m) => {
                                const MIcon = m.icon
                                const isSelected = mode === m.id
                                return (
                                    // Opção de dropdown: segue <button type="button"> cru, só tokenizada.
                                    <button
                                        key={m.id}
                                        type="button"
                                        role="menuitemradio"
                                        aria-checked={isSelected}
                                        onClick={() => { setMode(m.id); setIsModeOpen(false) }}
                                        className={cn(
                                            'w-full flex min-h-[3rem] items-center gap-3 px-3 py-2.5 rounded-sm transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                                            isSelected
                                                ? 'border border-primary/20 bg-primary/10 text-primary font-semibold'
                                                : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
                                        )}
                                    >
                                        <MIcon aria-hidden="true" className="w-4 h-4" />
                                        <div className="flex flex-col items-start">
                                            <span className="text-sm font-bold">{m.label}</span>
                                            <span className="text-[10px] text-muted-foreground">{m.description}</span>
                                        </div>
                                        {isSelected && <Check aria-hidden="true" className="w-3 h-3 ml-auto" />}
                                    </button>
                                )
                            })}
                        </div>,
                        document.body,
                    )}
                </div>
            ) : (
                <Logo variant="full" height={24} />
            )}

            {/* Centro: símbolo da marca (apenas para OG, que usa a esquerda p/ o modo) */}
            {isOg && (
                <div className="absolute left-1/2 -translate-x-1/2 pointer-events-none">
                    <Logo variant="symbol" height={20} />
                </div>
            )}

            {/* Direita: avatar → abre Sheet de perfil */}
            <Sheet open={isProfileOpen} onOpenChange={setIsProfileOpen}>
                <SheetTrigger asChild>
                    {/* Avatar: área clicável, não botão visual — fica cru e tokenizado. */}
                    <button
                        type="button"
                        className={cn(
                            // 44x44: era 36, e este e o unico caminho para perfil, tema,
                            // impersonacao e sair no telefone (criterio 1 da §5.4.8).
                            'w-11 h-11 rounded-full border border-border shadow-e1 transition-transform active:scale-90 bg-muted text-muted-foreground flex items-center justify-center overflow-hidden font-semibold text-sm',
                            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                            impersonating && 'ring-2 ring-warning ring-offset-2 ring-offset-background'
                        )}
                    >
                        {user?.avatar_url
                            ? <img src={user.avatar_url} alt="Avatar" className="w-full h-full object-cover" />
                            : <span>{getInitials(user?.name, user?.email)}</span>
                        }
                    </button>
                </SheetTrigger>
                <SheetContent side="right" className="p-0 border-l border-border bg-background/95 backdrop-blur-3xl w-full sm:max-w-sm">
                    <MobileContextSheet onClose={() => setIsProfileOpen(false)} />
                </SheetContent>
            </Sheet>
        </header>
    )
}
