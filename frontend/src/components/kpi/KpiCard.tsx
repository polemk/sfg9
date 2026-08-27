// Componente de KPI Card — Safegold. Renderiza título, valor (com count-up),
// variação (%) e ícone. Borderless: a separação do fundo vem do contraste
// --card vs --background + elevação tokenizada, nunca de uma borda.
import React from 'react'
import { cn } from '@/lib/utils'
import { ArrowUpRight, ArrowDownRight, Activity } from 'lucide-react'
import { useCountUp } from '@/hooks/useCountUp'

type IconType = React.ComponentType<React.SVGProps<SVGSVGElement>>

/**
 * **O corpo do valor sai do COMPRIMENTO do texto** — e é a correção do defeito
 * que apareceu cinco vezes no painel do Safegold, em cinco larguras diferentes.
 *
 * O valor era sempre `text-4xl` (36 px). Na Fira Mono isso gasta ~18 px por
 * dígito, então `R$ 174.493.854,98` (17 caracteres) pede ~306 px de texto —
 * mais que a largura útil de um cartão em grade de três ou quatro colunas. O
 * componente não encolhia nem truncava: **o último dígito saía pela borda**.
 * Num sistema de crédito isso não é layout, é um número errado na tela, e
 * nenhum type-check o pega.
 *
 * Cada consumidor vinha remendando por fora com seletor de descendente. Cinco
 * remendos para o mesmo defeito é sinal de que a conta pertence a quem sabe a
 * largura do próprio cartão — aqui.
 *
 * **Nada muda para valor curto no desktop.** Até 12 caracteres o corpo continua
 * sendo o `text-4xl` de sempre a partir de `sm:`, que é onde as quatro telas que
 * já usam o componente vivem (`formatMoney` de milhares, contagens). A redução
 * por comprimento só entra quando o texto passa do que cabe — ou seja,
 * exatamente onde hoje ele é cortado.
 *
 * **No telefone tudo desce um degrau** (26/08/2026, pedido do usuário: *"na dash
 * no mobile os cards de KPI podem ser bem menores com fontes menores, pois é
 * mobile"*). O motivo não é só gosto: no telefone os cartões **empilham em
 * coluna única**, então cada um custa altura de rolagem inteira, e quatro
 * cartões em tamanho de desktop empurram todo gráfico para fora da primeira
 * tela. Um número em `text-4xl` não fica mais legível num aparelho de 390 px —
 * fica maior, que não é a mesma coisa. O respiro (`p-6` → `p-4`) e o bloco do
 * ícone encolhem junto, pelo mesmo motivo.
 */
function corpoDoValor(texto: string, density: 'default' | 'compact'): string {
  const n = texto.length
  if (density === 'compact') {
    return n <= 16 ? 'text-lg sm:text-2xl' : n <= 20 ? 'text-base sm:text-xl' : 'text-sm sm:text-lg'
  }
  if (n <= 12) return 'text-2xl sm:text-4xl'
  if (n <= 16) return 'text-xl sm:text-3xl'
  if (n <= 20) return 'text-lg sm:text-2xl'
  return 'text-base sm:text-xl'
}

