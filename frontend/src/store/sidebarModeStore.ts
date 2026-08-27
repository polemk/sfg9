import { create } from 'zustand'
import { persist } from 'zustand/middleware'

/**
 * Modo de visualização da sidebar — **os modos SÃO os grupos do menu**.
 *
 * Até o trim, os modos eram os do ai9 (`negocio`/`conteudo`/`plataforma`), que
 * existiam para separar Galeria e Chatbot do resto. Essas features saíram, e os
 * modos ficaram sem significado: `conteudo` filtrava um menu que não tinha mais
 * conteúdo nenhum.
 *
 * Agora o modo filtra o menu pelos **contextos de trabalho do Safegold**, que são
 * os mesmos grupos que o menu do legado já usava. Em vez de acordeão — que obriga
 * a abrir e fechar seção para achar uma tela — a sidebar fica **plana** e o modo
 * decide o que ela mostra.
 *
 * `id` casa com o `id` do grupo em `consoleNavigation.tsx`: a lista de modos é
 * **derivada** dos grupos, não uma segunda lista para manter em sincronia. Grupo
 * novo lá vira modo aqui sozinho, desde que entre em `MODE_GROUPS`.
 */
export type SidebarMode = 'all' | 'results_group' | 'project_group' | 'management' | 'admin_settings' | 'platform'

/** Os grupos que viram modo, na ordem em que aparecem no seletor. */
export const MODE_GROUPS: Exclude<SidebarMode, 'all'>[] = [
    'results_group',
    'project_group',
    'management',
    'admin_settings',
    'platform',
]

/**
 * Grupos que NÃO entram no filtro: são destinos, não contextos de trabalho.
 * Aparecem sempre, em qualquer modo — senão o usuário perde o caminho de volta
 * ao trocar de contexto.
 */
export const ALWAYS_VISIBLE_GROUPS = ['dash', 'faq']

/**
 * Grupos que saem da sidebar por completo, em qualquer modo.
 *
 * `account` (Perfil) já é alcançável pelo dropdown do avatar, no rodapé da
 * sidebar. Repetir o mesmo destino em dois lugares da mesma casca não dá acesso
 * novo — só gasta uma linha do menu e faz o usuário se perguntar se os dois
 * levam ao mesmo lugar.
 */
export const HIDDEN_GROUPS = ['account']

const VALID_MODES: SidebarMode[] = ['all', ...MODE_GROUPS]

/**
 * Modos que existiram antes e ficam gravados no `localStorage` de quem já usou o
 * app. Sem a conversão, esses usuários abririam o console com o menu **vazio** —
 * foi exatamente o que o modo `blog` causou depois do trim do AI9-004.
 */
const LEGACY_MODE_MAP: Record<string, SidebarMode> = {
    blog: 'all',
    negocio: 'results_group',
    conteudo: 'all',
    plataforma: 'platform',
}

interface SidebarModeState {
    mode: SidebarMode
    setMode: (mode: SidebarMode) => void
}

export const useSidebarModeStore = create<SidebarModeState>()(
    persist(
        (set) => ({
            mode: 'all',
            setMode: (mode) => set({ mode }),
        }),
        {
            name: 'sidebar-mode-storage',
        }
    )
)

export function useSidebarMode() {
    const stored = useSidebarModeStore((s) => s.mode)
    const setMode = useSidebarModeStore((s) => s.setMode)
    const mode = VALID_MODES.includes(stored)
        ? stored
        : (LEGACY_MODE_MAP[stored as string] ?? 'all')
    return { mode, setMode }
}
