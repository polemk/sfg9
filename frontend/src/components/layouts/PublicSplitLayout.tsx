/**
 * PublicSplitLayout - Responsive Layout (Spec 4.2 & 4.3)
 *
 * Breakpoints:
 * - Desktop (>= 1024px): Split layout - site left, chat anchored right
 * - Mobile (< 1024px): Full height layout with:
 *   - Site Mode: Content scrollable, chat minimized to bottom bar (56px)
 *   - AI Mode: Chat fullscreen overlay with slide-up animation
 *
 * Mobile Behavior:
 * - Scroll down > 50px delta: Auto-minimize chat (Site Mode)
 * - Click chat bar / toggle: Expand chat (AI Mode)
 * - Uses CSS visibility (not unmounting) to preserve socket connection
 *
 * iOS Safari Fix:
 * - Uses 100dvh + -webkit-fill-available for proper viewport height
 * - Includes safe-area padding for notch/home indicator
 */
import { ReactNode, useState, useEffect, useRef, useCallback, useMemo } from 'react'
import { AIChatWidget } from '@/components/chat/AIChatWidget'
import { MobileChatBar } from '@/components/chat/MobileChatBar'
import { useChat } from '@/contexts/ChatContext'
import { useAgentRouter } from '@/hooks/useAgentRouter'
import { useQuery } from '@tanstack/react-query'
import { publicChatApi } from '@/lib/api/publicChat'

type DeviceType = 'mobile' | 'desktop'

interface PublicSplitLayoutProps {
  children: ReactNode
  /** Whether to show the chat panel on desktop (default: true) */
  showChat?: boolean
  /** Custom class for the content area */
  contentClassName?: string
}

