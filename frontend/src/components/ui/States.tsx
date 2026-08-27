import * as React from 'react'
import { AlertTriangle, Inbox, RefreshCw } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from './Button'
import { Spinner } from './Spinner'

/**
 * Os três estados que não são "conteúdo": carregando, vazio e **erro**.
 *
 * Por que são da biblioteca e não de cada tela: o legado tinha três estados e
 * **nenhum de erro** (FE-401), e a base ai9 trata erro só por `toast` — o toast
 * some em 4 segundos e a tela fica em branco, indistinguível de "não há nada".
 * O usuário não sabe se a lista está vazia ou se a requisição falhou, e não tem
 * como tentar de novo. Padronizar aqui é o que garante que **toda** listagem
 * nova nasça com o quarto estado.
 *
 * Os três compartilham a mesma moldura (mesmo espaçamento, mesma hierarquia de
 * texto, mesmo lugar da ação) para que a troca entre eles não sacuda o layout.
 */
interface StateShellProps {
  icon?: React.ReactNode
  title: React.ReactNode
  description?: React.ReactNode
  action?: React.ReactNode
  className?: string
  /** `inline` encolhe a moldura para caber dentro de um card pequeno. */
  size?: 'default' | 'inline'
  /**
   * O papel ARIA é do ESTADO, não da moldura: erro é `alert` (interrompe e é
   * anunciado na hora), carregando e vazio são `status` (anunciados sem cortar
   * o que a pessoa está lendo). Sem isto os três eram três `div` mudas — e a
   * varredura em 390×844 achou **zero** `role="alert"` em 33 telas, nos dois
   * modos: para quem usa leitor de tela, falha de carga e lista vazia eram
   * literalmente a mesma coisa.
   */
  role?: 'alert' | 'status'
  ariaBusy?: boolean
}

function StateShell({
  icon,
  title,
  description,
  action,
  className,
  size = 'default',
  role,
  ariaBusy,
}: StateShellProps) {
  return (
    <div
      role={role}
      aria-busy={ariaBusy}
      className={cn(
        'flex w-full flex-col items-center justify-center gap-3 text-center',
        size === 'inline' ? 'px-4 py-8' : 'px-6 py-14',
        className,
      )}
    >
      {icon && <div className="flex h-11 w-11 items-center justify-center rounded-full bg-muted">{icon}</div>}
      <div className="flex flex-col gap-1">
        <p className="font-title text-base font-semibold text-foreground">{title}</p>
        {description && <p className="max-w-md text-sm text-muted-foreground">{description}</p>}
      </div>
      {action && <div className="mt-1 flex items-center gap-2">{action}</div>}
    </div>
  )
}

export interface LoadingStateProps {
  /** Texto sob o spinner. Sempre diga *o que* está carregando. */
  label?: string
  className?: string
  size?: 'default' | 'inline'
}

export function LoadingState({ label = 'Carregando…', className, size = 'default' }: LoadingStateProps) {
  return (
    <StateShell
      size={size}
      className={className}
      role="status"
      ariaBusy
      icon={<Spinner size="md" label={null} className="text-muted-foreground" />}
      title={<span className="text-sm font-medium text-muted-foreground">{label}</span>}
    />
  )
}

export interface EmptyStateProps {
  title?: React.ReactNode
  description?: React.ReactNode
  icon?: React.ReactNode
  action?: React.ReactNode
  className?: string
  size?: 'default' | 'inline'
}

export function EmptyState({
  title = 'Nada por aqui ainda',
  description,
  icon,
  action,
  className,
  size = 'default',
}: EmptyStateProps) {
  return (
    <StateShell
      size={size}
      className={className}
      role="status"
      icon={icon ?? <Inbox aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
      title={title}
      description={description}
      action={action}
    />
  )
}

export interface ErrorStateProps {
  title?: React.ReactNode
  /** Mensagem do servidor, quando houver. Cai num texto genérico se faltar. */
  description?: React.ReactNode
  onRetry?: () => void
  retryLabel?: string
  retrying?: boolean
  className?: string
  size?: 'default' | 'inline'
}

export function ErrorState({
  title = 'Não foi possível carregar',
  description = 'Houve uma falha ao buscar estes dados. Tente novamente em instantes.',
  onRetry,
  retryLabel = 'Tentar de novo',
  retrying,
  className,
  size = 'default',
}: ErrorStateProps) {
  return (
    <StateShell
      size={size}
      // Erro **não pode parecer vazio**: além do papel ARIA, a moldura ganha o
      // traço destrutivo. Antes os dois eram a mesma caixa branca com um ícone
      // diferente, e quem decide sobre carteira lendo "nada aqui" quando a
      // verdade é "não consegui perguntar" decide errado.
      className={cn('rounded-lg border border-destructive/30 bg-destructive/5', className)}
      role="alert"
      icon={<AlertTriangle aria-hidden="true" className="h-5 w-5 text-destructive" />}
      title={title}
      description={description}
      action={
        onRetry && (
          <Button variant="secondary" size="sm" onClick={onRetry} loading={retrying}>
            <RefreshCw aria-hidden="true" className="h-4 w-4" />
            {retryLabel}
          </Button>
        )
      }
    />
  )
}
