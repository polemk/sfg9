import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { AsyncSection } from '@/components/ui/AsyncSection'

/**
 * FE-401 — o legado tinha três estados e **nenhum de erro**. O teste que
 * importa não é "renderiza uma lista": é que o quarto estado existe e que a
 * ordem de decisão está certa.
 */
describe('AsyncSection — os quatro estados', () => {
  it('carregando, sem dado e sem erro', () => {
    render(
      <AsyncSection loading data={null} loadingLabel="Carregando recebíveis…">
        {() => <p>conteúdo</p>}
      </AsyncSection>,
    )
    expect(screen.getByText('Carregando recebíveis…')).toBeInTheDocument()
  })

  it('vazio quando a lista chega sem itens', () => {
    render(
      <AsyncSection data={[] as string[]} emptyTitle="Nenhum recebível">
        {() => <p>conteúdo</p>}
      </AsyncSection>,
    )
    expect(screen.getByText('Nenhum recebível')).toBeInTheDocument()
  })

  it('ERRO com a mensagem do servidor e botão de tentar de novo', () => {
    const onRetry = vi.fn()
    render(
      <AsyncSection
        data={null}
        error={{ response: { data: { error: 'Projeto não encontrado' } } }}
        onRetry={onRetry}
      >
        {() => <p>conteúdo</p>}
      </AsyncSection>,
    )
    expect(screen.getByText('Não foi possível carregar')).toBeInTheDocument()
    expect(screen.getByText('Projeto não encontrado')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Tentar de novo/ }))
    expect(onRetry).toHaveBeenCalled()
  })

  it('conteúdo quando há dado', () => {
    render(<AsyncSection data={['a', 'b']}>{(d) => <p>{d.length} itens</p>}</AsyncSection>)
    expect(screen.getByText('2 itens')).toBeInTheDocument()
  })

  it('erro VENCE carregamento — senão a tela gira para sempre sobre uma falha', () => {
    render(
      <AsyncSection loading error={new Error('falhou')} data={null}>
        {() => <p>conteúdo</p>}
      </AsyncSection>,
    )
    expect(screen.getByText('Não foi possível carregar')).toBeInTheDocument()
  })

  it('dado antigo VENCE carregamento — atualização em segundo plano não apaga a tela', () => {
    render(
      <AsyncSection loading data={['a']}>
        {(d) => <p>{d.length} itens</p>}
      </AsyncSection>,
    )
    expect(screen.getByText('1 itens')).toBeInTheDocument()
  })
})
