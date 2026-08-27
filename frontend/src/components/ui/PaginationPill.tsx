import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * PaginationPill — paginação de desktop (DEC-62).
 *
 * Trazido de `apl9/frontend/src/components/ui/PaginationPill.tsx`, um produto
 * irmão da mesma base que já roda em produção — não é componente inventado
 * aqui. O **comportamento** veio inteiro; a **aparência** foi refeita nos
 * tokens da marca Safegold: o original tinha `slate-*`, `bg-white/90`,
 * `#151a21` e o verde `#00fd93` do apl9 escritos à mão. Nada de cor literal
 * sobrevive — trocar a marca é trocar `globals.css`, e mais nada.
 *
 * O par mobile é `components/mobile/MobilePagination.tsx`: view própria com
 * sensação nativa (Anterior/Próxima, alvo grande, sem controle de tamanho de
 * página), compartilhando a mesma API e o mesmo estado (`usePagination`).
 *
 * O componente é **agnóstico ao envelope**: recebe `page`/`totalPages`/`perPage`
 * já traduzidos. Quem lê cabeçalho x corpo é `lib/api/pagination.ts`, um lugar
 * só, à espera da decisão do S0-backend.
 */
interface PaginationPillProps {
  page: number
  totalPages: number
  perPage: number
  onPageChange: (page: number) => void
  onPerPageChange: (perPage: number) => void
  loading?: boolean
  className?: string
}

