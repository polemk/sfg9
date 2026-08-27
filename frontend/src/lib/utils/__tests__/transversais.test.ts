import { describe, it, expect, vi, afterEach } from 'vitest'
import { chopMiddleWords, sliceIn } from '../text'
import {
  timeAgo,
  toIsoDate,
  toIsoDateTime,
  monthOptions,
  yearWindow,
  nomeDoDiaDaSemanaPorIndice,
} from '../date'
import { formatMoney } from '../number'
import { avatarTone } from '@/components/ui/UserAvatar'

/**
 * S19 — os transversais de formatação. **Um utilitário por conceito**: cada
 * bloco aqui corresponde a um helper de view do legado que virou (ou já era)
 * uma função só nesta base.
 */

afterEach(() => vi.useRealTimers())

describe('chopMiddleWords (FE-434)', () => {
  it('devolve primeiro e último nome', () => {
    expect(chopMiddleWords('Maria da Silva Souza')).toBe('Maria Souza')
  })

  it('nome único passa inteiro', () => {
    expect(chopMiddleWords('Madonna')).toBe('Madonna')
  })

  it('entrada vazia devolve vazio, como no legado', () => {
    expect(chopMiddleWords('')).toBe('')
    expect(chopMiddleWords('   ')).toBe('')
  })

  // No legado `chop_middle_words(nil)` era NoMethodError, e o único consumidor
  // passava `current_user.formal`, que pode ser nulo.
  it('nulo não levanta', () => {
    expect(chopMiddleWords(null)).toBe('')
    expect(chopMiddleWords(undefined)).toBe('')
  })

  it('espaços repetidos não viram nomes vazios', () => {
    expect(chopMiddleWords('  Ana   Beatriz   Costa ')).toBe('Ana Costa')
  })
})

describe('sliceIn (FE-439)', () => {
  it('intercala em N colunas, como o legado', () => {
    expect(sliceIn([1, 2, 3, 4, 5], 2)).toEqual([[1, 3, 5], [2, 4]])
  })

  it('coluna sem item fica vazia, não some', () => {
    expect(sliceIn([1], 3)).toEqual([[1], [], []])
  })

  // No legado `slice_in(lista, 0)` devolvia `[]` e a lista inteira sumia.
  it('zero colunas NÃO descarta a lista', () => {
    expect(sliceIn([1, 2, 3], 0)).toEqual([[1, 2, 3]])
  })

  it('aceita filtro, como o bloco do legado', () => {
    expect(sliceIn([1, 2, 3, 4], 2, (n) => n % 2 === 0)).toEqual([[2], [4]])
  })
})

describe('timeAgo (FE-430)', () => {
  it('é UM utilitário e produz texto relativo em pt-BR', () => {
    vi.useFakeTimers().setSystemTime(new Date('2026-03-10T12:00:00Z'))
    // O `date-fns` pt-BR diz "há 3 dias" no passado e "em 3 dias" no futuro.
    // O legado tinha DUAS formas para a mesma coisa: removia "aproximadamente"
    // no passado e o mantinha no futuro.
    expect(timeAgo('2026-03-07T12:00:00Z')).toBe('há 3 dias')
    expect(timeAgo('2026-03-13T12:00:00Z')).toBe('em 3 dias')
  })

  it('data inválida devolve o fallback em vez de "Invalid Date"', () => {
    expect(timeAgo('nada')).toBe('—')
    expect(timeAgo(null, 'N/A')).toBe('N/A')
  })
})

describe('ISO-8601 na fronteira (FE-440)', () => {
  it('dia de calendário sai como aaaa-mm-dd', () => {
    expect(toIsoDate('14/09/2026')).toBe('2026-09-14')
  })

  it('instante sai com fuso', () => {
    expect(toIsoDateTime(new Date('2026-09-14T15:04:05Z'))).toBe('2026-09-14T15:04:05.000Z')
  })

  it('nunca devolve formato brasileiro para a API', () => {
    expect(toIsoDate('14/09/2026')).not.toMatch(/\d{2}\/\d{2}\/\d{4}/)
    expect(toIsoDateTime('14/09/2026')).not.toMatch(/\d{2}\/\d{2}\/\d{4}/)
  })

  it('entrada inválida devolve null, não uma data inventada', () => {
    expect(toIsoDate('nada')).toBeNull()
    expect(toIsoDateTime('nada')).toBeNull()
  })
})

describe('monthOptions (FE-436)', () => {
  it('doze meses em pt-BR, com o valor 1..12 que o servidor espera', () => {
    const meses = monthOptions()
    expect(meses).toHaveLength(12)
    expect(meses[0]).toEqual({ value: 1, label: 'Janeiro' })
    expect(meses[11]).toEqual({ value: 12, label: 'Dezembro' })
  })
})

describe('yearWindow (FE-437)', () => {
  it('preserva a faixa do legado: ano-5 até ano+5', () => {
    const anos = yearWindow(5, new Date(2026, 0, 1))
    expect(anos[0]).toBe(2021)
    expect(anos[anos.length - 1]).toBe(2031)
    // O legado chamava de "ten_years" e devolvia ONZE. O intervalo é o que vale.
    expect(anos).toHaveLength(11)
  })
})

describe('nomeDoDiaDaSemanaPorIndice (FE-442)', () => {
  it('domingo e sábado NÃO ganham "-feira"', () => {
    expect(nomeDoDiaDaSemanaPorIndice(0)).toBe('Domingo')
    expect(nomeDoDiaDaSemanaPorIndice(6)).toBe('Sábado')
  })

  it('os dias úteis ganham', () => {
    expect(nomeDoDiaDaSemanaPorIndice(1)).toBe('Segunda-feira')
    expect(nomeDoDiaDaSemanaPorIndice(5)).toBe('Sexta-feira')
  })

  it('índice fora da faixa dá a volta, como o `% 7` do legado', () => {
    expect(nomeDoDiaDaSemanaPorIndice(7)).toBe('Domingo')
    expect(nomeDoDiaDaSemanaPorIndice(-1)).toBe('Sábado')
  })
})

describe('reuso — não há segunda implementação (FE-431, FE-433, FE-435)', () => {
  it('moeda é `formatMoney` de utils/number', () => {
    // O `Intl` separa o símbolo com espaço NÃO quebrável (U+00A0) — normalizar
    // aqui é o que impede a próxima pessoa de "consertar" a formatação.
    expect(formatMoney(1234.5).replace(/\u00a0/g, ' ')).toBe('R$ 1.234,50')
  })

  // FE-435: no legado `random_color` sorteava a cada render, e o mesmo item
  // mudava de cor ao rolar a lista.
  it('a cor de identificação é determinística', () => {
    expect(avatarTone('abc-123')).toBe(avatarTone('abc-123'))
    expect(avatarTone(42)).toBe(avatarTone(42))
  })
})
