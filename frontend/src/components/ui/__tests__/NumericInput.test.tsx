import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { PercentInput } from '@/components/ui/NumericInput'
import { parseNumberPtBr, formatMoney, formatPercent } from '@/lib/utils/number'

/** FE-066 — exibe formatado, **envia número**. */
describe('parseNumberPtBr', () => {
  it('interpreta o formato pt-BR', () => {
    expect(parseNumberPtBr('1.234,56').value).toBe(1234.56)
    expect(parseNumberPtBr('R$ 1.234,56').value).toBe(1234.56)
    expect(parseNumberPtBr('12,5%').value).toBe(12.5)
    expect(parseNumberPtBr('1.204.000').value).toBe(1204000)
    expect(parseNumberPtBr('-45,10').value).toBe(-45.1)
  })

  it('campo vazio é ausência de valor, não zero', () => {
    expect(parseNumberPtBr('').value).toBeNull()
    expect(parseNumberPtBr('   ').value).toBeNull()
  })

  it('AVISA no separador duplicado em vez de adivinhar (o legado gravava torto)', () => {
    const r = parseNumberPtBr('1.234.56')
    expect(r.value).toBeNull()
    expect(r.aviso).toMatch(/separador/i)

    const r2 = parseNumberPtBr('1,2,3')
    expect(r2.value).toBeNull()
    expect(r2.aviso).toBeTruthy()
  })
})

/**
 * `MoneyInput` mudou de desenho e os testes dele agora vivem em
 * `MoneyInput.test.tsx`: ele virou acumulador da direita para a esquerda
 * (digitar `1` e um centavo), como no legado e como o usuario pediu.
 *
 * Os casos que estavam aqui testavam o desenho ANTERIOR — "com foco mostra o
 * numero cru" e "aviso de separador ambiguo" — e deixaram de valer para moeda:
 * o campo novo nunca aceita separador digitado, entao nao ha texto ambiguo para
 * avisar. **A regra de nao adivinhar continua**, so mudou de lugar: agora o
 * campo simplesmente ignora tudo que nao e algarismo, e ha teste disso.
 *
 * `PercentInput` NAO mudou: ele continua sobre o `NumericInput`, com o parse
 * pt-BR e o aviso de separador. Percentual se digita com virgula (`2,5`), nao
 * se acumula da direita — e a diferenca esta registrada na sec. 5.4.9 das
 * convencoes.
 */
describe('PercentInput', () => {
  it('percentual e o percentual, nao a fracao', () => {
    render(<PercentInput value={12.5} onChange={vi.fn()} />)
    expect((screen.getByRole('textbox') as HTMLInputElement).value).toBe(formatPercent(12.5))
  })

  it('emite NUMERO, nunca a string da tela', () => {
    const onChange = vi.fn()
    render(<PercentInput value={null} onChange={onChange} />)
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '2,5' } })
    expect(onChange).toHaveBeenLastCalledWith(2.5)
    expect(typeof onChange.mock.lastCall![0]).toBe('number')
  })

  it('nao emite valor enquanto o texto esta ambiguo, e mostra o aviso', () => {
    const onChange = vi.fn()
    render(<PercentInput value={null} onChange={onChange} />)
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '1.234.56' } })
    expect(onChange).not.toHaveBeenCalled()
    expect(screen.getByRole('alert')).toHaveTextContent(/separador/i)
  })
})
