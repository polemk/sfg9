import { useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CornerDownLeft, Search } from 'lucide-react'
import { SearchInput } from '@/components/ui/SearchInput'
import { FloatingPanel } from '@/components/ui/FloatingPanel'
import { Tooltip } from '@/components/ui/Tooltip'
import { useNavItems } from '@/hooks/useNavItems'
import { cn } from '@/lib/utils'

/**
 * Busca de áreas do console — **na sidebar, não numa barra superior**.
 *
 * O ai9 não tem topbar: o que orienta e navega vive na sidebar. A busca estava
 * numa `ConsoleTopbar` junto de um título e de um chip de usuário que **já
 * existiam em outro lugar** — o título em cada `PageHeader`, o usuário no cartão
 * do rodapé. Sobrou a busca, e ela é navegação, então é aqui que mora.
 *
 * A busca procura entre as áreas que o usuário **realmente enxerga** (as mesmas
 * de `useNavItems`, já filtradas por papel, participação e modo) e leva até lá.
 * Busca de conteúdo é de cada tela — esta é atalho de navegação.
 *
 * Com a sidebar recolhida vira um botão de ícone: abrir o painel exigiria um
 * campo de texto que não cabe em 72 px, e um campo cortado é pior que um ícone
 * honesto.
 *
 * O painel de resultados é `FloatingPanel` (portal). Obrigatório: o `<aside>`
 * usa `.glass-panel`, que aplica `backdrop-filter` — e `backdrop-filter` cria
 * contexto de empilhamento, prendendo qualquer descendente `absolute` ao
 * `z-index` do aside, por mais alto que seja o dele.
 */
export function SidebarSearch({ collapsed, onNavigate }: { collapsed?: boolean; onNavigate?: () => void }) {
  const navigate = useNavigate()
  const itens = useNavItems()

  const [termo, setTermo] = useState('')
  const [aberto, setAberto] = useState(false)
  const [ativo, setAtivo] = useState(0)
  const ancora = useRef<HTMLDivElement>(null)

  const resultados = useMemo(() => {
    const t = termo.trim().toLowerCase()
    if (!t) return []
    return itens.filter((i) => i.label.toLowerCase().includes(t)).slice(0, 8)
  }, [termo, itens])

  const ir = (path: string) => {
    setTermo('')
    setAberto(false)
    navigate(path)
    onNavigate?.()
  }

  if (collapsed) {
    return (
      <Tooltip content="Buscar área" side="right" className="block w-full">
        <button
          type="button"
          aria-label="Buscar área do console"
          onClick={() => navigate('/dashboard')}
          className={cn(
            'flex w-full items-center justify-center rounded-md p-2.5 text-muted-foreground transition-colors',
            'hover:bg-accent/60 hover:text-foreground',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          )}
        >
          <Search aria-hidden="true" className="h-5 w-5" />
        </button>
      </Tooltip>
    )
  }

  return (
    <div ref={ancora} className="relative">
      <SearchInput
        value={termo}
        onValueChange={(v) => {
          setTermo(v)
          setAberto(true)
          setAtivo(0)
        }}
        onFocus={() => setAberto(true)}
        size="sm"
        placeholder="Buscar área…"
        aria-label="Buscar área do console"
        onKeyDown={(e) => {
          if (!resultados.length) return
          if (e.key === 'ArrowDown') {
            e.preventDefault()
            setAtivo((i) => (i + 1) % resultados.length)
          } else if (e.key === 'ArrowUp') {
            e.preventDefault()
            setAtivo((i) => (i - 1 + resultados.length) % resultados.length)
          } else if (e.key === 'Enter') {
            e.preventDefault()
            ir(resultados[ativo].path)
          } else if (e.key === 'Escape') {
            setAberto(false)
          }
        }}
      />

      <FloatingPanel
        open={aberto && resultados.length > 0}
        anchorRef={ancora}
        onDismiss={() => setAberto(false)}
        matchWidth
        className="p-1"
      >
        {resultados.map((r, i) => {
          const Icon = r.icon
          return (
            <button
              key={r.path}
              type="button"
              onMouseEnter={() => setAtivo(i)}
              onClick={() => ir(r.path)}
              className={cn(
                'flex w-full items-center gap-3 rounded-sm px-3 py-2 text-left text-sm transition-colors',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                i === ativo ? 'bg-accent text-accent-foreground' : 'text-popover-foreground',
              )}
            >
              <Icon aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="flex-1 truncate">{r.label}</span>
              {i === ativo && <CornerDownLeft aria-hidden="true" className="h-3.5 w-3.5 text-muted-foreground" />}
            </button>
          )
        })}
      </FloatingPanel>

      {aberto && termo.trim() && resultados.length === 0 && (
        <p className="mt-1 flex items-center gap-1.5 px-1 text-xs text-muted-foreground">
          <Search aria-hidden="true" className="h-3 w-3" />
          Nenhuma área com esse nome.
        </p>
      )}
    </div>
  )
}
