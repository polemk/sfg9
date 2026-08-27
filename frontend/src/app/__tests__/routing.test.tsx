import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter, Routes, Route, Link, useNavigate } from 'react-router-dom'
import { NotFoundPage, ServerErrorPage, UnprocessablePage } from '@/app/pages/ErrorPages'
import { RouteErrorBoundary } from '@/components/RouteErrorBoundary'
import { destinoPorPapel } from '@/components/RootRedirect'
import { RoleRoute } from '@/components/RoleRoute'
import { useAuthStore } from '@/store/authStore'

/**
 * Roteamento do console — 6.3.2 e FE-404.
 *
 * Os dois defeitos que estes testes travam:
 *  - `App.tsx` não tinha rota `*`, e área desconhecida virava **tela em
 *    branco**;
 *  - o legado **rebaixava em silêncio para o `dash`**, o que é pior: o usuário
 *    achava que tinha chegado.
 */

function comRota(caminho: string, elemento: React.ReactNode) {
  return render(
    <MemoryRouter initialEntries={[caminho]}>
      <Routes>
        <Route path="/conhecida" element={<p>área conhecida</p>} />
        <Route path="*" element={elemento} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('rota curinga (6.3.2)', () => {
  it('área desconhecida mostra a tela de não encontrado — nunca tela em branco', () => {
    comRota('/area-que-nao-existe', <NotFoundPage />)

    expect(screen.getByText(/esta página não existe/i)).toBeInTheDocument()
    expect(screen.getByText('Erro 404')).toBeInTheDocument()
  })

  it('não há rebaixamento silencioso: a tela NÃO é a inicial', () => {
    comRota('/area-que-nao-existe', <NotFoundPage />)

    expect(screen.queryByText('área conhecida')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /ir para o início/i })).toBeInTheDocument()
  })

  it('rota conhecida continua abrindo a área, não o 404', () => {
    comRota('/conhecida', <NotFoundPage />)
    expect(screen.getByText('área conhecida')).toBeInTheDocument()
  })
})

describe('as três páginas de erro (F.4 / OPS-634)', () => {
  it('422 e 500 existem e dizem o código', () => {
    const { unmount } = render(<MemoryRouter><UnprocessablePage /></MemoryRouter>)
    expect(screen.getByText('Erro 422')).toBeInTheDocument()
    unmount()

    render(<MemoryRouter><ServerErrorPage detail="boom" /></MemoryRouter>)
    expect(screen.getByText('Erro 500')).toBeInTheDocument()
    expect(screen.getByText('boom')).toBeInTheDocument()
  })
})

describe('fronteira de erro', () => {
  function Explode(): React.ReactElement {
    throw new Error('falha proposital')
  }

  /**
   * Este caso afirmava "vira o 500 da casa" e checava o texto `Erro 500`.
   * **Estava travando o comportamento errado**, e o usuário reportou o sintoma:
   * o detalhe de projeto caiu com `Cannot read properties of null (reading
   * 'trim')` e a tela anunciou "ERRO 500 — algo quebrou do nosso lado — a falha
   * foi registrada". Nenhuma das três é verdade para uma exceção do navegador,
   * e a última manda o time procurar num log de servidor onde não há nada.
   */
  it('exceção numa tela vira a queda DO CLIENTE — não um 500 —, nunca tela branca', () => {
    // O React loga o erro capturado; silenciado para o relatório do teste ficar legível.
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})

    render(
      <MemoryRouter>
        <RouteErrorBoundary>
          <Explode />
        </RouteErrorBoundary>
      </MemoryRouter>,
    )

    expect(screen.getByText('Esta tela não conseguiu abrir')).toBeInTheDocument()
    // A mensagem técnica continua visível: é ela que vai para o chamado.
    expect(screen.getByText('falha proposital')).toBeInTheDocument()
    // E o rótulo NÃO pode voltar a mentir que foi o servidor.
    expect(screen.queryByText(/erro 500/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/do nosso lado/i)).not.toBeInTheDocument()
    spy.mockRestore()
  })
})

/**
 * FE-404 — o redirecionador por papel, que é **tudo** o que o `dash` do legado
 * é (`dash/_body.js.erb:8-22`). Não existe dashboard (DC-15): um dashboard de
 * verdade é a `NEW-002`, fatia S15.
 */
