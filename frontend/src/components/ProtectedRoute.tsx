import React, { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'
import { getAccessToken, setCsrfToken } from '@/lib/api/tokenStore'

interface ProtectedRouteProps {
  children: React.ReactNode
}

export function ProtectedRoute({ children }: ProtectedRouteProps) {
  const { restoreSession, logout } = useAuthStore()
  const [checking, setChecking] = useState(true)
  const [sessionValid, setSessionValid] = useState<boolean | null>(null)

  useEffect(() => {
    let mounted = true

    /**
     * Bootstrap de sessão: troca o refresh token do cookie HttpOnly por um novo
     * access token (em memória). É o único jeito de restaurar a sessão após um
     * reload, já que o access token não é persistido em lugar nenhum.
     * @returns true se a sessão foi restaurada (ou se o componente desmontou no
     *          meio, caso em que o chamador não deve mexer em estado).
     */
    async function tryRefresh(): Promise<boolean> {
      // **Um 429 aqui NAO e sessao invalida.**
      //
      // Isto mandava gente logada de volta para o login em producao. Depois de um
      // F5 nao ha access token em memoria — ele nunca e persistido —, entao o
      // bootstrap SEMPRE passa por aqui. Se a renovacao levava 429, o `catch`
      // devolvia `false` e o chamador dava `logout()`.
      //
      // E o 429 estava acontecendo em uso normal: teto de 60/min para uma tela
      // que dispara uma chamada por navegacao e refaz TODAS as consultas quando
      // se troca de projeto.
      //
      // A distincao e simples: 401 e 403 sao veredito do servidor sobre a
      // credencial — ai a sessao acabou mesmo. Qualquer outra coisa (429, erro
      // de rede, 5xx) e transitoria, e o cookie de refresh continua valido.
      // Nesses casos vale esperar e tentar de novo, e nao destruir a sessao.
      const ESPERAS_MS = [1500, 4000]

      for (let tentativa = 0; ; tentativa += 1) {
        try {
          const renewed = await authService.refreshAccessToken()
          if (!mounted) return true
          if (!renewed?.access_token) return false

          const retry = await authService.checkSessionStatus()
          if (!mounted) return true
          if (!((retry?.authenticated || retry?.valid) && retry.user)) return false

          restoreSession(retry.user as any)
          if (retry.csrf_token) setCsrfToken(retry.csrf_token)
          setSessionValid(true)
          return true
        } catch (e) {
          if (!mounted) return true

          const status = (e as { response?: { status?: number } })?.response?.status ?? 0
          const credencialRecusada = status === 401 || status === 403

          // Sem mais tentativas, ou o servidor recusou a credencial: desiste.
          if (credencialRecusada || tentativa >= ESPERAS_MS.length) return false

          await new Promise((resolve) => setTimeout(resolve, ESPERAS_MS[tentativa]))
          if (!mounted) return true
        }
      }
    }

    async function verify() {
      try {
        // Reload/aba nova: sem access em memória, restaura direto pelo cookie
        if (!getAccessToken()) {
          if (await tryRefresh()) return
          logout()
          setSessionValid(false)
          return
        }

        const res = await authService.checkSessionStatus()
        if (!mounted) return

        if ((res?.authenticated || res?.valid) && res.user) {
          restoreSession(res.user as any)
          if (res.csrf_token) setCsrfToken(res.csrf_token)
          setSessionValid(true)
        } else {
          // Access token expirado NÃO é o mesmo que sessão inválida: o /sessions/status
          // responde 200 {valid:false} nesse caso, então o interceptor do axios nunca é
          // acionado e nenhum refresh é tentado.
          if (await tryRefresh()) return

          logout()
          setSessionValid(false)
        }
      } catch {
        if (!mounted) return
        // Erro de rede/servidor com access em memória: não destrói a sessão;
        // confia no token local e deixa as próximas chamadas tratarem expiração.
        if (getAccessToken()) {
          setSessionValid(true)
        } else {
          logout()
          setSessionValid(false)
        }
      } finally {
        if (mounted) setChecking(false)
      }
    }

    verify()
    return () => { mounted = false }
  }, [restoreSession, logout])

  if (!checking && (sessionValid === false || !getAccessToken())) {
    return <Navigate to="/login" replace />
  }

  if (checking) {
    return (
      <div className="flex h-screen items-center justify-center">
        <span className="text-sm text-muted-foreground">Verificando sessão…</span>
      </div>
    )
  }

  return <>{children}</>
}
