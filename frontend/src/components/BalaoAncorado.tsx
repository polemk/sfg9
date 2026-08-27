import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

/**
 * Balão preso a um botão, desenhado FORA da árvore de quem o abriu.
 *
 * A parede da TV é `overflow-hidden` de propósito: ela ocupa a tela inteira e
 * não pode rolar. Só que isso recorta qualquer `position: absolute` que cresça
 * além da borda — foi assim que o diálogo de período sumiu pela lateral. Trocar
 * por `fixed` num portal resolve na raiz: o balão passa a ser posicionado
 * contra a JANELA, não contra o cartão que o contém.
 *
 * Onde ele encosta:
 *
 *   por baixo    o topo do balão alinha com a base do botão (+ folga), que é
 *                para onde o olho já vai depois do clique.
 *   por cima     se não couber embaixo, vira para cima em vez de vazar.
 *   preso        na horizontal ele é grudado à borda do botão e depois
 *                travado dentro da janela, com 8px de respiro dos dois lados.
 *   encolhido    se não couber nem virando, ele limita a própria altura e
 *                rola por dentro. Nunca sai da tela.
 *
 * No celular nada disso vale: vira folha inferior, onde o polegar alcança.
 */

const FOLGA = 8
const MARGEM = 8

type Lado = 'baixo' | 'cima'

export function BalaoAncorado({
    aberto,
    aoFechar,
    ancora,
    largura = 288,
    alinhamento = 'direita',
    rotulo,
    children,
    className,
}: {
    aberto: boolean
    aoFechar: () => void
    /** O elemento a que o balão se prende — normalmente o botão que o abriu. */
    ancora: React.RefObject<HTMLElement | null>
    largura?: number
    alinhamento?: 'esquerda' | 'direita'
    rotulo: string
    children: ReactNode
    className?: string
}) {
    const balaoRef = useRef<HTMLDivElement | null>(null)
    const [pos, setPos] = useState<{ top: number; left: number; maxH: number; lado: Lado; seta: number } | null>(null)

    const medir = useCallback(() => {
        const alvo = ancora.current
        const balao = balaoRef.current
        if (!alvo || !balao) return

        const r = alvo.getBoundingClientRect()
        const vw = window.innerWidth
        const vh = window.innerHeight
        const alturaDesejada = balao.scrollHeight

        // Cabe embaixo? Senão, o lado com mais espaço ganha.
        const espacoAbaixo = vh - r.bottom - FOLGA - MARGEM
        const espacoAcima = r.top - FOLGA - MARGEM
        const lado: Lado = alturaDesejada <= espacoAbaixo || espacoAbaixo >= espacoAcima ? 'baixo' : 'cima'

        const maxH = Math.max(160, lado === 'baixo' ? espacoAbaixo : espacoAcima)
        const altura = Math.min(alturaDesejada, maxH)
        const top = lado === 'baixo' ? r.bottom + FOLGA : r.top - FOLGA - altura

        // Gruda na borda escolhida e depois trava dentro da janela.
        const preferido = alinhamento === 'direita' ? r.right - largura : r.left
        const left = Math.min(Math.max(MARGEM, preferido), vw - largura - MARGEM)

        // A seta aponta para o CENTRO do botão, mesmo depois do travamento —
        // é o que mantém a leitura de "isto saiu daqui".
        const seta = Math.min(Math.max(14, r.left + r.width / 2 - left), largura - 14)

        setPos({ top, left, maxH, lado, seta })
    }, [ancora, largura, alinhamento])

    // Antes da primeira pintura: sem isto o balão aparece no canto e salta.
    useLayoutEffect(() => {
        if (!aberto) { setPos(null); return }
        medir()
    }, [aberto, medir])

    useEffect(() => {
        if (!aberto) return

        const aoTeclar = (e: KeyboardEvent) => { if (e.key === 'Escape') aoFechar() }
        const aoClicarFora = (e: MouseEvent) => {
            const alvo = e.target as Node
            if (balaoRef.current?.contains(alvo)) return
            if (ancora.current?.contains(alvo)) return
            aoFechar()
        }

        // `true` na captura: pega rolagem de qualquer contêiner interno, não só
        // da janela.
        window.addEventListener('scroll', medir, true)
        window.addEventListener('resize', medir)
        document.addEventListener('keydown', aoTeclar)
        document.addEventListener('mousedown', aoClicarFora)
        return () => {
            window.removeEventListener('scroll', medir, true)
            window.removeEventListener('resize', medir)
            document.removeEventListener('keydown', aoTeclar)
            document.removeEventListener('mousedown', aoClicarFora)
        }
    }, [aberto, medir, aoFechar, ancora])

    if (!aberto) return null

    return createPortal(
        <>
            {/* Fundo só no celular: no desktop o clique fora já fecha, e escurecer
                a parede inteira para mexer num filtro seria um exagero. */}
            <div
                className="fixed inset-0 z-modal-backdrop bg-brand-ink/70 backdrop-blur-sm lg:hidden"
                onClick={aoFechar}
            />

            <div
                ref={balaoRef}
                role="dialog"
                aria-label={rotulo}
                className={cn(
                    'bg-popover/95 border border-border backdrop-blur-2xl shadow-e3',
                    'animate-in duration-150',
                    // celular: folha inferior
                    'fixed inset-x-0 bottom-0 z-modal max-h-[85dvh] overflow-y-auto',
                    'rounded-t-lg border-b-0 pb-[env(safe-area-inset-bottom)] slide-in-from-bottom-4',
                    // desktop: balão medido, preso à janela. As medidas entram
                    // por variável para que só valham do `lg:` para cima — no
                    // celular a folha inferior continua mandando.
                    'lg:inset-x-auto lg:bottom-auto lg:rounded-lg lg:border-b lg:pb-0',
                    'lg:fade-in lg:zoom-in-95 lg:slide-in-from-bottom-0',
                    'lg:top-[var(--balao-top)] lg:left-[var(--balao-left)]',
                    'lg:w-[var(--balao-w)] lg:max-h-[var(--balao-maxh)]',
                    // Sem medida ainda: existe no DOM (para poder ser medido) e
                    // não pisca no canto da tela.
                    'data-[medido=nao]:lg:invisible',
                    className,
                )}
                style={pos ? {
                    ['--balao-top' as string]: `${pos.top}px`,
                    ['--balao-left' as string]: `${pos.left}px`,
                    ['--balao-w' as string]: `${largura}px`,
                    ['--balao-maxh' as string]: `${pos.maxH}px`,
                    ['--balao-seta' as string]: `${pos.seta}px`,
                } : undefined}
                data-lado={pos?.lado}
                // A visibilidade evita o pisca-pisca do primeiro quadro, quando a
                // medida ainda não existe.
                data-medido={pos ? 'sim' : 'nao'}
            >
                {/* Puxador da folha (só celular). */}
                <div className="flex justify-center pt-2 lg:hidden" aria-hidden="true">
                    <span className="h-1 w-9 rounded-full bg-border" />
                </div>

                {/* O rabicho do balão — o detalhe que diz de onde ele saiu. */}
                <span
                    aria-hidden="true"
                    className={cn(
                        'hidden lg:block absolute h-2.5 w-2.5 rotate-45 border-border bg-popover',
                        pos?.lado === 'cima'
                            ? 'bottom-[-6px] border-b border-r'
                            : 'top-[-6px] border-l border-t',
                    )}
                    style={{ left: 'calc(var(--balao-seta) - 5px)' }}
                />

                {children}
            </div>
        </>,
        document.body,
    )
}