export function KpiCard({
  title,
  value,
  change,
  changeLabel,
  changeType,
  icon: Icon,
  color = 'hsl(var(--muted-foreground))',
  accentColor,
  footer,
  glow = false,
  density = 'default',
}: {
  title: string
  value: string | number
  change?: string
  changeLabel?: string
  changeType?: 'positive' | 'negative' | 'neutral'
  icon: IconType
  color?: string
  // accentColor: tinge o badge de delta com uma cor custom, exceto changeType==='negative'
  // (mantém vermelho). Backward compatible (opcional).
  accentColor?: string
  // footer: slot opcional abaixo do valor (ex.: Sparkline). Backward compatible.
  footer?: React.ReactNode
  // glow: destaque do KPI principal. Antes era uma aura borrada; agora é o
  // contorno sólido de marca (`.card-highlight`), o destaque padrão da casa.
  glow?: boolean
  /**
   * **`compact`: o cartão de UM NÚMERO CURTO, para fileira estreita.**
   *
   * O modo padrão empilha ícone → rótulo → valor, e um cartão cujo valor é `1`
   * fica com a mesma altura de um que carrega `R$ 174.493.854,98` — puro vazio
   * vertical. Em `compact` o ícone sobe para a MESMA linha do rótulo, o que
   * devolve uma linha inteira de altura, e o respiro encolhe (`p-6` → `p-4`).
   * Isso libera largura horizontal para o rótulo, que é o que faz
   * "RENEGOCIAÇÕES EM ATRASO" caber sem esticar o cartão.
   *
   * O padrão é `default`: nenhuma das quatro telas que já usam o componente
   * muda de aparência.
   */
  density?: 'default' | 'compact'
}) {
  const useAccent = !!accentColor && changeType !== 'negative'
  // Backward compatibility: if change is missing, changeLabel is the value
  const displayValue = change || changeLabel;
  // If change IS provided, changeLabel is the suffix (default "mês anterior").
  // If change IS NOT provided, suffix is fixed to "mês anterior" (as per old behavior)
  const displaySuffix = change ? (changeLabel || 'mês anterior') : 'mês anterior';
  const animatedValue = useCountUp(value)
  // **O corpo sai do valor FINAL, não do animado.** O `useCountUp` interpola e o
  // texto muda de comprimento durante a animação — medir o animado faria a
  // fonte pular a cada quadro.
  const corpo = corpoDoValor(String(value), density)
  const compacto = density === 'compact'

  return (
    <div
      className={cn(
        'relative group overflow-hidden rounded-lg bg-card transition-shadow duration-300 shadow-e1 hover:shadow-e2',
        glow && 'card-highlight',
      )}
    >
      <div className={cn('relative z-base', compacto ? 'p-3 sm:p-4' : 'p-4 sm:p-6')}>
        {/* Linha superior: ícone + badge de variação.

            Em `compact` o ícone **não** ocupa esta linha — ele desce para junto
            do rótulo, e é isso que devolve uma linha inteira de altura. */}
        <div
          className={cn(
            'flex items-start',
            // Em `compact` o ícone não está nesta linha, então sobra só o badge
            // — e com `justify-between` ele encostava à ESQUERDA, como se fosse
            // um rótulo solto. Visto na tela.
            compacto ? 'justify-end mb-1' : 'justify-between mb-2 sm:mb-4',
          )}
        >
          {!compacto && (
          <div className="p-2 sm:p-3 rounded-md bg-secondary transition-colors duration-300">
            <Icon
              className="h-5 w-5 sm:h-6 sm:w-6 transition-opacity duration-300 group-hover:opacity-100 opacity-70"
              style={{ color }}
            />
          </div>
          )}

          {displayValue && (
            <div
              className={cn(
                "flex items-center gap-1 text-xs font-semibold px-2.5 py-1 rounded-full font-numeric",
                useAccent
                  ? "bg-secondary"
                  : (changeType === 'positive'
                    ? "text-success bg-success/10"
                    : changeType === 'negative'
                      ? "text-destructive bg-destructive/10"
                      : "text-muted-foreground bg-secondary")
              )}
              style={useAccent ? { color: accentColor } : undefined}
            >
              {changeType === 'positive'
                ? <ArrowUpRight className="w-3 h-3" />
                : changeType === 'negative'
                  ? <ArrowDownRight className="w-3 h-3" />
                  : <Activity className="w-3 h-3" />
              }
              {displayValue}
            </div>
          )}
        </div>

        {/* Título e valor */}
        <div className={cn(compacto ? 'space-y-0.5' : 'space-y-1')}>
          {compacto ? (
            // Ícone AO LADO do rótulo. Além da linha de altura que isso devolve,
            // o rótulo passa a ter a largura do cartão inteiro menos o ícone —
            // e o `tracking` menor com `text-balance` faz um rótulo longo cair
            // em duas linhas equilibradas em vez de uma órfã.
            <div className="flex items-center gap-2">
              <span className="shrink-0 rounded-md bg-secondary p-1.5">
                <Icon className="h-3.5 w-3.5 opacity-70" style={{ color }} />
              </span>
              <h3 className="text-balance text-[10px] font-bold uppercase leading-tight tracking-[0.12em] text-muted-foreground">
                {title}
              </h3>
            </div>
          ) : (
            <h3 className="text-muted-foreground text-[10px] font-bold uppercase tracking-[0.2em]">{title}</h3>
          )}
          <div className={cn(corpo, 'font-bold text-card-foreground tracking-tight font-numeric')}>{animatedValue}</div>
          {change && (
            <p className="text-[10px] text-muted-foreground/60">{displaySuffix}</p>
          )}
          {footer && <div className="pt-1">{footer}</div>}
        </div>
      </div>
    </div>
  )
}
