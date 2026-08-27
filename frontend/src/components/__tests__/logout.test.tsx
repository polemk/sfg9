import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { authService } from '@/lib/api/auth'
import { useAuthStore } from '@/store/authStore'
import { setAccessToken, getAccessToken } from '@/lib/api/tokenStore'
import { impersonateApi } from '@/lib/api/endpoints'

// O Sidebar depende de contextos que não têm relação com o logout; mockados
// para o teste exercitar só a decisão que interessa.
vi.mock('@/contexts/ChatContext', () => ({
  useChat: () => ({ isOpen: false, toggleChat: vi.fn() }),
}))

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual<any>('react-router-dom')
  return { ...actual, useNavigate: () => vi.fn(), useLocation: () => ({ pathname: '/dashboard' }) }
})

// A sidebar agora lê o projeto corrente (contrato C1) por React Query, para o
// gate `projects.count > 0` do menu. `retry: false` evita que a chamada que
// falha no ambiente de teste segure o `waitFor`.
function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

/**
 * O menu do usuário virou `FloatingPanel` (portal), e painel fechado não tem
 * DOM — a correção da armadilha do `backdrop-filter` na `Sidebar`. Para chegar
 * ao "Sair" é preciso ABRIR o cartão de perfil, que é exatamente o que o
 * usuário faz.
 */
function abrirMenuDoUsuario() {
  fireEvent.click(screen.getByLabelText('Menu do usuário'))
}

/**
 * Com a sessão no cookie HttpOnly, o "logout" que limpa só o estado local NÃO
 * desloga: o JS não alcança o cookie, então ele sobrevive e o próximo bootstrap
 * (ProtectedRoute → /sessions/refresh) ressuscita a sessão. Só o DELETE no
 * backend revoga os tokens na denylist e apaga os cookies.
 *
 * Este teste existe porque a migração para cookie quebrou exatamente isso em
 * dois componentes que antes davam conta removendo o token do localStorage.
 */
describe('logout — precisa chamar o backend, não só limpar o estado', () => {
  beforeEach(() => {
    setAccessToken('access-vivo')
    useAuthStore.getState().setAuth('access-vivo', { id: 'u-1', name: 'Mestre' } as any)
  })

  afterEach(() => vi.restoreAllMocks())

  it('Sidebar: o botão Sair emite DELETE /auth/v1/sessions/logout', async () => {
    const spy = vi.spyOn(authService, 'logout').mockResolvedValue(undefined)
    const { Sidebar } = await import('@/components/Sidebar')

    render(<Envolvido><Sidebar /></Envolvido>)

    abrirMenuDoUsuario()
    const botao = await screen.findByRole('button', { name: /^sair$/i })
    fireEvent.click(botao)

    await waitFor(() => expect(spy).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(useAuthStore.getState().isAuthenticated).toBe(false))
    expect(getAccessToken()).toBeNull()
  })

  it('mesmo com o backend fora do ar, o estado local é limpo', async () => {
    const spy = vi.spyOn(authService, 'logout').mockRejectedValue(new Error('network'))
    const { Sidebar } = await import('@/components/Sidebar')

    render(<Envolvido><Sidebar /></Envolvido>)
    abrirMenuDoUsuario()
    fireEvent.click(await screen.findByRole('button', { name: /^sair$/i }))

    await waitFor(() => expect(spy).toHaveBeenCalled())
    await waitFor(() => expect(useAuthStore.getState().isAuthenticated).toBe(false))
  })

  // Mesma CLASSE de defeito, terceiro ponto: o fallback de erro do
  // stop-impersonation também derrubava só o estado local.
  it('ImpersonateSelector: o logout de emergência também emite o DELETE', async () => {
    useAuthStore.setState({ impersonating: true, trueUser: { id: 'u-og', name: 'OG' } as any })
    vi.spyOn(impersonateApi, 'stop').mockRejectedValue({ response: { status: 500 } })
    const spy = vi.spyOn(authService, 'logout').mockResolvedValue(undefined)
    const { ImpersonateSelector } = await import('@/components/ImpersonateSelector')

    const { container } = render(<Envolvido><ImpersonateSelector /></Envolvido>)
    // Buscar por ÍNDICE quebrou quando o gatilho virou o cartão padronizado:
    // o teste passou a clicar noutro botão. O rótulo acessível é estável e é o
    // que o usuário de leitor de tela usa.
    fireEvent.click(screen.getByLabelText('Encerrar impersonação'))

    await waitFor(() => expect(spy).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(useAuthStore.getState().isAuthenticated).toBe(false))
    expect(getAccessToken()).toBeNull()
  })
})
