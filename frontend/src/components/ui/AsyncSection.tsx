import * as React from 'react'
import { EmptyState, ErrorState, LoadingState } from './States'
import {
  MobileEmptyState,
  MobileErrorState,
  MobileListSkeleton,
} from '@/components/mobile/MobileListState'
import { useMobile } from '@/hooks/useMobile'

/**
 * AsyncSection — os **quatro** estados de um bloco que depende de rede.
 *
 * carregando · vazio · **erro** · conteúdo. O quarto (erro) é o que faltava: o
 * legado tinha três (FE-401) e a base trata falha só por `toast`, que some e
 * deixa a tela indistinguível de "não há nada".
 *
 * A ordem de decisão é fixa e é o valor do componente: **erro vence
 * carregamento**. Numa refetch que falha, o React Query mantém `isFetching`
 * verdadeiro por um instante junto com o erro; se o carregamento vencesse, a
 * tela ficaria girando para sempre sobre uma falha. E **dado antigo vence
 * carregamento**: quando já há conteúdo na tela, uma atualização em segundo
 * plano não pode apagá-la e mostrar um spinner — isso é o "flash de vazio" que
 * faz o usuário achar que perdeu o filtro.
 *
 * É membro da biblioteca porque é a mesma decisão em toda listagem, todo card
 * de KPI e todo painel de detalhe. Escrita à mão em cada tela, ela diverge — e
 * a que esquecer o erro só é descoberta em produção.
 *
 * ### No telefone os três estados são os da biblioteca mobile (DEC-100)
 *
 * A §5.4.8 é específica: **carregando é esqueleto com a forma do `MobileCard`,
 * não spinner** — assim o conteúdo não pula quando chega e a pessoa já lê a
 * estrutura antes do dado. Abaixo de 768 px este componente passa a renderizar
 * `MobileListSkeleton` / `MobileEmptyState` / `MobileErrorState` no lugar dos
 * três do desktop.
 *
 * **A decisão fica aqui, num lugar só, e não em cada tela**, que é a diferença
 * entre o padrão pegar e o padrão existir no papel: a passada de mobile achou
 * que as 33 telas auditadas herdavam o spinner e nenhuma tinha `role="alert"`
 * — não por descuido de quem escreveu cada uma, mas porque todas herdavam o
 * mesmo bloco. Um sinalizador opcional (`variant="list"`) repetiria o modo de
 * falha do DEC-100: quem esquece de passar volta a ter a tela pela metade.
 *
 * O `size="inline"` continua com o spinner: ele marca o bloco pequeno dentro de
 * um card, onde um esqueleto de lista mentiria sobre o que vem.
 */
export interface AsyncSectionProps<T> {
  /** Carregamento inicial (React Query: `isPending`/`isLoading`). */
  loading?: boolean
  /** Erro da consulta. Qualquer valor não nulo conta como erro. */
  error?: unknown
  /** Os dados. `null`/`undefined` = ainda não chegou. */
  data?: T | null
  /** Decide se o que chegou é "vazio". Padrão: array de tamanho zero. */
  isEmpty?: (data: T) => boolean
  onRetry?: () => void
  /** Personalização dos três estados não-conteúdo. */
  loadingState?: React.ReactNode
  emptyState?: React.ReactNode
  errorState?: React.ReactNode
  emptyTitle?: React.ReactNode
  emptyDescription?: React.ReactNode
  emptyAction?: React.ReactNode
  loadingLabel?: string
  size?: 'default' | 'inline'
  className?: string
  children: (data: T) => React.ReactNode
}

function vazioPadrao(data: unknown): boolean {
  if (Array.isArray(data)) return data.length === 0
  if (data && typeof data === 'object') return Object.keys(data).length === 0
  return data === null || data === undefined
}

/**
 * Extrai uma mensagem legível de erro de axios, de `Error` ou de string.
 *
 * **`message` vem ANTES de `error`, e a ordem é o contrato.** O formato único de
 * erro do servidor (`api/CONTRATO.md` §3, `error_payload_for`) define `error`
 * como o **identificador estável** (`conflict`, `not_found`, `forbidden`) e
 * `message` como o **texto para o humano**. Lendo `error` primeiro, a tela
 * mostrava a palavra `conflict` no lugar de "Escolha um projeto para ver estes
 * dados." — visto renderizando no console de risco, com o 409 de escopo.
 *
 * O irmão `mensagemDoServidor` (`lib/api/catalogs.ts`) já lia na ordem certa; as
 * duas agora concordam.
 */
export function mensagemDeErro(error: unknown): string | undefined {
  if (!error) return undefined
  if (typeof error === 'string') return error
  const e = error as any
  return e?.response?.data?.message ?? e?.response?.data?.error ?? e?.message ?? undefined
}

export function AsyncSection<T>({
  loading,
  error,
  data,
  isEmpty,
  onRetry,
  loadingState,
  emptyState,
  errorState,
  emptyTitle,
  emptyDescription,
  emptyAction,
  loadingLabel,
  size = 'default',
  className,
  children,
}: AsyncSectionProps<T>) {
  const estreito = useMobile()
  // O bloco `inline` mora dentro de um card e não é uma lista: ali o esqueleto de
  // linhas mentiria sobre o que está chegando, e o spinner continua sendo o certo.
  const usarMobile = estreito && size !== 'inline'

  // 1. Erro primeiro — inclusive por cima de um carregamento em andamento.
  if (error) {
    return (
      <div className={className}>
        {errorState ??
          (usarMobile ? (
            <MobileErrorState detail={mensagemDeErro(error)} onRetry={onRetry} />
          ) : (
            <ErrorState size={size} description={mensagemDeErro(error)} onRetry={onRetry} />
          ))}
      </div>
    )
  }

  // 2. Dado que já está na tela vence spinner de atualização.
  if (data !== null && data !== undefined) {
    const vazio = isEmpty ? isEmpty(data) : vazioPadrao(data)
    if (vazio) {
      return (
        <div className={className}>
          {emptyState ?? renderVazio()}
        </div>
      )
    }
    return <div className={className}>{children(data)}</div>
  }

  // 3. Sem dado e sem erro: carregando (ou nunca pedido).
  if (loading) {
    return (
      <div className={className}>
        {loadingState ??
          (usarMobile ? <MobileListSkeleton /> : <LoadingState size={size} label={loadingLabel} />)}
      </div>
    )
  }

  return <div className={className}>{emptyState ?? renderVazio()}</div>

  function renderVazio() {
    if (usarMobile) {
      return (
        <MobileEmptyState
          title={emptyTitle ?? 'Nada por aqui ainda'}
          description={emptyDescription}
          actionSlot={emptyAction}
        />
      )
    }
    return <EmptyState size={size} title={emptyTitle} description={emptyDescription} action={emptyAction} />
  }
}
