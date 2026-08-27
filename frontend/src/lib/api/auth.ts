import { apiClient } from './client'
/* import { toast } from 'sonner' */

export interface MagicLoginRequest {
  identifier: string // email ou whatsapp
  method: 'email' | 'whatsapp'
}

export interface MagicLoginResponse {
  success: boolean
  message: string
  identifier: string
  method: 'email' | 'whatsapp'
  code?: string
}

export interface CodeValidationRequest {
  identifier: string
  code: string
  method: 'email' | 'whatsapp'
}

export interface AuthResponse {
  access_token: string
  // O refresh NUNCA volta no corpo — sai em cookie HttpOnly (Path=/auth/v1).
  refresh_token?: string
  user: {
    id: string
    email?: string
    whatsapp?: string
    name?: string
    avatar?: string
  }
}

export interface VerifyCodeResponse {
  success: boolean
  message?: string
  access_token?: string
  refresh_token?: string
  user?: {
    id: string
    email?: string
    whatsapp?: string
    phone?: string
    name?: string
    avatar?: string
  }
}

export interface OAuthUrlResponse {
  url: string
  provider?: 'google' | 'facebook'
  state?: string
}

export interface OAuthCallbackResponse {
  access_token: string
  refresh_token: string
  user: {
    id: string
    email?: string
    whatsapp?: string
    name?: string
    avatar?: string
  }
}

export interface SessionStatusResponse {
  // Alguns backends retornam `authenticated`; outros retornam `valid`.
  // Mantemos ambos por compatibilidade e normalizamos na função.
  authenticated?: boolean
  valid?: boolean
  user: {
    id: string
    email?: string
    whatsapp?: string
    name?: string
    avatar?: string
  } | null
  expires_at?: string
  csrf_token?: string | null
}

export interface RefreshTokenResponse {
  access_token: string
  // Sem refresh_token: ele vai em cookie HttpOnly, invisível ao JS.
  user?: any
}

class AuthService {
  // Magic Login - Solicitar código
  async requestMagicLogin(data: MagicLoginRequest): Promise<MagicLoginResponse> {
    try {
      const response = await apiClient.post<MagicLoginResponse>('/auth/v1/magic_login/request_code', data)
      return response
    } catch (error) {
      throw error
    }
  }

  // Magic Login - Validar código
  async validateMagicCode(data: CodeValidationRequest): Promise<AuthResponse> {
    try {
      const response = await apiClient.post<AuthResponse>('/auth/v1/magic_login/validate_code', data)
      const normalized: AuthResponse = {
        access_token: (response as any).access_token ?? (response as any).token,
        refresh_token: (response as any).refresh_token,
        user: (response as any).user
      }
      return normalized
    } catch (error) {
      throw error
    }
  }

  /**
   * Pede o código de acesso.
   *
   * Chamava `/auth/v1/pre_register`, que era a rota de **auto-cadastro** da base
   * ai9 e foi removida pela DEC-49 — no Safegold entra-se só por convite
   * (DEC-18.7), e aquela rota era a porta pela qual o defeito D-39 voltava.
   * `magic_login/request_code` faz o que o login precisa e **não cria usuário**:
   * responde "Usuário não encontrado" (`magic_login_service.rb:19`).
   */
  async requestLoginCode(data: { identifier: string; method: 'email' | 'whatsapp' }) {
    return await apiClient.post('/auth/v1/magic_login/request_code', data)
  }

  /**
   * Valida o código de acesso e abre a sessão.
   *
   * Chamava-se `verifyPreRegisterCode`, e o nome mentia duas vezes: não há
   * pré-cadastro (DEC-49 removeu as 4 rotas de auto-cadastro) e não há cadastro
   * nenhum neste caminho — entra-se só por convite (DEC-18.7). Renomeado junto com a
   * mudança, pela Regra de fronteira: nome que mente é reconsertado de volta pela
   * próxima pessoa.
   *
   * O terceiro desfecho `requires_completion` também saiu. Ele mandava o front para a
   * tela "Completar cadastro", que fazia `POST /auth/v1/complete_registration` — rota
   * removida. Era o mesmo defeito de fronteira que derrubou o login em 25/08/2026,
   * esperando o primeiro usuário que caísse no ramo.
   */
  async validateLoginCode(data: CodeValidationRequest): Promise<VerifyCodeResponse> {
    const response = await apiClient.postPublic<any>('/auth/v1/verify_code', data)
    return {
      success: response.success ?? true,
      message: response.message,
      access_token: response.access_token ?? response.token,
      refresh_token: response.refresh_token,
      user: response.user
    }
  }

  // OAuth - Google
  async getGoogleAuthUrl(): Promise<OAuthUrlResponse> {
    try {
      return await apiClient.get<OAuthUrlResponse>('/auth/v1/oauth/google_url')
    } catch (error) {
      throw error
    }
  }

  // OAuth - Facebook
  async getFacebookAuthUrl(): Promise<OAuthUrlResponse> {
    try {
      return await apiClient.get<OAuthUrlResponse>('/auth/v1/oauth/facebook_url')
    } catch (error) {
      throw error
    }
  }

  // OAuth - Callback
  async handleOAuthCallback(provider: 'google' | 'facebook', code: string): Promise<OAuthCallbackResponse> {
    try {
      const response = await apiClient.post<any>(`/auth/v1/oauth/callback`, { provider, code })
      const normalized: OAuthCallbackResponse = {
        access_token: response.access_token ?? response.token,
        refresh_token: response.refresh_token,
        user: response.user
      }
      return normalized
    } catch (error) {
      throw error
    }
  }

  // Sessão - Status
  async checkSessionStatus(): Promise<SessionStatusResponse> {
    try {
      const raw = await apiClient.get<any>('/auth/v1/sessions/status')
      const normalized: SessionStatusResponse = {
        authenticated: raw?.authenticated ?? raw?.valid ?? false,
        valid: raw?.valid,
        user: raw?.user ?? null,
        expires_at: raw?.expires_at,
        csrf_token: raw?.csrf_token ?? null,
      }
      return normalized
    } catch (error) {
      // Não mostrar erro para verificação de sessão
      throw error
    }
  }

  // Sessão - Refresh Token. Sem argumento: o refresh vive em cookie HttpOnly,
  // invisível ao JS, e o navegador o anexa sozinho (Path=/auth/v1).
  async refreshAccessToken(): Promise<RefreshTokenResponse | null> {
    const renewed = await apiClient.refreshSession()
    if (!renewed) return null
    return { access_token: renewed.accessToken, user: renewed.user }
  }

  // Magic Link - Verificar token e obter JWT
  async verifyMagicLink(token: string): Promise<AuthResponse> {
    const response = await apiClient.getPublic<any>(`/auth/v1/magic_link/verify?token=${encodeURIComponent(token)}`)
    return {
      access_token: response.token,
      user: response.user
    }
  }

  // `visitorSignup` FOI REMOVIDO. Chamava `/auth/v1/visitor_signup`, uma das 4 rotas
  // de auto-cadastro que a DEC-49 apagou — respondia 404 desde então. Método de
  // cliente apontando para rota que não existe é a metade de fronteira que ninguém vê:
  // compila, passa no `tsc`, e só falha na tela de quem clicar.

  // Sessão - Logout
  async logout(): Promise<void> {
    try {
      await apiClient.delete('/auth/v1/sessions/logout')
    } catch (error) {
      throw error
    }
  }
}

export const authService = new AuthService()
