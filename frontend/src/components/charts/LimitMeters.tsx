import { AlertTriangle } from 'lucide-react'
import { formatMoney } from '@/lib/utils/number'
import { CHART_TOKENS } from './chartTokens'

/**
 * **Medidor de consumo contra um teto conhecido** — a terceira forma do sistema.
 *
 * ## A pergunta que ele responde
 *
 * *"Algum tipo de limite está perto do teto?"* — a pergunta que o gestor faz
 * antes de aprovar a próxima operação. Não é "quanto foi usado" (isso é o
 * cartão de exposição) nem "onde está concentrado" (isso é o ranking por
 * portador): é **quanto ainda cabe**.
 *
 * ## Por que medidor, e não mais uma barra
 *
 * Barra compara categorias entre si. Aqui cada linha se compara com **o próprio
 * teto**, que é diferente em cada tipo — num gráfico de barras comum, um limite
 * de 490 mil com 2% usado desenharia uma barra maior que um limite de 10 mil
 * estourado, que é o contrário da resposta. O trilho é o teto; o preenchimento
 * é o consumo. A leitura é imediata e não depende de comparar comprimentos.
 *
 * ## Cor com significado, e nunca sozinha
 *
 * Três estados, não dois: **verde** com folga, **âmbar** perto do teto,
 * **vermelho** no teto ou além. Verde e vermelho são o **mesmo par de tokens**
 * do semáforo da tela de risco (FE-238), para que o painel e o detalhe não usem
 * duas cores para a mesma condição; o âmbar foi escolhido por contraste medido,
 * não por nome (ver `chartTokens`). Quem não está em `ok` ganha **ícone e
 * rótulo** além da cor: cor nunca é o único portador de informação.
 *
 * ## Nada é calculado aqui
 *
 * `percentLabel` chega **pronto para leitura** — ou do servidor (o texto de
 * `Money.percent`, com os arredondamentos que a DEC-01 manda preservar, só com o
 * separador trocado para pt-BR), ou do `formatPercent` sobre o número que o
 * domínio mandou. `used`/`total` servem só para o **comprimento** do
 * preenchimento, que é geometria, não número exibido.
 */
export interface LimitMeterItem {
  /** Chave estável. Sem ela, dois limites de mesmo título viram a mesma linha
   *  no React ("two children with the same key" — visto no console). */
  id?: string
  label: string
  /** Segunda linha do rótulo — portador, tipo. Opcional. */
  sublabel?: string
  used: number
  total: number
  available: number
  /** Texto pronto para leitura, já em pt-BR. Impresso como chegou. */
  percentLabel: string
  /**
   * O que a linha significa, e é o que decide a cor:
   * `ok` com folga, `warning` perto do teto, `danger` no teto ou além.
   *
   * É um **tom nomeado**, não um booleano, porque a mesma lista precisa de três
   * estados e um `atCeiling: false` não distingue "com folga" de "a 99%".
   */
  tone?: 'ok' | 'warning' | 'danger'
}

/** Fração do trilho, entre 0 e 1. Só geometria — nunca vira texto na tela. */
function preenchimento(item: LimitMeterItem): number {
  if (item.total <= 0) return item.used > 0 ? 1 : 0
  return Math.min(1, Math.max(0, item.used / item.total))
}

export function LimitMeters({ items }: { items: LimitMeterItem[] }) {
  return (
    <ul className="space-y-3">
      {items.map((item, indice) => {
        const fracao = preenchimento(item)
        const tom = item.tone ?? 'ok'
        const cor =
          tom === 'danger' ? CHART_TOKENS.negative : tom === 'warning' ? CHART_TOKENS.warning : CHART_TOKENS.positive

        return (
          <li key={item.id ?? `${item.label}-${indice}`} className="space-y-1">
            <div className="flex items-baseline justify-between gap-3">
              <span className="flex min-w-0 items-center gap-1.5 text-sm text-foreground">
                {/* Ícone junto da cor: cor sozinha nunca carrega o estado. */}
                {tom !== 'ok' && (
                  <AlertTriangle
                    aria-hidden="true"
                    className={'h-3.5 w-3.5 shrink-0 ' + (tom === 'danger' ? 'text-destructive' : 'text-warning')}
                  />
                )}
                <span className="min-w-0 truncate">
                  {item.label}
                  {item.sublabel && <span className="text-muted-foreground"> · {item.sublabel}</span>}
                </span>
                {tom !== 'ok' && (
                  <span className="sr-only">{tom === 'danger' ? '— limite no teto' : '— perto do teto'}</span>
                )}
              </span>
              <span
                className={
                  'shrink-0 font-numeric text-xs ' +
                  (tom === 'danger'
                    ? 'font-semibold text-destructive'
                    : tom === 'warning'
                      ? 'font-semibold text-warning'
                      : 'text-muted-foreground')
                }
              >
                {item.percentLabel}
              </span>
            </div>

            <div
              className="h-2 w-full overflow-hidden rounded-full"
              style={{ backgroundColor: CHART_TOKENS.track }}
              role="meter"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(fracao * 100)}
              aria-label={`${item.label}: ${item.percentLabel} do limite utilizado`}
            >
              <div className="h-full rounded-full" style={{ width: `${fracao * 100}%`, backgroundColor: cor }} />
            </div>

            <p className="font-numeric text-[11px] text-muted-foreground">
              {formatMoney(item.used)} de {formatMoney(item.total)} · disponível {formatMoney(item.available)}
            </p>
          </li>
        )
      })}
    </ul>
  )
}
