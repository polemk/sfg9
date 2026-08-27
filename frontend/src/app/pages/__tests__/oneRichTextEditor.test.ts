import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'

/**
 * S12 / tarefa 5.20 — **um editor rich text só** (flag F-14 / DEC-63).
 *
 * A base chegou com **dois**: Slate, em uso em `RichTextEditor.tsx`, e TipTap,
 * declarado no `package.json` **sem nenhum consumidor**. Dois editores é peso de
 * bundle e ambiguidade para quem chegar depois — a DEC-63 removeu o TipTap do
 * `package.json`.
 *
 * Este teste é a trava: ele reprova se `@tiptap/*` voltar, por import em
 * qualquer arquivo do front **ou** por dependência declarada. Sem ele, a
 * remoção dura até o primeiro `npm install` de alguém que "precisava de um
 * editor".
 */
const RAIZ = resolve(__dirname, '../../..')

function arquivosDeCodigo(dir: string, acc: string[] = []): string[] {
  for (const entrada of readdirSync(dir)) {
    if (entrada === 'node_modules' || entrada === 'dist' || entrada.startsWith('.')) continue
    const caminho = join(dir, entrada)
    if (statSync(caminho).isDirectory()) arquivosDeCodigo(caminho, acc)
    else if (/\.(ts|tsx|js|jsx)$/.test(entrada)) acc.push(caminho)
  }
  return acc
}

describe('um editor rich text só (F-14 / DEC-63)', () => {
  it('nenhum arquivo do front importa `@tiptap/*`', () => {
    const infratores = arquivosDeCodigo(RAIZ).filter((caminho) => {
      const conteudo = readFileSync(caminho, 'utf8')
      return /from\s+['"]@tiptap\/|require\(['"]@tiptap\//.test(conteudo)
    })

    expect(infratores).toEqual([])
  })

  it('`@tiptap/*` não está no `package.json`', () => {
    const pkg = JSON.parse(readFileSync(resolve(RAIZ, '../package.json'), 'utf8'))
    const deps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) }
    expect(Object.keys(deps).filter((d) => d.startsWith('@tiptap/'))).toEqual([])
  })

  it('o editor em uso continua sendo o Slate', () => {
    const editor = readFileSync(resolve(RAIZ, 'components/RichTextEditor.tsx'), 'utf8')
    expect(editor).toMatch(/from ['"]slate-react['"]/)
  })
})
