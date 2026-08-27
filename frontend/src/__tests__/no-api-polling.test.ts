import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

/**
 * Princípio 10 — **nenhuma tela do Safegold consulta a API em intervalo fixo.**
 *
 * O legado tinha uma única instanciação de `PollingManager` (o monitor de usuário
 * da navbar, 1 requisição por segundo) e ela já estava desligada — por isso FE-480
 * é `dropped`, não "conversão de polling para realtime". O que este teste protege
 * não é o passado: é o futuro. Um `setInterval` chamando a API é a solução óbvia
 * para "a tela precisa saber quando o job terminou", e ela funciona — até a décima
 * aba aberta.
 *
 * O caminho certo é `useJobProgress` / `useChannel`: o servidor avisa, o React Query
 * revalida.
 *
 * Timer que NÃO fala com a API (contagem regressiva, carrossel) é permitido — o que
 * o princípio proíbe é a requisição periódica.
 */
const SRC = path.resolve(__dirname, '..')

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === '__tests__') continue
      walk(full, acc)
    } else if (/\.tsx?$/.test(entry.name)) {
      acc.push(full)
    }
  }
  return acc
}

// `useAutoRefresh.ts` é um helper de polling da base ai9 SEM NENHUM CONSUMIDOR
// (flag 16 de upstream). Ele fica onde está — a base pode querer —, mas nenhuma
// tela do Safegold o usa, e este teste é o que garante que continue assim.
const HELPER_DE_POLLING = 'useAutoRefresh'

/**
 * **O comentário não é código.**
 *
 * A varredura procura `setInterval` no fonte cru, e o arquivo que **documenta**
 * a proibição naturalmente escreve a palavra proibida — foi o que aconteceu com
 * `lib/api/dashboard.ts` (S15), reprovado por um comentário que dizia
 * literalmente "nenhuma consulta usa `setInterval`". Reprovar a documentação da
 * própria regra é o pior incentivo possível: o próximo autor deixa de nomear o
 * que está proibindo, e a regra vira folclore.
 *
 * O corte é o mesmo que `riskOperations.test.tsx` e `dashboard.test.tsx` já
 * usam: comparar contra o texto **sem comentário de linha nem de bloco**. Isto
 * não afrouxa a regra — `setInterval` de verdade continua sendo código.
 */
function semComentarios(texto: string): string {
  return texto.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')
}

describe('Princípio 10 — nada de polling de API', () => {
  const files = walk(SRC)

  it('nenhum arquivo combina setInterval com chamada à API', () => {
    const offenders = files.filter((file) => {
      const source = semComentarios(fs.readFileSync(file, 'utf8'))
      if (!/setInterval/.test(source)) return false
      // O sinal de "está batendo na API": o cliente HTTP ou um objeto `*Api`.
      return /apiClient\.|\bfetch\(|Api\.(get|post|put|patch|delete)\(/.test(source)
    })

    expect(offenders.map((f) => path.relative(SRC, f))).toEqual([])
  })

  it('o helper de polling da base continua sem consumidor no Safegold', () => {
    const consumers = files.filter(
      (file) =>
        !file.includes(`hooks/${HELPER_DE_POLLING}`) &&
        new RegExp(`\\b${HELPER_DE_POLLING}\\b`).test(fs.readFileSync(file, 'utf8'))
    )

    expect(consumers.map((f) => path.relative(SRC, f))).toEqual([])
  })
})
