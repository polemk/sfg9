import type { LucideIcon } from 'lucide-react'
import { Layers } from 'lucide-react'
import { CONSOLE_NAV_GROUPS } from '@/app/consoleNavigation'
import { MODE_GROUPS, type SidebarMode } from '@/store/sidebarModeStore'

/**
 * **A lista de modos, derivada dos grupos de navegação — uma vez só.**
 *
 * O `SidebarModeToggle` já fazia essa derivação, e o comentário dele dizia por
 * quê: *"duas listas para a mesma coisa é como um grupo novo aparece no menu e
 * some do seletor"*.
 *
 * Foi exatamente o que aconteceu, e por outro caminho: a `MobileTopBar` tinha a
 * **própria** lista, escrita à mão, com os modos ANTIGOS do ai9 — `negocio`,
 * `conteudo`, `plataforma`. Quando os modos do Safegold entraram
 * (`results_group`, `project_group`, `management`, `admin_settings`,
 * `platform`), o desktop acompanhou sozinho e o telefone ficou para trás:
 * mostrava quatro opções erradas, e escolher qualquer uma **não fazia nada**,
 * porque o id não existe mais em `VALID_MODES`.
 *
 * Por isso a derivação mora aqui e não dentro de um dos dois seletores: o lugar
 * de uma regra compartilhada não é a casa do primeiro que precisou dela.
 */
export interface ModeEntry {
  id: SidebarMode
  label: string
  description: string
  icon: LucideIcon
}

const TODOS: ModeEntry = {
  id: 'all',
  label: 'Tudo',
  description: 'Todos os itens do menu',
  icon: Layers,
}

function construirModos(): ModeEntry[] {
  const porId = new Map(CONSOLE_NAV_GROUPS.map((g) => [g.id, g]))
  const derivados = MODE_GROUPS.flatMap<ModeEntry>((id) => {
    const g = porId.get(id)
    if (!g) return []
    return [{
      id,
      label: g.title,
      // As três primeiras entradas do grupo dizem mais do que uma frase
      // inventada — e acompanham sozinhas quando o grupo muda.
      description: g.items.length ? g.items.slice(0, 3).map((i) => i.label).join(' · ') : g.title,
      icon: g.icon,
    }]
  })
  return [TODOS, ...derivados]
}

export const MODE_ENTRIES: ModeEntry[] = construirModos()

/** O modo corrente, ou "Tudo" quando o gravado no navegador não existe mais. */
export function modeEntryFor(mode: SidebarMode): ModeEntry {
  return MODE_ENTRIES.find((m) => m.id === mode) ?? MODE_ENTRIES[0]
}
