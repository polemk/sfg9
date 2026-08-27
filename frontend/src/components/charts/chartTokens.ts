/**
 * **Os tokens de cor que um gráfico usa** — e o registro de por que este arquivo
 * existe ao lado de `theme.ts`.
 *
 * `charts/theme.ts` é da base ai9 e **não é editado** (Princípio 6b). Ele expõe
 * `primary`, `accent`, `fgMuted`, `grid` e uma paleta categórica de seis cores
 * por índice. O que falta para um gráfico financeiro são os dois tokens de
 * **estado** — o mesmo par que o semáforo da tela de risco usa (FE-238) — com
 * nome, em vez de `defaultPalette()[4]`.
 *
 * Nada aqui é uma cor: são referências a variável CSS, resolvidas em runtime, e
 * por isso o mesmo componente serve claro e escuro sem um único `dark:`.
 *
 * ## O que foi MEDIDO, e muda a paleta desta fatia
 *
 * Contraste da marca sobre a superfície do card, pelo validador do `dataviz`:
 *
 * | token | claro (`#ffffff`) | escuro (`#20201d`) |
 * | ----- | ----------------: | -----------------: |
 * | `--primary` (ouro `#ffc105`) | **1,63:1** | passa |
 * | `--brand-gold-deep` (`#eb9500`) | **2,38:1** | passa |
 * | `--info` (`#2a47bb` / `#738ae8`) | passa | passa |
 * | `--success` (`#217d57` / `#30a66f`) | passa | passa |
 * | `--negative` (`#7b1f1e` / `#ce3b43`) | passa | passa |
 *
 * O mínimo para uma marca de dado é **3:1**. Ou seja: **o ouro da marca não pode
 * carregar dado no modo claro.** Ele continua sendo a cor de ação do produto
 * (botão primário, destaque); dentro do gráfico entra `--info`. Isto não é gosto
 * — é a razão pela qual o mesmo gráfico é legível nos dois modos.
 */
export const CHART_TOKENS = {
  /** A medida. Uma série, uma cor. */
  series: 'hsl(var(--info))',
  /** Estado bom — dentro do teto. O mesmo token do semáforo de limite. */
  positive: 'hsl(var(--success))',
  /** Estado ruim — disponível negativo, limite estourado. */
  negative: 'hsl(var(--negative))',
  /**
   * Estado de **atenção** — perto do teto, ainda não estourado.
   *
   * É `--warning-text`, e não `--warning`: medido no validador, o âmbar cheio
   * (`#e6ac00`) dá **2,05:1** sobre o card claro e não alcança o mínimo de 3:1
   * para marca de dado; `--warning-text` (`#9e6400` no claro, o ouro no escuro)
   * **passa nos dois modos**. O sufixo `-text` diz de onde ele veio, não onde
   * pode ser usado: o que qualifica um token para marca de dado é o contraste.
   */
  warning: 'hsl(var(--warning-text))',
  /** Trilho do medidor: o teto. Neutro, nunca a marca — ele é o fundo contra o
   *  qual o consumo é lido, não um dado. */
  track: 'hsl(var(--muted))',
} as const
