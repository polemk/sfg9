import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { CONSOLE_NAV_GROUPS } from '@/app/consoleNavigation'

/**
 * S7 — os testes de contrato do bloco de operações de risco **no front**.
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * As seis migrations desta família estão entre as **24 que nunca subiram**
 * (`analise-dump-producao.md` §1). Os goldens de número estão no backend
 * (`spec/services/risk/chain_spec.rb` e vizinhos) e travam a leitura do **fonte
 * de 2022** — não há oráculo de produção para nenhum deles.
 *
 * Aqui se prova só o que **o front pode quebrar sozinho**.
 */

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
const RISCO = join(RAIZ, 'features/risk')

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
 * **O comentário não é código.** Metade das varreduras abaixo procura hex, `BRL`
 * e `dark:` — e os comentários desta fatia CITAM os três, de propósito, para
 * explicar por que não se usa nenhum deles. Comparar contra o arquivo cru
 * reprovaria exatamente a documentação que se quer manter. O `codigo` é o texto
 * sem comentário de linha nem de bloco.
 */
function semComentarios(texto: string): string {
  return texto
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
}

const FONTES = arquivos(RISCO).map((caminho) => {
  const texto = readFileSync(caminho, 'utf8')
  return { caminho, texto, codigo: semComentarios(texto) }
})

/** Só as telas da S7 — as da S5 (console, limites, catálogos) não são desta fatia. */
const ARQUIVOS_S7 = [
  'RiskOperationsPage.tsx',
  'RiskOperationDetailPage.tsx',
  'RiskOperationDrawer.tsx',
  'OperationGeneralTab.tsx',
  'MovementsTab.tsx',
  'MovementDrawer.tsx',
  'LastMovementCard.tsx',
  'ExtensionsTab.tsx',
  'ExtensionDrawer.tsx',
  'RenewalsCard.tsx',
  'RenewalDrawer.tsx',
  'CamposDoCartao.tsx',
]
const FONTES_S7 = FONTES.filter(({ caminho }) => ARQUIVOS_S7.some((nome) => caminho.endsWith(nome)))

it('a lista de arquivos da fatia está completa — nenhum ficou de fora da varredura', () => {
  expect(FONTES_S7.map((f) => f.caminho.split('/').pop()).sort()).toEqual([...ARQUIVOS_S7].sort())
})

// ======================================================================
// C2 — nenhum componente React soma saldo
// ======================================================================
describe('C2 — a cadeia de saldos não existe no front', () => {
  /**
   * As marcas de uma reimplementação da cadeia
   * (`prev + credit_type_value × movement_value`,
   * `../sfg/app/models/risk_operation.rb:104`). Se alguma aparecer, alguém
   * recriou no cliente o cálculo que o `Risk::Calculator` já faz — e a tela
   * passa a poder mostrar um número diferente do extrato (D-09).
   */
  const PROIBIDOS: Array<[RegExp, string]> = [
    [/movement_value_sign\s*\*\s*/, 'multiplicação pelo sinal do movimento'],
    [/\*\s*movement_value_sign/, 'multiplicação pelo sinal do movimento'],
    [/credit_type\s*===\s*'C'\s*\?\s*-1/, 'derivação do sinal a partir do credit_type'],
    [/saldo\s*\+=|balance\s*\+=/, 'acumulação de saldo'],
    [/reduce\([^)]*balance/, 'redução sobre saldo'],
  ]

  it.each(PROIBIDOS)('não reimplementa %s (%s)', (padrao) => {
    const culpados = FONTES_S7.filter(({ codigo }) => padrao.test(codigo)).map(({ caminho }) => caminho)
    expect(culpados).toEqual([])
  })

  it('o sufixo C/D vem do campo do servidor, não de uma dedução local', () => {
    const extrato = FONTES_S7.find(({ caminho }) => caminho.endsWith('MovementsTab.tsx'))!
    // O sufixo é FORMATAÇÃO replicada (FE-270): o `credit_type` chega pronto.
    expect(extrato.texto).toContain('m.credit_type')
  })
})

