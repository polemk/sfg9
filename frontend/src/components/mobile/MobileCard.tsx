import React from 'react'
import { cn } from '@/lib/utils'
// A moeda vem da configuracao do app (§5.4.9), nunca de `'BRL'` cravado: era
// exatamente a copia numero oito da decisao que `lib/config/currency` centralizou.
import { formatMoney } from '@/lib/utils/number'

/**
 * **A linha de uma lista, no telefone** — DEC-100.
 *
 * É o substituto da linha de tabela: no celular a tabela vira `overflow-x`, e coluna fora da
 * tela é coluna que o usuário nunca descobre. Aqui os mesmos campos empilham — identificação
 * em cima, estado no meio, valor à direita.
 *
 * **O nome do estado é semântico, não de paleta.** `statusTone` fala `success`/`warning`/
 * `destructive`/`info`/`neutral`, que são os tokens; antes falava `emerald`/`rose`/`amber`,
 * herdado da paleta do ai9. O nome importa porque é ele que a próxima pessoa copia: quem lê
 * `statusColor="emerald"` conclui que cor literal é aceitável nesta base, e §5.4.2 diz que
 * não é.
 */
export type MobileCardTone = 'success' | 'warning' | 'destructive' | 'info' | 'neutral'

interface MobileCardProps extends React.HTMLAttributes<HTMLDivElement> {
    children?: React.ReactNode
    className?: string
    title?: string
    subtitle?: string
    value?: number
    /** Sinal e cor do valor: entrada, saída ou sem conotação. */
    type?: 'receita' | 'despesa' | 'neutral'
    status?: string
    /** Token de estado do selo. Ver `MobileCardTone`. */
    statusTone?: MobileCardTone
    icon?: React.ReactNode
    imageUrl?: string
    rightSlot?: React.ReactNode
    footer?: React.ReactNode
    headerAction?: React.ReactNode
}

export const MobileCard: React.FC<MobileCardProps> = ({
    children,
    className,
    title,
    subtitle,
    value,
    type = 'neutral',
    status,
    statusTone = 'neutral',
    icon,
    imageUrl,
    rightSlot,
    footer,
    headerAction,
    ...props
}) => {
    const classesDoSelo = (tom: MobileCardTone) => {
        switch (tom) {
            case 'success':     return 'text-success bg-success/10 border-success/20'
            case 'destructive': return 'text-destructive bg-destructive/10 border-destructive/20'
            case 'warning':     return 'text-warning bg-warning/10 border-warning/20'
            case 'info':        return 'text-info bg-info/10 border-info/20'
            default:            return 'text-muted-foreground bg-muted border-border'
        }
    }

    // Card clicável é o padrão de "abrir o registro" numa lista mobile. Mas `onClick` num
    // `<div>` é inacessível ao teclado e invisível ao leitor de tela: quem navega por Tab
    // simplesmente não alcança a linha. Quando a tela passa `onClick`, o card ganha papel,
    // foco e as duas teclas que ativam um botão.
    const clicavel = typeof props.onClick === 'function'

    return (
        <div
            role={clicavel ? 'button' : undefined}
            tabIndex={clicavel ? 0 : undefined}
            onKeyDown={
                clicavel
                    ? (evento) => {
                          if (evento.key === 'Enter' || evento.key === ' ') {
                              evento.preventDefault()
                              props.onClick?.(evento as unknown as React.MouseEvent<HTMLDivElement>)
                          }
                      }
                    : undefined
            }
            className={cn(
                'w-full rounded-lg bg-card text-card-foreground border border-border',
                'p-5 mb-4 shadow-e2 relative group transition-all',
                clicavel &&
                    'cursor-pointer active:scale-[0.98] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                className,
            )}
            {...props}
        >
            <div className="flex justify-between items-start mb-3">
                <div className="flex gap-3 min-w-0">
                    {imageUrl ? (
                        <div className="w-12 h-12 rounded-md overflow-hidden border border-border shrink-0 bg-muted">
                            <img src={imageUrl} alt="" aria-hidden="true" className="w-full h-full object-cover" />
                        </div>
                    ) : icon && (
                        <div className="p-2.5 rounded-md bg-muted border border-border shrink-0 group-hover:bg-accent transition-colors">
                            {icon}
                        </div>
                    )}
                    <div className="min-w-0 flex-1">
                        {title && (
                            <h3 className="text-sm font-bold text-card-foreground tracking-tight truncate leading-tight">
                                {title}
                            </h3>
                        )}
                        {subtitle && (
                            <p className="text-xs text-muted-foreground font-medium truncate mt-0.5">{subtitle}</p>
                        )}
                        {status && (
                            <div className={cn(
                                // Era `text-[8px]`: abaixo do legível num telefone, e este
                                // selo é quem diz se o borderô está pago ou vencido.
                                'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider border mt-2',
                                classesDoSelo(statusTone),
                            )}>
                                {status}
                            </div>
                        )}
                    </div>
                </div>

                <div className="flex flex-col items-end gap-2 shrink-0">
                    {rightSlot || headerAction}
                    {value !== undefined && (
                        <div className={cn(
                            'text-sm font-black tracking-tight font-numeric',
                            type === 'receita' ? 'text-success' :
                            type === 'despesa' ? 'text-destructive' :
                            'text-card-foreground',
                        )}>
                            {type === 'despesa' ? '-' : ''}
                            {formatMoney(value)}
                        </div>
                    )}
                </div>
            </div>

            {children && <div className="mt-4">{children}</div>}

            {footer && (
                <div className="mt-4 pt-3 border-t border-border">
                    {footer}
                </div>
            )}
        </div>
    )
}
