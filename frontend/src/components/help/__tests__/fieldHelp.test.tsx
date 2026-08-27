import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

/**
 * S12 / OPS-545 + DEC-88 — o mecanismo da ajuda de campo.
 *
 * Duas regras que este teste trava:
 *  - **chave ausente não quebra a tela** (e não deixa ícone órfão);
 *  - **`TODO:` não vira tooltip** — as 4 chaves pendentes ficam invisíveis.
 */

const scope = vi.fn()

vi.mock('@/lib/api/help', () => ({
  fieldHelpApi: { all: vi.fn(), scope: (...a: any[]) => scope(...a) },
}))

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

async function montar(field: string) {
  const { FieldHelp } = await import('@/components/help/FieldHelp')
  return render(
    <Envolvido>
      <FieldHelp scope="receivables" field={field} />
    </Envolvido>,
  )
}

describe('FieldHelp', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    scope.mockResolvedValue({
      receivables: {
        valor_bruto: 'Valor de face dos títulos enviados.',
        // Uma chave `TODO:` que escapou do filtro do servidor: a segunda trava
        // é aqui, no cliente.
        contrato: 'TODO: precisa saber qual contrato este campo identifica.',
      },
    })
  })

  it('mostra o texto do campo ao passar o mouse', async () => {
    await montar('valor_bruto')
    const gatilho = await screen.findByLabelText('Ajuda sobre o campo valor_bruto')
    fireEvent.mouseEnter(gatilho.parentElement!)
    expect(await screen.findByRole('tooltip')).toHaveTextContent('Valor de face dos títulos enviados.')
  })

  it('campo com texto `TODO:` NÃO ganha ícone nenhum', async () => {
    const { container } = await montar('contrato')
    await waitFor(() => expect(scope).toHaveBeenCalled())
    expect(container.querySelector('button')).toBeNull()
  })

  it('chave ausente não quebra a tela — simplesmente não renderiza', async () => {
    const { container } = await montar('campo_que_nao_existe')
    await waitFor(() => expect(scope).toHaveBeenCalled())
    expect(container.innerHTML).toBe('')
  })

  it('falha ao buscar os textos não derruba o formulário', async () => {
    scope.mockRejectedValue(new Error('sem rede'))
    const { container } = await montar('valor_bruto')
    await waitFor(() => expect(scope).toHaveBeenCalled())
    expect(container.innerHTML).toBe('')
  })
})
