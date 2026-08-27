import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'
import { getAccessToken, setAccessToken, clearTokens } from '@/lib/api/tokenStore'

const USER = { id: 'u-1', email: 'mestre@ai9.dev', name: 'Mestre' } as any

function renderGuarded() {
  return render(
    <MemoryRouter initialEntries={['/painel']}>
      <Routes>
        <Route
          path="/painel"
          element={
            <ProtectedRoute>
              <div data-testid="conteudo-protegido">conteúdo</div>
            </ProtectedRoute>
          }
        />
        <Route path="/login" element={<div data-testid="tela-login">login</div>} />
      </Routes>
    </MemoryRouter>
  )
}

// Modelo de sessão: access token SÓ em memória (tokenStore); refresh em cookie
// HttpOnly — o JS não o vê, então o bootstrap é sempre via refreshAccessToken().
describe('ProtectedRoute — bootstrap e sobrevivência da sessão', () => {
  beforeEach(() => {
    clearTokens()
    useAuthStore.getState().logout()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('restaura a sessão pelo cookie no reload (sem access em memória)', async () => {
    // Reload: memória vazia, cookie válido → refresh renova e status confirma
    const refresh = vi
      .spyOn(authService, 'refreshAccessToken')
      .mockImplementation(async () => {
        setAccessToken('access-novo') // o apiClient faz isso no fluxo real
        return { access_token: 'access-novo', user: USER }
      })
    const status = vi
      .spyOn(authService, 'checkSessionStatus')
      .mockResolvedValue({ authenticated: true, valid: true, user: USER })

    renderGuarded()

    expect(await screen.findByTestId('conteudo-protegido')).toBeInTheDocument()
    expect(refresh).toHaveBeenCalledTimes(1)
    expect(status).toHaveBeenCalledTimes(1)
    expect(getAccessToken()).toBe('access-novo')
    expect(useAuthStore.getState().isAuthenticated).toBe(true)
    expect(screen.queryByTestId('tela-login')).not.toBeInTheDocument()
  })

  // Regressão: /sessions/status responde 200 {valid:false} quando o access expira,
  // então o interceptor do axios nunca é acionado — o guard precisa tentar o
  // refresh via cookie em vez de derrubar a sessão.
  it('renova via cookie quando o access em memória expirou', async () => {
    setAccessToken('access-expirado')

    const status = vi
      .spyOn(authService, 'checkSessionStatus')
      .mockResolvedValueOnce({ authenticated: false, valid: false, user: null })
      .mockResolvedValueOnce({ authenticated: true, valid: true, user: USER })
    const refresh = vi
      .spyOn(authService, 'refreshAccessToken')
      .mockImplementation(async () => {
        setAccessToken('access-novo')
        return { access_token: 'access-novo', user: USER }
      })

    renderGuarded()

    expect(await screen.findByTestId('conteudo-protegido')).toBeInTheDocument()
    expect(refresh).toHaveBeenCalledTimes(1)
    expect(status).toHaveBeenCalledTimes(2)
    expect(getAccessToken()).toBe('access-novo')
    expect(useAuthStore.getState().isAuthenticated).toBe(true)
  })

  it('vai para o /login quando o refresh via cookie é rejeitado', async () => {
    // Sem access em memória e cookie inválido/ausente → sessão realmente acabou
    const refresh = vi
      .spyOn(authService, 'refreshAccessToken')
      .mockResolvedValue(null)
    const status = vi.spyOn(authService, 'checkSessionStatus')

    renderGuarded()

    expect(await screen.findByTestId('tela-login')).toBeInTheDocument()
    expect(refresh).toHaveBeenCalledTimes(1)
    expect(status).not.toHaveBeenCalled()
    expect(getAccessToken()).toBeNull()
    expect(useAuthStore.getState().isAuthenticated).toBe(false)
  })

  it('não tenta refresh quando a sessão já é válida', async () => {
    setAccessToken('access-valido')

    vi.spyOn(authService, 'checkSessionStatus').mockResolvedValue({
      authenticated: true,
      valid: true,
      user: USER
    })
    const refresh = vi.spyOn(authService, 'refreshAccessToken')

    renderGuarded()

    expect(await screen.findByTestId('conteudo-protegido')).toBeInTheDocument()
    expect(refresh).not.toHaveBeenCalled()
    expect(getAccessToken()).toBe('access-valido')
  })

  /**
   * **429 no bootstrap NAO pode custar a sessao.**
   *
   * Aconteceu em producao em 27/08/2026: depois de um F5 nao ha access token em
   * memoria — ele nunca e persistido —, entao o bootstrap sempre passa pelo
   * refresh. Com o teto de 60/min estourado por uso normal (uma chamada por
   * navegacao, e TODAS as consultas refeitas ao trocar de projeto), a renovacao
   * levava 429, o `catch` devolvia `false` e a pessoa era mandada para o login.
   *
   * 401 e 403 sao veredito do servidor sobre a credencial. 429 e "tente daqui a
   * pouco" — o cookie de refresh continua valido.
   */
  it('429 na renovação é TENTADO DE NOVO, e a sessão sobrevive', async () => {
    const err429 = Object.assign(new Error('Too Many Requests'), {
      response: { status: 429 },
    })

    const refresh = vi
      .spyOn(authService, 'refreshAccessToken')
      .mockRejectedValueOnce(err429)
      // O `apiClient` grava o token no fluxo real; o mock precisa fazer o
      // mesmo, senão o guarda cai no ramo `!getAccessToken()` e navega para
      // o login por outro motivo que não o que este exemplo investiga.
      .mockImplementationOnce(async () => {
        setAccessToken('access-apos-429')
        return { access_token: 'access-apos-429', user: USER }
      })

    vi.spyOn(authService, 'checkSessionStatus')
      .mockResolvedValue({ authenticated: true, valid: true, user: USER } as never)

    renderGuarded()

    // A segunda tentativa acontece depois de uma espera — o exemplo aguarda por
    // ela em vez de fingir que e sincrona.
    await waitFor(() => expect(refresh).toHaveBeenCalledTimes(2), { timeout: 5000 })
    await waitFor(() => expect(screen.queryByText(/Verificando sessão/)).toBeNull())

    // O que importa: NAO foi para o login.
    expect(screen.queryByTestId('tela-login')).toBeNull()
  }, 10000)

  /**
   * O contrario tambem tem de valer: 401 e veredito, e ai a sessao acaba mesmo.
   * Sem este exemplo, alguem poderia "consertar" o de cima tornando o bootstrap
   * indestrutivel — e sessao revogada continuaria abrindo a tela.
   */
  it('401 na renovação encerra a sessão — isso é veredito, não espera', async () => {
    const err401 = Object.assign(new Error('Unauthorized'), {
      response: { status: 401 },
    })
    const refresh = vi.spyOn(authService, 'refreshAccessToken').mockRejectedValue(err401)

    renderGuarded()

    await waitFor(() => expect(screen.getByTestId('tela-login')).toBeTruthy())
    // Uma vez só: não fica insistindo contra um "não".
    expect(refresh).toHaveBeenCalledTimes(1)
  })

})
