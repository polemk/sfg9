import { describe, it, expect, beforeEach } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import type { RenegotiationInstallment } from '@/lib/api/renegotiations'
import { InstallmentRow } from '../InstallmentRow'

/**
 * **FE-213 — as nove colunas de valor da previsão.**
 *
 * O legado mostrava nove (`renegotiation_installments/list/_widget.html.erb:9-27`):
 * Principal, Juros, P+J, CM, P+J+CM, Mora, Total, Pago e Pendente. A migração
 * trouxe **quatro** — Principal, Total, Pago e Pendente — e as cinco do meio
 * sumiram.
 *
 * Não é detalhe de exibição: as cinco são a **decomposição** do total. Sem elas
 * o usuário vê o resultado e não vê a conta, e numa renegociação com correção
 * monetária a pergunta "por que o total é este?" deixa de ter resposta na tela.
 * O dado já vinha do servidor inteiro — só não era desenhado.
 */

const PARCELA = {
  id: 'p-1',
  number: 1,
  due_date: '2026-09-10',
  main_value: '1000.00',
  interest_value: '120.00',
  main_value_with_interest: '1120.00',
  monetary_correction_value: '30.00',
  main_value_with_interest_cm: '1150.00',
  late_payment_value: '15.00',
  installment_total_value: '1165.00',
  paid_value: '0.00',
  pending_value: '1165.00',
  is_paid: false,
  color: '#4d1717',
  payments: [],
} as unknown as RenegotiationInstallment

function montar(compacto: boolean, expandida = false) {
  return render(
    <ul>
      <InstallmentRow
        parcela={PARCELA}
        compacto={compacto}
        expandida={expandida}
        onToggleExpandir={() => {}}
        modoSelecao={false}
        selecionada={false}
        onToggleSelecao={() => {}}
        podeEscrever={false}
        onGerarPagamento={() => {}}
        onEditar={() => {}}
        onRemover={() => {}}
        onEditarPagamento={() => {}}
        onRemoverPagamento={() => {}}
        onAcoesMobile={() => {}}
      />
    </ul>,
  )
}

const DO_MEIO = ['Juros', 'P+J', 'CM', 'P+J+CM', 'Mora']
const SEMPRE = ['Principal', 'Total', 'Pago', 'Pendente']

beforeEach(() => {
  // `src/test/setup.ts` não chama `cleanup()` (UF-S15-04).
  cleanup()
})

describe('InstallmentRow — as nove colunas do legado (FE-213)', () => {
  it('no DESKTOP mostra as nove, e não só as quatro', () => {
    montar(false)

    for (const rotulo of [...SEMPRE, ...DO_MEIO]) {
      expect(screen.getByText(rotulo), `faltou a coluna "${rotulo}"`).toBeInTheDocument()
    }
  })

  it('os VALORES das cinco do meio são os do servidor, não recalculados aqui', () => {
    montar(false)

    // P+J = 1000 + 120, P+J+CM = 1120 + 30. A tela não faz a conta: ela mostra o
    // que o servidor calculou, que é o contrato desta migração.
    expect(screen.getByText('R$ 1.120,00')).toBeInTheDocument()
    expect(screen.getByText('R$ 1.150,00')).toBeInTheDocument()
    expect(screen.getByText('R$ 15,00')).toBeInTheDocument()
  })

  it('no TELEFONE a linha fechada mostra só as quatro — nove valores a 375 px não se lê', () => {
    montar(true)

    for (const rotulo of SEMPRE) expect(screen.getByText(rotulo)).toBeInTheDocument()
    for (const rotulo of DO_MEIO) expect(screen.queryByText(rotulo)).not.toBeInTheDocument()
  })

  it('no TELEFONE a linha EXPANDIDA mostra a decomposição inteira', () => {
    montar(true, true)

    for (const rotulo of DO_MEIO) {
      expect(screen.getByText(rotulo), `faltou "${rotulo}" na linha expandida`).toBeInTheDocument()
    }
  })
})
