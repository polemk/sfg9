import { describe, it, expect, vi, beforeEach } from 'vitest'
import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

/**
 * FE-011 / IMP-A27 / U11 — **a tela de contas nunca renderiza dado falso.**
 *
 * `UsersPage.tsx` servia um array `mockUsers` hardcoded (nove pessoas inventadas, com
 * papéis `client` que a DEC-41 removeu) sempre que o usuário logado fosse visitante ou
 * cliente. Num sistema de crédito isso é inaceitável: quem abrisse a tela veria uma
 * base que não é a dele, sem sinal nenhum de que era exemplo.
 *
 * O primeiro teste é de **fonte**, de propósito. Um teste de render só pega o mock se
 * cair exatamente no ramo que o servia — e o ramo dependia do papel do usuário. Ler o
 * arquivo pega o mock em qualquer ramo, inclusive um que alguém acrescente depois.
 */
// `vi.mock` é içado para o topo do arquivo, então a fábrica não pode fechar sobre uma
// constante declarada aqui embaixo. `vi.hoisted` cria o objeto ANTES do içamento.
const usersApiMock = vi.hoisted(() => ({
  list: vi.fn(),
  get: vi.fn(),
  stats: vi.fn(),
  block: vi.fn(),
  unblock: vi.fn(),
  delete: vi.fn(),
  update: vi.fn(),
  create: vi.fn()
}))

vi.mock('@/lib/api/endpoints', () => ({
  usersApi: usersApiMock,
  impersonateApi: { start: vi.fn(), stop: vi.fn() }
}))

vi.mock('@/lib/api/client', () => ({ apiClient: { post: vi.fn() } }))

vi.mock('@/store/authStore', () => ({
  useAuthStore: Object.assign(
    (selector: any) => selector({ user: { id: 'u1', name: 'OG', user_type: 'OG', user_type_slug: 'og' } }),
    { getState: () => ({ setUser: vi.fn(), startImpersonation: vi.fn() }) }
  )
}))

import { UsersPage } from '../UsersPage'

/**
 * A tela agora **deriva o drawer da URL** (FE-018): `/users/new` e `/users/:id/edit`
 * são rotas de verdade. Por isso o render precisa de um roteador — não é andaime de
 * teste, é o contrato da tela.
 */
