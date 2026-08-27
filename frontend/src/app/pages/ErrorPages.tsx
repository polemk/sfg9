import { useNavigate } from 'react-router-dom'
import { Compass, ServerCrash, FileWarning, ArrowLeft, RefreshCw, Bug, type LucideIcon } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Logo } from '@/components/brand/Logo'
import { useAuthStore } from '@/store/authStore'

/**
 * As páginas de erro do console — **404, 422 e 500** (OPS-634 / tarefa F.4).
 *
 * ### Por que a rota curinga é obrigatória e é nova
 *
 * `App.tsx` **não tinha rota `*`**: qualquer caminho desconhecido virava **tela
 * em branco**, sem cabeçalho, sem menu e sem nada a clicar. E o legado tinha um
 * vício pior — ele **rebaixava em silêncio para o `dash`**: o usuário digitava
 * um endereço errado, via a tela inicial e achava que tinha chegado.
 *
 * Aqui endereço desconhecido diz que é desconhecido, **mostra o caminho que
 * falhou** (é o que a pessoa vai colar no chamado) e oferece a saída.
 *
 * As três telas compartilham a mesma moldura, o mesmo lugar da ação e a mesma
 * hierarquia de texto dos estados de `components/ui/States.tsx`: um erro de
 * rota e uma lista que falhou não podem parecer dois produtos diferentes.
 *
 * Cor: só token. O ícone usa `text-muted-foreground` sobre `bg-muted`; a moldura
 * é `bg-card` sobre `bg-background`. Confere nos dois modos porque nenhum valor
 * literal participa.
 */

interface ErrorScreenProps {
  code: string
  icon: LucideIcon
  title: string
  description: React.ReactNode
  /** Detalhe técnico monoespaçado — caminho, id, mensagem do servidor. */
  detail?: string
  action?: React.ReactNode
}

export function ErrorScreen({ code, icon: Icon, title, description, detail, action }: ErrorScreenProps) {
  return (
    <div className="flex min-h-[60vh] w-full items-center justify-center bg-background px-4 py-12 text-foreground">
      <div className="flex w-full max-w-lg flex-col items-center gap-6 rounded-lg border border-border bg-card p-8 text-center shadow-e2">
        <Logo variant="symbol" height={28} />

        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-muted">
          <Icon aria-hidden="true" className="h-6 w-6 text-muted-foreground" />
        </div>

        <div className="flex flex-col items-center gap-2">
          {/* O número é dado, então é `font-numeric` como qualquer número da casa. */}
          <span className="font-numeric text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">
            Erro {code}
          </span>
          <h1 className="font-title text-2xl font-semibold tracking-tight text-foreground">{title}</h1>
          <p className="max-w-sm text-sm leading-relaxed text-muted-foreground">{description}</p>
        </div>

        {detail && (
          <code className="max-w-full overflow-x-auto rounded-sm border border-border bg-muted px-3 py-2 font-numeric text-xs text-muted-foreground">
            {detail}
          </code>
        )}

        {action && <div className="flex flex-wrap items-center justify-center gap-2">{action}</div>}
      </div>
    </div>
  )
}

/** Para onde o botão de saída leva: console se há sessão, login se não há. */
function useDestinoDeVolta() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  return isAuthenticated ? '/dashboard' : '/'
}

/** 404 — a rota curinga. */
export function NotFoundPage() {
  const navigate = useNavigate()
  const destino = useDestinoDeVolta()
  const caminho = typeof window !== 'undefined' ? window.location.pathname : ''

  return (
    <ErrorScreen
      code="404"
      icon={Compass}
      title="Esta página não existe"
      description="O endereço que você abriu não corresponde a nenhuma área do console. Ele pode ter mudado, ou o link pode estar incompleto."
      detail={caminho || undefined}
      action={
        <>
          <Button variant="secondary" onClick={() => navigate(-1)}>
            <ArrowLeft aria-hidden="true" className="h-4 w-4" />
            Voltar
          </Button>
          <Button onClick={() => navigate(destino)}>Ir para o início</Button>
        </>
      }
    />
  )
}

/** 422 — a requisição chegou, foi entendida e foi recusada pela regra. */
export function UnprocessablePage({ detail }: { detail?: string }) {
  const navigate = useNavigate()
  const destino = useDestinoDeVolta()

  return (
    <ErrorScreen
      code="422"
      icon={FileWarning}
      title="Não deu para processar"
      description="Os dados enviados chegaram ao servidor, mas alguma regra recusou a operação. Reveja o formulário e tente de novo."
      detail={detail}
      action={
        <>
          <Button variant="secondary" onClick={() => navigate(-1)}>
            <ArrowLeft aria-hidden="true" className="h-4 w-4" />
            Voltar
          </Button>
          <Button onClick={() => navigate(destino)}>Ir para o início</Button>
        </>
      }
    />
  )
}

/** 500 — falha do **servidor**. Exceção do navegador usa `ClientCrashPage`. */
export function ServerErrorPage({ detail, onRetry }: { detail?: string; onRetry?: () => void }) {
  const navigate = useNavigate()
  const destino = useDestinoDeVolta()

  return (
    <ErrorScreen
      code="500"
      icon={ServerCrash}
      title="Algo quebrou do nosso lado"
      description="A falha foi registrada. Tentar de novo costuma resolver quando é intermitente; se insistir, avise o suporte com o detalhe abaixo."
      detail={detail}
      action={
        <>
          <Button variant="secondary" onClick={onRetry ?? (() => window.location.reload())}>
            <RefreshCw aria-hidden="true" className="h-4 w-4" />
            Tentar de novo
          </Button>
          <Button onClick={() => navigate(destino)}>Ir para o início</Button>
        </>
      }
    />
  )
}

/**
 * Exceção **no navegador** — não é 500, e dizer que é engana quem lê.
 *
 * A tela de detalhe de projeto quebrou com `Cannot read properties of null
 * (reading 'trim')` e o console mostrou "ERRO 500 — algo quebrou do nosso lado
 * — a falha foi registrada". Três afirmações, três erradas: não houve 500, não
 * quebrou no servidor, e nada foi registrado além de um `console.error`. Quem
 * abre chamado com isso manda o time olhar o log do servidor, onde não há nada.
 *
 * O que muda é só a honestidade do texto: mesma moldura, mesmo detalhe técnico,
 * mesmas ações. "Recarregar" aparece porque, para falha de runtime do cliente,
 * remontar às vezes não basta — o estado que causou a queda pode continuar de pé.
 */
export function ClientCrashPage({ detail, onRetry }: { detail?: string; onRetry?: () => void }) {
  const navigate = useNavigate()
  const destino = useDestinoDeVolta()

  return (
    <ErrorScreen
      code="ERRO NA TELA"
      icon={Bug}
      title="Esta tela não conseguiu abrir"
      description="A falha foi no seu navegador, não no servidor — seus dados não foram afetados. Tentar de novo costuma resolver; se insistir, mande o detalhe abaixo para o suporte."
      detail={detail}
      action={
        <>
          <Button variant="secondary" onClick={onRetry ?? (() => window.location.reload())}>
            <RefreshCw aria-hidden="true" className="h-4 w-4" />
            Tentar de novo
          </Button>
          <Button variant="secondary" onClick={() => window.location.reload()}>
            Recarregar a página
          </Button>
          <Button onClick={() => navigate(destino)}>Ir para o início</Button>
        </>
      }
    />
  )
}
