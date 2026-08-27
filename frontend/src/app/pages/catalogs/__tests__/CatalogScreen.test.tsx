import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

/**
 * S3 / tarefas 4.4.1 e 4.4.2 — as duas garantias das cinco telas de catálogo.
 *
 * 1. **Os quatro estados existem, e a FALHA aparece.** No legado o callback de
 *    erro era vazio: a requisição falhava e a tela ficava em branco,
 *    indistinguível de "não há nada". O usuário não sabia se a lista estava
 *    vazia ou se a rede caiu, e não tinha como tentar de novo.
 * 2. **O critério do botão "Remover" é o critério do SERVIDOR.** No legado o
 *    botão sumia por uma contagem que divergia da lista, e a exclusão passava
 *    assim mesmo — deixando `group_id` órfão. Aqui: botão visível ⇒ a exclusão
 *    passa; botão oculto ⇒ o servidor recusaria com 422.
 */
vi.mock('@/hooks/useNavItems', () => ({ useRoleSlug: () => 'og' }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

/**
 * DEC-108 — o modo **Somente Leitura**, que não cabe em `writeRoles`.
 *
 * `user_is_readonly` é concessão por USUÁRIO, não papel: o mesmo `og` do mock
 * acima pode tê-la. `vi.hoisted` porque `vi.mock` sobe para o topo do arquivo e
 * o estado precisa existir antes dele.
 */
const permissao = vi.hoisted(() => ({ somenteLeitura: false }))
vi.mock('@/hooks/useMyPermissions', () => ({ useIsReadonly: () => permissao.somenteLeitura }))

import { CatalogScreen } from '../CatalogScreen'
import type { CatalogRecord } from '@/lib/api/catalogs'

interface Registro extends CatalogRecord {
  projects_count: number
}

function registro(over: Partial<Registro> = {}): Registro {
  return {
    id: 'a1', title: 'Segmento Alfa', integration_key: 'segmento_alfa', is_active: true,
    created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z',
    projects_count: 0, ...over,
  }
}

const api = {
  list: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
  remove: vi.fn(),
}

const TEXTOS = {
  title: 'Segmentos',
  subtitle: 'Ramo de atuação',
  singular: 'segmento',
  createLabel: 'Novo segmento',
  emptyTitle: 'Nenhum segmento cadastrado',
  emptyDescription: 'Cadastre o primeiro.',
  searchPlaceholder: 'Buscar segmento…',
}

function montar() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <MemoryRouter>
      <QueryClientProvider client={client}>
        <CatalogScreen<Registro>
          queryKey="teste"
          api={api}
          texts={TEXTOS}
          columns={[{ key: 'title', header: 'Segmento', accessor: (r) => r.title }]}
          usageCount={(r) => r.projects_count}
          usageLabel={(r) => `${r.projects_count} projetos usam este segmento — não é possível excluir`}
          emptyForm={() => ({ title: '' })}
          toForm={(r) => ({ title: r.title })}
          form={() => null}
        />
      </QueryClientProvider>
    </MemoryRouter>,
  )
}

const META = { page: 1, perPage: 20, total: 1, totalPages: 1 }

describe('CatalogScreen — os quatro estados (4.4.1)', () => {
  beforeEach(() => vi.clearAllMocks())

  it('mostra o CARREGANDO antes de o dado chegar', async () => {
    api.list.mockReturnValue(new Promise(() => {}))
    montar()
    expect(await screen.findByText(/Carregando segmentos/i)).toBeInTheDocument()
  })

  it('mostra a LISTA quando há dado', async () => {
    api.list.mockResolvedValue({ items: [registro()], meta: META })
    montar()
    expect(await screen.findByText('Segmento Alfa')).toBeInTheDocument()
  })

  it('mostra o VAZIO com o texto PRÓPRIO da tela', async () => {
    api.list.mockResolvedValue({ items: [], meta: { ...META, total: 0 } })
    montar()
    expect(await screen.findByText('Nenhum segmento cadastrado')).toBeInTheDocument()
  })

  // O quarto estado — o que faltava no legado.
  it('mostra a FALHA e oferece tentar de novo', async () => {
    api.list.mockRejectedValue(new Error('rede fora'))
    montar()
    expect(await screen.findByText(/Não foi possível carregar/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Tentar de novo/i })).toBeInTheDocument()
  })

  // FE-062 — o vazio de busca CITA o termo.
  it('o vazio de BUSCA cita o termo procurado', async () => {
    api.list.mockResolvedValue({ items: [], meta: { ...META, total: 0 } })
    montar()

    fireEvent.change(await screen.findByPlaceholderText('Buscar segmento…'), {
      target: { value: 'fomento' },
    })

    expect(await screen.findByText(/Nenhum resultado para «fomento»/, {}, { timeout: 2000 })).toBeInTheDocument()
  })
})

