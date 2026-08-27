import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { AuthFlow } from '../AuthFlow'
import { useAuthStore } from '@/store/authStore'

/**
 * **S1 — tarefa 9.4.2.** O fluxo de login em etapas funciona nas **duas** abas
 * (E-mail e WhatsApp).
 *
 * ## Por que este teste existe, e por que ele exercita o fluxo INTEIRO
 *
 * O teste que já havia (`MagicLogin.test.tsx`) mocka o `useAuth` e verifica que a
 * tela **renderiza**. Isso não prova o fluxo: o login desta base já esteve quebrado
 * com quatro métodos inexistentes sendo chamados, e o `rspec` inteiro verde —
 * porque os specs estubavam exatamente o que faltava. Aqui o `useAuth` e o store
 * são os **de verdade**; o único mock é a borda de rede (`authService`), que é o
 * limite legítimo de um teste de unidade.
 *
 * O que cada exemplo trava:
 *  - **destino → código** é uma transição de etapa, não dois formulários empilhados
 *    (FE-001: o legado tinha Entrar / Cadastre-se / Esqueci a senha, três painéis na
 *    mesma tela);
 *  - a aba **WhatsApp** manda `method: 'whatsapp'` com o número **só de dígitos**, e
 *    a de e-mail manda `method: 'email'` — DEC-14, telefone é canal de login de
 *    primeira classe, não um extra;
 *  - **não há campo de senha em etapa nenhuma** (DEC-14).
 */
const authServiceMock = vi.hoisted(() => ({
  requestLoginCode: vi.fn(),
  requestMagicLogin: vi.fn(),
  validateLoginCode: vi.fn(),
  validateMagicCode: vi.fn(),
  checkSessionStatus: vi.fn(),
  logout: vi.fn(),
  getGoogleAuthUrl: vi.fn(),
  getFacebookAuthUrl: vi.fn(),
}))

vi.mock('@/lib/api/auth', () => ({ authService: authServiceMock }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() } }))

// O seletor de país do `PhoneInputGroup` busca `/api/v1/countries` ao montar. A
// lista embutida dele já cobre o Brasil; o stub só evita a chamada de rede.
vi.mock('@/lib/api/client', () => ({
  apiClient: {
    get: vi.fn().mockResolvedValue({ countries: [{ name: 'Brazil', iso2: 'BR', dial_code: '55' }] }),
    post: vi.fn(),
  },
}))

function estadoLimpo() {
  useAuthStore.setState({
    isAuthenticated: false,
    user: null,
    loginMethod: 'email',
    identifier: '',
    loginCode: '',
    isLoading: false,
    error: null,
    devCode: null,
  })
}

describe('S1 9.4.2 — o login em etapas nas duas abas', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    estadoLimpo()
    authServiceMock.requestLoginCode.mockResolvedValue({ success: true })
  })

  afterEach(() => estadoLimpo())

  it('começa na etapa de DESTINO, com as duas abas e sem campo de senha', () => {
    render(<AuthFlow />)

    expect(screen.getByText('Acessar o painel')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /e-mail/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /whatsapp/i })).toBeInTheDocument()

    // DEC-14 — não há senha. Um campo de senha aqui seria um segundo sistema de
    // identidade dentro do produto.
    expect(document.querySelector('input[type="password"]')).toBeNull()
    expect(screen.queryByText(/esqueci a senha/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/cadastre-se/i)).not.toBeInTheDocument()
  })

  it('ABA E-MAIL: pede o código e AVANÇA para a etapa de verificação', async () => {
    render(<AuthFlow />)

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'fulana@example.com' } })
    fireEvent.click(screen.getByRole('button', { name: /^entrar$/i }))

    await waitFor(() =>
      expect(authServiceMock.requestLoginCode).toHaveBeenCalledWith({
        identifier: 'fulana@example.com',
        method: 'email',
      }),
    )

    // A ETAPA MUDOU. Este é o requisito: um fluxo em etapas, não dois formulários.
    expect(await screen.findByRole('heading', { name: 'Verificar código' })).toBeInTheDocument()
    expect(screen.getByText('fulana@example.com')).toBeInTheDocument()
    expect(screen.getByLabelText('Dígito 1 do código')).toBeInTheDocument()
  })

  it('ABA WHATSAPP: troca de canal, pede o código só com dígitos e avança', async () => {
    render(<AuthFlow />)

    fireEvent.click(screen.getByRole('button', { name: /whatsapp/i }))
    await waitFor(() => expect(useAuthStore.getState().loginMethod).toBe('whatsapp'))

    // O `PhoneInputGroup` normaliza para DDI + número. O store guarda o resultado.
    useAuthStore.getState().setIdentifier('5548999998888')
    await waitFor(() => expect(useAuthStore.getState().identifier).toBe('5548999998888'))

    fireEvent.click(screen.getByRole('button', { name: /^entrar$/i }))

    await waitFor(() =>
      expect(authServiceMock.requestLoginCode).toHaveBeenCalledWith({
        identifier: '5548999998888',
        method: 'whatsapp',
      }),
    )
    expect(await screen.findByRole('heading', { name: 'Verificar código' })).toBeInTheDocument()
  })

  it('"Voltar para o login" desfaz a etapa — o fluxo anda nos dois sentidos', async () => {
    render(<AuthFlow />)

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'fulana@example.com' } })
    fireEvent.click(screen.getByRole('button', { name: /^entrar$/i }))
    await screen.findByRole('heading', { name: 'Verificar código' })

    fireEvent.click(screen.getByRole('button', { name: /voltar para o login/i }))
    expect(await screen.findByText('Acessar o painel')).toBeInTheDocument()
  })

  /**
   * O defeito que este exemplo trava está descrito em `MagicLogin.handleSubmit`:
   * a aba **WhatsApp** com número curto **não dizia nada** — sem mensagem, sem
   * avanço, só um `console.warn`. Escolhi a aba do WhatsApp de propósito: na de
   * e-mail o `<input type="email">` aciona a validação nativa do navegador antes do
   * `submit`, então o defeito ficava escondido atrás do tipo do campo.
   */
  it('WhatsApp curto NÃO avança de etapa, e DIZ o motivo na tela', async () => {
    render(<AuthFlow />)

    fireEvent.click(screen.getByRole('button', { name: /whatsapp/i }))
    await waitFor(() => expect(useAuthStore.getState().loginMethod).toBe('whatsapp'))

    useAuthStore.getState().setIdentifier('5548999')
    await waitFor(() => expect(useAuthStore.getState().identifier).toBe('5548999'))

    fireEvent.click(screen.getByRole('button', { name: /^entrar$/i }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/whatsapp com código do país/i)
    expect(authServiceMock.requestLoginCode).not.toHaveBeenCalled()
    expect(screen.queryByRole('heading', { name: 'Verificar código' })).not.toBeInTheDocument()
  })
})
