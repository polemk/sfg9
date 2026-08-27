import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { authService } from '@/lib/api/auth'
import { notify } from '@/lib/notify'
import { useAuthStore } from '@/store/authStore'
import { Logo } from '@/components/brand/Logo'

export function OAuthCallbackPage() {
  const [params] = useSearchParams()
  const code = params.get('code') || ''
  const state = params.get('state') || ''
  const providerParam = (params.get('provider') || '').toLowerCase()
  const providerStored = localStorage.getItem('oauth_provider') || ''
  const provider = (providerParam || providerStored) as 'google' | 'facebook'
  // O Devise sinaliza sucesso com ?oauth=success e entrega os tokens em cookie
  // HttpOnly — antes vinham na query string, que vaza em histórico do navegador,
  // header Referer e log de acesso do nginx.
  const oauthSuccess = params.get('oauth') === 'success'
  const setAuth = useAuthStore((s) => s.setAuth)

  useEffect(() => {
    const run = async () => {
      // Devise já autenticou e setou os cookies: basta trocá-los por um access
      // em memória. Sem isso a sessão viveria só no cookie e o app não saberia.
      if (oauthSuccess) {
        const renewed = await authService.refreshAccessToken()
        if (renewed?.access_token) {
          setAuth(renewed.access_token, (renewed.user ?? { id: 'me' }) as any)
          window.location.href = '/dashboard'
          return
        }
        notify.error('Não foi possível concluir o login')
        window.location.href = '/login'
        return
      }

      // Fluxo via code/state (Grape)
      if (!code || !provider) {
        notify.error('Callback inválido')
        window.location.href = '/login'
        return
      }
      try {
        const expectedState = localStorage.getItem('oauth_state')
        if (expectedState && state && expectedState !== state) {
          notify.error('State inválido')
          window.location.href = '/login'
          return
        }
        const resp = await authService.handleOAuthCallback(provider, code)
        const user = resp.user as any
        setAuth(resp.access_token, user)
        if ((user.user_type || '').toLowerCase() === 'free') {
           window.location.href = '/profile'
        } else {
           window.location.href = '/dashboard'
        }
      } catch (e) {
        notify.error('Falha na autenticação OAuth')
        window.location.href = '/login'
      }
    }
    run()
  }, [code, provider, state, oauthSuccess, setAuth])

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-sm rounded-lg border border-border bg-card p-8 text-center shadow-e1">
        {/* A marca é sempre o componente Logo — nenhuma tela redesenha o Safegold */}
        <Logo variant="full" height={32} className="mb-6 justify-center" />
        <p className="text-sm text-muted-foreground">Processando login...</p>
      </div>
    </div>
  )
}