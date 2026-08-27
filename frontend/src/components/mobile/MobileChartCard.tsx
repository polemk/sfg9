import React from 'react'
import {
    AreaChart,
    Area,
    XAxis,
    YAxis,
    CartesianGrid,
    Tooltip,
    ResponsiveContainer,
} from 'recharts'
import { cn } from '@/lib/utils'
import { APP_CURRENCY } from '@/lib/config/currency'
import { LucideIcon } from 'lucide-react'

/**
 * **Um gráfico, no telefone** — DEC-100.
 *
 * Três coisas que estavam erradas e viram sete telas erradas se S10/S15 copiarem daqui:
 *
 * 1. **`data: any[]`.** Numa tela financeira, `any` é como a coluna errada chega ao
 *    gráfico sem o `tsc` dizer nada. Agora a série é tipada por `categoryKey`/`dataKey`.
 * 2. **Valor sem formato pt-BR.** O rótulo saía `R$ 1234567.89` — ponto decimal, sem
 *    separador de milhar. `Intl.NumberFormat('pt-BR')` resolve, e é o mesmo formato do
 *    `MobileCard`, senão a mesma cifra aparece de dois jeitos na mesma rolagem.
 * 3. **Bolinha pulsando no canto.** Ela dizia "ao vivo" sobre um dado que não é ao vivo.
 *    Indicador que mente é pior que indicador nenhum — saiu.
 *
 * E o gráfico **sem dado** deixa de ser um retângulo vazio: diz que não há série no
 * período, que é diferente de estar carregando.
 */
export interface MobileChartPoint {
    [chave: string]: string | number | null | undefined
}

interface MobileChartCardProps {
    title: string
    data: MobileChartPoint[]
    dataKey: string
    categoryKey?: string
    color?: string
    icon?: LucideIcon
    /** `currency` formata na moeda do app (§5.4.9); `plain` só agrupa o milhar. */
    valueFormat?: 'currency' | 'plain'
    /** Texto do estado vazio, na voz do domínio. */
    emptyLabel?: string
    className?: string
}

// Moeda e locale da configuracao do app (§5.4.9), nunca cravados na tela.
const FORMATO_MOEDA = new Intl.NumberFormat(APP_CURRENCY.locale, {
    style: 'currency',
    currency: APP_CURRENCY.code,
})
const FORMATO_SIMPLES = new Intl.NumberFormat(APP_CURRENCY.locale)

export function MobileChartCard({
    title,
    data,
    dataKey,
    categoryKey = 'name',
    // Cor da série: token por padrão. Recharts precisa de string, então vai
    // como `hsl(var(--…))` em vez de classe Tailwind.
    color = 'hsl(var(--primary))',
    icon: Icon,
    valueFormat = 'currency',
    emptyLabel = 'Sem dados no período',
    className,
}: MobileChartCardProps) {
    const formatar = (valor: number) =>
        valueFormat === 'currency' ? FORMATO_MOEDA.format(valor) : FORMATO_SIMPLES.format(valor)

    const vazio = !data || data.length === 0

    return (
        // `glass-panel` saiu: ele já pinta `--card` a 88% E aplica `backdrop-filter`, então
        // vinha empilhado com o `bg-card` seguinte — duas declarações de fundo disputando a
        // mesma superfície. Pior, `backdrop-filter` cria contexto de empilhamento (§5.4.4),
        // e este card vai hospedar tooltip de gráfico. Superfície de card é `bg-card`, igual
        // à do `MobileCard` e à do `MobileKPI`: os três têm que parecer o mesmo material.
        <div className={cn(
            'rounded-lg p-5 border border-border',
            'bg-card text-card-foreground shadow-e2 relative overflow-hidden',
            className,
        )}>
            <div className="flex items-center justify-between mb-6">
                <div className="flex items-center gap-3">
                    {Icon && (
                        <div
                            className="p-2 rounded-md bg-muted border border-border"
                            style={{ color }}
                        >
                            <Icon className="w-5 h-5" />
                        </div>
                    )}
                    <h3 className="text-sm font-black uppercase tracking-widest text-muted-foreground">
                        {title}
                    </h3>
                </div>
            </div>

            <div className="h-[200px] w-full">
                {vazio ? (
                    <div className="flex h-full items-center justify-center rounded-md border border-dashed border-border text-center">
                        <p className="max-w-[24ch] text-xs text-muted-foreground">{emptyLabel}</p>
                    </div>
                ) : (
                <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={data} margin={{ top: 10, right: 0, left: -20, bottom: 0 }}>
                        <defs>
                            <linearGradient id={`colorGradient-${dataKey}`} x1="0" y1="0" x2="0" y2="1">
                                <stop offset="5%" stopColor={color} stopOpacity={0.3} />
                                <stop offset="95%" stopColor={color} stopOpacity={0} />
                            </linearGradient>
                        </defs>
                        <CartesianGrid
                            strokeDasharray="3 3"
                            vertical={false}
                            stroke="currentColor"
                            className="text-border"
                        />
                        <XAxis
                            dataKey={categoryKey}
                            axisLine={false}
                            tickLine={false}
                            tick={{ fill: 'currentColor', fontSize: 10, fontWeight: 700 }}
                            className="text-muted-foreground"
                            dy={10}
                        />
                        <YAxis
                            axisLine={false}
                            tickLine={false}
                            tick={{ fill: 'currentColor', fontSize: 10, fontWeight: 700 }}
                            className="text-muted-foreground"
                            // Eixo compacto (1,2 mi) em vez de 1200000: no 390 de largura o
                            // rótulo inteiro come um terço da area de plotagem.
                            tickFormatter={(valor: number) =>
                                new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 }).format(valor)
                            }
                        />
                        <Tooltip
                            contentStyle={{
                                backgroundColor: 'hsl(var(--popover))',
                                border: '1px solid hsl(var(--border))',
                                borderRadius: 'var(--radius)',
                                boxShadow: 'var(--elevation-2)',
                                padding: '12px',
                            }}
                            itemStyle={{ color: 'hsl(var(--popover-foreground))', fontSize: '12px', fontWeight: 'bold' }}
                            labelStyle={{ color: 'hsl(var(--muted-foreground))', fontSize: '10px', marginBottom: '4px', textTransform: 'uppercase', fontWeight: '900' }}
                            formatter={(value: number | string | undefined) => [formatar(Number(value ?? 0)), title]}
                        />
                        <Area
                            type="monotone"
                            dataKey={dataKey}
                            stroke={color}
                            strokeWidth={3}
                            fillOpacity={1}
                            fill={`url(#colorGradient-${dataKey})`}
                            animationDuration={1500}
                        />
                    </AreaChart>
                </ResponsiveContainer>
                )}
            </div>
        </div>
    )
}
