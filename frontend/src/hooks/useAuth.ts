import { useState, useCallback, useEffect } from 'react'
import { setCsrfToken, clearTokens } from '@/lib/api/tokenStore'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'
import { notify } from '@/lib/notify'

export const useAuth = () => {
  const {
    loginMethod,
    identifier,
    loginCode,
    isLoading,
    error,
    setLoginMethod,
    setIdentifier,
    setLoginCode,
    setLoading,
    setError,
    clearError,
    setAuth,
    setDevCode,
    logout: logoutStore,
    isAuthenticated
  } = useAuthStore()

  const [isValidating, setIsValidating] = useState(false)
  const [lastRequestTime, setLastRequestTime] = useState<number>(0)
  const REQUEST_COOLDOWN = 3000 // 3 segundos entre requisições
  const [refreshTimerId, setRefreshTimerId] = useState<number | null>(null)

  // Validação de email
  const validateEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  }

  // Validação de WhatsApp (número brasileiro)
  const validateWhatsApp = (phone: string): boolean => {
    const cleanPhone = phone.replace(/\D/g, '')
    return cleanPhone.length >= 11 && cleanPhone.length <= 15
  }

  // Solicitar código de login
  const requestMagicLogin = useCallback(async () => {
    if (!identifier.trim()) {
      setError('Por favor, insira seu email ou número de WhatsApp')
      return
    }

    // Validação baseada no método
    if (loginMethod === 'email' && !validateEmail(identifier)) {
      setError('Por favor, insira um email válido')
      return
    }

    if (loginMethod === 'whatsapp' && !validateWhatsApp(identifier)) {
      setError('Por favor, insira o WhatsApp com código do país sem + (ex: 5511999999999)')
      return
    }

    // Rate limiting - verificar cooldown
    const now = Date.now()
    const timeSinceLastRequest = now - lastRequestTime
    if (timeSinceLastRequest < REQUEST_COOLDOWN) {
      const remainingTime = Math.ceil((REQUEST_COOLDOWN - timeSinceLastRequest) / 1000)
      setError(`Aguarde ${remainingTime} segundos antes de solicitar um novo código`)
      return
    }

    setLoading(true)
    setError(null)
    setLastRequestTime(now)

    try {
      const normalizedIdentifier = loginMethod === 'whatsapp'
        ? identifier.replace(/\D/g, '')
        : identifier.trim()
      const response = await authService.requestLoginCode({
        identifier: normalizedIdentifier,
        method: loginMethod
      })

      console.log('Magic login code requested successfully:', { identifier, method: loginMethod })
      if (import.meta.env.MODE === 'development' && (response as any)?.code) {
        setDevCode((response as any).code)
      } else {
        setDevCode(null)
      }
      return true
    } catch (error: any) {
      const data = error.response?.data
      const errorMessage = data?.message || data?.error || 'Erro ao enviar código'
      console.error('Magic login request failed:', error)
      setError(errorMessage)
      return false
    } finally {
      setLoading(false)
    }
  }, [identifier, loginMethod, setLoading, setError])

  // Agendar refresh antes da expiração
  useEffect(() => {
    // Sem auto-refresh: manter sessão até expirar e então deslogar
    if (refreshTimerId) window.clearTimeout(refreshTimerId)
    setRefreshTimerId(null)
  }, [isAuthenticated])

  // Validar código de 6 dígitos
  const validateMagicCode = useCallback(async () => {
    const { loginCode: currentCode, identifier: currentIdentifier, loginMethod: currentMethod } = useAuthStore.getState()
    if (!currentCode.trim()) {
      setError('Por favor, insira o código recebido')
      return false
    }

    if (currentCode.length !== 6) {
      setError('O código deve ter 6 dígitos')
      return false
    }

    // Validação de caracteres numéricos apenas
    if (!/^\d{6}$/.test(currentCode)) {
      setError('O código deve conter apenas números')
      return false
    }

    // Rate limiting para validação
    const now = Date.now()
    const timeSinceLastRequest = now - lastRequestTime
    if (timeSinceLastRequest < REQUEST_COOLDOWN) {
      const remainingTime = Math.ceil((REQUEST_COOLDOWN - timeSinceLastRequest) / 1000)
      setError(`Aguarde ${remainingTime} segundos antes de tentar novamente`)
      return false
    }

    if (!currentIdentifier) {
      setError('Identificador não encontrado')
      return false
    }

    setIsValidating(true)
    setError(null)
    setLastRequestTime(now)

    try {
      const result = await authService.validateLoginCode({
        identifier: currentIdentifier,
        code: currentCode,
        method: currentMethod
      })
      if (result.access_token && result.user) {
        // Persistir tokens
        setAuth(result.access_token, result.user as any)
        // Validar sessão no backend antes de redirecionar
        const status = await authService.checkSessionStatus()
        if (status?.authenticated || status?.valid) {
          if (status.csrf_token) {
            setCsrfToken(status.csrf_token)
          }
          if (((status.user as any)?.user_type || '').toLowerCase() === 'free') {
            window.location.href = '/profile'
          } else {
            window.location.href = '/dashboard'
          }
          return 'login'
        }
        // Sessão inválida: limpar e informar. O backend acabou de setar os
        // cookies HttpOnly, então o DELETE é necessário — sem ele o refresh
        // sobreviveria e restauraria a sessão que acabou de ser recusada.
        try {
          await authService.logout()
        } catch {
          // Rede fora ou sessão já morta: segue com a limpeza local.
        }
        clearTokens()
        useAuthStore.getState().logout()
        notify.error('Sessão inválida. Faça login novamente.')
        return 'invalid'
      }
      return 'invalid'
    } catch (error: any) {
      // O corpo de erro da API é `{error, message, code}` (api/CONTRATO.md §3), então
      // a mensagem está em `data.message` — `data.error.message` era leitura de uma
      // forma que a API nunca devolveu, e por isso TODO erro de login virava o texto
      // genérico. Conta bloqueada é o caso que mais doía: a pessoa via "Código
      // inválido ou expirado" quando o problema era outro (IMP-A17).
      const data = error.response?.data
      if (data?.code === 'ACCOUNT_BLOCKED') {
        setError(data.message || 'Sua conta está bloqueada. Fale com o administrador do projeto.')
        return 'blocked'
      }
      const errorMessage = data?.message || data?.error || 'Código inválido ou expirado'
      console.error('Magic login validation failed:', error)
      setError(errorMessage)
      return 'invalid'
    } finally {
      setIsValidating(false)
    }
  }, [loginCode, identifier, loginMethod, setAuth, setError])

  // Login com Google
  const loginWithGoogle = useCallback(async () => {
    try {
      const response = await authService.getGoogleAuthUrl()
      if (response.state) localStorage.setItem('oauth_state', response.state)
      localStorage.setItem('oauth_provider', 'google')
      window.location.href = response.url
    } catch (error) {
      notify.error('Erro ao conectar com Google')
    }
  }, [])

  // Login com Facebook
  const loginWithFacebook = useCallback(async () => {
    try {
      const response = await authService.getFacebookAuthUrl()
      if (response.state) localStorage.setItem('oauth_state', response.state)
      localStorage.setItem('oauth_provider', 'facebook')
      window.location.href = response.url
    } catch (error) {
      notify.error('Erro ao conectar com Facebook')
    }
  }, [])

  // Logout
  // **FE-039 — erro de logout deixa de ser silenciosamente ignorado.**
  //
  // A limpeza local acontece de qualquer jeito (`finally`): prender a pessoa numa
  // sessão que ela pediu para encerrar seria pior. Mas ela precisa SABER que o
  // servidor não confirmou, porque nesse caso a sessão pode continuar válida noutro
  // dispositivo — e é a diferença entre "saí" e "achei que tinha saído".
  //
  // Logout de quem já está deslogado não cai aqui: o backend passou a responder 200
  // (BE-005), então sair de uma sessão expirada não mostra susto nenhum.
  const logout = useCallback(async () => {
    try {
      await authService.logout()
    } catch (error) {
      console.error('Erro ao fazer logout:', error)
      notify.error('Não foi possível confirmar o logout no servidor. Se estiver em um computador compartilhado, feche o navegador.')
    } finally {
      // Limpar localStorage
      clearTokens()
      
      // Limpar store
      logoutStore()
      
      // Redirecionar para login
      window.location.href = '/login'
    }
  }, [logoutStore])

  // Verificar status da sessão
  const checkSession = useCallback(async () => {
    try {
      const response = await authService.checkSessionStatus()
      return response
    } catch (error: any) {
      if (error.response?.status === 401) {
        return { authenticated: false, user: null }
      }
      throw error
    }
  }, [logoutStore])

  return {
    // Estado
    loginMethod,
    identifier,
    loginCode,
    isLoading,
    isValidating,
    error,
    
    // Actions
    setLoginMethod,
    setIdentifier,
    setLoginCode,
    clearError,
    requestMagicLogin,
    validateMagicCode,
    loginWithGoogle,
    loginWithFacebook,
    logout,
    checkSession
  }
}
