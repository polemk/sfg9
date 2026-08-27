import { LucideIcon, TrendingUp, TrendingDown, Minus } from 'lucide-react'
import { cn } from '@/lib/utils'
import { APP_CURRENCY } from '@/lib/config/currency'

/**
 * **Um indicador, no telefone** — DEC-100.
 *
 * É o cartão de número único: exposição atual, total operado, limite ocupado, atraso. S10 e
 * S15 vão instanciá-lo às dezenas, então a API dele tinha que parar de ser ambígua.
 *
 * **O que mudou, e por quê:**
 *
 * - **Três booleanos de formato viraram um `format`.** Era `isCurrency` (padrão `true`) mais
 *   `isPercentage`; com os dois ligados o resultado dependia da ordem dos `if`, e "moeda por
 *   padrão" fazia uma contagem de parcelas sair como `R$ 12`. Agora é
 *   `'currency' | 'percent' | 'plain'`, sem padrão implícito perigoso.
 * - **`change` e `evolution` faziam a mesma coisa.** Duas props para um texto, resolvidas com
 *   `evolution || change`. Ficou `change`, e só.
 * - **Carregando existe.** Um KPI que ainda não tem número mostrava `NaN`/vazio; agora tem
 *   esqueleto com a mesma forma, e o layout não pula quando o dado chega.
 *
 * O número usa `font-numeric` (Fira Mono + `tabular-nums`) porque KPIs empilhados com
 * larguras de dígito diferentes não alinham — §5.4.2 trata isso como defeito, não estética.
 */

export type MobileKPIFormat = 'currency' | 'percent' | 'plain'

interface MobileKPIProps {
    title: string
    /** String passa direto: use quando o valor já vem formatado do servidor. */
    value: number | string
    icon: LucideIcon
    /**
     * Cor do ícone. Precisa ser string por causa do `style` — então é
     * `hsl(var(--token))`, **nunca** um `#hex`. O padrão é o ouro da marca.
     */
    color?: string
    /** Texto da variação: "+12,4%", "3 a mais que ontem". */
    change?: string
    changeType?: 'positive' | 'negative' | 'neutral'
    format?: MobileKPIFormat
    /** Enquanto o dado não chega: esqueleto no lugar do número. */
    loading?: boolean
    className?: string
}

// KPI arredonda para a unidade inteira de proposito — cabecalho de indicador com
// centavos nao cabe num 390 e nao acrescenta informacao. O que NAO pode e a moeda
// vir cravada: `'BRL'` aqui era uma oitava copia da decisao que vive em
// `lib/config/currency` (§5.4.9).
const FORMATO_MOEDA = new Intl.NumberFormat(APP_CURRENCY.locale, {
    style: 'currency',
    currency: APP_CURRENCY.code,
    maximumFractionDigits: 0,
})
const FORMATO_SIMPLES = new Intl.NumberFormat(APP_CURRENCY.locale)

export function MobileKPI({
    title,
    value,
    icon: Icon,
    color = 'hsl(var(--primary))',
    change,
    changeType = 'neutral',
    format = 'currency',
    loading = false,
    className,
}: MobileKPIProps) {
    const formatarValor = (val: number | string) => {
        if (typeof val === 'string') return val
        if (format === 'percent') return `${FORMATO_SIMPLES.format(val)}%`
        if (format === 'plain') return FORMATO_SIMPLES.format(val)
        return FORMATO_MOEDA.format(val)
    }

    const classesDaVariacao = () => {
        if (changeType === 'positive') return 'text-success bg-success/10 border-success/20'
        if (changeType === 'negative') return 'text-destructive bg-destructive/10 border-destructive/20'
        return 'text-info bg-info/10 border-info/20'
    }

    const IconeTendencia =
        changeType === 'positive' ? TrendingUp : changeType === 'negative' ? TrendingDown : Minus

    return (
        <div
            className={cn(
                'relative overflow-hidden rounded-lg p-5 border border-border',
                'bg-card text-card-foreground transition-all shadow-e2',
                className,
            )}
            aria-busy={loading || undefined}
        >
            <div className="flex flex-col gap-3 relative z-base">
                <div className="flex items-center justify-between">
                    <div className="p-2.5 rounded-md border border-border bg-muted" style={{ color }}>
                        <Icon aria-hidden="true" className="w-5 h-5" />
                    </div>

                    {change && !loading && (
                        <div
                            className={cn(
                                'flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-[10px] font-bold uppercase tracking-widest font-numeric',
                                classesDaVariacao(),
                            )}
                        >
                            <IconeTendencia aria-hidden="true" className="w-3 h-3" />
                            <span>{change}</span>
                        </div>
                    )}
                </div>

                <div className="space-y-1">
                    <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground">
                        {title}
                    </p>
                    {loading ? (
                        <span
                            aria-hidden="true"
                            className="block h-7 w-32 animate-pulse rounded-sm bg-muted"
                        />
                    ) : (
                        <p className="text-2xl font-black text-card-foreground tracking-tight leading-none font-numeric">
                            {formatarValor(value)}
                        </p>
                    )}
                </div>
            </div>
        </div>
    )
}
