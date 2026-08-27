import axios, { AxiosInstance, AxiosRequestConfig, AxiosError } from 'axios'
/* import { toast } from 'sonner' */
import { useAuthStore } from '@/store/authStore'
import { getAccessToken, setAccessToken, clearTokens } from './tokenStore'

const API_URL = import.meta.env.VITE_API_URL || ''

class ApiClient {
  private client: AxiosInstance
  private isRefreshing = false
  private refreshQueue: Array<(token: string | null) => void> = []

  constructor() {
    this.client = axios.create({
      baseURL: `${API_URL}`,
      timeout: 30000,
      // withCredentials: envia o cookie HttpOnly do refresh (restrito a /auth/v1
      // pelo atributo Path — os demais endpoints não recebem cookie algum).
      withCredentials: true,
      // headers: { 'Content-Type': 'application/json' } // Default handling by Axios is better for FormData support
    })

    this.setupInterceptors()
  }

  /**
   * Renova a sessão usando o cookie HttpOnly (sem argumentos: o refresh token é
   * invisível ao JS). Retorna o novo access token ou null se a sessão acabou.
   * Usado pelo interceptor de 401 e pelo bootstrap de sessão (ProtectedRoute).
   */
  async refreshSession(): Promise<{ accessToken: string; user: any } | null> {
    try {
      // X-Skip-Auth: não anexa o access expirado e faz o 401 deste próprio POST
      // ser rejeitado de imediato (guard `isPublic`) em vez de entrar na
      // refreshQueue — que geraria deadlock, já que quem drena a fila é este await.
      const { data } = await this.client.post<{ access_token?: string; token?: string; user?: any }>(
        '/auth/v1/sessions/refresh',
        {},
        { headers: { 'X-Skip-Auth': '1' } }
      )
      const newAccess = data.access_token || data.token
      if (!newAccess) return null
      setAccessToken(newAccess)
      return { accessToken: newAccess, user: data.user ?? null }
    } catch {
      return null
    }
  }

