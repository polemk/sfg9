import { describe, it, expect, vi, beforeEach } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { DatePicker } from '../DatePicker'

/**
 * **FE-177 — a restrição mútua das datas, e FE-745 — o atalho "Hoje".**
 *
 * A regra do legado, lida em `receivables/new/_body.js.erb:74-106`: escolher a
 * data do borderô define o `minDate` do seletor de CRÉDITO, e escolher a de
 * crédito define o `maxDate` do seletor do BORDERÔ. **O crédito nunca é
 * anterior ao borderô**, e a trava vale nos dois sentidos.
 *
 * A migração trouxe os dois campos sem `min` nem `max`. O componente aceitava
 * ambos e ninguém passava — e como nenhum dos dois lados valida a combinação
 * (nem o legado validava), a tela SEMPRE foi a única defesa. Ela tinha sumido.
 *
 * Os exemplos abaixo travam o componente, não a tela: é aqui que a regra é
 * executável.
 */
beforeEach(() => {
  // `src/test/setup.ts` não chama `cleanup()` (UF-S15-04).
  cleanup()
  vi.clearAllMocks()
})

// Setembro de 2026, fixo: o calendário abre no mês do `value`, e um exemplo que
// procura "10 de setembro" com agosto na tela falharia por motivo errado — e
// passaria a falhar sozinho na virada do mês.
const NO_MES = new Date(2026, 8, 5)

function abrir(props: Partial<React.ComponentProps<typeof DatePicker>> = {}) {
  const onChange = vi.fn()
  render(<DatePicker value={NO_MES} onChange={onChange} {...props} />)
  fireEvent.click(screen.getByRole('button', { name: /Abrir calendário/i }))
  return onChange
}

/** O dia é nomeado por extenso no `aria-label` (acessibilidade), não pelo número. */
const dia = (n: number) => screen.getByRole('button', { name: `${n} de setembro de 2026` })

describe('DatePicker — limites e atalho', () => {
  it('dia ANTERIOR ao `min` não é escolhível', () => {
    const onChange = abrir({ min: new Date(2026, 8, 15) })

    const dia10 = dia(10)
    expect(dia10).toBeDisabled()

    fireEvent.click(dia10)
    expect(onChange).not.toHaveBeenCalled()
  })

  it('dia POSTERIOR ao `max` não é escolhível', () => {
    const onChange = abrir({ max: new Date(2026, 8, 15) })

    const dia20 = dia(20)
    expect(dia20).toBeDisabled()

    fireEvent.click(dia20)
    expect(onChange).not.toHaveBeenCalled()
  })

  it('o PRÓPRIO dia do limite continua escolhível — a regra é `>=`, não `>`', () => {
    const onChange = abrir({ min: new Date(2026, 8, 15) })

    const dia15 = dia(15)
    expect(dia15).not.toBeDisabled()

    fireEvent.click(dia15)
    expect(onChange).toHaveBeenCalledTimes(1)
  })

  // FE-745 — o atalho que o legado tinha no rodapé do calendário.
  it('"Hoje" escolhe o dia corrente', () => {
    const onChange = vi.fn()
    render(<DatePicker value={null} onChange={onChange} />)
    fireEvent.click(screen.getByRole('button', { name: /Abrir calendário/i }))

    fireEvent.click(screen.getByRole('button', { name: /^Hoje$/i }))

    expect(onChange).toHaveBeenCalledTimes(1)
    const escolhido = onChange.mock.calls[0][0] as Date
    const hoje = new Date()
    expect(escolhido.getFullYear()).toBe(hoje.getFullYear())
    expect(escolhido.getMonth()).toBe(hoje.getMonth())
    expect(escolhido.getDate()).toBe(hoje.getDate())
  })

  it('"Hoje" fica DESABILITADO quando hoje está fora da faixa', () => {
    // Um campo "até" cujo `min` é o mês que vem: oferecer hoje seria oferecer
    // uma data que o próprio calendário recusa.
    const futuro = new Date()
    futuro.setMonth(futuro.getMonth() + 1)
    render(<DatePicker value={null} min={futuro} onChange={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /Abrir calendário/i }))

    expect(screen.getByRole('button', { name: /^Hoje$/i })).toBeDisabled()
  })
})
