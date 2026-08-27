import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen } from '@testing-library/react'
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
})
