import { describe, it, expect, beforeEach } from 'vitest'
import { render, renderHook, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { RoleRoute } from '@/components/RoleRoute'
import { CONSOLE_NAV_GROUPS, type NavItem } from '@/app/consoleNavigation'
import { filtrarGrupos } from '@/hooks/useNavItems'
import { useAuthStore, useRole } from '@/store/authStore'

/**
 * **S1 — tarefa 9.1.3.** `Gerente NÃO alcança /permissions · Admin alcança`.
 *
 * O lado do servidor já está travado em
 * `backend/spec/requests/api/v1/permissions_hierarchy_spec.rb` (403 no catálogo e no
 * `PUT` para o Gerente, 200 para o Admin). **Este arquivo trava o outro lado**, e
 * os dois são necessários por um motivo concreto: no legado a autorização existia
 * **só** nas views (D-23), e por isso qualquer requisição feita fora da tela fazia
 * tudo (D-34). Testar só o servidor deixaria a tela levando o Gerente para uma
 * página que vai encher de 403; testar só a tela repetiria o erro do legado.
 *
 * Os três exemplos cobrem as três formas de chegar na área: o **menu**, o
 * **endereço digitado à mão** e o **registro** de onde as duas saem.
 */
function comoPapel(slug: string | null) {
  useAuthStore.setState({
    isAuthenticated: true,
    user: slug ? ({ id: 'u1', name: 'Fulano', user_type_slug: slug } as any) : null,
  })
}

function itemDePermissoes(): NavItem {
  const item = CONSOLE_NAV_GROUPS.flatMap((g) => g.items).find((i) => i.id === 'permissions')
  if (!item) throw new Error('O item de menu `permissions` sumiu do registro de navegação.')
  return item
}

describe('S1 9.1.3 — /permissions é de OG e Admin (DEC-18.2)', () => {
  beforeEach(() => {
    useAuthStore.setState({ isAuthenticated: false, user: null })
  })

  it('o registro declara os papéis, e a tela está MONTADA (não é `element: null`)', () => {
    const item = itemDePermissoes()

    expect(item.roles).toEqual(['og', 'admin'])
    // Um item com `element: null` some do menu e a rota não existe — foi o estado
    // em que esta área ficou quando a S1 fechou. O teste é o que impede a tela de
    // ser "entregue" enquanto ninguém consegue abri-la.
    expect(item.element).not.toBeNull()
  })

  it('o MENU esconde o item do Gerente e mostra para o Admin', () => {
    const visiveis = (papel: any) =>
      filtrarGrupos(CONSOLE_NAV_GROUPS, { role: papel, hasProject: true, mode: 'all' })
        .flatMap((g) => g.items)
        .map((i) => i.id)

    expect(visiveis('gerente')).not.toContain('permissions')
    expect(visiveis('admin')).toContain('permissions')
    expect(visiveis('og')).toContain('permissions')
  })

  it('o ENDEREÇO digitado à mão para o Gerente e passa para o Admin', () => {
    const arvore = (
      <MemoryRouter initialEntries={['/permissions']}>
        <Routes>
          <Route
            path="/permissions"
            element={
              <RoleRoute roles={['og', 'admin']}>
                <p>tela de permissões</p>
              </RoleRoute>
            }
          />
          <Route path="/dashboard" element={<p>início</p>} />
        </Routes>
      </MemoryRouter>
    )

    comoPapel('gerente')
    const { unmount } = render(arvore)
    expect(screen.queryByText('tela de permissões')).not.toBeInTheDocument()
    expect(screen.getByText('início')).toBeInTheDocument()
    unmount()

    comoPapel('admin')
    render(arvore)
    expect(screen.getByText('tela de permissões')).toBeInTheDocument()
  })
})

/**
 * **S1 — tarefa 8.14 / DEC-18.3.** "Ver como" é de OG **ou** Admin.
 *
 * Este exemplo existe porque o hook dizia `canImpersonate: isOg` — o Admin tinha o
 * poder no servidor (`Authorization::Hierarchy`) e **nenhuma porta na tela**.
 * Recurso construído e inalcançável foi o defeito mais comum do legado; um teste é
 * o que impede a regressão silenciosa.
 */
describe('S1 8.14 — quem enxerga "Ver como" (DEC-18.3)', () => {
  const canImpersonateComo = (slug: string) => {
    comoPapel(slug)
    // Chama o HOOK de verdade. Reimplementar a regra aqui faria o teste passar
    // contra a sua própria cópia — que é o jeito mais fácil de um teste verde
    // conviver com um botão ausente.
    return renderHook(() => useRole()).result.current.canImpersonate
  }

  it('OG e Admin sim; Gerente e Colaborador não', () => {
    expect(canImpersonateComo('og')).toBe(true)
    expect(canImpersonateComo('admin')).toBe(true)
    expect(canImpersonateComo('gerente')).toBe(false)
    expect(canImpersonateComo('colaborador')).toBe(false)
  })
})
