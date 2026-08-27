import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'

/**
 * **"Nova renegociação" não pode oferecer o fornecedor que o servidor recusa.**
 *
 * A `integration_key` da renegociação é derivada do nome do fornecedor e é
 * **única por projeto** (`Renegotiation`, S9). Um fornecedor que já tem
 * renegociação neste projeto responde **422** — com "Chave de integração já
 * está em uso neste projeto", uma mensagem que nomeia um campo que a pessoa
 * nunca viu, sobre uma escolha que a própria tela ofereceu.
 *
 * Medido com o seed de demonstração: três das oito opções do `select` eram 422
 * garantido, e um QA que tentou os três primeiros recebeu três erros seguidos.
 *
 * ## O que este arquivo NÃO substitui
 *
 * O servidor continua sendo a defesa — a unicidade é validação de model **e**
 * índice do banco. Isto é a conveniência que evita o erro. As duas coisas,
 * sempre.
 */
const providersApi = { list: vi.fn() }
const companiesApi = { list: vi.fn() }
const renegotiationsApi = {
  list: vi.fn(),
  options: vi.fn(),
  get: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
}

vi.mock('@/lib/api/projects', () => ({
  providersApi: { list: (...a: unknown[]) => providersApi.list(...a) },
  companiesApi: { list: (...a: unknown[]) => companiesApi.list(...a) },
}))
vi.mock('@/lib/api/renegotiations', () => ({
  renegotiationsApi: {
    list: (...a: unknown[]) => renegotiationsApi.list(...a),
    options: (...a: unknown[]) => renegotiationsApi.options(...a),
    get: (...a: unknown[]) => renegotiationsApi.get(...a),
    create: (...a: unknown[]) => renegotiationsApi.create(...a),
    update: (...a: unknown[]) => renegotiationsApi.update(...a),
  },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))

import { RenegotiationFormPage } from '../RenegotiationFormPage'

const META = { page: 1, perPage: 100, total: 0, totalPages: 1 }

function montar() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <MemoryRouter>
      <QueryClientProvider client={client}>
        <RenegotiationFormPage />
      </QueryClientProvider>
    </MemoryRouter>,
  )
}

describe('Nova renegociação — o fornecedor já usado não é oferecido', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    renegotiationsApi.options.mockResolvedValue({
      kinds: ['Financeiro'], origins: ['Fornecedor'], states: [], interval_types: [],
    })
    companiesApi.list.mockResolvedValue({
      items: [{ id: 'emp-1', title: 'Empresa Um' }], meta: META,
    })
    providersApi.list.mockResolvedValue({
      items: [
        { id: 'for-1', title: 'Metalpar Insumos Industriais Ltda' },
        { id: 'for-2', title: 'Rodoviário Cristal Transportes Ltda' },
        { id: 'for-3', title: 'Fundição Morro Alto Ltda' },
      ],
      meta: META,
    })
  })

  async function abrirSelectDeFornecedor() {
    const gatilho = await screen.findByRole('combobox', { name: '' }).catch(() => null)
    const alvo = gatilho ?? document.getElementById('provider_id')
    fireEvent.click(alvo as Element)
  }

  it('marca como indisponível o fornecedor que já tem renegociação no projeto', async () => {
    renegotiationsApi.list.mockResolvedValue({
      items: [{ id: 'rn-1', provider_id: 'for-1' }], meta: META,
    })
    montar()

    expect(await screen.findByText('Nova renegociação')).toBeInTheDocument()
    await abrirSelectDeFornecedor()

    const usado = await screen.findByRole('option', { name: /Metalpar/i })
    const livre = await screen.findByRole('option', { name: /Fundição Morro Alto/i })

    expect(usado).toBeDisabled()
    expect(livre).not.toBeDisabled()
    // A razão fica escrita: sumir com a opção faria a pessoa procurar o
    // fornecedor que ela sabe que existe.
    expect(screen.getByText(/Já tem renegociação neste projeto/i)).toBeInTheDocument()
  })

  it('sem renegociação nenhuma, todos ficam disponíveis', async () => {
    renegotiationsApi.list.mockResolvedValue({ items: [], meta: META })
    montar()

    expect(await screen.findByText('Nova renegociação')).toBeInTheDocument()
    await abrirSelectDeFornecedor()

    for (const nome of [/Metalpar/i, /Rodoviário Cristal/i, /Fundição Morro Alto/i]) {
      expect(await screen.findByRole('option', { name: nome })).not.toBeDisabled()
    }
    expect(screen.queryByText(/Já tem renegociação neste projeto/i)).not.toBeInTheDocument()
  })
})
