/**
 * Armazenamento de credenciais de sessão SOMENTE em memória.
 *
 * Segurança: nenhum token é persistido em localStorage/sessionStorage — um XSS
 * não encontra credencial durável para roubar. A persistência da sessão entre
 * reloads vem do refresh_token em cookie HttpOnly (invisível ao JS), trocado
 * por um novo access token via POST /auth/v1/sessions/refresh no boot do app.
 *
 * Implementado com Zustand (sem `persist`) para que os tokens continuem apenas
 * em memória E, ao mesmo tempo, componentes possam REAGIR à chegada do access
 * token após o bootstrap (ex.: useCable reconecta o WebSocket quando o token
 * aparece; sem isso o realtime ficava mudo após um reload).
 */
import { create } from 'zustand'

interface TokenState {
  accessToken: string | null
  csrfToken: string | null
}

const useTokenStore = create<TokenState>(() => ({
  accessToken: null,
  csrfToken: null,
}))

export function getAccessToken(): string | null {
  return useTokenStore.getState().accessToken
}

export function setAccessToken(token: string | null): void {
  useTokenStore.setState({ accessToken: token })
}

export function getCsrfToken(): string | null {
  return useTokenStore.getState().csrfToken
}

export function setCsrfToken(token: string | null): void {
  useTokenStore.setState({ csrfToken: token })
}

/** Limpa todos os tokens em memória (logout/sessão inválida). */
export function clearTokens(): void {
  useTokenStore.setState({ accessToken: null, csrfToken: null })
}

/** Hook reativo: re-renderiza quando o access token muda (null → válido → rotação). */
export function useAccessToken(): string | null {
  return useTokenStore((s) => s.accessToken)
}

/**
 * Remove resíduos de tokens que versões antigas do app persistiam em
 * localStorage (chaves cruas e o estado persistido do authStore).
 * Chamado no boot — garante que sessões antigas não deixem credenciais expostas.
 */
export function purgeLegacyTokenStorage(): void {
  try {
    const legacyKeys = ['access_token', 'refresh_token', 'csrf_token', 'token']
    legacyKeys.forEach((key) => localStorage.removeItem(key))
    // Estado antigo do zustand/persist continha accessToken/refreshToken
    const persisted = localStorage.getItem('auth-storage')
    if (persisted && persisted.includes('"accessToken"')) {
      const parsed = JSON.parse(persisted)
      if (parsed?.state) {
        delete parsed.state.accessToken
        delete parsed.state.refreshToken
        localStorage.setItem('auth-storage', JSON.stringify(parsed))
      }
    }
  } catch {
    /* storage indisponível (SSR/teste) — nada a limpar */
  }
}
