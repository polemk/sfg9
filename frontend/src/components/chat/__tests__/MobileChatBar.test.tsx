import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MobileChatBar } from '../MobileChatBar'

// Mock useChat context
const mockSetViewMode = vi.fn()
vi.mock('@/contexts/ChatContext', () => ({
  useChat: () => ({ setViewMode: mockSetViewMode })
}))

// Mock useLocation
let mockPathname = '/dashboard'
vi.mock('react-router-dom', () => ({
  useLocation: () => ({ pathname: mockPathname })
}))

// Mock chatBarTracker
vi.mock('@/lib/chatBarTracker', () => ({
  trackChatBarEvent: vi.fn()
}))

// Mock DataSphere — canvas pesado, substitui por div simples
vi.mock('@/components/chat/DataSphere', () => ({
  DataSphere: ({ onClick, className }: any) => (
    <div data-testid="data-sphere" className={className} onClick={onClick} />
  )
}))

// Mock sessionStorage
const sessionStorageMock = (() => {
  let store: Record<string, string> = {}
  return {
    getItem: vi.fn((key: string) => store[key] ?? null),
    setItem: vi.fn((key: string, value: string) => { store[key] = value }),
    removeItem: vi.fn((key: string) => { delete store[key] }),
    clear: vi.fn(() => { store = {} }),
  }
})()
Object.defineProperty(window, 'sessionStorage', { value: sessionStorageMock })

describe('MobileChatBar', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    sessionStorageMock.clear()
    mockPathname = '/dashboard'
  })

  it('mostra texto contextual do dashboard quando sem mensagens', () => {
    render(<MobileChatBar />)
    expect(screen.getByText(/painel principal/)).toBeTruthy()
  })

  it('mostra fallback quando rota não mapeada', () => {
    mockPathname = '/some/random/page'
    render(<MobileChatBar />)
    expect(screen.getByText(/falar com o assistente/)).toBeTruthy()
  })

  it('mostra preview da última mensagem do agente', () => {
    const msgs = [
      { role: 'user', content: 'Oi' },
      { role: 'agent', content: 'Olá! Bem-vindo ao painel de demonstração, posso ajudar com algo?' }
    ]
    sessionStorageMock.setItem('ai9_flow_messages', JSON.stringify(msgs))
    render(<MobileChatBar />)
    expect(screen.getByText(/Olá! Bem-vindo ao painel de demonstração, posso aj\.\.\./)).toBeTruthy()
  })

  it('tap na barra chama setViewMode("ai")', () => {
    render(<MobileChatBar />)
    const expandBtn = screen.getByLabelText('Abrir chat com Assistente')
    fireEvent.click(expandBtn)
    expect(mockSetViewMode).toHaveBeenCalledWith('ai')
  })

  it('DataSphere renderiza no lugar do botão de carrinho', () => {
    render(<MobileChatBar />)
    expect(screen.getByTestId('data-sphere')).toBeTruthy()
  })

  it('renderiza avatar quando avatarUrl é fornecido', () => {
    render(<MobileChatBar avatarUrl="/test-avatar.png" />)
    const img = screen.getByAltText('Assistente')
    expect(img.getAttribute('src')).toBe('/test-avatar.png')
  })

  it('renderiza inicial quando não há avatarUrl', () => {
    render(<MobileChatBar agentName="Nathy" />)
    expect(screen.getByText('N')).toBeTruthy()
  })

  it('usa personaName do flow ativo para label', () => {
    render(<MobileChatBar personaName="Martha da PK" />)
    const expandBtn = screen.getByLabelText('Abrir chat com Martha da PK')
    expect(expandBtn).toBeTruthy()
  })

  it('registra evento de impression na montagem', async () => {
    const tracker = await import('@/lib/chatBarTracker')
    render(<MobileChatBar />)
    expect(tracker.trackChatBarEvent).toHaveBeenCalledWith(
      'impression',
      '/dashboard',
      expect.objectContaining({ persona: 'Assistente' })
    )
  })
})