describe('redirecionador por papel (FE-404)', () => {
  const tudoMontado = () => true

  it('OG vai para usuários, com ou sem projeto', () => {
    expect(destinoPorPapel('og', false, tudoMontado)).toBe('/users')
    expect(destinoPorPapel('og', true, tudoMontado)).toBe('/users')
  })

  it('Admin e Gerente: projetos sem projeto, recebíveis com projeto', () => {
    for (const papel of ['admin', 'gerente'] as const) {
      expect(destinoPorPapel(papel, false, tudoMontado)).toBe('/projects')
      expect(destinoPorPapel(papel, true, tudoMontado)).toBe('/receivables')
    }
  })

  it('Colaborador: minha conta sem projeto, área de projeto com projeto', () => {
    expect(destinoPorPapel('colaborador', false, tudoMontado)).toBe('/profile')
    expect(destinoPorPapel('colaborador', true, tudoMontado)).toBe('/risk')
  })

  it('área ainda não entregue cai no início — nunca num 404', () => {
    const nadaMontado = () => false
    expect(destinoPorPapel('og', true, nadaMontado)).toBe('/dashboard')
    expect(destinoPorPapel('colaborador', false, nadaMontado)).toBe('/dashboard')
  })

  it('papel desconhecido cai no destino do papel mais restrito', () => {
    expect(destinoPorPapel(null, false, tudoMontado)).toBe('/profile')
  })
})

/**
 * O gate de rota por papel. Esconder o item de menu **não** é gatear a rota: no
 * legado a única autorização real morava nos gates das views (D-23), e por isso
 * qualquer requisição feita fora da tela fazia tudo (D-34). O endereço digitado
 * à mão tem que parar.
 */
describe('RoleRoute — o endereço digitado à mão para (D-23/D-34)', () => {
  function montar(userTypeSlug: string | null) {
    useAuthStore.setState({
      isAuthenticated: true,
      user: userTypeSlug ? ({ id: 'u1', name: 'T', user_type_slug: userTypeSlug } as any) : ({ id: 'u1', name: 'T' } as any),
    })
    return render(
      <MemoryRouter initialEntries={['/restrita']}>
        <Routes>
          <Route path="/restrita" element={<RoleRoute roles={['og', 'admin']}><p>área restrita</p></RoleRoute>} />
          <Route path="/dashboard" element={<p>início</p>} />
        </Routes>
      </MemoryRouter>,
    )
  }

  it('OG e Admin entram', () => {
    for (const papel of ['og', 'admin']) {
      const { unmount } = montar(papel)
      expect(screen.getByText('área restrita'), papel).toBeInTheDocument()
      unmount()
    }
  })

  it('Gerente e Colaborador NÃO entram — são levados ao início', () => {
    for (const papel of ['gerente', 'colaborador']) {
      const { unmount } = montar(papel)
      expect(screen.queryByText('área restrita'), papel).not.toBeInTheDocument()
      expect(screen.getByText('início'), papel).toBeInTheDocument()
      unmount()
    }
  })

  it('papel desconhecido NÃO entra', () => {
    montar(null)
    expect(screen.queryByText('área restrita')).not.toBeInTheDocument()
  })

  it('sem sessão vai para o login', () => {
    useAuthStore.setState({ isAuthenticated: false, user: null })
    render(
      <MemoryRouter initialEntries={['/restrita']}>
        <Routes>
          <Route path="/restrita" element={<RoleRoute roles={['og']}><p>área restrita</p></RoleRoute>} />
          <Route path="/login" element={<p>tela de login</p>} />
        </Routes>
      </MemoryRouter>,
    )
    expect(screen.getByText('tela de login')).toBeInTheDocument()
  })
})

/**
 * 6.3.3 / IMP-A11 — o botão Voltar **navega dentro do console**.
 *
 * No legado a URL era espelhada por `replaceState`, nunca `pushState` (D-92):
 * o histórico não registrava a navegação entre áreas, então Voltar saltava
 * para FORA do console. Com `<Link>`/`<NavLink>` cada troca de área é uma
 * entrada nova de histórico — e é isso que este teste trava.
 *
 * O teste distingue de verdade: com `replace` (o comportamento do legado) o
 * histórico teria uma entrada só, e o "voltar" seria um no-op que deixaria a
 * tela em B.
 */
describe('histórico do navegador (6.3.3, D-92)', () => {
  function Voltar() {
    const navigate = useNavigate()
    return (
      <>
        <p>área B</p>
        <button type="button" onClick={() => navigate(-1)}>voltar</button>
      </>
    )
  }

  it('trocar de área empilha no histórico e Voltar retorna à área anterior', () => {
    render(
      <MemoryRouter initialEntries={['/a']}>
        <Routes>
          <Route path="/a" element={<Link to="/b">ir para B</Link>} />
          <Route path="/b" element={<Voltar />} />
        </Routes>
      </MemoryRouter>,
    )

    fireEvent.click(screen.getByText('ir para B'))
    expect(screen.getByText('área B')).toBeInTheDocument()

    fireEvent.click(screen.getByText('voltar'))
    expect(screen.getByText('ir para B')).toBeInTheDocument()
    expect(screen.queryByText('área B')).not.toBeInTheDocument()
  })
})
