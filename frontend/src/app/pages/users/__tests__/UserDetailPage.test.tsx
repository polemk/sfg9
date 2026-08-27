import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

/**
 * **BE-027 — `/u/users/:id` e `/u/:id`, o detalhe da conta.**
 *
 * As duas rotas do legado (`routes.rb:16` e `:226`) apontavam para o mesmo
 * `show` e viraram uma só. O comportamento conferia na leitura; o que faltava
 * era a terceira perna: **não existia nenhum teste automatizado desta tela** —
 * só render manual em 1440x900 e 390x844.
 *
 * O que se trava aqui são os quatro defeitos do legado que a tela fecha, e o
 * primeiro deles é o que mais importa: no legado a ABA e o CONTEÚDO eram
 * gateados em lugares diferentes, com condições diferentes, e o resultado
 * medido foi o Gerente vendo a aba "Projetos" abrir vazia.
 */
// `vi.mock` é IÇADO acima das declarações do módulo, então as duplas têm de
// nascer dentro de `vi.hoisted` — sem isso a fábrica do mock roda antes do
// `const` e estoura "Cannot access 'api' before initialization".
const { papel, somenteLeitura, api } = vi.hoisted(() => ({
  papel: vi.fn(() => 'og'),
  somenteLeitura: vi.fn(() => false),
  api: {
    get: vi.fn(),
    memberships: vi.fn(),
    permissions: vi.fn(),
    setPermission: vi.fn(),
  },
}))

vi.mock('@/hooks/useNavItems', () => ({ useRoleSlug: () => papel() }))
vi.mock('@/hooks/useMyPermissions', () => ({ useIsReadonly: () => somenteLeitura() }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

vi.mock('@/lib/api/endpoints', async (original) => {
  const real = await original<typeof import('@/lib/api/endpoints')>()
  return { ...real, usersApi: { ...real.usersApi, ...api } }
})

import { UserDetailPage } from '../UserDetailPage'

const CONTA = {
  id: 'u-7',
  name: 'Fulana de Tal',
  email: 'fulana@exemplo.com',
  user_type: 'Gerente',
  user_type_slug: 'gerente',
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
}

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/users/u-7']}>
        <Routes>
          <Route path="/users/:id" element={<UserDetailPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('UserDetailPage — o detalhe da conta (BE-027)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    papel.mockReturnValue('og')
    somenteLeitura.mockReturnValue(false)
    api.get.mockResolvedValue(CONTA)
    api.memberships.mockResolvedValue({ items: [], meta: { total: 0, page: 1, perPage: 20, totalPages: 1 } })
    api.permissions.mockResolvedValue({ permissions: [] })
  })

  it('carrega a conta pelo `:id` da rota', async () => {
    montar()

    expect((await screen.findAllByText('Fulana de Tal')).length).toBeGreaterThan(0)
    expect(api.get).toHaveBeenCalledWith('u-7')
  })

  it('as três abas aparecem', async () => {
    montar()

    expect(await screen.findByRole('tab', { name: /geral/i })).toBeTruthy()
    expect(screen.getByRole('tab', { name: /projetos/i })).toBeTruthy()
    expect(screen.getByRole('tab', { name: /permiss/i })).toBeTruthy()
  })

  /**
   * **Defeito 1 do legado, e o mais caro.**
   *
   * Lá `detail/_body.html.erb:14` decidia se a aba aparecia e `:22` decidia se
   * o conteúdo existia — com condições DIFERENTES. O Gerente via a aba e ela
   * abria vazia.
   *
   * A correção foi estrutural: nenhuma aba tem condição de visibilidade
   * própria. Este exemplo troca o papel para Gerente e exige as duas metades —
   * a aba E o conteúdo dela.
   */
  it('para o GERENTE a aba Projetos aparece E abre com conteúdo', async () => {
    papel.mockReturnValue('gerente')
    // A forma vem de `usersApi.memberships`: o item JÁ é o projeto
    // (`{id, name, slug, is_active}`), não um vínculo com o projeto dentro.
    api.memberships.mockResolvedValue({
      items: [{ id: 1, name: 'Acme', slug: 'acme', is_active: true }],
      meta: { total: 1, page: 1, perPage: 20, totalPages: 1 },
    })
    montar()

    fireEvent.click(await screen.findByRole('tab', { name: /projetos/i }))

    await waitFor(() => expect(api.memberships).toHaveBeenCalled())
    // A metade que faltava no legado: o conteúdo.
    expect(await screen.findByText('Acme')).toBeTruthy()
  })

  /**
   * **Defeito 4** — a aba listava `Project.all`: abrir o perfil de qualquer
   * pessoa mostrava a carteira inteira do sistema. Agora a chamada é a
   * participação DAQUELA conta, paginada.
   */
  it('a aba Projetos pergunta pelas participações da conta, não por todos os projetos', async () => {
    montar()

    fireEvent.click(await screen.findByRole('tab', { name: /projetos/i }))

    await waitFor(() => expect(api.memberships).toHaveBeenCalled())
    expect(api.memberships.mock.calls[0][0]).toBe('u-7')
  })

  /**
   * **Defeito 3** — o painel listava 17 abilities escritas na view. Agora ele
   * renderiza o que o servidor devolve. O exemplo prova pela ausência: com o
   * servidor devolvendo lista vazia, nada de permissão aparece — se houvesse
   * lista escrita no arquivo, ela apareceria assim mesmo.
   */
  it('as permissões vêm do SERVIDOR — lista vazia não vira lista escrita na tela', async () => {
    montar()

    fireEvent.click(await screen.findByRole('tab', { name: /permiss/i }))

    await waitFor(() => expect(api.permissions).toHaveBeenCalledWith('u-7'))
    expect(screen.queryByText(/may_create_users/i)).toBeNull()
  })

  /**
   * **Defeito 2** — "Editar" era gateado por `may_delete_users?`, permissão de
   * REMOVER: quem podia editar e não podia remover não via o botão.
   *
   * Aqui o gate é o de escrita (OG/Admin, DEC-18) — o mesmo que o servidor
   * aplica no `PUT`.
   */
  it('Colaborador não vê o botão de editar', async () => {
    papel.mockReturnValue('colaborador')
    montar()

    expect((await screen.findAllByText('Fulana de Tal')).length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: /editar/i })).toBeNull()
  })

  it('somente-leitura tira o botão mesmo de um OG', async () => {
    somenteLeitura.mockReturnValue(true)
    montar()

    expect((await screen.findAllByText('Fulana de Tal')).length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: /editar/i })).toBeNull()
  })
})
