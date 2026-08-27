import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

/**
 * **FE-140 — o cartão "Dados do template".**
 *
 * A lista cobria Nº, Título, Natureza, Prazo e os marcadores. Ficavam de fora
 * **Escopo**, **criado por / criado em** e o "há X desde a atualização" — e não
 * havia tela de detalhe nenhuma para onde levá-los.
 *
 * O painel "Projetos" do legado
 * (`availability_templates/detail/_body.html.erb:76-91`) chamava
 * `@availability_template.projects`, associação que **não existe** em nenhum dos
 * três models (BE-133): abrir o detalhe de um padrão de projeto levantava
 * `NoMethodError` e o painel nunca renderizou. O que existe é `belongs_to
 * :project` — um padrão de projeto pertence a UM projeto, e é assim que
 * aparece.
 */
const { buscar } = vi.hoisted(() => ({ buscar: vi.fn() }))

vi.mock('@/lib/api/availability', async (original) => {
  const real = await original<typeof import('@/lib/api/availability')>()
  return {
    ...real,
    availabilityTemplatesApi: { ...real.availabilityTemplatesApi, get: buscar },
  }
})

import { AvailabilityTemplateDetailPage } from '../AvailabilityTemplateDetailPage'

const PADRAO = {
  id: 't-1',
  type: 'GlobalAvailabilityTemplate',
  title: 'Recebimento em cartão',
  position_path: '1.2',
  operation_type_label: 'Crédito',
  deadline_type_label: 'Dias corridos',
  scope_label: 'Global',
  is_mandatory: true,
  is_cumulative: false,
  is_adjusted: true,
  is_locked: false,
  locked_message: null,
  author_name: 'Fulana de Tal',
  project_name: null,
  created_at: '2026-01-10T13:45:00Z',
  updated_at: '2026-08-20T13:45:00Z',
}

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/availability-templates/t-1']}>
        <Routes>
          <Route path="/availability-templates/:id" element={<AvailabilityTemplateDetailPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('detalhe do padrão de disponibilidade (FE-140)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    buscar.mockResolvedValue(PADRAO)
  })

  it('mostra o que a LISTA não mostrava: escopo, autor e atualização', async () => {
    montar()

    expect(await screen.findByText('Escopo')).toBeTruthy()
    expect(screen.getByText('Global')).toBeTruthy()
    expect(screen.getByText('Criado por')).toBeTruthy()
    expect(screen.getByText(/Fulana de Tal em /)).toBeTruthy()
    expect(screen.getByText('Atualizado')).toBeTruthy()
  })

  /**
   * "NÃO" não é ausência de informação — é informação. Um traço no lugar dele
   * faria "não é acumulável" parecer "não sabemos".
   */
  it('os três SIM/NÃO aparecem como SIM/NÃO, e não como traço', async () => {
    montar()

    expect(await screen.findByText('Acumulável')).toBeTruthy()
    expect(screen.getAllByText('SIM').length).toBe(2)
    expect(screen.getAllByText('NÃO').length).toBe(1)
  })

  it('no catálogo GLOBAL não há bloco de projeto', async () => {
    montar()

    expect(await screen.findByText('Dados do template')).toBeTruthy()
    expect(screen.queryByText('Projeto')).toBeNull()
  })

  it('no padrão de PROJETO o projeto aparece — no singular, que é o que o dado é', async () => {
    buscar.mockResolvedValue({
      ...PADRAO,
      type: 'ProjectAvailabilityTemplate',
      scope_label: 'Específico',
      project_name: 'Acme',
    })
    montar()

    expect(await screen.findByText('Projeto')).toBeTruthy()
    expect(screen.getByText('Acme')).toBeTruthy()
  })

  it('sem autor, a data de criação continua aparecendo', async () => {
    buscar.mockResolvedValue({ ...PADRAO, author_name: null })
    montar()

    expect(await screen.findByText('Criado por')).toBeTruthy()
    // Dizer "—" para tudo esconderia o QUANDO por falta do QUEM.
    expect(screen.getByText(/2026/)).toBeTruthy()
  })
})
