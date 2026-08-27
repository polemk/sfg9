import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { Link, MemoryRouter, Route, Routes, useLocation } from 'react-router-dom'
import { FormActionBar } from '@/components/ui/FormActionBar'
import { useUnsavedChanges } from '@/hooks/useUnsavedChanges'

/**
 * **S2 / tarefa 4.7 — FE-400, a barra de ações pendentes com estado sujo.**
 *
 * A tarefa ficou aberta na S2 por um motivo escrito: a barra só tem sentido com
 * um formulário longo, e o único formulário daquela fatia cabia num drawer de
 * dois campos. A S6 entregou o formulário de borderô; isto é o que faltava.
 *
 * Os três cenários abaixo são os da spec `console-admin` (FE-400), e cada um
 * deles corresponde a um defeito medido no legado:
 *
 * - **descartar sem recarregar** — o `cancel()` da barra do legado montava
 *   `{ reload: defaultReload() }` **com os parênteses**, então a recarga da
 *   página acontecia na hora de montar o objeto, antes de qualquer confirmação
 *   (`bottom_bar/_container.js.erb:138`);
 * - **aviso ao sair** — o `go()` do console fechava a gaveta e descartava a
 *   edição em silêncio;
 * - **falha ao salvar** — a barra tem que dizer o MOTIVO e voltar a ser
 *   acionável; o legado desempilhava a ação sem mensagem nenhuma.
 */
describe('FormActionBar — o que a barra DIZ (FE-400)', () => {
  it('sem pendência e sem alteração, mostra o resumo', () => {
    render(
      <FormActionBar pendencias={[]} resumo={<span>Líquido R$ 10,00</span>}>
        <button type="button">Salvar</button>
      </FormActionBar>,
    )
    expect(screen.getByText('Líquido R$ 10,00')).toBeInTheDocument()
    expect(screen.queryByText(/Alterações não salvas/)).not.toBeInTheDocument()
  })

  it('com alteração pendente, anuncia "Alterações não salvas"', () => {
    render(
      <FormActionBar pendencias={[]} alterado resumo={<span>Líquido R$ 10,00</span>}>
        <button type="button">Salvar</button>
      </FormActionBar>,
    )
    expect(screen.getByText(/Alterações não salvas/)).toBeInTheDocument()
  })

  // A precedência importa: quem não pode enviar precisa saber O QUE FALTA antes
  // de saber que há coisa não salva — a segunda informação é inútil sem a
  // primeira.
  // As duas variações (desktop e telefone) convivem no DOM e são escolhidas por
  // media query — que o jsdom não aplica. Por isso `getAllByText`: contar UM
  // aqui seria testar o CSS, não o comportamento.
  it('pendência ganha do estado sujo', () => {
    render(
      <FormActionBar pendencias={['empresa', 'portador']} alterado>
        <button type="button">Salvar</button>
      </FormActionBar>,
    )
    expect(screen.getAllByText(/Falta preencher: empresa, portador\./).length).toBeGreaterThan(0)
    expect(screen.queryByText(/Alterações não salvas/)).not.toBeInTheDocument()
  })

  // **A regressão medida em 390×844**: com o formulário em branco são nove
  // pendências, e a frase inteira empurrava o botão de salvar para fora da tela.
  // No telefone a lista nasce recolhida, com a CONTAGEM em primeiro plano — o
  // número é a informação que decide se vale a pena abrir.
  it('no telefone, muitas pendências nascem recolhidas e a contagem aparece', () => {
    const nove = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']
    render(
      <FormActionBar pendencias={nove}>
        <button type="button">Salvar</button>
      </FormActionBar>,
    )
    const alternador = screen.getByRole('button', { name: /Faltam 9 campos/ })
    expect(alternador).toHaveAttribute('aria-expanded', 'false')
    expect(alternador).toHaveTextContent('Faltam 9 campos: a, b…')

    fireEvent.click(alternador)
    expect(alternador).toHaveAttribute('aria-expanded', 'true')
    expect(alternador).toHaveTextContent('a, b, c, d, e, f, g, h, i')
  })

  // O `toast` some em 4 s e leva o motivo junto. A falha fica na barra, e é
  // `role="alert"` — ela INTERROMPE, ao contrário das outras três.
  it('a falha ao salvar ganha de tudo, e é um alerta', () => {
    render(
      <FormActionBar pendencias={['empresa']} alterado erro="Portador não conectado ao projeto.">
        <button type="button">Salvar</button>
      </FormActionBar>,
    )
    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent('Portador não conectado ao projeto.')
    expect(screen.queryByText(/Falta preencher/)).not.toBeInTheDocument()
  })
})

