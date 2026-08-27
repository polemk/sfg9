import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { AuthFlow } from '@/features/auth/AuthFlow'
import { LoginNotice, safeNextPath } from '@/features/auth/LoginNotice'
import { useAuthStore } from '@/store/authStore'
import { LoginCarousel } from '@/components/LoginCarousel'
import { Logo } from '@/components/brand/Logo'
import { ThemeToggle } from '@/components/ThemeToggle'

export function LoginPage() {
  const { isAuthenticated, user } = useAuthStore()
  const navigate = useNavigate()

  // O tipo `free` não existe mais (DEC-41), então o desvio para `/profile` que
  // dependia dele era código morto. O destino agora é o `?next=` — validado como
  // **same-origin** por `safeNextPath` — ou o dashboard.
  useEffect(() => {
    if (isAuthenticated && user) {
      const next = safeNextPath(new URLSearchParams(window.location.search).get('next'))
      navigate(next || '/dashboard')
    }
  }, [isAuthenticated, user, navigate])

  return (
    <div className="flex min-h-screen overflow-hidden bg-background text-foreground">
      {/* Formulário — segue o tema do usuário (claro OU escuro), nunca uma
          superfície escura fixa. Era `bg-[#0A0A0B]` cravado, o que dava painel
          preto sobre app claro. */}
      <div className="relative z-20 flex w-full min-w-[320px] flex-col justify-center border-r border-border bg-background px-8 sm:px-12 lg:w-[38%]">
        <div className="absolute right-6 top-6">
          <ThemeToggle />
        </div>

        <div className="mx-auto w-full max-w-sm space-y-8 duration-700 animate-in fade-in slide-in-from-bottom-4">
          <div className="flex justify-center">
            <Logo variant="full" height={38} />
          </div>

          <LoginNotice />

          <AuthFlow />

          <p className="text-center text-xs text-muted-foreground">
            Safegold — gestão de risco e recebíveis
          </p>
        </div>
      </div>

      {/* Painel de marca */}
      <div className="relative z-10 hidden lg:block lg:w-[62%]">
        <LoginCarousel />
      </div>
    </div>
  )
}
