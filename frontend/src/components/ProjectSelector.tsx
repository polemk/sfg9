import { useRef, useState } from 'react'
import { Check, ChevronsUpDown, FolderKanban } from 'lucide-react'
import { SidebarSelectorCard } from '@/components/ui/SidebarSelectorCard'
import { FloatingPanel } from '@/components/ui/FloatingPanel'
import { Spinner } from '@/components/ui/Spinner'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { cn } from '@/lib/utils'

/**
 * FE-393 / BE-412 — o seletor de projeto da topbar.
 *
 * É a interface direta do contrato **C1**: o projeto corrente é **estado de
 * servidor**, e este controle só troca entre projetos em que o usuário
 * **participa** — a lista vem de `memberships`, não de `projects`.
 *
 * Três coisas do legado que **não** são portadas:
 *
 *  - o cookie `cached_info` (**D-28**) que carregava o tenant, escrito pelo
 *    servidor e pelo cliente com codificações diferentes, 4 dias de vida e
 *    nenhuma flag de segurança;
 *  - a heurística de, ao não bater o cookie com o usuário, **selecionar a
 *    segunda opção** do select — sem justificativa nenhuma;
 *  - o `<select>` nativo, cuja lista de `<option>` é desenhada pelo sistema
 *    operacional, branca, ignorando o tema escuro inteiro (foi por isso que a
 *    `.glass-select` saiu no FE-417).
 *
 * O painel é um `FloatingPanel` — **portal no `document.body`**. A topbar fica
 * dentro de contêineres com `backdrop-filter`, e `backdrop-filter` cria
 * contexto de empilhamento: um painel `absolute` aqui ficaria preso ao
 * `z-index` do ancestral, por mais alto que fosse o dele.
 */
export function ProjectSelector({ className, collapsed }: { className?: string; collapsed?: boolean }) {
  const [open, setOpen] = useState(false)
  const anchorRef = useRef<HTMLButtonElement>(null)
  const { current, projects, isLoading, switchProject, isSwitching } = useCurrentProject()

  // Sem participação em projeto nenhum não há o que selecionar — e um seletor
  // vazio na topbar é ruído que sugere que falta configurar algo.
  if (isLoading || projects.length === 0) return null

  const rotulo = current?.name ?? 'Selecione um projeto'

  return (
    <>
      <SidebarSelectorCard
        ref={anchorRef}
        label="Projeto"
        value={rotulo}
        icon={FolderKanban}
        collapsed={collapsed}
        open={open}
        loading={isSwitching}
        onClick={() => setOpen((v) => !v)}
        className={className}
      />

      <FloatingPanel
        open={open}
        anchorRef={anchorRef}
        onDismiss={() => setOpen(false)}
        matchWidth={false}
        align="start"
        className="min-w-[16rem] p-1"
        role="listbox"
        aria-label="Projetos"
      >
        <div className="px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
          Seus projetos
        </div>
        {projects.map((p) => {
          const ativo = p.id === current?.id
          return (
            <button
              key={p.id}
              type="button"
              role="option"
              aria-selected={ativo}
              onClick={() => {
                setOpen(false)
                if (!ativo) switchProject(p.id)
              }}
              className={cn(
                'flex w-full items-center justify-between gap-3 rounded-sm px-3 py-2 text-left text-sm transition-colors',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                ativo ? 'bg-accent text-accent-foreground' : 'text-popover-foreground hover:bg-accent',
              )}
            >
              <span className="truncate">{p.name}</span>
              {ativo && <Check aria-hidden="true" className="h-4 w-4 shrink-0 text-primary" />}
            </button>
          )
        })}
      </FloatingPanel>
    </>
  )
}
