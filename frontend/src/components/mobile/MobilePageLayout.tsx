import React from 'react'
import { motion } from 'framer-motion'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/Button'

/**
 * **A moldura de uma tela no telefone** — DEC-100.
 *
 * Existe por um motivo só, e é um motivo de layout: o `Layout` do console fixa a
 * `MobileTopBar` no topo e a `MobileBottomBar` no rodapé. Uma tela que não reserve espaço
 * para as duas **termina embaixo da barra de abas** — e o que fica escondido é justamente o
 * fim da lista e o botão de confirmar.
 *
 * O respiro do rodapé é `env(safe-area-inset-bottom)` somado à altura da barra: instalado
 * como PWA (`display: standalone`, NEW-003) o navegador some e o indicador de início do
 * iPhone entra na conta. Sem isso a última linha da lista fica sob o traço do aparelho.
 *
 * O FAB flutua **acima** da barra de abas pelo mesmo cálculo, com alvo de 56 px — o mínimo
 * que o polegar acerta sem mirar.
 */
interface MobilePageLayoutProps {
    children: React.ReactNode
    className?: string
    noPadding?: boolean
    fab?: {
        icon: React.ReactNode
        onClick: () => void
        /** Vira o `aria-label` do botão. Um FAB sem rótulo é um ícone mudo no leitor de tela. */
        label?: string
    }
}

/** Altura da barra de abas + folga, somada à inset do aparelho. */
const RESPIRO_RODAPE = 'calc(5rem + env(safe-area-inset-bottom))'

export function MobilePageLayout({ children, className, noPadding, fab }: MobilePageLayoutProps) {
    return (
        <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.3 }}
            style={{ paddingBottom: RESPIRO_RODAPE }}
            className={cn(
                'min-h-[calc(100dvh-128px)] w-full flex flex-col',
                !noPadding && 'px-4 pt-6',
                className,
            )}
        >
            {children}

            {fab && (
                <div
                    className="fixed right-4 z-fab"
                    style={{ bottom: 'calc(5.5rem + env(safe-area-inset-bottom))' }}
                >
                    <Button
                        variant="primary"
                        size="icon"
                        onClick={fab.onClick}
                        className="h-14 w-14 rounded-full shadow-e3 active:scale-95"
                        aria-label={fab.label || 'Ação flutuante'}
                    >
                        {fab.icon}
                    </Button>
                </div>
            )}
        </motion.div>
    )
}