export function PublicSplitLayout({
  children,
  showChat = true,
  contentClassName = ''
}: PublicSplitLayoutProps) {
  const {
    sessionId,
    currentAgentId,
    viewMode,
    setViewMode,
    openChat,
    closeChat,
    activePersona
  } = useChat()

  const [device, setDevice] = useState<DeviceType>('desktop')
  const [isXL, setIsXL] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)
  const lastScrollY = useRef(0)

  // Track screen size for responsive behavior
  useEffect(() => {
    const checkDevice = () => {
      const width = window.innerWidth
      // Use 1024px as the breakpoint (lg in Tailwind)
      setDevice(width >= 1024 ? 'desktop' : 'mobile')
      setIsXL(width >= 1280)
    }
    checkDevice()
    window.addEventListener('resize', checkDevice)
    return () => window.removeEventListener('resize', checkDevice)
  }, [])

  // Agent routing - get matching agent for current route
  const { matchingAgent, shouldOverride } = useAgentRouter(currentAgentId ? Number(currentAgentId) : undefined)

  // Busca dados do agent ativo pelo ID (independente de route matching)
  // Usa a mesma query cacheada do useAgentRouter para não duplicar requests
  const { data: allAgents = [] } = useQuery({
    queryKey: ['agent-route-mappings'],
    queryFn: () => publicChatApi.getRouting(),
    staleTime: 1000 * 60 * 5,
  })

  // Resolve o agent ativo: prioridade busca por ID > matchingAgent
  const activeAgent = useMemo(() => {
    if (currentAgentId && allAgents.length) {
      return allAgents.find((a: any) => a.id === Number(currentAgentId) || a.id === currentAgentId) || null
    }
    return matchingAgent
  }, [currentAgentId, allAgents, matchingAgent])

  const isDesktop = device === 'desktop'
  const isMobile = device === 'mobile'

  // Responsive margin based on screen size
  const sideMargin = isXL ? '10vw' : '5vw'

  // Handle scroll to auto-minimize chat on mobile
  const handleScroll = useCallback((e: React.UIEvent<HTMLDivElement>) => {
    if (!isMobile) return

    const currentScrollY = (e.target as HTMLDivElement).scrollTop
    const delta = currentScrollY - lastScrollY.current

    // If scrolling down more than 50px while in AI mode, minimize chat
    if (delta > 50 && viewMode === 'ai') {
      setViewMode('site')
    }

    lastScrollY.current = currentScrollY

    // Dispatch custom event for other components
    window.dispatchEvent(new CustomEvent('container-scroll', {
      detail: { scrollY: currentScrollY }
    }))
  }, [isMobile, viewMode, setViewMode])

  // Handle chat bar expand
  const handleExpandChat = useCallback(() => {
    setViewMode('ai')
    openChat()
  }, [setViewMode, openChat])

  // Handle close fullscreen chat
  const handleCloseChat = useCallback(() => {
    setViewMode('site')
    closeChat()
  }, [setViewMode, closeChat])

  // 5C: Body scroll lock — só quando chat fullscreen está visível
  useEffect(() => {
    if (!isMobile || viewMode !== 'ai') return
    const html = document.documentElement
    const body = document.body
    html.style.overflow = 'hidden'
    body.style.overflow = 'hidden'
    return () => {
      html.style.overflow = ''
      body.style.overflow = ''
    }
  }, [isMobile, viewMode])

  // For desktop, use flex layout. For mobile, use simple block layout for iOS compatibility
  if (isDesktop) {
    return (
      <div
        className="
          w-full overflow-y-auto overflow-x-hidden flex flex-row
          h-[100dvh]
        "
        onScroll={(e) => {
          const scrollY = (e.target as HTMLElement).scrollTop
          window.dispatchEvent(new CustomEvent('container-scroll', { detail: { scrollY } }))
        }}
      >
        {/* Site Content */}
        <div
          ref={scrollRef}
          className={`
            min-h-full min-w-0
            ${showChat ? 'flex-1' : 'w-full'}
            ${contentClassName}
          `}
          style={showChat ? { marginRight: isXL ? '-3vw' : '-2vw' } : undefined}
        >
          {children}
        </div>

        {/* Desktop: Anchored Chat Sidebar */}
        {showChat && (
          <aside
            className="flex flex-col justify-start shrink-0 sticky top-0 h-[100dvh] z-sticky"
            style={{
              width: isXL ? '21vw' : '24vw',
              minWidth: '320px',
              maxWidth: '400px',
              paddingTop: 'calc(var(--topbar-h, 64px) + 0.6vw)',
            }}
          >
            <AIChatWidget
              isOpen={true}
              onClose={() => { }}
              sessionId={sessionId || undefined}
              flowId={currentAgentId || undefined}
              mode="flow"
              embedded={false}
              className="h-full max-h-[calc(100dvh-var(--topbar-h,64px)-1vw)]"
              anchored
            />
          </aside>
        )}
      </div>
    )
  }

  // Mobile Layout - Simpler structure for iOS Safari compatibility
  return (
    <>
      {/* Site Content - Full page scroll, no overflow tricks */}
      <div
        ref={scrollRef}
        className={`
          min-h-[100dvh] w-full overflow-x-hidden
          ${contentClassName}
        `}
        style={{
          // iOS Safari smooth scrolling
          WebkitOverflowScrolling: 'touch'
        }}
        onScroll={handleScroll}
      >
        {children}
      </div>

      {/* Mobile Chat Bar (Minimized) - FIXO no viewport bottom */}
      {/* IMPORTANTE: NÃO usar transition-all nem translate aqui!
          transition-all aplica transform implícito que cria novo containing block,
          quebrando position:fixed dos filhos (CSS spec). */}
      <div
        className={`
          fixed bottom-0 left-0 right-0 z-fab
          transition-[opacity,visibility] duration-300 ease-out
          ${viewMode === 'site'
            ? 'opacity-100 visible'
            : 'opacity-0 invisible pointer-events-none'
          }
        `}
      >
        <MobileChatBar
          avatarUrl={activePersona?.avatar || activeAgent?.persona_avatar}
          agentName={activePersona?.name || activeAgent?.name || 'Assistente'}
          personaName={activePersona?.name || activeAgent?.persona_name}
          onExpand={handleExpandChat}
        />
      </div>

      {/* Mobile Fullscreen Chat - Shows in AI Mode */}
      {/* IMPORTANTE: NÃO usar transition-all aqui!
          transition-all aplica transform implícito que cria novo containing block,
          invalidando position:fixed dos filhos (AIChatWidget).
          Resultado: topbar some, width fica maior que tela após fechar teclado iOS. */}
      <div
        className={`
          fixed inset-0 z-drawer
          bg-background
          overflow-hidden
          transition-[opacity,visibility] duration-200 ease-out
          ${viewMode === 'ai'
            ? 'opacity-100 visible'
            : 'opacity-0 invisible pointer-events-none'
          }
        `}
        style={{
          // Garante que o container nunca exceda o viewport
          width: '100vw',
          maxWidth: '100%',
        }}
      >
        <AIChatWidget
          isOpen={true}
          onClose={handleCloseChat}
          sessionId={sessionId || undefined}
          flowId={matchingAgent?.id ? String(matchingAgent.id) : (currentAgentId || undefined)}
          mode="flow"
          fullscreen
        />
      </div>
    </>
  )
}

export default PublicSplitLayout
