import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { FileWarning, X } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import { useAuthStore } from '@/store/authStore'
import { contractsApi } from '@/lib/api/contracts'

/**
 * **O banner de aceite pendente** — a DEC-65 inteira, numa faixa.
 *
 * ## Por que banner e não bloqueio
 *
 * No legado o aceite explícito está morto por **quatro** causas independentes:
 * o bloqueio de acesso está inteiramente comentado
 * (`pub_application_controller.rb:55-63`); os dois botões "ACEITAR" estão
 * comentados nas views (`contracts/header/_body.html.erb:44`,
 * `_toolbar_body.html.erb:22`) com os handlers e a rota `PUT` **vivos e
 * inalcançáveis**; o cálculo de pendência levantava exceção por
 * `source: :contract_deal` inexistente (`user_decorator.rb:40`), de modo que
 * quem abrisse `/contract/:type` recebia 500; e os checkboxes vinham
 * pré-marcados sem controller nenhum que os lesse. **Hoje não existe nenhuma
 * forma de aceitar um contrato pela interface.**
 *
 * A DEC-65 escolheu a opção (b): o botão volta, com **banner persistente até o
 * aceite**, e **sem bloquear o acesso**. Ligar o bloqueio numa demo comercial
 * arrisca travar o cliente na primeira tela. O ciclo completo com bloqueio está
 * registrado para o cutover, com o prazo que o jurídico definir.
 *
 * ## O que "persistente" quer dizer aqui
 *
 * Dispensar esconde a faixa **na sessão atual do componente**, não grava nada:
 * na próxima navegação de página inteira ela volta. Persistir a dispensa
 * transformaria "aceite pendente" em "aviso que a pessoa fechou uma vez", que é
 * como o aceite morreu da primeira vez.
 *
 * ## E o usuário somente-leitura
 *
 * Ele **precisa** conseguir aceitar (armadilha registrada na DEC-38): se o gate
 * de `user_is_readonly` bloqueasse o aceite, o readonly nunca aceitaria e
 * ficaria trancado fora do sistema. As duas rotas usadas aqui
 * (`/api/v1/me/terms` e `/api/v1/contracts/:id/accept`) estão em
 * `READONLY_EXEMPT_PATHS`, e há spec provando que os padrões casam as rotas reais.
 */
export function TermsBanner() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const [dispensado, setDispensado] = useState(false)
  const queryClient = useQueryClient()

  const pendentes = useQuery({
    queryKey: ['contracts', 'pending'],
    queryFn: () => contractsApi.pending(),
    enabled: isAuthenticated,
    // Pendência muda quando alguém publica; não vale refazer a cada foco.
    staleTime: 5 * 60 * 1000,
    retry: false,
  })

  const aceitar = useMutation({
    mutationFn: () => contractsApi.acceptAllPending(),
    onSuccess: () => {
      notify.success('Obrigado. Seu aceite foi registrado.')
      queryClient.invalidateQueries({ queryKey: ['contracts'] })
      queryClient.invalidateQueries({ queryKey: ['me', 'terms'] })
    },
    onError: (erro: any) => {
      // O legado tinha o callback de falha VAZIO: erro de rede não mostrava
      // nada e a pessoa clicava de novo achando que não tinha clicado.
      notify.error(erro?.response?.data?.message ?? 'Não foi possível registrar o aceite. Tente de novo.')
    },
  })

  const lista = pendentes.data ?? []
  if (!isAuthenticated || dispensado || lista.length === 0) return null

  const vencido = lista.some((c) => c.overdue)
  const nomes = lista.map((c) => c.title).join(' e ')

  return (
    <div
      role="status"
      aria-live="polite"
      className="flex flex-wrap items-center gap-3 border-b border-border bg-warning/10 px-4 py-2.5 md:px-6"
    >
      <FileWarning aria-hidden="true" className="h-4 w-4 shrink-0 text-warning" />

      <p className="min-w-0 flex-1 text-sm text-foreground">
        <span className="font-medium">
          {vencido ? 'Aceite pendente há mais de 30 dias.' : 'Você ainda não aceitou os documentos vigentes.'}
        </span>{' '}
        <span className="text-muted-foreground">
          {nomes}.{' '}
          {lista.map((c, i) => (
            <span key={c.id}>
              {i > 0 && ' · '}
              <Link
                to={`/contract/${c.slug}`}
                className="text-primary underline underline-offset-2 hover:no-underline"
              >
                Ler {c.title} (v{c.version})
              </Link>
            </span>
          ))}
        </span>
      </p>

      <div className="flex shrink-0 items-center gap-2">
        <Button size="sm" onClick={() => aceitar.mutate()} disabled={aceitar.isPending}>
          {aceitar.isPending ? 'Registrando…' : 'Aceitar'}
        </Button>
        <button
          type="button"
          aria-label="Dispensar aviso"
          onClick={() => setDispensado(true)}
          className="rounded-sm p-1 text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <X aria-hidden="true" className="h-4 w-4" />
        </button>
      </div>
    </div>
  )
}
