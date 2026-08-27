import { useMemo, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { CornerDownLeft, Search } from 'lucide-react'
import { SearchInput } from '@/components/ui/SearchInput'
import { FloatingPanel } from '@/components/ui/FloatingPanel'
import { ProjectSelector } from '@/components/ProjectSelector'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { useAuthStore } from '@/store/authStore'
import { useNavGroups, useNavItems } from '@/hooks/useNavItems'
import { cn } from '@/lib/utils'

/**
 * FE-392, FE-393, FE-394 — a barra superior do console.
 *
 * Três peças, e nada além: **seletor de projeto**, **busca global** e o **chip
 * do usuário**. O legado tinha aqui um `respond_to` de duas caras e um splash
 * preto de `99vw × 98vh` com polling de 10 ms; nada disso é portado.
 *
 * A barra é `bg-card` com borda inferior, **não `.glass-panel`**. A regra vale a
 * repetição: `.glass-panel` aplica `backdrop-filter`, e `backdrop-filter` cria
 * contexto de empilhamento — todo painel flutuante desenhado por um descendente
 * fica preso ao `z-index` deste bloco. O seletor de projeto e a busca já
 * renderizam em portal (`FloatingPanel`), então estariam seguros de qualquer
 * jeito; a superfície opaca é para o conteúdo que rola por baixo não borrar o
 * texto da barra.
 *
 * A busca é **navegação**, não consulta ao servidor: ela procura entre as áreas
 * que o usuário realmente enxerga (as mesmas de `useNavItems`) e leva até lá.
 * Busca de conteúdo é de cada tela.
 */
export function ConsoleTopbar() {
  const navigate = useNavigate()
  const location = useLocation()
  const user = useAuthStore((s) => s.user)
  const itens = useNavItems()
  const grupos = useNavGroups()

  const [termo, setTermo] = useState('')
  const [aberto, setAberto] = useState(false)
  const [ativo, setAtivo] = useState(0)
  const buscaRef = useRef<HTMLDivElement>(null)

  const resultados = useMemo(() => {
    const t = termo.trim().toLowerCase()
    if (!t) return []
    return itens
      .filter((i) => i.label.toLowerCase().includes(t))
      .slice(0, 8)
  }, [termo, itens])

  const ir = (path: string) => {
    setTermo('')
    setAberto(false)
    navigate(path)
  }

  // O título é o do item ativo; grupo-link sem itens (o "Início") não aparece
  // em `itens`, então entra pelo `path` do grupo.
  const titulo = useMemo(() => {
    const item = itens.find((i) => location.pathname.startsWith(i.path))
    if (item) return item.label
    const grupo = grupos.find((g) => g.path && location.pathname.startsWith(g.path))
    return grupo?.title ?? 'Console'
  }, [itens, grupos, location.pathname])

  return (
    <header className="sticky top-0 z-appbar hidden h-16 shrink-0 items-center gap-4 border-b border-border bg-card px-6 md:flex">
      <div className="min-w-0 flex-1">
        <h1 className="truncate font-title text-sm font-semibold tracking-tight text-foreground">{titulo}</h1>
      </div>

      <div ref={buscaRef} className="relative w-full max-w-sm">
        <SearchInput
          value={termo}
          size="sm"
          placeholder="Buscar área…"
          aria-label="Buscar área do console"
          onValueChange={(v) => {
            setTermo(v)
            setAtivo(0)
            setAberto(true)
          }}
          onFocus={() => setAberto(true)}
          onKeyDown={(e) => {
            if (resultados.length === 0) return
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
          anchorRef={buscaRef as React.RefObject<HTMLElement>}
          onDismiss={() => setAberto(false)}
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
          <p className="absolute left-0 top-full mt-1 flex items-center gap-1.5 text-xs text-muted-foreground">
            <Search aria-hidden="true" className="h-3 w-3" />
            Nenhuma área com esse nome.
          </p>
        )}
      </div>

      <ProjectSelector />

      <div className="flex items-center gap-2">
        <UserAvatar name={user?.name} email={user?.email} src={user?.avatar_url} size={32} />
        <div className="hidden min-w-0 lg:block">
          <p className="truncate text-xs font-medium text-foreground">{user?.name?.split(' ')[0] || user?.email}</p>
          <p className="truncate text-[11px] uppercase tracking-wider text-muted-foreground">
            {user?.user_type || 'Membro'}
          </p>
        </div>
      </div>
    </header>
  )
}
