import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

/**
 * **Barra de ações CONTEXTUAL do telefone** — DEC-100.
 *
 * Não confundir com `MobileBottomBar`, que é a **navegação** (as cinco abas do
 * rodapé). Esta é a barra que aparece **por causa de uma seleção** e some
 * quando a seleção acaba: "3 selecionados · Conectar · Desconectar".
 *
 * Nasce na biblioteca compartilhada, e não dentro da tela de conexões, porque o
 * padrão se repete em toda lista com ação em lote — conexões de portador,
 * conexões de indicador, e o que vier em S6 e S11.
 *
 * Três decisões:
 *
 * 1. **Fica ACIMA da barra de navegação**, com `bottom` calculado a partir da
 *    altura dela mais o `safe-area-inset-bottom`. Sobrepor a navegação é como
 *    se perde o caminho de volta no meio de uma seleção.
 * 2. **`bg-popover`**, não `bg-card`: é superfície flutuante (§5.4.4 das
 *    convenções), e precisa se destacar do conteúdo que rola por baixo.
 * 3. **`role="region"` com rótulo**, para que o leitor de tela anuncie que
 *    apareceu uma área de ações em vez de ler dois botões soltos.
 */
export function MobileActionBar({
  children,
  label = 'Ações da seleção',
  className,
}: {
  children: ReactNode
  label?: string
  className?: string
}) {
  return (
    <div
      role="region"
      aria-label={label}
      className={cn(
        'fixed inset-x-0 z-fab border-t border-border bg-popover text-popover-foreground shadow-e3',
        'px-4 py-3',
        className,
      )}
      // A barra de navegação tem 4rem; o `env()` cobre o indicador de início do
      // iPhone, que só aparece no aparelho — nunca no DevTools.
      style={{ bottom: 'calc(4rem + env(safe-area-inset-bottom))' }}
    >
      {children}
    </div>
  )
}
