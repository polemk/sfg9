import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

/**
 * S17 — **a marca do Safegold tem UMA fonte, e este teste é o portão dela.**
 *
 * A fatia S17 nasceu como "CRUD de temas com precedência e tokens em runtime" e
 * encolheu para "marca em fonte única" por duas decisões:
 *
 *  - **DEC-55** — a área de temas do legado NÃO é portada. O motor não pintava
 *    nada: `app_theme_template.css` tem 167 linhas e o arquivo **inteiro** está
 *    dentro de um comentário (abre `/*` na linha 1, fecha na 167, zero regras
 *    fora) — o defeito D-55. E a área não tinha item de menu (D-63).
 *  - **DEC-56** — `UserTheme` é descartado; a precedência passa a ter dois
 *    níveis (claro/escuro), não três.
 *
 * Sem CRUD de tema, a única coisa que impede a marca de se espalhar de novo em
 * `#hex` por dentro das telas é disciplina — e disciplina que ninguém mede
 * apodrece. Este teste é a §5.4.7 de `ai9-conventions.md` executada a cada
 * `vitest`, em vez de um `grep` que alguém lembra de rodar.
 *
 * **O que ele NÃO faz:** verificação visual. `tsc` limpo e este teste verde
 * convivem perfeitamente com um popover invisível — já conviveram. DEC-98 e
 * DEC-100 continuam exigindo abrir a tela nos dois modos e em 390×844.
 */
const SRC = path.resolve(__dirname, '..')

/** Onde a cor literal é legítima (§5.4.5 e §5.4.2). */
const ISENTOS = [
  // A definição dos tokens. É a fonte — é aqui que o hex mora.
  'styles/globals.css',
]

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === '__tests__') continue
      walk(full, acc)
    } else if (/\.(tsx?|css)$/.test(entry.name)) {
      acc.push(full)
    }
  }
  return acc
}

/**
 * Tira comentário antes de procurar cor.
 *
 * Isto não é preciosismo: quase toda menção a `#EB9600` ou a `bg-blue-500` que
 * sobra no repo está **em comentário**, explicando de onde o token veio ou o que
 * foi removido. Essa documentação é desejável; o que não pode é cor literal
 * chegando ao DOM. Um scanner que não separa os dois vira ruído e é desligado.
 */
function semComentarios(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, ' ') // bloco /* … */ (cobre o {/* … */} do JSX)
    .replace(/(^|[^:])\/\/.*$/gm, '$1 ') // linha // … , preservando "https://"
}

function ocorrencias(source: string, re: RegExp): string[] {
  return source.match(re) ?? []
}

/** Paleta literal do Tailwind — a que existe fora do nosso mapa semântico. */
const PALETA_LITERAL =
  /\b(?:bg|text|border|ring|from|via|to|fill|stroke|divide|shadow|outline|accent|caret|placeholder|decoration)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|white|black)(?:-\d{2,3})?(?:\/\d+)?\b/g

/** `#fff`, `#2D2D2A`, `#2D2D2AFF`. */
const HEX = /#[0-9a-fA-F]{3,8}\b/g

/**
 * `rgb()`/`rgba()` cravado. `hsl(var(--token))` **não** entra aqui de propósito:
 * é o token, só que escrito como string porque Recharts e afins não aceitam
 * classe Tailwind. Cor literal dentro de `hsl(…)` cai na regra do HEX ou dos
 * números soltos abaixo.
 */
const RGB_LITERAL = /\brgba?\(\s*\d/g

/** `hsl(0 0% 100%)` cravado — o mesmo pecado com outra notação. */
const HSL_LITERAL = /\bhsla?\(\s*[\d.]+[\s,]/g

/** z-index arbitrário: `z-[999]`. A escala nomeada existe justamente por isso. */
const Z_ARBITRARIO = /\bz-\[[^\]]+\]/g

/** Sombra e raio arbitrários — `shadow-e1|e2|e3` e `rounded-sm|md|lg` cobrem tudo. */
const ELEVACAO_ARBITRARIA = /\b(?:shadow|rounded)-\[[^\]]+\]/g