export function PaginationPill({
  page,
  totalPages,
  perPage,
  onPageChange,
  onPerPageChange,
  loading,
  className,
}: PaginationPillProps) {
  const [draft, setDraft] = useState(String(perPage))

  useEffect(() => {
    setDraft(String(perPage))
  }, [perPage])

  const containerRef = useRef<HTMLDivElement>(null)

  // Anima o scroll até o topo ANTES de disparar a troca de página. Na troca, a
  // lista costuma colapsar para um estado de "carregando", o que faz o navegador
  // clampar o scroll e abortar um `behavior: 'smooth'` nativo. Por isso animamos
  // manualmente sobre o conteúdo atual e só então executamos a ação.
  //
  // IMPORTANTE: a ação (`done`) é disparada por `setTimeout`, NÃO pelo fim da
  // animação. O `requestAnimationFrame` pode ser pausado (aba inativa, preview
  // sem composição) e, se a ação dependesse dele, a paginação travaria. A
  // animação é "melhor esforço"; a ação sempre acontece.
  const scrollToTopThen = (done: () => void) => {
    let el = containerRef.current?.parentElement ?? null
    while (el) {
      const overflowY = getComputedStyle(el).overflowY
      if ((overflowY === 'auto' || overflowY === 'scroll') && el.scrollHeight > el.clientHeight) break
      el = el.parentElement
    }
    const setTop = (v: number) => {
      if (el) el.scrollTop = v
      else window.scrollTo(0, v)
    }
    const start = el ? el.scrollTop : window.scrollY
    if (start <= 0) {
      done()
      return
    }

    const duration = 320
    const t0 = performance.now()
    const ease = (t: number) => 1 - Math.pow(1 - t, 3)
    const step = (now: number) => {
      const p = Math.min(1, (now - t0) / duration)
      setTop(start * (1 - ease(p)))
      if (p < 1) requestAnimationFrame(step)
    }
    requestAnimationFrame(step)
    window.setTimeout(done, duration)
  }

  const handlePageChange = (next: number) => {
    if (next === page) return
    scrollToTopThen(() => onPageChange(next))
  }

  const handlePerPageChange = (next: number) => {
    scrollToTopThen(() => onPerPageChange(next))
  }

  const commit = () => {
    const parsed = parseInt(draft, 10)
    if (!Number.isFinite(parsed) || parsed < 1) {
      setDraft(String(perPage))
      return
    }
    if (parsed !== perPage) handlePerPageChange(parsed)
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      ;(e.target as HTMLInputElement).blur()
    } else if (e.key === 'Escape') {
      setDraft(String(perPage))
      ;(e.target as HTMLInputElement).blur()
    }
  }

  const atFirst = page <= 1 || !!loading
  const atLast = page >= totalPages || !!loading

  const btnBase =
    'flex h-9 w-9 items-center justify-center rounded-full text-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent'

  return (
    <>
      {/*
        **O espacador — e o "o scroll precisa calcular isso".**

        A pilula flutua FIXA no rodape, entao ela sai do fluxo e nao empurra mais
        nada. Sem este bloco, o ultimo item da lista termina embaixo dela: a
        pessoa rola ate o fim e a ultima linha fica coberta.

        A altura e a da pilula (50 px) mais o respiro de baixo e de cima. No
        telefone soma ainda a barra de abas e a area segura do aparelho, porque
        la a pilula sobe para nao ficar atras das abas.
      */}
      <div
        aria-hidden="true"
        className="h-[5.5rem] shrink-0 max-md:h-[calc(5.5rem+5rem+env(safe-area-inset-bottom))]"
      />

      <div
        ref={containerRef}
        className={cn(
          // **Fixa, nao `sticky`.** Com `sticky` a pilula so encostava no rodape
          // quando a lista era longa o bastante para rolar; com lista curta ela
          // parava logo abaixo do conteudo, no meio da tela. Medido: numa janela
          // de 900 px com a lista terminando em 533, a pilula ficava em 589.
          //
          // `left` vem de `--sidebar-w`, publicada pela `Sidebar`: sem isso ela
          // centralizaria sobre a janela inteira e sairia deslocada para a
          // direita, por cima da barra lateral.
          'pointer-events-none fixed bottom-4 right-0 z-sticky flex justify-center px-4',
          'left-0 lg:left-[var(--sidebar-w,0px)]',
          // No telefone, acima da barra de abas e da area segura — senao ela
          // fica ATRAS das abas, que e o oposto de "sempre visivel".
          'max-md:bottom-[calc(5.25rem+env(safe-area-inset-bottom))]',
          className,
        )}
      >
      <nav
        aria-label="Paginação"
        className="pointer-events-auto flex items-center gap-1 rounded-full border border-border bg-popover px-2 py-1.5 text-popover-foreground shadow-e3"
      >
        <button
          type="button"
          aria-label="Primeira página"
          onClick={() => handlePageChange(1)}
          disabled={atFirst}
          className={btnBase}
        >
          <ChevronsLeft className="h-4 w-4" />
        </button>
        <button
          type="button"
          aria-label="Página anterior"
          onClick={() => handlePageChange(Math.max(1, page - 1))}
          disabled={atFirst}
          className={btnBase}
        >
          <ChevronLeft className="h-4 w-4" />
        </button>

        <div className="flex items-center gap-1.5 px-2">
          <span className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground">por página</span>
          <input
            type="number"
            inputMode="numeric"
            min={1}
            value={draft}
            disabled={loading}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={handleKeyDown}
            aria-label="Itens por página"
            className="h-7 w-14 rounded-full border border-input bg-background px-2 text-center font-numeric text-xs font-bold text-foreground outline-none transition-colors focus:border-ring focus:ring-2 focus:ring-ring [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
          />
        </div>

        <div
          aria-live="polite"
          className="mx-1 hidden font-numeric text-[10px] font-bold uppercase tracking-widest text-muted-foreground sm:block"
        >
          {page} / {Math.max(1, totalPages)}
        </div>

        <button
          type="button"
          aria-label="Próxima página"
          onClick={() => handlePageChange(Math.min(totalPages, page + 1))}
          disabled={atLast}
          className={btnBase}
        >
          <ChevronRight className="h-4 w-4" />
        </button>
        <button
          type="button"
          aria-label="Última página"
          onClick={() => handlePageChange(totalPages)}
          disabled={atLast}
          className={btnBase}
        >
          <ChevronsRight className="h-4 w-4" />
        </button>
      </nav>
    </div>
    </>
  )
}
