import { useMemo } from 'react'
import { ALWAYS_VISIBLE_GROUPS, HIDDEN_GROUPS, useSidebarMode, type SidebarMode } from '@/store/sidebarModeStore'
import { useAuthStore } from '@/store/authStore'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import {
  CONSOLE_NAV_GROUPS,
  type NavGroup,
  type NavItem,
  type RoleSlug,
} from '@/app/consoleNavigation'

export type { NavGroup, NavItem, RoleSlug }
export { CONSOLE_NAV_GROUPS }

/**
 * O filtro do menu. A configuração está em `app/consoleNavigation.tsx`; aqui
 * ficam só as três regras que decidem quem vê o quê.
 *
 * Substitui `create_console_menu` (`../sfg/app/helpers/application_helper.rb:100-172`),
 * a maior regra de autorização de interface do legado — 6 grupos montados com
 * `if current_user.og? || …` dentro de um helper de view.
 *
 * **O menu não autoriza nada.** Ele decide o que APARECE; quem decide o que
 * pode é `Authorization::Matrix` no servidor. Esconder o item e não gatear a
 * rota é o D-23/D-34 do legado, onde a única autorização que existia estava nos
 * gates das views — e qualquer requisição fora da tela fazia tudo.
 */

/** O papel do usuário logado, como o servidor o nomeia (`user_type_slug`). */
export function useRoleSlug(): RoleSlug | null {
  const user = useAuthStore((s) => s.user)
  const slug = (user?.user_type_slug || '').toLowerCase()
  if (slug === 'og' || slug === 'admin' || slug === 'gerente' || slug === 'colaborador') return slug
  // `is_og` é o fallback do entity antigo. Sem papel reconhecido, o usuário cai
  // no conjunto mais restrito — nunca no mais amplo.
  if (user?.is_og) return 'og'
  return null
}

function papelPassa(roles: RoleSlug[] | undefined, papel: RoleSlug | null): boolean {
  if (!roles) return true
  if (!papel) return false
  return roles.includes(papel)
}

function projetoPassa(requiresProject: boolean | undefined, hasProject: boolean | undefined): boolean {
  if (!requiresProject) return true
  // `undefined` = a consulta ainda não voltou. Esconder é o lado seguro: o item
  // aparece quando a resposta chega, em vez de piscar e sumir.
  return hasProject === true
}

/**
 * O modo filtra por **grupo**, não por item.
 *
 * Antes, cada item declarava em quais modos aparecia (`modes: ['conteudo']`) —
 * herança dos modos do ai9, que separavam Galeria e Chatbot. Essas features
 * saíram no trim e os modos ficaram sem significado.
 *
 * Agora **o modo É o grupo**: escolher "Gestão" mostra o grupo Gestão, e só ele.
 * Os grupos de `ALWAYS_VISIBLE_GROUPS` (Início, Ajuda) escapam do filtro porque
 * são destinos, não contextos — sem eles o usuário perderia o caminho de volta
 * ao trocar de modo.
 */
function grupoPassaNoModo(grupoId: string, modo: SidebarMode): boolean {
  if (ALWAYS_VISIBLE_GROUPS.includes(grupoId)) return true
  if (modo === 'all') return true
  return grupoId === modo
}

export interface NavFilterInput {
  role: RoleSlug | null
  hasProject: boolean | undefined
  mode: SidebarMode
}

/**
 * **Regra 1 — autorização de navegação.** Papel + participação + modo, e nada
 * mais. É a tradução do `create_console_menu`, e é o que os testes de C3
 * exercitam: um papel novo muda o menu sem tocar em componente (tarefa F.1).
 *
 * Separada de propósito da regra 2: misturar as duas faria o teste de "o
 * Gerente traz o grupo Cadastro" depender de quais telas já foram entregues, e
 * ele passaria a falhar ou a passar por motivo errado conforme as outras fatias
 * chegassem.
 */
export function filtrarPorPermissao(
  grupos: NavGroup[],
  { role, hasProject, mode }: NavFilterInput,
): NavGroup[] {
  return grupos
    .filter((g) => !HIDDEN_GROUPS.includes(g.id))
    .filter(
      (g) =>
        papelPassa(g.roles, role) &&
        projetoPassa(g.requiresProject, hasProject) &&
        grupoPassaNoModo(g.id, mode),
    )
    .map((g) => ({
      ...g,
      items: g.items.filter(
        (i) => papelPassa(i.roles, role) && projetoPassa(i.requiresProject, hasProject),
      ),
    }))
}

/**
 * **Regra 2 — a área existe?** Item cuja página a fatia dona ainda não entregou
 * não aparece: menu que leva a 404 é pior que menu curto. Grupo que ficou sem
 * item algum e sem destino próprio some junto — o legado desenhava o cabeçalho
 * do grupo vazio e o acordeão abria em nada.
 */
export function apenasMontados(grupos: NavGroup[]): NavGroup[] {
  return grupos
    .map((g) => ({ ...g, items: g.items.filter((i) => i.element !== null) }))
    .filter((g) => g.items.length > 0 || Boolean(g.path))
}

/** As duas regras, na ordem em que a `Sidebar` precisa delas. */
export function filtrarGrupos(grupos: NavGroup[], entrada: NavFilterInput): NavGroup[] {
  return apenasMontados(filtrarPorPermissao(grupos, entrada))
}

/** Os grupos visíveis para o usuário atual. É o que a `Sidebar` renderiza. */
export function useNavGroups(): NavGroup[] {
  const { mode } = useSidebarMode()
  const role = useRoleSlug()
  const { hasProject } = useCurrentProject()

  return useMemo(
    () => filtrarGrupos(CONSOLE_NAV_GROUPS, { role, hasProject, mode }),
    [role, hasProject, mode],
  )
}

/**
 * A lista achatada dos itens visíveis. Consumida pela `MobileBottomBar`, que
 * mostra os 5 primeiros.
 */
export function useNavItems(): NavItem[] {
  const grupos = useNavGroups()
  return useMemo(() => grupos.flatMap((g) => g.items), [grupos])
}