/**
 * **O 409 de escopo de projeto é ESTADO, não erro.**
 *
 * Achado abrindo o app com o usuário OG, o único sem projeto corrente:
 * `/companies`, `/providers`, `/project-guarantees` — as três construídas sobre
 * este molde — pintavam a caixa VERMELHA de falha, com um botão "Tentar de
 * novo" que não podia funcionar, enquanto as outras catorze telas escopadas
 * mostravam "Escolha um projeto para continuar". Mesma resposta do servidor,
 * duas telas diferentes.
 */
describe('CatalogScreen — o escopo de projeto (409) não é falha', () => {
  beforeEach(() => vi.clearAllMocks())

  function erro409(code: string) {
    return { response: { status: 409, data: { code } } }
  }

  it('PROJECT_NOT_SELECTED vira "escolha um projeto", não erro', async () => {
    api.list.mockRejectedValue(erro409('PROJECT_NOT_SELECTED'))
    montar()

    expect(await screen.findByText(/Escolha um projeto para continuar/i)).toBeInTheDocument()
    expect(screen.queryByText(/Não foi possível carregar/i)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Tentar de novo/i })).not.toBeInTheDocument()
  })

  it('PROJECT_NONE_AVAILABLE manda falar com um administrador', async () => {
    api.list.mockRejectedValue(erro409('PROJECT_NONE_AVAILABLE'))
    montar()

    expect(await screen.findByText(/ainda não participa de nenhum projeto/i)).toBeInTheDocument()
  })

  // A frase precisa nomear o recurso — "Estes dados" genérico não diz à pessoa
  // o que ela está deixando de ver.
  it('a frase usa o `scopeResource` da tela', async () => {
    api.list.mockRejectedValue(erro409('PROJECT_NOT_SELECTED'))
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    render(
      <MemoryRouter>
        <QueryClientProvider client={client}>
          <CatalogScreen<Registro>
            queryKey="teste-escopo"
            api={api}
            texts={{ ...TEXTOS, scopeResource: 'as empresas' }}
            columns={[{ key: 'title', header: 'Segmento', accessor: (r) => r.title }]}
            usageCount={(r) => r.projects_count}
            usageLabel={() => ''}
            emptyForm={() => ({ title: '' })}
            toForm={(r) => ({ title: r.title })}
            form={() => null}
          />
        </QueryClientProvider>
      </MemoryRouter>,
    )

    expect(await screen.findByText(/As empresas são de um projeto por vez/i)).toBeInTheDocument()
  })

  // E o 409 que NÃO é de escopo continua sendo erro — casar só pelo status
  // transformaria qualquer conflito em "escolha um projeto".
  it('409 sem código de escopo continua sendo FALHA', async () => {
    api.list.mockRejectedValue(erro409('SOME_OTHER_CONFLICT'))
    montar()

    expect(await screen.findByText(/Não foi possível carregar/i)).toBeInTheDocument()
  })
})

describe('CatalogScreen — o botão segue o critério do servidor (4.4.2)', () => {
  beforeEach(() => vi.clearAllMocks())

  it('SEM vínculo: o botão de excluir aparece', async () => {
    api.list.mockResolvedValue({ items: [registro({ projects_count: 0 })], meta: META })
    montar()
    expect(await screen.findByRole('button', { name: /Excluir Segmento Alfa/i })).toBeInTheDocument()
  })

  it('COM vínculo: o botão some E a razão fica visível no lugar dele', async () => {
    api.list.mockResolvedValue({ items: [registro({ projects_count: 3 })], meta: META })
    montar()

    await screen.findByText('Segmento Alfa')
    expect(screen.queryByRole('button', { name: /Excluir Segmento Alfa/i })).not.toBeInTheDocument()
    expect(
      screen.getByLabelText('3 projetos usam este segmento — não é possível excluir'),
    ).toBeInTheDocument()
  })

  it('excluir chama o servidor e recarrega a lista', async () => {
    api.list.mockResolvedValue({ items: [registro()], meta: META })
    api.remove.mockResolvedValue({ deleted: true })
    montar()

    fireEvent.click(await screen.findByRole('button', { name: /Excluir Segmento Alfa/i }))
    fireEvent.click(await screen.findByRole('button', { name: /^Excluir$/ }))

    await waitFor(() => expect(api.remove).toHaveBeenCalledWith('a1'))
  })
})

