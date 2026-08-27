import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * DetailList — o par rótulo/conteúdo do card denso de detalhe (FE-414, FE-415).
 *
 * É `<dl>`/`<dt>`/`<dd>` de verdade, não `div` com dois `span`. A diferença
 * aparece no leitor de tela: com a lista de definição, "Vencimento" e
 * "31/12/2026" são anunciados como **par**; com dois `div`, são duas frases
 * soltas e o usuário perde a associação numa tela com vinte campos — que é
 * exatamente o formato das telas de recebível e de renegociação.
 *
 * Membro da biblioteca porque o card de detalhe é o formato padrão de "ver um
 * registro" no Safegold inteiro, e a versão mobile do mesmo dado é o
 * `MobileCard`: mesma API de dados, apresentação própria.
 *
 * `layout="grid"` põe rótulo e valor em colunas (desktop, tela larga);
 * `layout="stack"` empilha (mobile, coluna estreita). A escolha é do
 * consumidor, porque a mesma lista aparece nos dois lugares.
 */
export interface DetailItem {
  label: React.ReactNode
  content: React.ReactNode
  /** Valor numérico/monetário: recebe `font-numeric` e alinha à direita. */
  numeric?: boolean
  /** Ocupa a linha inteira (observação, endereço). */
  full?: boolean
  hidden?: boolean
}

export interface DetailListProps extends React.HTMLAttributes<HTMLDListElement> {
  items: DetailItem[]
  layout?: 'grid' | 'stack'
  /** Colunas no `grid`. Padrão 2. */
  columns?: 1 | 2 | 3
  /** Texto exibido quando o conteúdo é nulo/vazio. */
  emptyValue?: string
}

const colunas: Record<1 | 2 | 3, string> = {
  1: 'sm:grid-cols-1',
  2: 'sm:grid-cols-2',
  3: 'sm:grid-cols-3',
}

function vazio(v: React.ReactNode): boolean {
  return v === null || v === undefined || v === '' || (typeof v === 'string' && v.trim() === '')
}

export function DetailList({
  items,
  layout = 'grid',
  columns: cols = 2,
  emptyValue = '—',
  className,
  ...props
}: DetailListProps) {
  const visiveis = items.filter((i) => !i.hidden)

  return (
    <dl
      className={cn(
        layout === 'grid' ? cn('grid grid-cols-1 gap-x-6 gap-y-4', colunas[cols]) : 'flex flex-col divide-y divide-border',
        className,
      )}
      {...props}
    >
      {visiveis.map((item, i) => (
        <div
          key={i}
          className={cn(
            layout === 'grid' ? 'flex min-w-0 flex-col gap-0.5' : 'flex items-baseline justify-between gap-4 py-2.5 first:pt-0 last:pb-0',
            item.full && layout === 'grid' && 'sm:col-span-full',
          )}
        >
          <dt className="text-[11px] font-bold uppercase tracking-widest text-muted-foreground">{item.label}</dt>
          <dd
            className={cn(
              'min-w-0 break-words text-sm',
              vazio(item.content) ? 'text-muted-foreground' : 'text-foreground',
              item.numeric && 'font-numeric tabular-nums',
              layout === 'stack' && 'text-right',
            )}
          >
            {vazio(item.content) ? emptyValue : item.content}
          </dd>
        </div>
      ))}
    </dl>
  )
}
