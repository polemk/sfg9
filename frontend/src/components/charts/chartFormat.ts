import { formatAmount, formatAmountCompact, formatMoney, formatMoneyCompact } from '@/lib/utils/number'

/**
 * **Como um número vira texto dentro de um gráfico** — e por que isso é um
 * arquivo, e não uma linha em cada componente.
 *
 * Dois defeitos, os dois vistos na tela e não deduzidos:
 *
 * 1. **O tooltip imprimia o número cru.** `605602.54` — ponto decimal de
 *    JavaScript, sem separador de milhar e sem `R$`, num valor financeiro na
 *    frente do cliente. É a mesma família do `2.55%` que a S8 achou hoje: cada
 *    componente decidindo sozinho como escrever número.
 * 2. **O rótulo do eixo Y saía cortado** (`00000`, `0`). A margem do gráfico é
 *    fixa e o rótulo formatado de sete dígitos não cabe nela.
 *
 * A correção dos dois é a mesma: **o formato é do sistema, não do gráfico**, e a
 * largura do eixo sai do rótulo mais largo que a série **realmente produz** —
 * nunca de um valor chutado.
 *
 * `formatMoney` continua sendo a única forma de escrever moeda para leitura
 * (FE-431). Aqui só se escolhe **qual** delas o eixo e o tooltip usam.
 */
export type ChartFormat = 'currency' | 'decimal'

/** Valor exato — tooltip, rótulo direto e tabela. É o que a pessoa lê. */
export function formatExact(valor: number, formato: ChartFormat): string {
  return formato === 'currency' ? formatMoney(valor) : formatAmount(valor)
}

/** Rótulo de escala — eixo. Compacto porque a margem é finita. */
export function formatTick(valor: number, formato: ChartFormat): string {
  return formato === 'currency' ? formatMoneyCompact(valor) : formatAmountCompact(valor)
}

/**
 * A largura que o eixo Y precisa, em pixels, para o **maior rótulo que esta
 * série produz**.
 *
 * Recharts não mede texto: ele usa `width={60}` fixo e corta o que passar. A
 * conta aqui é a do pior caso do rótulo compacto na fonte do eixo (12 px,
 * ~7 px por caractere) mais o respiro do tique. O mínimo de 44 px evita um eixo
 * grudado no texto quando os valores são curtos.
 *
 * **A escala do eixo é maior que o maior dado**: Recharts arredonda o topo para
 * um número "bonito", que pode ter um dígito a mais. Por isso a medição usa o
 * máximo com folga, e não o máximo cru — foi essa diferença de um caractere que
 * cortava o primeiro dígito.
 */
export function yAxisWidth(values: number[], formato: ChartFormat): number {
  const finitos = values.filter((v) => Number.isFinite(v))
  if (finitos.length === 0) return 44

  const extremos = [Math.min(...finitos, 0), Math.max(...finitos, 0)]
  const comFolga = extremos.map((v) => v * 1.25)
  const maisLargo = [...extremos, ...comFolga]
    .map((v) => formatTick(v, formato).length)
    .reduce((a, b) => Math.max(a, b), 0)

  return Math.min(120, Math.max(44, maisLargo * 7 + 14))
}