/** Tela mínima com um campo e a guarda — o que o formulário de borderô faz. */
function Formulario({ aoSair }: { aoSair?: () => void }) {
  const [texto, setTexto] = useState('')
  const alterado = texto !== ''
  const saida = useUnsavedChanges(alterado)

  return (
    <div>
      <input aria-label="campo" value={texto} onChange={(e) => setTexto(e.target.value)} />
      {/* `Link` de verdade: é o que a barra lateral usa (`NavLink`), e é o
          caminho de saída que o legado descartava em silêncio. */}
      <Link to="/outra">Ir para outra área</Link>
      <button type="button" onClick={() => saida.interceptar(() => aoSair?.())}>
        Cancelar
      </button>
      <button type="button" onClick={() => { setTexto(''); }}>
        Descartar
      </button>
      {saida.perguntando && (
        <div role="dialog">
          <button type="button" onClick={saida.confirmar}>
            Sair sem salvar
          </button>
          <button type="button" onClick={saida.cancelar}>
            Continuar editando
          </button>
        </div>
      )}
      <FormActionBar pendencias={[]} alterado={alterado}>
        <span />
      </FormActionBar>
    </div>
  )
}

function Onde() {
  return <span data-testid="rota">{useLocation().pathname}</span>
}

function montar(aoSair?: () => void) {
  return render(
    <MemoryRouter initialEntries={['/form']}>
      <Onde />
      <Routes>
        <Route path="/form" element={<Formulario aoSair={aoSair} />} />
        <Route path="/outra" element={<span>Outra área</span>} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('useUnsavedChanges — o aviso antes de perder (FE-400)', () => {
  it('formulário intocado deixa sair SEM perguntar', () => {
    const sair = vi.fn()
    montar(sair)
    fireEvent.click(screen.getByText('Cancelar'))
    expect(sair).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('com alteração, a saída é REPRESADA — e só acontece na confirmação', () => {
    const sair = vi.fn()
    montar(sair)
    fireEvent.change(screen.getByLabelText('campo'), { target: { value: 'x' } })

    fireEvent.click(screen.getByText('Cancelar'))
    // O bug do legado era exatamente este: a ação executava na hora de montar
    // o objeto, e não na confirmação.
    expect(sair).not.toHaveBeenCalled()
    expect(screen.getByRole('dialog')).toBeInTheDocument()

    fireEvent.click(screen.getByText('Sair sem salvar'))
    expect(sair).toHaveBeenCalledTimes(1)
  })

  it('"Continuar editando" fica na tela e preserva o que foi digitado', () => {
    const sair = vi.fn()
    montar(sair)
    fireEvent.change(screen.getByLabelText('campo'), { target: { value: 'x' } })
    fireEvent.click(screen.getByText('Cancelar'))
    fireEvent.click(screen.getByText('Continuar editando'))

    expect(sair).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(screen.getByLabelText('campo')).toHaveValue('x')
  })

  // O caminho de saída REAL: o item de menu, que é um `<a href>` do `NavLink`.
  it('clique num link interno é interceptado, e a rota NÃO muda antes da confirmação', () => {
    montar()
    fireEvent.change(screen.getByLabelText('campo'), { target: { value: 'x' } })

    fireEvent.click(screen.getByText('Ir para outra área'))
    expect(screen.getByTestId('rota')).toHaveTextContent('/form')
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  it('link interno com formulário intocado navega normalmente', () => {
    montar()
    fireEvent.click(screen.getByText('Ir para outra área'))
    expect(screen.getByTestId('rota')).toHaveTextContent('/outra')
  })

  // Descartar devolve o formulário ao ponto inicial. A barra deixa de anunciar
  // pendência, e nada recarrega.
  it('descartar limpa o estado sujo sem recarregar', () => {
    montar()
    fireEvent.change(screen.getByLabelText('campo'), { target: { value: 'x' } })
    expect(screen.getByText(/Alterações não salvas/)).toBeInTheDocument()

    fireEvent.click(screen.getByText('Descartar'))
    expect(screen.queryByText(/Alterações não salvas/)).not.toBeInTheDocument()
    expect(screen.getByTestId('rota')).toHaveTextContent('/form')
  })
})