describe('§5.4 — a marca vem do token, e de mais lugar nenhum', () => {
  const files = walk(SRC).filter(
    (f) => !ISENTOS.some((isento) => f.endsWith(path.normalize(isento)))
  )

  function varrer(re: RegExp): Record<string, string[]> {
    const achados: Record<string, string[]> = {}
    for (const file of files) {
      const hits = ocorrencias(semComentarios(fs.readFileSync(file, 'utf8')), re)
      if (hits.length) achados[path.relative(SRC, file)] = [...new Set(hits)]
    }
    return achados
  }

  it('nenhuma cor em `#hex` fora de comentário', () => {
    expect(varrer(HEX)).toEqual({})
  })

  it('nenhum `rgb()`/`rgba()` nem `hsl()` com número cravado', () => {
    expect(varrer(RGB_LITERAL)).toEqual({})
    expect(varrer(HSL_LITERAL)).toEqual({})
  })

  it('nenhuma classe de paleta literal do Tailwind (slate-, blue-, white…)', () => {
    expect(varrer(PALETA_LITERAL)).toEqual({})
  })

  it('nenhum z-index arbitrário — a escala nomeada cobre os onze casos', () => {
    expect(varrer(Z_ARBITRARIO)).toEqual({})
  })

  it('nenhuma sombra nem raio arbitrário', () => {
    expect(varrer(ELEVACAO_ARBITRARIA)).toEqual({})
  })

  /**
   * O sintoma que denuncia cor hardcodada mesmo quando o hex não aparece: se a
   * tela precisou de um `dark:` para consertar COR, o token não estava sendo
   * usado — porque token já troca sozinho entre os dois modos.
   *
   * `dark:` para o que não é cor (esconder/mostrar, inverter uma imagem) segue
   * legítimo; por isso a regra olha só as propriedades de cor.
   */
  it('nenhuma variante `dark:` consertando cor — token já troca sozinho', () => {
    const re =
      /\bdark:(?:bg|text|border|ring|from|via|to|fill|stroke|divide|placeholder|caret|accent|decoration|outline)-/g
    expect(varrer(re)).toEqual({})
  })
})

describe('DEC-55/DEC-56 — não existe área de tema para reconstruir', () => {
  const files = walk(SRC)

  /**
   * O legado tinha `/u/console/themes` com lista, detalhe e formulário, os três
   * respondendo erro (BE-375), sem autenticação nenhuma nos endpoints de escrita
   * (BE-384: **anônimo trocava o tema global**) e sem item de menu (D-63).
   *
   * Nada disso é portado. Este teste existe porque "adicionar uma telinha de
   * tema" é uma ideia que volta — e ela traria de volta um CRUD que no legado
   * nunca pintou um pixel.
   */
  it('nenhuma rota, tela ou chamada de API de CRUD de tema', () => {
    const re = /\/api\/v1\/themes|\/console\/themes|app_themes|override_css|UserTheme/g
    const offenders: Record<string, string[]> = {}
    for (const file of files) {
      const hits = ocorrencias(semComentarios(fs.readFileSync(file, 'utf8')), re)
      if (hits.length) offenders[path.relative(SRC, file)] = [...new Set(hits)]
    }
    expect(offenders).toEqual({})
  })
})

describe('DEC-93 — as variantes de logo existem como arquivo', () => {
  const BRAND = path.resolve(__dirname, '../../public/images/brand')

  /**
   * `SFG/theme.rb:47-57` declarava `_WHITE` e `_MONO` apontando **todas para o
   * mesmo arquivo colorido**: no legado não havia logo branco nem monocromático.
   * As três famílias abaixo são derivadas — a branca por remoção de fundo com
   * alpha real, a monocromática pelo canal alfa preenchido com uma cor só.
   */
  const ESPERADOS = [
    'safegold-logo.png',
    'safegold-logo-white.png',
    'safegold-logo-mono.png',
    'safegold-logo-mono-white.png',
    'safegold-wordmark.png',
    'safegold-wordmark-white.png',
    'safegold-wordmark-mono.png',
    'safegold-wordmark-mono-white.png',
    'safegold-symbol.png',
    'safegold-symbol-white.png',
    'safegold-symbol-mono.png',
    'safegold-symbol-mono-white.png',
    'safegold-icon-32.png',
    'safegold-icon-180.png',
    'safegold-icon-192.png',
    'safegold-icon-512.png',
    // Maskable tem arquivo PRÓPRIO, com fundo cheio: o Android recorta um
    // maskable transparente errado, e o símbolo sai mordido.
    'safegold-icon-maskable-512.png',
  ]

  it.each(ESPERADOS)('%s existe e não está vazio', (file) => {
    expect(fs.statSync(path.join(BRAND, file)).size).toBeGreaterThan(0)
  })

  it('todo caminho de logo citado no componente aponta para arquivo existente', () => {
    const source = fs.readFileSync(path.join(SRC, 'components/brand/Logo.tsx'), 'utf8')
    const caminhos = ocorrencias(source, /\/images\/brand\/[a-z0-9-]+\.png/g)

    expect(caminhos.length).toBeGreaterThan(0)
    for (const caminho of new Set(caminhos)) {
      expect(
        fs.existsSync(path.resolve(__dirname, '../../public', caminho.slice(1))),
        `${caminho} não existe em public/`
      ).toBe(true)
    }
  })

  /**
   * A marca desenhada à mão é o jeito mais fácil de a fonte única deixar de ser
   * única: um `<span>` estilizado com "Safegold", um `<img>` apontando direto
   * para o arquivo. Se precisa da marca, importa `<Logo>`.
   */
  it('nenhuma tela referencia o arquivo do logo direto — só o componente Logo', () => {
    const offenders = walk(SRC)
      .filter((f) => !f.endsWith(path.normalize('components/brand/Logo.tsx')))
      .filter((f) => /\/images\/brand\/safegold-(logo|wordmark|symbol)/.test(fs.readFileSync(f, 'utf8')))

    expect(offenders.map((f) => path.relative(SRC, f))).toEqual([])
  })
})
