import React from 'react'
import { cn } from '@/lib/utils'

/**
 * PageHeader — o cabeçalho de tela, no lugar das 751 linhas de
 * `ContextToolbar`/`Toolbar`/`SearchBar` do legado (FE-740).
 *
 * O que sai, e por quê: o `ContextToolbar` (`app/frontend/js/toolbars.js`, 751
 * linhas de jQuery, mais 480 de SCSS) era uma barra **imperativa** que media a
 * janela, escondia a si mesma na rolagem, se "estendia" por um fator da altura
 * da tela, hospedava um loader, um wrapper de mensagem e até um manipulador de
 * geolocalização. Estado de UI guardado em `data-` no DOM e lido de volta com
 * `parseFloat` — a fonte da verdade era a folha de estilo.
 *
 * Aqui é declarativo: `position: sticky` faz o que 300 linhas de `scroll`
 * handler faziam, os slots substituem os "wrappers", e a busca é o
 * `SearchInput` da biblioteca — não uma barra própria do cabeçalho.
 *
 * Todos os campos além de `title` são opcionais e os antigos continuam com o
 * mesmo nome (`subtitle`, `rightSlot`, `centerSlot`): as 11 telas que já usam o
 * componente não mudam.
 */
export interface PageHeaderProps {
  title: string
  subtitle?: string
  /** Ações da tela — sempre à direita, no máximo um `Button primary`. */
  rightSlot?: React.ReactNode
  /** Bloco centralizado (seletor de período, indicador). */
  centerSlot?: React.ReactNode
  /** Campo de busca. Fica abaixo do título e ocupa a largura em telas estreitas. */
  searchSlot?: React.ReactNode
  /** Trilha de navegação, acima do título. */
  breadcrumb?: React.ReactNode
  /** Abas da tela, coladas na base do cabeçalho. */
  tabsSlot?: React.ReactNode
  /**
   * Gruda no topo ao rolar. É o que o `ContextToolbar` fazia no `scroll`
   * handler — aqui é uma linha de CSS.
   */
  sticky?: boolean
  /**
   * Barra fina de progresso indeterminado na base (o `toolbar_loader` do
   * legado). Use para atualização em segundo plano: ela não substitui o
   * `LoadingState`, que é para o carregamento inicial do conteúdo.
   */
  loading?: boolean
  className?: string
}

export function PageHeader({
  title,
  subtitle,
  rightSlot,
  centerSlot,
  searchSlot,
  breadcrumb,
  tabsSlot,
  sticky,
  loading,
  className,
}: PageHeaderProps) {
  return (
    <div
      className={cn(
        'relative z-sticky mb-6 pt-6',
        // **A animacao de entrada so no desktop.** No telefone a navegacao e por
        // aba, e trocar de aba refazia 500 ms de fade + deslize da esquerda a
        // cada toque — o usuario descreveu como "a tela pisca". Aplicativo
        // nativo troca de aba instantaneamente; a animacao aqui custava
        // velocidade percebida sem dar nada em troca.
        //
        // No desktop a navegacao e mais esparsa e a entrada ajuda a situar,
        // entao la fica como sempre foi.
        'md:animate-in md:fade-in md:slide-in-from-left-2 md:duration-500',
        sticky && 'sticky top-0 bg-background/95 backdrop-blur-sm',
        className,
      )}
    >
      {/* A trilha é navegação de verdade — é por ela que se volta da tela de
          detalhe. Com `text-xs` o link tinha 16 px de altura: alvo de ponteiro.
          O seletor de descendente dá 44 px a todo link da trilha no telefone sem
          obrigar cada tela a lembrar disso (§5.4.8, critério 1). */}
      {breadcrumb && (
        <div className="mb-2 text-xs text-muted-foreground [&_a]:inline-flex [&_a]:min-h-[2.75rem] [&_a]:items-center md:[&_a]:min-h-0">
          {breadcrumb}
        </div>
      )}

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="mb-1 font-title text-2xl font-bold tracking-tight text-foreground">{title}</h1>
          {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
        </div>

        {centerSlot && <div className="absolute left-1/2 top-6 -translate-x-1/2">{centerSlot}</div>}

        {rightSlot && <div className="flex flex-wrap items-center gap-2">{rightSlot}</div>}
      </div>

      {searchSlot && <div className="mt-4 w-full max-w-md">{searchSlot}</div>}

      {tabsSlot && <div className="mt-4">{tabsSlot}</div>}

      {loading && (
        <div
          role="progressbar"
          aria-label="Atualizando"
          className="absolute inset-x-0 bottom-0 h-0.5 overflow-hidden rounded-full bg-muted"
        >
          <div className="h-full w-1/3 animate-progress-indeterminate bg-primary" />
        </div>
      )}
    </div>
  )
}

export default PageHeader
