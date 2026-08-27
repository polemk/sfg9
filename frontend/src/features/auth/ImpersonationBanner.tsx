import { useState } from 'react'
import { Eye, UserX } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import { clearTokens } from '@/lib/api/tokenStore'
import { authService } from '@/lib/api/auth'
import { impersonateApi } from '@/lib/api/endpoints'
import { useAuthStore } from '@/store/authStore'

/**
 * **A faixa persistente de "Vendo como"** — FE-037.
 *
 * ## Por que ela existe, e por que no `Layout`
 *
 * O aviso de impersonação vivia **só dentro da barra lateral**
 * (`Sidebar → ImpersonationWarning`), e a barra lateral nasce **recolhida**
 * (`localStorage.sidebar_collapsed` default `true`) e **não existe no telefone**.
 * Ou seja: na configuração padrão, e no celular inteiro, quem estava vendo o
 * sistema como outra pessoa via um ícone de olho — ou nada.
 *
 * Isso é perigoso de um jeito específico: cada ação feita nesse estado é gravada
 * na trilha como do usuário personificado. Quem esquece que está personificando
 * lança dado financeiro no nome de outra pessoa. **A faixa é a única peça que
 * aparece em todas as larguras e em todas as telas do console**, e por isso ela
 * mora na moldura, não numa tela — é a mesma razão do `TermsBanner` ao lado.
 *
 * ## O que ela NÃO faz
 *
 * Não pode ser dispensada. O `TermsBanner` pode, porque aceitar um contrato é uma
 * pendência administrativa; estar personificando é um **estado da sessão**, e um
 * aviso de estado que a pessoa fecha é um aviso que ela deixa de ver justamente
 * quando ele importa.
 *
 * ## Encerrar
 *
 * `POST /auth/v1/impersonate/stop`. Se o servidor recusar, o caminho é o mesmo do
 * botão "Sair": o `DELETE` de logout, porque limpar só o estado local deixaria os
 * cookies HttpOnly vivos e a próxima rota protegida ressuscitaria a sessão
 * personificada — que é o pior desfecho possível aqui.
 */
export function ImpersonationBanner() {
  const impersonating = useAuthStore((s) => s.impersonating)
  const alvo = useAuthStore((s) => s.user)
  const eu = useAuthStore((s) => s.trueUser)
  const stopImpersonation = useAuthStore((s) => s.stopImpersonation)
  const logout = useAuthStore((s) => s.logout)
  const [encerrando, setEncerrando] = useState(false)

  if (!impersonating) return null

  async function encerrar() {
    setEncerrando(true)
    try {
      const data = await impersonateApi.stop()
      stopImpersonation(data.access_token, data.user)
      notify.success('Você voltou à sua conta')
      window.location.href = '/dashboard'
    } catch (erro: any) {
      const status = erro?.response?.status
      const code = erro?.response?.data?.error

      // 422 `not_impersonating`: o servidor já encerrou (a sessão personificada
      // expira em 1 hora) e só o estado local ficou para trás.
      if (status === 422 || code === 'not_impersonating') {
        useAuthStore.setState({ impersonating: false, trueUser: null })
        notify.info('A sessão de impersonação já havia terminado.')
        window.location.reload()
        return
      }

      notify.error('Não consegui encerrar pelo servidor. Encerrando a sessão inteira por segurança.')
      try {
        await authService.logout()
      } catch {
        // Rede fora: segue com a limpeza local, que agora é a única saída.
      }
      clearTokens()
      logout()
      window.location.href = '/login'
    } finally {
      setEncerrando(false)
    }
  }

  return (
    <div
      role="status"
      aria-live="polite"
      className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-warning/30 bg-warning/10 px-4 py-2.5 md:px-6"
    >
      <Eye aria-hidden="true" className="h-4 w-4 shrink-0 text-warning" />

      <p className="min-w-0 flex-1 text-sm text-foreground">
        <span className="font-semibold text-warning">Vendo como {alvo?.name || alvo?.email}</span>
        {eu && (
          <span className="text-muted-foreground">
            {' '}— tudo o que você fizer fica na trilha em nome de {alvo?.name?.split(' ')[0] || 'esta pessoa'},
            iniciado por {eu.name || eu.email}.
          </span>
        )}
      </p>

      <Button
        variant="secondary"
        size="sm"
        onClick={encerrar}
        disabled={encerrando}
        className="shrink-0"
      >
        <UserX aria-hidden="true" className="mr-1.5 h-3.5 w-3.5" />
        {encerrando ? 'Encerrando…' : 'Voltar a ser eu'}
      </Button>
    </div>
  )
}
