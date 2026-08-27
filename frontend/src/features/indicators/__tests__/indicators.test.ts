import { describe, expect, it } from 'vitest'
import { sanitizeRichText } from '@/components/ui/RichTextField'
import {
  anosDisponiveis,
  formatarValor,
  nomeDoMes,
  paraDecimalString,
  paraNumero,
} from '../lib/periodo'

/**
 * S10 — o que o front decide sozinho, travado por teste.
 *
 * Dois blocos, e os dois são regra, não estética: a **sanitização** (UF-1, XSS
 * armazenado com alcance de tenant) e a **distinção entre "não lançado" e
 * "zero"** (DEC-70), que é a leitura mais usada do módulo.
 */
describe('sanitizeRichText — UF-1', () => {
  it('mantém a formatação legítima da Instrução', () => {
    const html = '<p>Some o <strong>saldo</strong> e divida por <em>12</em>.</p><ul><li>Um</li></ul>'
    expect(sanitizeRichText(html)).toContain('<strong>saldo</strong>')
    expect(sanitizeRichText(html)).toContain('<li>Um</li>')
  })

  it('remove `<script>` inteiro — conteúdo junto', () => {
    const limpo = sanitizeRichText('<p>ok</p><script>alert(1)</script>')
    expect(limpo).not.toContain('script')
    expect(limpo).not.toContain('alert')
    expect(limpo).toContain('ok')
  })

  it('remove todo manipulador `on*`, que é o vetor mais direto', () => {
    const limpo = sanitizeRichText('<p onclick="roubar()">texto</p>')
    expect(limpo).not.toContain('onclick')
    expect(limpo).toContain('texto')
  })

  it('recusa `javascript:` no href e mantém o texto do link', () => {
    const limpo = sanitizeRichText('<a href="javascript:alert(1)">clique</a>')
    expect(limpo).not.toContain('javascript')
    expect(limpo).toContain('clique')
  })

  it('aceita http, https e mailto, e fecha o link com rel/target', () => {
    const limpo = sanitizeRichText('<a href="https://exemplo.com">site</a>')
    expect(limpo).toContain('href="https://exemplo.com"')
    expect(limpo).toContain('rel="noopener noreferrer"')
  })

  it('desembrulha tag desconhecida sem perder o texto', () => {
    const limpo = sanitizeRichText('<marquee>importante</marquee>')
    expect(limpo).not.toContain('marquee')
    expect(limpo).toContain('importante')
  })

  it('`<iframe>` some inteiro', () => {
    expect(sanitizeRichText('<iframe src="http://x"></iframe>')).toBe('')
  })

  it('vazio e nulo devolvem string vazia — nunca "undefined" na tela', () => {
    expect(sanitizeRichText(null)).toBe('')
    expect(sanitizeRichText(undefined)).toBe('')
    expect(sanitizeRichText('')).toBe('')
  })
})

/**
 * `Intl` separa o símbolo do número com espaço **não-quebrável** (U+00A0), que é
 * o certo tipograficamente e invisível numa comparação de string. Normalizar no
 * teste evita a asserção que falha dizendo `'R$ 0,00' !== 'R$ 0,00'`.
 */
function semNbsp(texto: string | null): string | null {
  return texto === null ? null : texto.replace(/\u00a0/g, ' ')
}

describe('período da grade — DEC-70 e DEC-10', () => {
  it('"não lançado" (`null`) NÃO vira zero', () => {
    // É a regra inteira num exemplo: o legado renderizava `0` aqui, e por isso
    // ausência e zero eram indistinguíveis na tela.
    expect(paraNumero(null)).toBeNull()
    expect(formatarValor(null)).toBeNull()
  })

  it('zero lançado é zero de verdade, e formatado', () => {
    expect(paraNumero('0.0')).toBe(0)
    expect(semNbsp(formatarValor('0.0'))).toBe('R$ 0,00')
  })

  it('formata em pt-BR com duas casas, e aceita negativo', () => {
    expect(semNbsp(formatarValor('1234.5'))).toBe('R$ 1.234,50')
    expect(semNbsp(formatarValor('-99.9'))).toBe('-R$ 99,90')
  })

  it('o valor sai como STRING com duas casas — decimal não passa por float', () => {
    expect(paraDecimalString(1234.5)).toBe('1234.50')
    expect(paraDecimalString(-99.9)).toBe('-99.90')
  })

  it('os meses saem em pt-BR e capitalizados, como o `.camelize` do legado', () => {
    expect(nomeDoMes(1)).toBe('Janeiro')
    expect(nomeDoMes(12)).toBe('Dezembro')
  })

  it('a janela de anos é atual −5 a +5 — ONZE anos, como o `ten_years_array`', () => {
    const anos = anosDisponiveis(2026)
    expect(anos).toHaveLength(11)
    expect(anos[0]).toBe(2021)
    expect(anos[10]).toBe(2031)
  })
})