  /**
   * Encerra a sessão local e volta para o login.
   *
   * `reason` é o texto que a tela de login vai mostrar. Sem ele, uma sessão derrubada
   * por conta bloqueada era **logout mudo**: a pessoa via o formulário de novo e não
   * sabia se errou o código, se caiu a rede ou se perdeu o acesso (IMP-A17). O motivo
   * viaja por `sessionStorage` porque a volta ao login é uma navegação de página
   * inteira — em query string ele ficaria no histórico do navegador.
   */
  private endSession(reason?: string) {
    clearTokens()
    useAuthStore.getState().logout()
    try {
      if (reason) sessionStorage.setItem('auth:endedReason', reason)
      if (!window.location.pathname.startsWith('/login')) {
        (window as any).location.href = '/login'
      }
    } catch { /* intentionally ignored */ }
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        // Skip ngrok browser warning in development
        config.headers['ngrok-skip-browser-warning'] = '1'

        const skip = (config.headers as any)?.['X-Skip-Auth'] === '1'
        if (!skip) {
          const token = getAccessToken()
          if (token) {
            config.headers.Authorization = `Bearer ${token}`
          }
        }
        return config
      },
      (error) => {
        return Promise.reject(error)
      }
    )

    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError) => {
        const original = error.config as (AxiosRequestConfig & { _retry?: boolean }) | undefined
        const status = error.response?.status || 0
        const isUnauthorized = status === 401
        const isForbidden = status === 403
        const data = error.response?.data as any

        // **DEC-39 — conta bloqueada.** O gate central responde 403 com
        // `ACCOUNT_BLOCKED` e o motivo. Não adianta tentar renovar a sessão: o token
        // não expirou, a conta é que perdeu o acesso. Encerra a sessão levando a
        // explicação para a tela de login.
        if (isForbidden && data?.code === 'ACCOUNT_BLOCKED') {
          this.endSession(data?.message || 'Sua conta está bloqueada. Fale com o administrador do projeto.')
          return Promise.reject(error)
        }

        // Perfil somente-leitura: o backend responde 403 com `READONLY_RESTRICTED`
        // (`require_not_readonly!`). O nome antigo lido aqui era `VISITOR_RESTRICTED`,
        // que nenhum endpoint emite desde que a DEC-41 removeu o tipo `visitor` — ou
        // seja, este ramo estava morto e todo 403 de readonly caía no fluxo de refresh.
        // O modal de upgrade que abria aqui saiu com o AI9-002 (Bloco 4).
        if (isForbidden && (data?.code === 'READONLY_RESTRICTED' || data?.code === 'ROLE_REQUIRED')) {
          return Promise.reject(error)
        }

        // Guard: if config is missing (network error, cancelled request), reject immediately
        if (!original) {
          return Promise.reject(error)
        }

        const isPublic = original.headers && (original.headers['X-Skip-Auth'] || (original.headers as any)['x-skip-auth'])

        if (!isUnauthorized || original._retry || isPublic) {
          return Promise.reject(error)
        }

        if (this.isRefreshing) {
          return new Promise((resolve, reject) => {
            this.refreshQueue.push((token) => {
              if (!token) {
                reject(error)
                return
              }
              original._retry = true
              original.headers = { ...(original.headers || {}), Authorization: `Bearer ${token}` }
              this.client.request(original).then(resolve).catch(reject)
            })
          })
        }

        this.isRefreshing = true
        try {
          // Tenta renovar via cookie HttpOnly. Se não houver cookie (nunca logou
          // ou sessão revogada), o backend responde 401 e caímos no catch.
          const renewed = await this.refreshSession()
          if (!renewed) throw error

          this.refreshQueue.forEach((cb) => cb(renewed.accessToken))
          this.refreshQueue = []
          original._retry = true
          original.headers = { ...(original.headers || {}), Authorization: `Bearer ${renewed.accessToken}` }
          return this.client.request(original)
        } catch (e) {
          this.refreshQueue.forEach((cb) => cb(null))
          this.refreshQueue = []
          // Refresh falhou: sessão inválida, limpar e redirecionar
          this.endSession()
          return Promise.reject(error)
        } finally {
          this.isRefreshing = false
        }
      }
    )
  }

  async get<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.get<T>(url, config)
    return response.data
  }

  /** Returns the full Axios response (with headers). Useful for blob downloads. */
  async getRaw<T>(url: string, config?: AxiosRequestConfig) {
    return this.client.get<T>(url, config)
  }

  async getPublic<T>(url: string, config?: AxiosRequestConfig) {
    const headers = { ...(config?.headers || {}), 'X-Skip-Auth': '1' }
    const response = await this.client.get<T>(url, { ...(config || {}), headers })
    return response.data
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.post<T>(url, data, config)
    return response.data
  }

  async postPublic<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const headers = { ...(config?.headers || {}), 'X-Skip-Auth': '1' }
    const response = await this.client.post<T>(url, data, { ...(config || {}), headers })
    return response.data
  }

  /** POST FormData to a public endpoint (no auth). Axios auto-sets multipart Content-Type. */
  async postPublicForm<T>(url: string, formData: FormData, config?: AxiosRequestConfig) {
    const headers = { ...(config?.headers || {}), 'X-Skip-Auth': '1' }
    const response = await this.client.post<T>(url, formData, { ...(config || {}), headers })
    return response.data
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.put<T>(url, data, config)
    return response.data
  }

  async patch<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.patch<T>(url, data, config)
    return response.data
  }

  async delete<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.delete<T>(url, config)
    return response.data
  }

  // --- Chat Flows ---
  async getFlowByContext(userType: string, routePath: string) {
    const token = getAccessToken()
    return this.get<any>(`/api/v1/flows/contextual`, {
      params: { user_type: userType, route_path: routePath },
      headers: token ? { Authorization: `Bearer ${token}` } : {}
    })
  }

}

export const apiClient = new ApiClient()