// ======================================================================
// §5.4 — nenhuma cor literal, nenhum `dark:` para consertar cor
// ======================================================================
describe('§5.4.2 — cor vem de token, sempre', () => {
  it('nenhum hex, rgb(), gradiente ou z-[] nas telas da fatia', () => {
    const culpados = FONTES_S7.filter(({ codigo }) =>
      /#[0-9a-fA-F]{3,6}\b|rgba?\(|bg-gradient|z-\[/.test(codigo),
    ).map(({ caminho }) => caminho)
    expect(culpados).toEqual([])
  })

  it('nenhuma classe de paleta literal do Tailwind', () => {
    const paleta = /\b(?:bg|text|border|ring)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d{2,3}\b|\b(?:bg|text)-(?:white|black)\b/
    const culpados = FONTES_S7.filter(({ codigo }) => paleta.test(codigo)).map(({ caminho }) => caminho)
    expect(culpados).toEqual([])
  })

  it('nenhum `dark:` — o token já muda sozinho entre os dois modos', () => {
    const culpados = FONTES_S7.filter(({ codigo }) => /\bdark:/.test(codigo)).map(({ caminho }) => caminho)
    expect(culpados).toEqual([])
  })

  it('valor monetário leva `font-numeric` (Fira Mono + tabular-nums)', () => {
    // Sem isso a coluna de valor de um borderô não alinha, e neste app isso é
    // defeito, não estética (§5.4.2).
    //
    // A classe pode vir **delegada**: `DetailList` aplica `font-numeric` a
    // todo item `numeric: true`, e `DataTable` faz o mesmo nas variantes
    // `money`/`number`/`percent`. Exigir a string literal na tela obrigaria a
    // duplicar o que a biblioteca já garante — que é o oposto do que a regra
    // quer.
    const comDinheiro = FONTES_S7.filter(({ codigo }) => codigo.includes('formatMoney'))
    expect(comDinheiro.length).toBeGreaterThan(0)
    const semFonte = comDinheiro.filter(
      ({ codigo }) => !codigo.includes('font-numeric') && !codigo.includes('numeric: true'),
    )
    expect(semFonte.map((f) => f.caminho)).toEqual([])
  })
})

