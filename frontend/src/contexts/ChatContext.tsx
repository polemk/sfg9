import { createContext, useContext, useState, useCallback, useEffect, type ReactNode } from 'react'
import { useSearchParams, useLocation } from 'react-router-dom'

interface TriggerFlowOptions {
  /** Optional intent message to send silently (e.g., "Lead clicked on Pricing") */
  intent?: string
  /** Whether to reset the chat session when switching agents */
  resetSession?: boolean
}

/** Mobile view mode: site shows content with minimized chat, ai shows fullscreen chat */
export type ViewMode = 'site' | 'ai'

interface ChatContextType {
  isOpen: boolean
  sessionId: string | null
  /** The currently active agent/flow ID */
  currentAgentId: string | null
  /** Optional pending intent to be sent to the agent */
  pendingIntent: string | null
  /** Mobile view mode: 'site' = minimized chat bar, 'ai' = fullscreen chat */
  viewMode: ViewMode
  /** Persona ativa do flow (name/avatar/role) — populada pelo AIChatWidget */
  activePersona: { name: string; avatar: string; role: string } | null
  openChat: (sessionId?: string) => void
  closeChat: () => void
  toggleChat: () => void
  /** Switch to a different agent/flow, optionally with an intent message */
  triggerFlow: (agentId: string, options?: TriggerFlowOptions) => void
  /** Clear the pending intent after it's been processed */
  clearPendingIntent: () => void
  /** Set the current agent ID (usually from route matching) */
  setCurrentAgentId: (agentId: string | null) => void
  /** Set mobile view mode */
  setViewMode: (mode: ViewMode) => void
  /** Toggle between site and ai mode */
  toggleViewMode: () => void
  /** Set persona data do flow ativo */
  setActivePersona: (persona: { name: string; avatar: string; role: string } | null) => void
}

const ChatContext = createContext<ChatContextType | null>(null)

export function ChatProvider({ children }: { children: ReactNode }) {
  const [isOpen, setIsOpen] = useState(false)
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [currentAgentId, setCurrentAgentId] = useState<string | null>(null)
  const [pendingIntent, setPendingIntent] = useState<string | null>(null)
  const [viewMode, setViewMode] = useState<ViewMode>('site')
  const [activePersona, setActivePersona] = useState<{ name: string; avatar: string; role: string } | null>(null)
  const [searchParams] = useSearchParams()
  const location = useLocation()

  // Check for smart_id in URL params on mount
  useEffect(() => {
    const smartId = searchParams.get('smart_id') || searchParams.get('chat')

    if (smartId) {
      // smart_id na URL é intencional (link compartilhado) — abre o chat.
      setSessionId(smartId)
      setIsOpen(true)
      return
    }

    // Restaura sessionId persistido SEM abrir o chat — quando o usuário
    // clicar no toggle, a sessão antiga é retomada.
    const storedSession = localStorage.getItem('ai9_chat_session')
    if (storedSession) {
      setSessionId(storedSession)
    }

    // Padrão: chat inicia FECHADO. Vale tanto pra visitor quanto pra usuário
    // logado. A abertura é sempre por interação explícita (botão Agentic Mode
    // no sidebar, clique em plano com flow vinculado, ou ?smart_id=).
    // Antes havia um auto-open via sessionStorage('ai9_flow_session') que
    // fazia o chat abrir sozinho a cada reload — removido para garantir
    // que o visitor explore a dashboard antes de interagir com a IA.
  }, [searchParams])

  // Store the current path for agent routing purposes
  useEffect(() => {
    // Path changes might trigger agent switches via useAgentRouter
    // This effect is mainly for tracking - actual routing happens in the component
  }, [location.pathname])

  const openChat = useCallback((newSessionId?: string) => {
    if (newSessionId) {
      setSessionId(newSessionId)
      localStorage.setItem('ai9_chat_session', newSessionId)
    }
    setIsOpen(true)
    sessionStorage.removeItem('ai9_chat_closed') // Forgot they closed it if they open it manually
  }, [])

  const closeChat = useCallback(() => {
    setIsOpen(false)
    sessionStorage.setItem('ai9_chat_closed', 'true')
  }, [])

  const toggleChat = useCallback(() => {
    setIsOpen(prev => {
      const willBeOpen = !prev
      if (!willBeOpen) {
        sessionStorage.setItem('ai9_chat_closed', 'true')
      } else {
        sessionStorage.removeItem('ai9_chat_closed')
      }
      return willBeOpen
    })
  }, [])

  /**
   * Switch to a different agent/flow.
   * Used by CTAs to change the active AI agent and optionally send an intent.
   */
  const triggerFlow = useCallback((agentId: string, options?: TriggerFlowOptions) => {
    const { intent, resetSession = false } = options || {}

    // Set the new agent
    setCurrentAgentId(agentId)

    // If there's an intent, store it for the chat widget to process
    if (intent) {
      setPendingIntent(intent)
    }

    // If resetting session, clear the stored session
    if (resetSession) {
      setSessionId(null)
      localStorage.removeItem('ai9_chat_session')
    }

    // Ensure chat is open
    setIsOpen(true)
  }, [])

  const clearPendingIntent = useCallback(() => {
    setPendingIntent(null)
  }, [])

  const toggleViewMode = useCallback(() => {
    setViewMode(prev => prev === 'site' ? 'ai' : 'site')
  }, [])

  return (
    <ChatContext.Provider value={{
      isOpen,
      sessionId,
      currentAgentId,
      pendingIntent,
      viewMode,
      activePersona,
      openChat,
      closeChat,
      toggleChat,
      triggerFlow,
      clearPendingIntent,
      setCurrentAgentId,
      setViewMode,
      toggleViewMode,
      setActivePersona
    }}>
      {children}
    </ChatContext.Provider>
  )
}

export function useChat() {
  const context = useContext(ChatContext)
  if (!context) {
    throw new Error('useChat must be used within a ChatProvider')
  }
  return context
}