/**
 * **O Somente Leitura não recebe botão que o servidor recusa.**
 *
 * Medido em 26/08/2026: o perfil `user_is_readonly` recebia criar/editar/excluir
 * nas **16 telas** que montam este molde e levava **403** no clique. O molde
 * decidia só por papel (`writeRoles`) e nunca consultava `useIsReadonly()` — o
 * mesmo hook que nove telas de outros blocos já usavam.
 *
 * Os dois sentidos são exigidos aqui de propósito. Um teste que só provasse
 * "some com a concessão" passaria com a tela inteira quebrada; o segundo exemplo
 * é o que impede a correção de virar bloqueio para todo mundo.
 */
describe('CatalogScreen — o Somente Leitura não vê ação que o servidor nega', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    permissao.somenteLeitura = false
  })
  afterEach(() => {
    permissao.somenteLeitura = false
  })

  it('COM `user_is_readonly`: nem criar, nem editar, nem excluir', async () => {
    permissao.somenteLeitura = true
    api.list.mockResolvedValue({ items: [registro({ projects_count: 0 })], meta: META })
    montar()

    await screen.findByText('Segmento Alfa')
    expect(screen.queryByRole('button', { name: /Novo segmento/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Editar Segmento Alfa/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Excluir Segmento Alfa/i })).not.toBeInTheDocument()
  })

  it('SEM a concessão, o MESMO papel continua com as três ações', async () => {
    api.list.mockResolvedValue({ items: [registro({ projects_count: 0 })], meta: META })
    montar()

    await screen.findByText('Segmento Alfa')
    expect(screen.getByRole('button', { name: /Novo segmento/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Editar Segmento Alfa/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Excluir Segmento Alfa/i })).toBeInTheDocument()
  })

  // O vazio tem o SEU botão de criar, e ele passava pelo mesmo furo.
  it('COM a concessão, o estado VAZIO também não oferece o atalho de criar', async () => {
    permissao.somenteLeitura = true
    api.list.mockResolvedValue({ items: [], meta: { ...META, total: 0 } })
    montar()

    await screen.findByText('Nenhum segmento cadastrado')
    expect(screen.queryByRole('button', { name: /Novo segmento/i })).not.toBeInTheDocument()
  })
})

describe('as cinco telas não repetem texto herdado de outro domínio (3.14)', () => {
  const telas = ['CarriersPage', 'CarrierGroupsPage', 'SegmentsPage', 'SubSegmentsPage', 'GuaranteeTypesPage']

  // O legado fez as cinco por cópia: o placeholder da tela de SUBsegmentos dizia
  // "Ex: Segmento Comercial", e o toast de excluir grupo dizia "O portador foi
  // excluído". Cada tela tem de falar do que ela cadastra.
  it('nenhuma tela cita "construtora" nem outro vocabulário de outra entidade', () => {
    telas.forEach((tela) => {
      const fonte = readFileSync(resolve(__dirname, `../${tela}.tsx`), 'utf-8')
      expect(fonte).not.toMatch(/construtora/i)
    })
  })

  it('a tela de subsegmentos não usa exemplo de SEGMENTO no placeholder', () => {
    const fonte = readFileSync(resolve(__dirname, '../SubSegmentsPage.tsx'), 'utf-8')
    expect(fonte).not.toMatch(/placeholder="Ex\.?: Segmento/i)
    expect(fonte).toMatch(/subsegmento/i)
  })

  it('nenhuma tela escreve cor literal — a marca vem de token (§5.4.2)', () => {
    ;[...telas, 'CatalogScreen', 'CatalogFields', 'CarrierDetailPage'].forEach((arquivo) => {
      const fonte = readFileSync(resolve(__dirname, `../${arquivo}.tsx`), 'utf-8')
      expect(fonte, `${arquivo} tem cor literal`).not.toMatch(/#[0-9a-fA-F]{3,6}\b|rgba?\(|\bz-\[/)
      expect(fonte, `${arquivo} usa paleta literal do Tailwind`).not.toMatch(
        /\b(bg|text|border)-(slate|gray|zinc|blue|emerald|red|amber)-\d{2,3}\b/,
      )
    })
  })
})