// ======================================================================
// §5.4.9 — dinheiro é MoneyInput; a moeda vem da configuração
// ======================================================================
describe('§5.4.9 — campo monetário', () => {
  it('os campos de dinheiro usam MoneyInput, e a taxa usa PercentInput', () => {
    const formulario = FONTES_S7.find(({ caminho }) => caminho.endsWith('RiskOperationDrawer.tsx'))!
    expect(formulario.texto).toContain('MoneyInput')
    expect(formulario.texto).toContain('PercentInput')
    // A quarta e última cópia de máscara do legado eliminada (FE-262).
    expect(formulario.texto).not.toMatch(/replace\(\/\\D\/g/)
  })

  it("nenhuma tela crava 'BRL'", () => {
    const culpados = FONTES_S7.filter(({ codigo }) => /'BRL'|"BRL"/.test(codigo)).map((f) => f.caminho)
    expect(culpados).toEqual([])
  })
})

// ======================================================================
// C1 — erro de escopo é ESTADO, não toast
// ======================================================================
describe('C1 — escopo de projeto', () => {
  it('as duas telas usam ProjectScopeState com o recurso nomeado', () => {
    for (const arquivo of ['RiskOperationsPage.tsx', 'RiskOperationDetailPage.tsx']) {
      const tela = FONTES_S7.find(({ caminho }) => caminho.endsWith(arquivo))!
      expect(tela.texto).toContain('ProjectScopeState')
      expect(tela.texto).toContain('recurso="as operações de risco"')
    }
  })

  it('nenhuma tela manda project_id no payload — o servidor resolve', () => {
    const culpados = FONTES_S7.filter(({ codigo }) => /project_id:\s/.test(codigo)).map((f) => f.caminho)
    expect(culpados).toEqual([])
  })
})

// ======================================================================
// Princípio 10 — nada de polling
// ======================================================================
describe('Princípio 10 — sem polling', () => {
  it('nenhum setInterval nem refetchInterval', () => {
    const culpados = FONTES_S7.filter(({ codigo }) => /setInterval|refetchInterval/.test(codigo)).map((f) => f.caminho)
    expect(culpados).toEqual([])
  })
})

// ======================================================================
// DEC-100 — a lista tem versão mobile própria, com os três estados
// ======================================================================
describe('DEC-100 — mobile é view própria', () => {
  it('as três listas usam MobileCard, não tabela com rolagem', () => {
    for (const arquivo of ['RiskOperationsPage.tsx', 'MovementsTab.tsx', 'ExtensionsTab.tsx']) {
      const tela = FONTES_S7.find(({ caminho }) => caminho.endsWith(arquivo))!
      expect(tela.texto, arquivo).toContain('MobileCard')
      expect(tela.texto, arquivo).toContain('useMobile')
    }
  })

  it('as três listas passam pelo AsyncSection — carregando, vazio e ERRO', () => {
    // FE-276: no legado não há estado de erro em nenhuma das listas do
    // detalhe. Erro que parece vazio faz quem decide sobre carteira decidir
    // errado.
    for (const arquivo of ['RiskOperationsPage.tsx', 'MovementsTab.tsx', 'ExtensionsTab.tsx']) {
      const tela = FONTES_S7.find(({ caminho }) => caminho.endsWith(arquivo))!
      expect(tela.texto, arquivo).toContain('AsyncSection')
      expect(tela.texto, arquivo).toMatch(/error=\{consulta\.error\}/)
    }
  })

  it('a paginação mobile é a MobilePagination, não a régua do desktop', () => {
    for (const arquivo of ['RiskOperationsPage.tsx', 'MovementsTab.tsx', 'ExtensionsTab.tsx']) {
      const tela = FONTES_S7.find(({ caminho }) => caminho.endsWith(arquivo))!
      expect(tela.texto, arquivo).toContain('MobilePagination')
    }
  })
})

// ======================================================================
// DEC-01 — o sinal, e as duas leituras que convivem
// ======================================================================
describe('DEC-01 — o saldo inicial negativo é REPLICADO', () => {
  it('o DETALHE exibe `original_balance` (negativo) e o FORMULÁRIO edita o módulo', () => {
    const geral = FONTES_S7.find(({ caminho }) => caminho.endsWith('OperationGeneralTab.tsx'))!
    expect(geral.codigo).toContain('operacao.original_balance')
    // E não o campo em módulo — trocar aqui "consertaria" o D-93 sem DEC.
    expect(geral.codigo).not.toContain('original_balance_abs')

    const formulario = FONTES_S7.find(({ caminho }) => caminho.endsWith('RiskOperationDrawer.tsx'))!
    expect(formulario.codigo).toContain('original_balance_abs')
    // E nenhum `Math.abs` local: quem inverte o sinal é o servidor.
    expect(formulario.codigo).not.toContain('Math.abs')
  })
})

// ======================================================================
// DEC-35 — a renovação NÃO encerra a original, e a tela diz isso
// ======================================================================
describe('DEC-35 — o ciclo de vida do legado é replicado', () => {
  it('o drawer de renovação avisa que a original continua aberta', () => {
    const drawer = FONTES_S7.find(({ caminho }) => caminho.endsWith('RenewalDrawer.tsx'))!
    expect(drawer.texto).toMatch(/não<\/strong> é encerrada/)
  })

  it('nenhuma tela marca is_ended por conta própria ao renovar', () => {
    // O `tasks.md` pedia IMP-R1 (encerrar a original); a DEC-35 decidiu o
    // contrário, DEPOIS. Um front que "ajudasse" encerrando aqui contrariaria
    // a decisão do usuário e mudaria a exposição.
    const drawer = FONTES_S7.find(({ caminho }) => caminho.endsWith('RenewalDrawer.tsx'))!
    expect(drawer.codigo).not.toMatch(/is_ended:\s*true/)
  })
})

// ======================================================================
// D-92 — a aba é endereço de verdade
// ======================================================================
describe('D-92 — deep-link por aba', () => {
  it('o detalhe usa useSearchParams, não history.replaceState', () => {
    const detalhe = FONTES_S7.find(({ caminho }) => caminho.endsWith('RiskOperationDetailPage.tsx'))!
    expect(detalhe.codigo).toContain('useSearchParams')
    // O comentário CITA `history.replaceState` para explicar o D-92; o que não
    // pode existir é a chamada.
    expect(detalhe.codigo).not.toContain('replaceState')
  })
})

// ======================================================================
// A rota existe, e o item de menu aponta para ela
// ======================================================================
describe('a área está alcançável', () => {
  it('o item "Operações de Risco" tem página e rota de detalhe', () => {
    const itens = CONSOLE_NAV_GROUPS.flatMap((g) => g.items)
    const item = itens.find((i) => i.id === 'risk_operations')
    expect(item).toBeDefined()
    expect(item?.element).not.toBeNull()
    expect(item?.requiresProject).toBe(true)
    expect(item?.children?.some((c) => c.path === ':id')).toBe(true)
  })
})
