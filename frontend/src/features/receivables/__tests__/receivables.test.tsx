import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { CONSOLE_NAV_GROUPS } from '@/app/consoleNavigation'

/**
 * S6 — os testes de contrato do bloco de recebíveis **no front**.
 *
 * Os goldens de fórmula estão no backend
 * (`spec/services/receivables/calculator_spec.rb`, 131 linhas de produção). Aqui
 * o que se prova é o que só o front pode quebrar.
 */

// ======================================================================
// 4.28 — FONTE ÚNICA: nenhuma fórmula do calculador pode reaparecer aqui
// ======================================================================
describe('C2 / D-09 — a conta do borderô não existe no front', () => {
  // `import.meta.url` aponta para dentro de `__tests__`; subir três níveis dá
  // `src/`. `fileURLToPath` em vez de `.pathname` porque este último devolve
  // um caminho relativo à raiz do Vite, e o `readdirSync` procurava em `/src`.
  const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')

  function arquivos(dir: string, acc: string[] = []): string[] {
    for (const nome of readdirSync(dir)) {
      const caminho = join(dir, nome)
      if (statSync(caminho).isDirectory()) {
        if (['node_modules', '__tests__', 'dist'].includes(nome)) continue
        arquivos(caminho, acc)
      } else if (/\.tsx?$/.test(nome)) {
        acc.push(caminho)
      }
    }
    return acc
  }

  /**
   * As marcas de uma reimplementação da fórmula. **Não é busca por palavra
   * bonita**: cada uma corresponde a uma operação concreta do
   * `Receivables::Calculator`.
   *
   * - `**` / `Math.pow` — os sete custos efetivos são potências;
   * - `0.000041` / `0.0038` — as alíquotas de IOF;
   * - `0.0333` — o expoente literal de `calc_valor_liq_correto`;
   * - `/ 30` sobre prazo — a conversão para taxa mensal.
   *
   * No legado a conta existia em JavaScript
   * (`../sfg/app/views/pub/receivables/new/_body.js.erb:339-504`), **parcial** e
   * com outro arredondamento. O usuário via um número na tela e outro depois de
   * salvar, e não havia como dizer qual estava certo (D-09). Este teste é o que
   * impede a fórmula de voltar por um atalho de "só para não piscar".
   */
  const MARCAS: { padrao: RegExp; porque: string }[] = [
    { padrao: /Math\.pow\s*\(/, porque: 'potência — os sete CETs são potências, e elas vivem no servidor' },
    { padrao: /\*\*\s*\(?\s*30\s*\//, porque: 'expoente `30 / prazo` — é a conversão do CET' },
    { padrao: /0\.000041/, porque: 'alíquota diária de IOF — ela vem de `IofRate`, no servidor' },
    { padrao: /0\.0038(?![0-9])/, porque: 'alíquota fixa de IOF' },
    { padrao: /0\.0333/, porque: 'o expoente literal de `calc_valor_liq_correto`' },
  ]

  /**
   * Só interessa `Math.pow` num arquivo que **fala de borderô**.
   *
   * A primeira versão deste teste varria `src` inteiro e acusava
   * `ParticlesBackground`, `PaginationPill` e `useCountUp` — animação, degraus
   * de paginação e suavização de contador. Um teste que reprova três arquivos
   * inocentes vira um teste que alguém desliga; então o critério passa a ser
   * "potência **perto de** um campo derivado do borderô".
   */
  const CAMPOS_DO_BORDERO =
    /(valor_liquido|vlr_bruto_final|custo_efetivo|taxa_desconto_nominal|prz_med_pond|tarifas_(desagio|iof|ad_valorem)|calc_valor_liq_correto|checagem_iof)/

  it('nenhum arquivo que fala de borderô reimplementa uma fórmula do calculador', () => {
    const achados: string[] = []
    for (const caminho of arquivos(RAIZ)) {
      if (caminho.endsWith('receivables.test.tsx')) continue
      const conteudo = readFileSync(caminho, 'utf8')
      if (!CAMPOS_DO_BORDERO.test(conteudo)) continue
      for (const { padrao, porque } of MARCAS) {
        if (padrao.test(conteudo)) achados.push(`${caminho.replace(RAIZ, '')}: ${padrao} — ${porque}`)
      }
    }
    expect(achados, `fórmula de borderô encontrada no front:\n${achados.join('\n')}`).toEqual([])
  })

  it('a varredura está OLHANDO os arquivos do borderô — senão ela passaria vazia', () => {
    // Um teste de varredura que não encontra nada porque não olhou nada é o
    // pior tipo de verde. Aqui se prova que o conjunto examinado inclui as
    // telas da fatia.
    const examinados = arquivos(RAIZ)
      .filter((c) => !c.endsWith('receivables.test.tsx'))
      .filter((c) => CAMPOS_DO_BORDERO.test(readFileSync(c, 'utf8')))
      .map((c) => c.replace(RAIZ, ''))

    expect(examinados).toContain('/lib/api/receivables.ts')
    expect(examinados).toContain('/features/receivables/components/CalculationPanel.tsx')
    expect(examinados.length).toBeGreaterThanOrEqual(4)
  })

  it('o cliente de recebíveis não expõe nenhuma função de cálculo', () => {
    const cliente = readFileSync(join(RAIZ, 'lib/api/receivables.ts'), 'utf8')
    // Ele monta parâmetros e lê o envelope de paginação. Nada mais.
    expect(cliente).not.toMatch(/function\s+calcul/i)
    expect(cliente).toMatch(/preview:/)
  })
})

// ======================================================================
// OPS-159 / D-117 — nulo NÃO é zero
// ======================================================================
describe('OPS-159 / D-117 — nulo e zero são distinguíveis', () => {
  // No legado toda exibição passava por `to_currency`, que faz `value.to_f`, e
  // `nil.to_f` é `0.0`: "não informado" e "zero reais" viravam o mesmo
  // `R$ 0,00`. Num sistema de crédito isso é informação perdida — vários
  // derivados do borderô são LEGITIMAMENTE nulos (as guardas `< 1` do legado
  // devolvem `nil`, e em 97% dos borderôs de produção a de IOF dispara).
  it('`formatMoney(null)` rende travessão e `formatMoney(0)` rende R$ 0,00', () => {
    expect(formatMoney(null)).toBe('—')
    expect(formatMoney(undefined)).toBe('—')
    expect(formatMoney(0)).not.toBe('—')
    expect(formatMoney(0)).toMatch(/0,00/)
  })

  it('o mesmo vale para percentual — o CET nulo não pode virar 0%', () => {
    expect(formatPercent(null)).toBe('—')
    expect(formatPercent(0)).toMatch(/0,00%/)
  })

  it('o CET é formatado em pt-BR com 4 casas (FE-162)', () => {
    // No legado o CET saía **cru** na tela.
    expect(formatPercent(2.0612, 4)).toBe('2,0612%')
  })
})

// ======================================================================
// A navegação e a rota — menu que leva a 404 é pior que menu curto
// ======================================================================
describe('S6 — as seis telas estão montadas e alcançáveis', () => {
  const itens = CONSOLE_NAV_GROUPS.flatMap((g) => g.items)

  it.each([
    ['receivables', '/receivables'],
    ['charges', '/charges'],
    ['wallets', '/wallets'],
    ['receivable_kinds', '/receivable-kinds'],
    ['movement_kinds', '/movement-kinds'],
  ])('o item «%s» aponta para %s e tem tela', (id, path) => {
    const item = itens.find((i) => i.id === id)
    expect(item, `item ${id} sumiu do menu`).toBeTruthy()
    expect(item!.path).toBe(path)
    expect(item!.element, `a tela de ${id} não está montada`).not.toBeNull()
  })

  it('o formulário de borderô tem rota própria, e `novo` vem ANTES de `:id`', () => {
    // O React Router casa na ordem: com `:id` na frente, `/receivables/novo`
    // cairia na rota de detalhe com o id literal `"novo"` e o formulário
    // tentaria carregar um borderô inexistente.
    const receivables = itens.find((i) => i.id === 'receivables')!
    const filhos = (receivables as { children?: { path: string }[] }).children ?? []
    expect(filhos.map((f) => f.path)).toEqual(['novo', ':id'])
  })

  it('nenhum item da fatia nasce travado', () => {
    for (const id of ['receivables', 'charges', 'wallets', 'receivable_kinds', 'movement_kinds']) {
      const item = itens.find((i) => i.id === id)! as Record<string, unknown>
      expect(item.locked ?? false, `item ${id}`).toBe(false)
    }
  })
})
