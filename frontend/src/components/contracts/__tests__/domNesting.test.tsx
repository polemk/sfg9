import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { ContractCard, ContractVersionRow } from '@/components/contracts/ContractCard'

/**
 * S12 — **aninhamento de DOM válido**.
 *
 * Regressão real, achada pelo aviso do React no navegador: o `ContractCard`
 * tinha um `<Badge>` (que é `<div>`) dentro de um `<p>`. `<div>` dentro de
 * `<p>` é HTML inválido, e o navegador **reescreve a árvore** — fecha o `<p>`
 * sozinho antes do `<div>`. O que se escreveu deixa de ser o que fica no DOM, e
 * o sintoma (espaçamento estranho, estilo que não aplica) aparece longe da
 * causa. `tsc` passa limpo e nenhum teste de comportamento reprova.
 *
 * Aqui o aviso vira **falha**: o `console.error` do React é interceptado e
 * qualquer `validateDOMNesting` reprova o exemplo. Silenciar o aviso seria
 * apagar o único sinal de que a árvore renderizada difere da escrita.
 */

function Envolvido({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

let avisos: string[] = []
let original: typeof console.error

beforeEach(() => {
  avisos = []
  original = console.error
  console.error = (...args: unknown[]) => {
    const texto = args.map(String).join(' ')
    if (texto.includes('validateDOMNesting') || texto.includes('cannot appear as a descendant')) {
      avisos.push(texto)
    }
    original(...(args as []))
  }
})

afterEach(() => {
  console.error = original
})

const CATALOGO = {
  kind: 'Termos de Uso',
  slug: 'termos-de-uso',
  current_version: 3,
  versions_count: 3,
  accepted_count: 12,
}

describe('aninhamento de DOM das telas de contrato', () => {
  it('ContractCard não põe `<div>` dentro de `<p>`', () => {
    render(
      <Envolvido>
        <ContractCard entry={CATALOGO} podePublicar />
      </Envolvido>,
    )
    expect(screen.getByText('Termos de Uso')).toBeInTheDocument()
    expect(avisos).toEqual([])
  })

  it('ContractCard sem versão publicada também é válido', () => {
    render(
      <Envolvido>
        <ContractCard entry={{ ...CATALOGO, current_version: null, versions_count: 0, accepted_count: 0 }} podePublicar={false} />
      </Envolvido>,
    )
    expect(avisos).toEqual([])
  })

  it('ContractVersionRow: o selo dentro do link é `<span>`', () => {
    render(
      <Envolvido>
        <ContractVersionRow
          to="/admin/contracts/termos-de-uso"
          version={3}
          title="Termos de Uso"
          publishedAt="2026-08-01T00:00:00Z"
          acceptedCount={12}
          divergentCount={4}
          isCurrent
        />
      </Envolvido>,
    )
    expect(screen.getByText('vigente').tagName).toBe('SPAN')
    expect(avisos).toEqual([])
  })
})

describe('aninhamento de DOM da Central de ajuda', () => {
  const tree = vi.fn()
  const items = vi.fn()

  it('a linha da categoria não vira `<input>` dentro de `<button>` ao renomear', async () => {
    vi.doMock('@/lib/api/help', () => ({
      helpAdminApi: {
        tree: (...a: any[]) => tree(...a),
        items: (...a: any[]) => items(...a),
        createGroup: vi.fn(), updateGroup: vi.fn(), groupImpact: vi.fn(), removeGroup: vi.fn(),
        createCategory: vi.fn(), updateCategory: vi.fn(), categoryImpact: vi.fn(), removeCategory: vi.fn(),
        getItem: vi.fn(), createItem: vi.fn(), updateItem: vi.fn(), removeItem: vi.fn(),
      },
    }))
    tree.mockResolvedValue([
      {
        id: 'g-1',
        title: 'Primeiros passos',
        position: 0,
        categories: [{ id: 'c-1', title: 'Acesso e conta', slug: 'acesso-e-conta', help_group_id: 'g-1', position: 0, items_count: 2 }],
      },
    ])
    items.mockResolvedValue({ items: [], meta: { page: 1, perPage: 20, total: 0, totalPages: 1 } })

    const { HelpCenterPage } = await import('@/app/pages/admin/HelpCenterPage')
    render(
      <Envolvido>
        <HelpCenterPage />
      </Envolvido>,
    )

    const rotulo = await screen.findByText('Acesso e conta')
    fireEvent.doubleClick(rotulo)

    const campo = await screen.findByRole('textbox', { name: /Renomear Acesso e conta/ })
    // O campo de renomeação NÃO pode estar dentro de um botão: a barra de
    // espaço digitada no nome ativaria o botão e trocaria de categoria.
    expect(campo.closest('button')).toBeNull()
    await waitFor(() => expect(avisos).toEqual([]))
  })
})
