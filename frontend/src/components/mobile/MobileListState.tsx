import type { ReactNode } from 'react'
import { AlertTriangle, Inbox, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/utils'

/**
 * **Os três estados que toda lista mobile tem, e que nenhuma tela deve redesenhar** — DEC-100.
 *
 * A biblioteca `components/mobile/` tinha o card, o KPI, o gráfico e a paginação, mas **não
 * tinha carregando, vazio nem erro**. O resultado previsível, com S5..S11 consumindo isto em
 * massa: cada fatia inventa o seu — um põe um `<Loader2>` girando, outro põe "Nenhum
 * resultado" em `<p>` cru, um terceiro não põe nada e a tela fica **em branco**, que no
 * telefone é indistinguível de app travado.
 *
 * As três telas de estado são um contrato, não decoração:
 *
 * 1. **Carregando é esqueleto, não spinner.** O esqueleto tem a forma do `MobileCard` que vai
 *    chegar, então o conteúdo não "pula" quando chega — e o usuário já lê a estrutura antes
 *    do dado. Spinner centralizado não diz nada sobre o que está vindo.
 * 2. **Vazio distingue "não há" de "seu filtro não achou".** São mensagens diferentes com
 *    saídas diferentes: sem registro nenhum, a ação é *criar*; com filtro, a ação é *limpar o
 *    filtro*. Trocar as duas é o que faz o usuário concluir que o sistema perdeu o dado dele.
 * 3. **Erro mostra o que houve e oferece tentar de novo.** Lista que falha e fica igual a
 *    lista vazia é o pior dos três: o usuário toma decisão financeira sobre uma tela que
 *    diz "nada aqui" quando a verdade é "não consegui perguntar".
 *
 * Cor só por token (§5.4.2), alvos de toque de 48 px e nada de `dark:` — os três nascem
 * certos nos dois modos.
 */

export interface MobileListSkeletonProps {
  /** Quantas linhas fantasma desenhar. O padrão cobre a altura de um 390×844. */
  rows?: number
  className?: string
}

/** Carregando: a silhueta do `MobileCard`, repetida. */
export function MobileListSkeleton({ rows = 5, className }: MobileListSkeletonProps) {
  return (
    <div
      className={cn('w-full', className)}
      role="status"
      aria-live="polite"
      aria-busy="true"
      aria-label="Carregando"
    >
      {Array.from({ length: rows }).map((_, indice) => (
        <div
          key={indice}
          aria-hidden="true"
          className="mb-4 w-full rounded-lg border border-border bg-card p-5 shadow-e2"
        >
          <div className="flex items-start gap-3">
            <div className="h-12 w-12 shrink-0 animate-pulse rounded-md bg-muted" />
            <div className="min-w-0 flex-1 space-y-2">
              <div className="h-3 w-2/3 animate-pulse rounded-sm bg-muted" />
              <div className="h-2.5 w-1/3 animate-pulse rounded-sm bg-muted" />
              <div className="h-4 w-24 animate-pulse rounded-full bg-muted" />
            </div>
            <div className="h-4 w-16 shrink-0 animate-pulse rounded-sm bg-muted" />
          </div>
        </div>
      ))}
      {/* Texto para leitor de tela: o esqueleto é `aria-hidden`, então sem isto a
          navegação por voz anuncia uma região vazia. */}
      <span className="sr-only">Carregando registros…</span>
    </div>
  )
}

export interface MobileEmptyStateProps {
  /** O que não existe, na voz do domínio: "Nenhum borderô neste período". */
  title: ReactNode
  /** Uma linha explicando o porquê ou o próximo passo. */
  description?: ReactNode
  icon?: ReactNode
  /**
   * `true` quando a lista está vazia **por causa de filtro/busca**. Muda a leitura de
   * "não existe" para "não achei com este recorte" — são coisas diferentes.
   */
  filtered?: boolean
  /** Ação principal: criar o primeiro registro, ou limpar o filtro. */
  action?: { label: string; onClick: () => void }
  /**
   * Ação já montada pelo chamador. Existe para quem entrega o botão pronto (o
   * `emptyAction` do `AsyncSection`, que é `ReactNode`): sem isto o botão teria
   * de ser desmontado em `{label, onClick}` e remontado, e o que se perde no
   * caminho é justamente o `disabled`, o `loading` e o ícone.
   */
  actionSlot?: ReactNode
  className?: string
}

/** Vazio: diz o que não há, distingue filtro de ausência e oferece a saída. */
export function MobileEmptyState({
  title,
  description,
  icon,
  filtered = false,
  action,
  actionSlot,
  className,
}: MobileEmptyStateProps) {
  return (
    <div
      className={cn(
        'flex w-full flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-border bg-card/50 px-6 py-12 text-center',
        className,
      )}
      role="status"
    >
      <span className="rounded-full border border-border bg-muted p-3 text-muted-foreground" aria-hidden="true">
        {icon ?? <Inbox className="h-6 w-6" />}
      </span>
      <p className="text-sm font-semibold text-card-foreground">{title}</p>
      {description && <p className="max-w-[28ch] text-xs text-muted-foreground">{description}</p>}
      {!description && filtered && (
        <p className="max-w-[28ch] text-xs text-muted-foreground">
          Nenhum registro corresponde ao filtro atual. Os dados continuam lá.
        </p>
      )}
      {action && (
        <Button variant={filtered ? 'secondary' : 'primary'} className="mt-2 min-h-[3rem]" onClick={action.onClick}>
          {action.label}
        </Button>
      )}
      {actionSlot && <div className="mt-2 flex items-center gap-2">{actionSlot}</div>}
    </div>
  )
}

export interface MobileErrorStateProps {
  /** Cabeçalho curto. O padrão serve para falha de carga de lista. */
  title?: ReactNode
  /** A mensagem do servidor, quando houver — é o que vai para o chamado. */
  detail?: ReactNode
  onRetry?: () => void
  className?: string
}

/** Erro: nunca se parece com vazio, e sempre oferece tentar de novo. */
export function MobileErrorState({
  title = 'Não consegui carregar',
  detail,
  onRetry,
  className,
}: MobileErrorStateProps) {
  return (
    <div
      className={cn(
        'flex w-full flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-6 py-12 text-center',
        className,
      )}
      role="alert"
    >
      <span className="rounded-full border border-destructive/20 bg-destructive/10 p-3 text-destructive" aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </span>
      <p className="text-sm font-semibold text-card-foreground">{title}</p>
      {detail && (
        // Detalhe técnico em monoespaçado: é o texto que a pessoa copia para o chamado.
        <p className="max-w-[32ch] break-words font-mono text-[11px] text-muted-foreground">{detail}</p>
      )}
      {onRetry && (
        <Button variant="secondary" className="mt-2 min-h-[3rem]" onClick={onRetry}>
          <RotateCcw aria-hidden="true" className="h-4 w-4" />
          Tentar de novo
        </Button>
      )}
    </div>
  )
}
