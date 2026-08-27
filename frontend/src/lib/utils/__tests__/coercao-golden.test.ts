import { describe, it, expect } from "vitest"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, resolve } from "node:path"
import { parseNumberPtBr, formatMoney } from "@/lib/utils/number"

/**
 * **Cross-check do contrato C2 (OPS-619) — o lado TS.**
 *
 * Lê o MESMO `golden/coercion.json` que `backend/spec/lib/sfg/coercion_spec.rb`
 * lê, e confere `number.ts` contra ele. Existe porque formatação divergente
 * entre a tela e a gravação é o D-09 por outra porta: os dois lados precisam
 * ler o mesmo conjunto de casos, ainda que um deles divirja de propósito.
 *
 * ⚠ **Isto era `scripts/check-coercion-golden.mjs`, e nunca rodou.** O
 * cabeçalho dele dizia "o vitest não roda neste ambiente; este script roda" —
 * ficou invertido: o vitest roda (64 arquivos), e o script não, porque `node`
 * puro não resolve TypeScript nem o alias `@/`. Ele falhava com
 * `ERR_MODULE_NOT_FOUND` na primeira linha de import, e nada o chamava —
 * nenhum `package.json`, nenhum CI. Uma verificação de paridade que ninguém
 * executa não é verificação; é um arquivo.
 *
 * Sendo teste, ele roda junto com a suíte e não tem como morrer de novo.
 */
const aqui = dirname(fileURLToPath(import.meta.url))
const golden = JSON.parse(
  readFileSync(resolve(aqui, "..", "..", "..", "..", "..", "golden", "coercion.json"), "utf8"),
)

describe("coerção — o front contra o golden do legado (OPS-619)", () => {
  /**
   * Onde o front NÃO reproduz o legado, por decisão.
   *
   * A direção do exame importa: se o front voltar a **bater** com o legado
   * aqui, isso é REGRESSÃO e não correção — a divergência foi escolhida.
   */
  describe("divergências declaradas", () => {
    for (const c of golden.frontend_divergences.parse_number_pt_br) {
      it(`parseNumberPtBr(${JSON.stringify(c.input)}) → ${c.frontend} · ${c.why}`, () => {
        expect(parseNumberPtBr(c.input).value).toBe(c.frontend)
      })
    }
  })

  /**
   * Todo caso do legado que o front também aceita tem de dar o MESMO número.
   * Divergir aqui sem estar declarado no golden reprova.
   */
  describe("casos não declarados — têm de bater com o legado", () => {
    const declarados = new Set(
      golden.frontend_divergences.parse_number_pt_br.map((c: { input: string }) => c.input),
    )
    for (const c of golden.string_to_number) {
      if (declarados.has(c.input)) continue
      it(`parseNumberPtBr(${JSON.stringify(c.input)}) → ${c.legacy}`, () => {
        expect(parseNumberPtBr(c.input).value).toBe(c.legacy)
      })
    }
  })

  /**
   * `formatMoney`: mesmos dígitos, tipografia própria.
   *
   * O legado escreve `R$1.234,56` (sem espaço, sinal depois do símbolo); o
   * `Intl.NumberFormat` escreve `R$ 1.234,56` (espaço duro, sinal antes). A
   * diferença é de tipografia e está declarada. O que **não** pode divergir é
   * o número — por isso a comparação tira tudo que não é dígito, vírgula,
   * ponto ou sinal.
   */
  describe("formatMoney — o número tem de bater, a tipografia não", () => {
    const soDigitos = (s: string) => s.replace(/[^\d.,-]/g, "")
    for (const c of golden.to_currency) {
      it(`formatMoney(${c.input}) ≡ ${JSON.stringify(c.legacy)}`, () => {
        expect(soDigitos(formatMoney(c.input))).toBe(soDigitos(c.legacy))
      })
    }
  })
})
