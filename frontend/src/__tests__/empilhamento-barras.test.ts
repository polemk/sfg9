import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import tailwind from '../../tailwind.config.js'

/**
 * Achado do usuário (26/08/2026): *"no scroll o conteúdo da tela fica por cima
 * da topbar — acontece em todas as páginas que tem scroll"*.
 *
 * A causa não era transparência nem `overflow`: era **empate de z-index**. O
 * `PageHeader` e a `MobileTopBar` usavam os dois `z-sticky` (20), e no empate
 * quem pinta por cima é quem vem **depois no DOM** — que é sempre o conteúdo,
 * porque a barra é montada antes do `main`. Por isso valia para toda tela que
 * rola: todas usam `PageHeader`.
 *
 * A correção foi dar um degrau próprio às barras do app. Estes testes existem
 * porque a próxima pessoa a precisar de "um z um pouco mais alto" vai encostar
 * de novo no 20 se ninguém disser que ele é território do cabeçalho de página.
 */
const Z = (tailwind as any).theme.extend.zIndex as Record<string, string>

function fonte(caminho: string): string {
  return readFileSync(resolve(__dirname, '..', caminho), 'utf8')
}

/** Só o código: comentário citando um token não é uso dele. */
function codigo(caminho: string): string {
  return fonte(caminho)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/[^\n]*/g, '')
}

describe('empilhamento — as barras do app acima do cabeçalho de página', () => {
  it('`appbar` fica ACIMA de `sticky`', () => {
    expect(Number(Z.appbar)).toBeGreaterThan(Number(Z.sticky))
  })

  it('`appbar` fica ABAIXO de modal e das superfícies flutuantes', () => {
    expect(Number(Z.appbar)).toBeLessThan(Number(Z.modal))
    expect(Number(Z.appbar)).toBeLessThan(Number(Z['modal-backdrop']))
  })

  it('as três barras fixas do app usam `z-appbar`', () => {
    expect(fonte('components/mobile/MobileTopBar.tsx')).toContain('z-appbar')
    expect(fonte('components/mobile/MobileBottomBar.tsx')).toContain('z-appbar')
    expect(fonte('components/ConsoleTopbar.tsx')).toContain('z-appbar')
  })

  it('nenhuma das barras voltou a empatar em `z-sticky`', () => {
    for (const c of [
      'components/mobile/MobileTopBar.tsx',
      'components/mobile/MobileBottomBar.tsx',
      'components/ConsoleTopbar.tsx',
    ]) {
      expect(codigo(c)).not.toContain('z-sticky')
    }
  })

  it('o `PageHeader` continua em `z-sticky` — é conteúdo de página, não barra do app', () => {
    const src = codigo('components/PageHeader.tsx')
    expect(src).toContain('z-sticky')
    expect(src).not.toContain('z-appbar')
  })

  it('a barra de cima é OPACA — conteúdo rola por baixo dela e não pode ser visto através', () => {
    const src = codigo('components/mobile/MobileTopBar.tsx')
    expect(src).toContain('bg-background')
    // `glass-panel` é 88% de opacidade: o texto que passa embaixo aparece.
    expect(src).not.toContain('glass-panel')
  })
})
