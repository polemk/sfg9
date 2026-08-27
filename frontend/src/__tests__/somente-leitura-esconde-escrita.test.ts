import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

/**
 * **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108) — e
 * oito telas não o consultavam.
 *
 * A conta somente-leitura do elenco (Tereza, `demo-seed-design.md` §9) existe
 * para provar, ao vivo, que ela vê *"os mesmos dados, sem nenhum botão de
 * escrita"*. Medido renderizando com ela: `/receivables` mostrava "Novo
 * borderô", `/charges` mostrava "Nova cobrança", e o servidor recusava os dois
 * com 403. É a mesma família do defeito que o usuário já tinha achado em 14
 * telas — **oferecer o que o servidor recusa**.
 *
 * ## Por que um teste de FONTE
 *
 * O defeito não está em nenhuma tela: está na **ausência** de uma linha em
 * várias. Um teste de render prova a tela que ele monta; este prova que
 * nenhuma das dezenove ficou de fora, e reprova a vigésima no dia em que
 * alguém escrever `podeEscrever` sem o modificador. Mesmo desenho de
 * `marca-fonte-unica.test.ts`.
 *
 * ## O que ele NÃO substitui
 *
 * A recusa de verdade é do servidor (`require_not_readonly!` roda em todo
 * `/api/v1/*`). Esconder o botão é conveniência; as duas coisas, sempre.
 */
const SRC = path.resolve(__dirname, '..')

function varrer(dir: string, acc: string[] = []): string[] {
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    const cheio = path.join(dir, entrada.name)
    if (entrada.isDirectory()) {
      if (entrada.name === 'node_modules' || entrada.name === '__tests__') continue
      varrer(cheio, acc)
    } else if (entrada.name.endsWith('.tsx')) {
      acc.push(cheio)
    }
  }
  return acc
}

describe('DEC-108 — nenhuma tela oferece escrita ao somente-leitura', () => {
  const arquivos = varrer(SRC)

  it('toda definição de `podeEscrever` consulta o modificador', () => {
    const sem: string[] = []

    for (const arquivo of arquivos) {
      const fonte = fs.readFileSync(arquivo, 'utf8')
      for (const linha of fonte.split('\n')) {
        if (!/^\s*const podeEscrever\s*=/.test(linha)) continue
        // `!readonly` e `!somenteLeitura` são as duas formas em uso; as duas
        // saem de `useIsReadonly`.
        if (/!\s*(readonly|somenteLeitura)\b/.test(linha)) continue

        sem.push(`${path.relative(SRC, arquivo)}: ${linha.trim()}`)
      }
    }

    expect(sem).toEqual([])
  })

  it('quem define `podeEscrever` importa o hook', () => {
    const sem: string[] = []

    for (const arquivo of arquivos) {
      const fonte = fs.readFileSync(arquivo, 'utf8')
      if (!/^\s*const podeEscrever\s*=/m.test(fonte)) continue
      if (fonte.includes('useIsReadonly')) continue

      sem.push(path.relative(SRC, arquivo))
    }

    expect(sem).toEqual([])
  })
})
