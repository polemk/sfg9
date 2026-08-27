import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'

/**
 * **FE-086 — o responsável na EDIÇÃO.**
 *
 * Os três modos existiam só na criação: o `fieldset` inteiro estava embrulhado
 * em `{!editing && …}`. Quem editasse um projeto não tinha nenhum controle de
 * responsável na tela — a troca só era possível pela API, apesar de o `doProjeto`
 * já mapear o modo e o id e de o payload já enviá-los quando editando.
 *
 * O legado mostrava, em dois formatos (`projects/new/_body.html.erb:132,167`):
 * projeto novo **ou sem responsável** → os três modos; projeto que já TEM
 * responsável → um select só, para trocar. É essa forma que estes exemplos
 * travam.
 */
const listar = vi.fn()
vi.mock('@/lib/api/projects', async (original) => {
  const real = await original<typeof import('@/lib/api/projects')>()
  return {
    ...real,
    projectsApi: {
      ...real.projectsApi,
      responsibleCandidates: (...args: unknown[]) => listar(...args),
    },
  }
})

import { ProjectForm, valoresIniciais, doProjeto } from '../ProjectForm'
import type { Project } from '@/lib/api/types'

function montar(editing: Project | null, valores = editing ? doProjeto(editing) : valoresIniciais()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <ProjectForm values={valores} onChange={() => {}} editing={editing} />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

const PROJETO = {
  id: 'p-1',
  name: 'Acme',
  slug: 'acme',
  integration_key: 'acme',
} as unknown as Project

describe('FE-086 — responsável na edição', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    listar.mockResolvedValue([])
  })

  it('na CRIAÇÃO os três modos aparecem', () => {
    montar(null)

    expect(screen.getByText('Responsável')).toBeTruthy()
    // Os três botões de modo.
    expect(screen.getAllByRole('button').length).toBeGreaterThanOrEqual(3)
  })

  /**
   * Este é o exemplo que faltava, e é o que o defeito produzia: editar e não
   * ter onde mexer no responsável.
   */
  it('editando um projeto SEM responsável, os modos continuam disponíveis', () => {
    montar({ ...PROJETO, responsible_id: null } as unknown as Project)

    expect(screen.getByText('Responsável')).toBeTruthy()
  })

  it('editando um projeto COM responsável, o campo de troca existe', () => {
    montar({ ...PROJETO, responsible_id: 'u-9' } as unknown as Project)

    expect(screen.getByText('Responsável')).toBeTruthy()
    expect(screen.getByLabelText('Buscar responsável')).toBeTruthy()
  })

  /**
   * **"Sem responsável" não aparece no meio da troca, e isso é deliberado.**
   *
   * O legado também não oferecia os modos nesse caso. Desfazer o vínculo é
   * outra ação; oferecê-la ao lado da troca faria um clique errado remover o
   * responsável sem nenhum aviso.
   */
  it('com responsável definido, os modos NÃO aparecem', () => {
    montar({ ...PROJETO, responsible_id: 'u-9' } as unknown as Project)

    expect(screen.queryByText('Sem responsável')).toBeNull()
  })
})
