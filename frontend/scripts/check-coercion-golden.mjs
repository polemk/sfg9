/**
 * Cross-check do contrato C2 (OPS-619) — o lado TS.
 *
 * Le o MESMO `golden/coercion.json` que `backend/spec/lib/sfg/coercion_spec.rb` le, e
 * confere `src/lib/utils/number.ts` contra ele. Existe porque formatacao divergente
 * entre a tela e a gravacao e o D-09 por outra porta: os dois lados precisam ler o
 * mesmo conjunto de casos, ainda que um deles divirja de proposito.
 *
 * O que ele checa, e a distincao importa:
 *
 *  - **Divergencias declaradas** (`frontend_divergences.parse_number_pt_br`): onde o
 *    front NAO reproduz o legado por decisao. O script exige que o front devolva o
 *    valor declarado como `frontend`. Se o front voltar a bater com o legado ali, e
 *    REGRESSAO, nao correcao — e o script reprova.
 *  - **`formatMoney`** contra os casos de `to_currency`, comparando so os digitos: o
 *    legado escreve `R$1.234,56` (sem espaco, sinal depois do simbolo) e o
 *    `Intl.NumberFormat` escreve `R$ 1.234,56` (com espaco duro, sinal antes). A
 *    diferenca e de tipografia e esta declarada aqui; o que NAO pode divergir e o
 *    numero.
 *
 * Rodar: `node --experimental-strip-types scripts/check-coercion-golden.mjs`
 * (o `vitest` nao roda neste ambiente; este script roda.)
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const goldenPath = resolve(here, '..', '..', 'golden', 'coercion.json')
const golden = JSON.parse(readFileSync(goldenPath, 'utf8'))

const { parseNumberPtBr, formatMoney } = await import('../src/lib/utils/number.ts')

const failures = []
let checks = 0

// 1. Divergencias declaradas: o front tem de devolver o valor DECLARADO.
for (const c of golden.frontend_divergences.parse_number_pt_br) {
  checks++
  const got = parseNumberPtBr(c.input).value
  if (got !== c.frontend) {
    failures.push(
      `parseNumberPtBr(${JSON.stringify(c.input)}) = ${got}, esperado ${c.frontend} (${c.why})`
    )
  }
}

// 2. Todo caso do legado que o front tambem aceita tem de dar o MESMO numero.
//    Os que o legado recusa (null) sao os que a divergencia declarada cobre.
const declarados = new Set(golden.frontend_divergences.parse_number_pt_br.map((c) => c.input))
for (const c of golden.string_to_number) {
  if (declarados.has(c.input)) continue
  checks++
  const got = parseNumberPtBr(c.input).value
  const esperado = c.legacy
  if (got !== esperado) {
    failures.push(
      `parseNumberPtBr(${JSON.stringify(c.input)}) = ${got}, o legado da ${esperado}` +
        ' — divergencia NAO declarada em golden/coercion.json'
    )
  }
}

// 3. formatMoney: mesmos digitos que o legado, tipografia propria.
const soDigitos = (s) => s.replace(/[^\d.,-]/g, '')
for (const c of golden.to_currency) {
  checks++
  const got = formatMoney(c.input)
  if (soDigitos(got) !== soDigitos(c.legacy)) {
    failures.push(`formatMoney(${c.input}) = ${JSON.stringify(got)}, o legado da ${JSON.stringify(c.legacy)}`)
  }
}

if (failures.length) {
  console.error(`FALHOU — ${failures.length} de ${checks} casos:`)
  for (const f of failures) console.error(`  - ${f}`)
  process.exit(1)
}

console.log(`OK — ${checks} casos conferidos contra golden/coercion.json`)
