import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

/**
 * **Nenhum número vira texto sem passar por pt-BR.**
 *
 * O mesmo descuido já apareceu **três** vezes neste projeto: a S8 achou `2.55%`,
 * a S15 achou `51.76%` ao lado de `109,0%` na mesma tela, e o usuário achou
 * `66.87% Pago` e `38.97% Pago` na lista de renegociações. Sempre o ponto decimal
 * de JavaScript escapando para uma tela em português — e sempre passando por
 * `tsc` e pela suíte, porque nada disso é erro de tipo.
 *
 * A varredura pega a forma que causou as três: **`toFixed` com casa decimal
 * costurado dentro de um texto**. `toFixed` escreve `72.5`; `Intl.NumberFormat`
 * com o locale do app escreve `72,5`. Os helpers de `lib/utils/number`
 * (`formatMoney`, `formatAmount`, `formatPercent`, `localizePercentLabel`) são o
 * caminho, e existe um só para não haver duas decisões de arredondamento.
 *
 * O que a regra **não** proíbe, de propósito:
 *
 * - `toFixed` fora de interpolação — `paraDecimalString` em
 *   `features/indicators/lib/periodo.ts` produz a string `decimal(15,2)` que a
 *   **API** recebe. Ali o ponto é o certo, e trocá-lo quebraria o servidor.
 * - `toFixed(0)`, que não escreve separador nenhum.
 * - percentual dentro de `style`/CSS (`width: ${x}%`), onde o ponto é a sintaxe.
 */
const SRC = path.resolve(__dirname, '..')

/** `${… .toFixed(2) …}` num literal de template, ou `{x.toFixed(1)}` em JSX. */
const TOFIXED_EM_TEXTO = [
  /\$\{[^}\n]*\.toFixed\([1-9]\d*\)/g,
  /\.toFixed\([1-9]\d*\)[ \t]*\}/g,
]

function fontes(dir: string, acc: string[] = []): string[] {
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    const completo = path.join(dir, entrada.name)
    if (entrada.isDirectory()) {
      // A varredura não se lê: este arquivo cita os padrões que proíbe.
      if (entrada.name === '__tests__' || entrada.name === 'test') continue
      fontes(completo, acc)
    } else if (/\.tsx?$/.test(entrada.name)) {
      acc.push(completo)
    }
  }
  return acc
}

describe('§5.4 — número que vira texto passa por Intl pt-BR', () => {
  const arquivos = fontes(SRC)

  it('nenhum `toFixed` com casa decimal costurado dentro de um texto', () => {
    const achados: Record<string, string[]> = {}
    for (const arquivo of arquivos) {
      const fonte = fs.readFileSync(arquivo, 'utf8')
      const hits = TOFIXED_EM_TEXTO.flatMap((re) => fonte.match(re) ?? [])
      if (hits.length) achados[path.relative(SRC, arquivo)] = [...new Set(hits)]
    }
    expect(achados).toEqual({})
  })
})