function montar(rota = '/users') {
  return render(
    <MemoryRouter initialEntries={[rota]}>
      <Routes>
        <Route path="/users" element={<UsersPage />} />
        <Route path="/users/new" element={<UsersPage />} />
        <Route path="/users/:id/edit" element={<UsersPage />} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('UsersPage — dado real, nunca mock (FE-011)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    usersApiMock.list.mockResolvedValue({ users: [], total: 0, total_pages: 1 })
    usersApiMock.stats.mockResolvedValue({
      total: 0, active: 0, recent: 0, og_count: 0,
      by_role: { og: 0, admin: 0, gerente: 0, colaborador: 0 }
    })
  })

  it('o arquivo-fonte não contém mais um array de usuários hardcoded', () => {
    const source = readFileSync(resolve(__dirname, '../UsersPage.tsx'), 'utf-8')
    expect(source).not.toMatch(/const mockUsers\s*=/)
    expect(source).not.toMatch(/const mockStatsData\s*=/)
    // Os nomes inventados que o mock servia. Se qualquer um voltar, este teste cai.
    for (const nome of ['Lucas Mendes', 'Mariana Silva', 'Rafael Costa', 'Ana Beatriz']) {
      expect(source).not.toContain(nome)
    }
  })

  it('chama a API em vez de servir uma lista local', async () => {
    montar()
    await waitFor(() => expect(usersApiMock.list).toHaveBeenCalled())
  })

  it('lista vazia mostra estado vazio explícito — não uma base inventada', async () => {
    montar()
    expect(await screen.findByText('Nenhuma conta encontrada')).toBeTruthy()
  })

  it('403 explica que falta permissão, em vez de parecer "nenhuma conta"', async () => {
    usersApiMock.list.mockRejectedValue({ response: { status: 403 } })
    montar()
    expect(await screen.findByText('Seu perfil não tem acesso à lista de contas.')).toBeTruthy()
  })

  it('conta bloqueada aparece com selo (DEC-39)', async () => {
    usersApiMock.list.mockResolvedValue({
      users: [{
        id: 'x1', name: 'Bloqueada', email: 'b@example.com', created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z', user_type: 'Colaborador', user_type_slug: 'colaborador',
        is_blocked: true, blocked_at: '2026-02-01T00:00:00Z', identifier: 'AB12CD'
      }],
      total: 1, total_pages: 1
    })
    montar()
    expect(await screen.findByText('BLOQUEADA')).toBeTruthy()
    expect(screen.getByText('AB12CD')).toBeTruthy()
    expect(screen.getByText('Nunca logou')).toBeTruthy()
  })

  it('o card de contagem lê `by_role`, não o alias removido `client_count`', async () => {
    usersApiMock.stats.mockResolvedValue({
      total: 12, active: 8, recent: 2, og_count: 1,
      by_role: { og: 1, admin: 2, gerente: 3, colaborador: 6 }
    })
    montar()
    expect(await screen.findByText('Colaboradores')).toBeTruthy()
    await waitFor(() => expect(screen.getByText('6')).toBeTruthy())
  })

  // --- FE-018 — o drawer vem da URL ------------------------------------------
  //
  // Estes dois exemplos travam o requisito que motivou a mudança: recarregar em
  // `/users/:id/edit` tem de abrir o formulário PREENCHIDO. Antes o drawer vivia num
  // `useState`, então a URL não abria nada; se alguém voltar a esse desenho, o
  // segundo exemplo cai (o formulário abre vazio e o `PATCH` gravaria por cima).
  it('/users/new abre o drawer de criação, e a conta nasce Colaborador (D-39)', async () => {
    montar('/users/new')

    expect(await screen.findByText('Criar conta')).toBeTruthy()
    const papel = screen.getByLabelText('Tipo de conta') as HTMLElement
    expect(papel.textContent).toContain('Colaborador')
  })

  it('/users/:id/edit abre o drawer PREENCHIDO, buscando a conta quando a lista não a tem', async () => {
    usersApiMock.get.mockResolvedValue({
      id: 'u-42', name: 'Fulana de Tal', email: 'fulana@example.com',
      user_type: 'Gerente', user_type_slug: 'gerente',
      created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
    })

    montar('/users/u-42/edit')

    await waitFor(() => expect(usersApiMock.get).toHaveBeenCalledWith('u-42'))
    expect(await screen.findByText('Editar conta')).toBeTruthy()
    await waitFor(() => {
      expect(screen.getByDisplayValue('Fulana de Tal')).toBeTruthy()
    })
  })

  // --- FE-021 — erro POR CAMPO -------------------------------------------------
  it('campo obrigatório reprova SOZINHO, com a mensagem embaixo do campo', async () => {
    montar('/users/new')

    await screen.findByText('Criar conta')
    const salvar = screen.getByRole('button', { name: /criar e convidar/i })
    salvar.click()

    // Nome vazio E sem e-mail/telefone: as duas mensagens aparecem, cada uma no
    // seu campo. A versão anterior mandava uma string única para um `toast`.
    expect(await screen.findByText('Informe o nome.')).toBeTruthy()
    expect(usersApiMock.create).not.toHaveBeenCalled()
  })

  // DEC-14 / D-38 — o campo de senha não existe, e o teste é o que impede alguém
  // de "completar o formulário" acrescentando-o de volta.
  it('o drawer NÃO tem campo de senha', async () => {
    montar('/users/new')

    await screen.findByText('Criar conta')
    expect(screen.queryByLabelText(/senha/i)).toBeNull()
    const source = readFileSync(resolve(__dirname, '../UsersPage.tsx'), 'utf-8')
    expect(source).not.toMatch(/type="password"/)
  })
})
