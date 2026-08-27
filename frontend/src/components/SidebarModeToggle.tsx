import { useState, useRef, useEffect } from 'react'
import { ChevronRight, Check, Briefcase, FileText, Settings2, Layers } from 'lucide-react'
import { Tooltip } from '@/components/ui/Tooltip'
import { cn } from '@/lib/utils'
import { SidebarSelectorCard } from '@/components/ui/SidebarSelectorCard'
import { useSidebarMode } from '@/store/sidebarModeStore'
import { MODE_ENTRIES } from '@/lib/sidebarModes'
import type { SidebarMode } from '@/store/sidebarModeStore'
import { CONSOLE_NAV_GROUPS } from '@/app/consoleNavigation'
import type { LucideIcon } from 'lucide-react'

interface SidebarModeToggleProps {
    collapsed?: boolean
}

// Os modos não têm mais uma cor decorativa cada (o antigo COLOR_MAP com neon,
// laranja, azul e violeta). A casca distingue o selecionado pelo ouro Safegold
// e pelo peso do texto — não por cinco matizes diferentes.
//
// A derivação a partir de `CONSOLE_NAV_GROUPS` **saiu daqui** para
// `@/lib/sidebarModes`: a `MobileTopBar` tinha a própria lista, escrita à mão e
// com os modos antigos do ai9, e o telefone ficou mostrando quatro opções que
// não existem mais. Regra compartilhada não mora na casa do primeiro que
// precisou dela.
const MODES = MODE_ENTRIES

export function SidebarModeToggle({ collapsed }: SidebarModeToggleProps) {
    const [isOpen, setIsOpen] = useState(false)
    const containerRef = useRef<HTMLDivElement>(null)
    const { mode, setMode } = useSidebarMode()

    const selectedMode = MODES.find(m => m.id === mode) || MODES[0]
    const Icon = selectedMode.icon

    useEffect(() => {
        function handleClickOutside(event: MouseEvent) {
            if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
                setIsOpen(false)
            }
        }
        document.addEventListener('mousedown', handleClickOutside)
        return () => document.removeEventListener('mousedown', handleClickOutside)
    }, [])

    const handleSelect = (modeId: SidebarMode) => {
        setMode(modeId)
        setIsOpen(false)
    }

    return (
        <div className="relative" ref={containerRef}>
            {/* Trigger Button */}
            <SidebarSelectorCard
                label="Modo"
                value={selectedMode.label}
                icon={Icon}
                collapsed={collapsed}
                open={isOpen}
                onClick={() => setIsOpen(!isOpen)}
            />

            {/* Dropdown */}
            {isOpen && (
                <div
                    className={cn(
                        "absolute top-full left-0 mt-2 z-modal w-64 origin-top-left",
                        "animate-in fade-in zoom-in-95 duration-200",
                        collapsed ? "left-12 top-0 mt-0" : ""
                    )}
                    style={{ minWidth: collapsed ? '16rem' : '100%' }}
                >
                    <div className="rounded-lg border border-border bg-popover text-popover-foreground backdrop-blur-2xl shadow-e3 overflow-hidden">
                        {/* Header */}
                        <div className="p-3 border-b border-border bg-muted/30">
                            <h3 className="text-xs font-bold text-foreground">Modo de Visualização</h3>
                            <p className="text-xs text-muted-foreground mt-0.5">Filtre o menu por contexto de trabalho</p>
                        </div>

                        {/* Modes List */}
                        <div className="p-1.5 space-y-1">
                            {MODES.map((m) => {
                                const ModeIcon = m.icon
                                const isSelected = mode === m.id

                                return (
                                    // Opção de menu suspenso: fica `<button type="button">` cru.
                                    <button
                                        key={m.id}
                                        type="button"
                                        onClick={() => handleSelect(m.id)}
                                        className={cn(
                                            "w-full flex items-center gap-3 px-3 py-3 rounded-md text-left transition-all duration-200 group border",
                                            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                                            isSelected
                                                ? "bg-accent text-accent-foreground border-primary"
                                                : "text-muted-foreground hover:text-foreground hover:bg-accent border-transparent"
                                        )}
                                    >
                                        <span className={cn(
                                            "w-9 h-9 rounded-md flex items-center justify-center transition-all flex-shrink-0",
                                            isSelected ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"
                                        )}>
                                            <ModeIcon className="w-4 h-4" />
                                        </span>

                                        <span className="flex-1 min-w-0">
                                            <span className={cn(
                                                "text-sm block",
                                                isSelected ? "font-bold text-foreground" : "font-medium"
                                            )}>
                                                {m.label}
                                            </span>
                                            <span className="text-xs text-muted-foreground block truncate">
                                                {m.description}
                                            </span>
                                        </span>

                                        {isSelected && (
                                            <span className="rounded-full p-0.5 animate-in zoom-in duration-200 bg-primary text-primary-foreground">
                                                <Check className="w-3 h-3 stroke-[3px]" />
                                            </span>
                                        )}
                                    </button>
                                )
                            })}
                        </div>

                        {/* Faixa inferior sólida de marca — sem gradiente. */}
                        <div className="h-0.5 w-full bg-primary/40" />
                    </div>
                </div>
            )}
        </div>
    )
}
