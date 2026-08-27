import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * **O título de uma zona da tela** — o que separa "cinco cartões soltos" de
 * "duas leituras, uma embaixo da outra".
 *
 * Uma tela de resumo sem zonas obriga a pessoa a descobrir sozinha que os
 * quatro primeiros blocos falam de carteira e os três seguintes falam de risco.
 * O rótulo faz esse trabalho em duas palavras — e é a mesma hierarquia que o
 * leitor de tela usa, porque cada zona vira uma `<section>` com nome.
 *
 * Nasce na biblioteca e não dentro do painel porque é a mesma decisão em toda
 * tela que tenha mais de uma leitura: um `h2` com filete e um contador opcional,
 * sempre com o mesmo peso, a mesma entrelinha e o mesmo respiro. Escrito à mão
 * em cada tela, ele diverge — que é como um app passa a ter três tamanhos de
 * título de seção.
 *
 * O filete é `--border`, não uma barra de cor: barra colorida à esquerda é
 * decoração, e num console financeiro cor tem significado reservado (estado).
 */
export interface SectionHeadingProps {
  children: React.ReactNode
  /** Uma linha de contexto — o período, a data de apuração. */
  hint?: React.ReactNode
  /** Ação da zona, alinhada à direita. */
  action?: React.ReactNode
  id?: string
  className?: string
}

export function SectionHeading({ children, hint, action, id, className }: SectionHeadingProps) {
  return (
    <div className={cn('mb-3 flex flex-wrap items-baseline gap-x-3 gap-y-1', className)}>
      <h2
        id={id}
        className="font-title text-xs font-semibold uppercase tracking-[0.14em] text-foreground"
      >
        {children}
      </h2>
      {/* O filete ocupa o espaço que sobra: ele **mede** a largura da zona, e é
          o que faz duas seções empilhadas lerem como duas, em vez de como uma
          lista contínua de cartões. */}
      <span aria-hidden="true" className="h-px min-w-6 flex-1 bg-border" />
      {hint && <span className="text-xs text-muted-foreground">{hint}</span>}
      {action}
    </div>
  )
}
