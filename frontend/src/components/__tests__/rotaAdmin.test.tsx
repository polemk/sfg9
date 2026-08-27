import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { OgRoute } from '@/components/OgRoute'
import { VisitorRoute } from '@/components/VisitorRoute'
import { useAuthStore } from '@/store/authStore'

/**
 * Achado da varredura de resíduos do trim (R-03, 26/08/2026).
 *
 * O `VisitorRoute` — **vivo**, nas três rotas `/admin/chat/*` — liberava acesso
 * por `typeSlug === 'client'`, `t.includes('cliente')` e `visitor`: tipos que a
 * **DEC-41 removeu**. O backend foi limpo quando a DEC entrou; o frontend não.
 *
 * O efeito prático já era "OG e Admin passam", mas escrito de um jeito que
 * convida ao erro: "cliente" é palavra corrente do domínio, e o primeiro tipo
 * criado com esse nome abriria as três rotas sem ninguém perceber.
 */
function entrarComo(user: Record<string, unknown> | null) {
  useAuthStore.setState({ isAuthenticated: user !== null, user: user as never })
}

function renderizar(Guard: typeof OgRoute) {
  return render(
    <MemoryRouter initialEntries={['/protegida']}>
      <Routes>
        <Route path="/protegida" element={<Guard><p>conteudo protegido</p></Guard>} />
        <Route path="/dashboard" element={<p>painel</p>} />
        <Route path="/login" element={<p>login</p>} />
      </Routes>
    </MemoryRouter>,
  )
}

describe.each([
  ['OgRoute', OgRoute],
  ['VisitorRoute', VisitorRoute],
])('%s — acesso ao console administrativo', (_nome, Guard) => {
  beforeEach(() => entrarComo(null))

  it('OG entra', () => {
    entrarComo({ id: '1', user_type_slug: 'og', is_og: true })
    renderizar(Guard)
    expect(screen.getByText('conteudo protegido')).toBeInTheDocument()
  })

  it('Admin entra', () => {
    entrarComo({ id: '2', user_type_slug: 'admin' })
    renderizar(Guard)
    expect(screen.getByText('conteudo protegido')).toBeInTheDocument()
  })

  it('Gerente NÃO entra', () => {
    entrarComo({ id: '3', user_type_slug: 'gerente' })
    renderizar(Guard)
    expect(screen.getByText('painel')).toBeInTheDocument()
  })

  it('Colaborador NÃO entra', () => {
    entrarComo({ id: '4', user_type_slug: 'colaborador' })
    renderizar(Guard)
    expect(screen.getByText('painel')).toBeInTheDocument()
  })

  it('sem autenticação vai para o login', () => {
    entrarComo(null)
    renderizar(Guard)
    expect(screen.getByText('login')).toBeInTheDocument()
  })

  it('tipo REMOVIDO pela DEC-41 não entra — `client`', () => {
    entrarComo({ id: '5', user_type_slug: 'client', user_type: 'Cliente' })
    renderizar(Guard)
    expect(screen.getByText('painel')).toBeInTheDocument()
  })

  it('tipo REMOVIDO pela DEC-41 não entra — `visitor`', () => {
    entrarComo({ id: '6', user_type_slug: 'visitor', user_type: 'Visitante' })
    renderizar(Guard)
    expect(screen.getByText('painel')).toBeInTheDocument()
  })

  it('nome que apenas CONTÉM "admin" não entra — casar por substring é o defeito', () => {
    // `t.includes('admin')` deixava "Administrativo" e "Sub-admin" passarem.
    entrarComo({ id: '7', user_type_slug: 'administrativo', user_type: 'Administrativo' })
    renderizar(Guard)
    expect(screen.getByText('painel')).toBeInTheDocument()
  })
})
