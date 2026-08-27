import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { authService } from '@/lib/api/auth'
import { useAuthStore } from '@/store/authStore'
import { Logo } from '@/components/brand/Logo'

export function MagicLinkCallbackPage() {
  const [params] = useSearchParams()
  const token = params.get('token') || ''
  const setAuth = useAuthStore((s) => s.setAuth)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!token) {
      setError('Link inválido ou expirado.')
      return
    }

    authService.verifyMagicLink(token)
      .then((resp) => {
        // Não exija refresh_token aqui: ele não volta mais no corpo — sai em
        // cookie HttpOnly (Set-Cookie), invisível ao JS. Enquanto a condição
        // existiu, TODO acesso por magic link caía no erro abaixo.
        if (!resp.access_token || !resp.user) {
          setError('Resposta inválida do servidor. Tente novamente.')
          return
        }
        // Access em memória; refresh chegou via Set-Cookie HttpOnly
        setAuth(resp.access_token, resp.user as any)
        window.history.replaceState({}, '', '/magic-login')
        window.location.href = '/dashboard'
      })
      .catch(() => {
        setError('Link expirado ou já utilizado. Solicite um novo acesso.')
      })
  }, [token, setAuth])

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-sm rounded-lg border border-border bg-card p-8 text-center shadow-e1">
        {/* A marca é sempre o componente Logo — nenhuma tela redesenha o Safegold */}
        <Logo variant="full" height={32} className="mb-6 justify-center" />

        {error ? (
          <>
            <p className="mb-4 rounded-md border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
              {error}
            </p>
            <a
              href="/login"
              className="text-sm text-primary underline rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              Voltar ao login
            </a>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">Autenticando...</p>
        )}
      </div>
    </div>
  )
}
