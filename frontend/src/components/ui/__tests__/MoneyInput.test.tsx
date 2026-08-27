import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import * as React from 'react'
import { MoneyInput } from '@/components/ui/NumericInput'
import { CURRENCIES } from '@/lib/config/currency'

/**
 * A regra, nas palavras do usuário: "conforme digita vai colocando as vírgulas e
 * pontos, ou seja ele é preenchido da direita para esquerda — se o user digitar
 * 1 é 0,01 ou seja um centavo, se ele digita 100 seria 1,00 ou seja um real".
 *
 * Estes testes existem porque a implementação ANTERIOR fazia o contrário de
 * propósito, com uma justificativa escrita no comentário. Sem eles, alguém lê
 * aquele raciocínio e "conserta" de volta.
 */

/**
 * O `Intl` separa o simbolo do numero com espaco NAO SEPARAVEL (U+00A0, e U+202F
 * em alguns locales). Comparar contra um espaco comum falha com as duas strings
 * parecendo identicas na tela — meia hora de depuracao para quem nao sabe.
 */
function txt(el: HTMLInputElement): string {
  return el.value.replace(/[\u00a0\u202f]/g, ' ')
}

/** Campo controlado de verdade — é o único jeito de testar acúmulo de dígitos. */
function Campo({ inicial = null, ...rest }: { inicial?: number | null } & Record<string, unknown>) {
  const [v, setV] = React.useState<number | null>(inicial)
  return <MoneyInput value={v} onChange={setV} aria-label="valor" {...rest} />
}

function digitar(input: HTMLInputElement, teclas: string) {
  for (const t of teclas) {
    fireEvent.change(input, { target: { value: input.value + t } })
  }
}

describe('MoneyInput — preenchimento da direita para a esquerda', () => {
  it('digitar 1 é um centavo', () => {
    render(<Campo />)
    const el = screen.getByLabelText('valor') as HTMLInputElement
    digitar(el, '1')
    expect(txt(el)).toBe('R$ 0,01')
  })

  it('digitar 100 é um real — o exemplo exato do usuário', () => {
    render(<Campo />)
    const el = screen.getByLabelText('valor') as HTMLInputElement
    digitar(el, '100')
    expect(txt(el)).toBe('R$ 1,00')
  })

  it('vai pondo o separador de milhar sozinho conforme cresce', () => {
    render(<Campo />)
    const el = screen.getByLabelText('valor') as HTMLInputElement
    digitar(el, '1')
    expect(txt(el)).toBe('R$ 0,01')
    digitar(el, '2')
    expect(txt(el)).toBe('R$ 0,12')
    digitar(el, '3')
    expect(txt(el)).toBe('R$ 1,23')
    digitar(el, '456')
    expect(txt(el)).toBe('R$ 1.234,56')
    digitar(el, '7')
    expect(txt(el)).toBe('R$ 12.345,67')
  })

  it('Backspace desfaz uma casa, empurrando o número de volta', () => {
    render(<Campo inicial={12.34} />)
    const el = screen.getByLabelText('valor') as HTMLInputElement
    expect(txt(el)).toBe('R$ 12,34')
    // Backspace no fim do texto formatado remove um caractere — o campo relê os dígitos.
    fireEvent.change(el, { target: { value: 'R$ 12,3' } })
    expect(txt(el)).toBe('R$ 1,23')
  })

  it('apagar tudo devolve null, não zero — vazio e zero são coisas diferentes', () => {
    const onChange = vi.fn()
    render(<MoneyInput value={9.99} onChange={onChange} aria-label="valor" />)
    fireEvent.change(screen.getByLabelText('valor'), { target: { value: '' } })
    expect(onChange).toHaveBeenCalledWith(null)
  })

  it('entrega número em unidade MAIOR, nunca os centavos crus', () => {
    const onChange = vi.fn()
    render(<MoneyInput value={null} onChange={onChange} aria-label="valor" />)
    fireEvent.change(screen.getByLabelText('valor'), { target: { value: '123456' } })
    expect(onChange).toHaveBeenLastCalledWith(1234.56)
  })

  it('ignora o que não é algarismo — colar de planilha não vira valor torto', () => {
    render(<Campo />)
    const el = screen.getByLabelText('valor') as HTMLInputElement
    fireEvent.change(el, { target: { value: 'R$ 1.234,56' } })
    expect(txt(el)).toBe('R$ 1.234,56')
  })

  it('zero à esquerda não se acumula', () => {
    render(<Campo />)
    const el = screen.getByLabelText('valor') as HTMLInputElement
    digitar(el, '0005')
    expect(txt(el)).toBe('R$ 0,05')
  })

  it('respeita o limite de algarismos, para não perder centavo em silêncio', () => {
    const onChange = vi.fn()
    render(<MoneyInput value={null} onChange={onChange} maxDigitos={4} aria-label="valor" />)
    fireEvent.change(screen.getByLabelText('valor'), { target: { value: '123456789' } })
    expect(onChange).toHaveBeenLastCalledWith(12.34)
  })

  it('a moeda vem da configuração, não do componente', () => {
    render(<MoneyInput value={1234.56} onChange={vi.fn()} currency={CURRENCIES.USD} aria-label="valor" />)
    expect(txt(screen.getByLabelText('valor') as HTMLInputElement)).toBe('$1,234.56')
  })

  it('moeda sem subunidade muda o significado da tecla: digitar 1 é uma unidade', () => {
    const onChange = vi.fn()
    render(
      <MoneyInput
        value={null}
        onChange={onChange}
        currency={{ code: 'JPY', locale: 'ja-JP', minorUnits: 0 }}
        aria-label="valor"
      />,
    )
    fireEvent.change(screen.getByLabelText('valor'), { target: { value: '1' } })
    expect(onChange).toHaveBeenLastCalledWith(1)
  })

  it('o campo vazio mostra o zero da moeda como placeholder', () => {
    render(<MoneyInput value={null} onChange={vi.fn()} aria-label="valor" />)
    expect((screen.getByLabelText('valor') as HTMLInputElement).placeholder.replace(/[\u00a0\u202f]/g, ' ')).toBe('R$ 0,00')
  })
})
