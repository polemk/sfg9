import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { MagicLinkCallbackPage } from '@/features/auth/MagicLinkCallbackPage'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'
import { getAccessToken, clearTokens } from '@/lib/api/tokenStore'

const USER = { id: 'u-1', email: 'mestre@ai9.dev', name: 'Mestre' } as any

function renderCallback() {
  return render(
    <MemoryRouter initialEntries={['/magic-login/callback?token=tok-do-link']}>
      <MagicLinkCallbackPage />
    </MemoryRouter>
  )
}

/**
 * Com o refresh em cookie HttpOnly, a resposta do /magic_link/verify passou a
 * trazer SÓ access_token e user — o refresh sai em Set-Cookie e o JS nunca o vê.
 * A página, porém, continuou exigindo `resp.refresh_token` para seguir, então
 * todo acesso por magic link caía em "Resposta inválida do servidor".
 *
 * Nenhum teste pegou: o caminho é de UI e depende do formato da resposta.
 */
describe('MagicLinkCallbackPage — sessão sem refresh_token no corpo', () => {
  beforeEach(() => {
    clearTokens()
    useAuthStore.getState().logout()
  })

  afterEach(() => vi.restoreAllMocks())

  it('autentica com a resposta atual (access_token + user, sem refresh_token)', async () => {
    vi.spyOn(authService, 'verifyMagicLink').mockResolvedValue({
      access_token: 'access-novo',
      user: USER
    } as any)

    renderCallback()

    await waitFor(() => expect(useAuthStore.getState().isAuthenticated).toBe(true))
    expect(getAccessToken()).toBe('access-novo')
    expect(screen.queryByText(/Resposta inválida do servidor/i)).toBeNull()
  })

  it('ainda recusa resposta sem access_token ou sem user', async () => {
    vi.spyOn(authService, 'verifyMagicLink').mockResolvedValue({
      access_token: 'access-novo'
    } as any)

    renderCallback()

    await waitFor(() => expect(screen.getByText(/Resposta inválida do servidor/i)).toBeTruthy())
    expect(useAuthStore.getState().isAuthenticated).toBe(false)
  })
})
