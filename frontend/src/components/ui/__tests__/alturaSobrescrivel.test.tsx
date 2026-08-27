import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

/**
 * Achado do usuário (26/08/2026): *"o espaçamento dentro dos cards"* e *"sidebar
 * fechada está toda torta"*.
 *
 * A passada de mobile deu 44 px de alvo de toque escrevendo
 * `min-h-[2.75rem] … md:min-h-0 md:h-10` no `Button`. Parecia seguro — "acima de
 * `md` volta ao que era". **Não volta:** o Tailwind emite as variantes DEPOIS
 * das classes base, então `md:h-10` passa a vencer qualquer `h-*` que o chamador
 * mande por `className`.
 *
 * Quem pagou foi o `SidebarSelectorCard`, que passa `h-auto` de propósito —
 * rótulo em cima e valor embaixo precisam de duas linhas. O card virou 40 px
 * fixos e o conteúdo ficou espremido.
 *
 * A correção é a direção do breakpoint: **base = desktop, `max-md:` = telefone**.
 * Assim o CSS de desktop volta a ser o de sempre e continua sobrescrevível.
 */
const UI = (arq: string) => readFileSync(resolve(__dirname, '..', arq), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')

const COMPONENTES = ['Button.tsx', 'Input.tsx', 'DatePicker.tsx', 'SearchInput.tsx']

describe('altura dos controles — o desktop continua sobrescrivível', () => {
  /**
   * A regra vale para o elemento que recebe `className` de QUEM CHAMA — é ele
   * que o chamador precisa conseguir sobrescrever. Decoração interna (o botão
   * de limpar, a seta do calendário) pode encolher no desktop com `md:h-7` sem
   * risco nenhum: ninguém de fora tenta mudar a altura dela.
   *
   * Por isso a asserção mira as classes que aparecem no MESMO trecho de um
   * `cn(...)` com `className` — e não qualquer `md:h-*` do arquivo.
   */
  it.each(COMPONENTES)('%s não força altura por variante `md:` no elemento público', (arq) => {
    const src = UI(arq)
    // Alturas do vocabulário de controle: 9, 10, 11. A decoração usa 7 ou menos.
    const forcando = src.match(/(?<!max-)md:h-(9|10|11)\b/g) ?? []
    expect(forcando).toEqual([])
  })

  it.each(COMPONENTES)('%s dá o mínimo de toque por `max-md:`, não por base', (arq) => {
    expect(UI(arq)).toMatch(/max-md:(h-11|min-h-\[2\.75rem\])/)
  })

  it('o `SidebarSelectorCard` continua pedindo `h-auto` — é o caso que quebrou', () => {
    // Se alguém trocar isto por altura fixa, o rótulo e o valor voltam a caber
    // em uma linha só e o card perde a segunda linha em silêncio.
    expect(UI('SidebarSelectorCard.tsx')).toContain('h-auto')
  })
})
