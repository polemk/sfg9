/**
 * MobileChatBar - Barra minimizada do chat mobile
 *
 * FIXA no bottom com tratativas iOS:
 * - position: fixed + safe-area-inset-bottom
 * - -webkit-fill-available fallback
 * - touch-action: manipulation (evita zoom duplo-tap)
 * - will-change: transform (GPU layer dedicado)
 *
 * Usa DataSphere (esfera de partículas) como indicador visual.
 * Dados do agente/flow ativo via props do PublicSplitLayout.
 * Tracking de eventos em localStorage.
 */
import { useMemo, useEffect, useRef } from 'react'
import { ChevronUp } from 'lucide-react'
import { useChat } from '@/contexts/ChatContext'
import { Button } from '@/components/ui/Button'
import { useLocation } from 'react-router-dom'
import { trackChatBarEvent } from '@/lib/chatBarTracker'
import { DataSphere } from '@/components/chat/DataSphere'

interface MobileChatBarProps {
  /** Avatar URL do agente/flow ativo */
  avatarUrl?: string
  /** Nome do agente/flow para acessibilidade */
  agentName?: string
  /** Nome da persona do flow ativo (exibido na barra) */
  personaName?: string
  /** Callback quando a barra é tocada para expandir */
  onExpand?: () => void
}

/**
 * Textos contextuais por rota — exibidos quando não há mensagens.
 * Incentivam o visitor a clicar e iniciar conversa.
 */
const ROUTE_HINTS: Record<string, string> = {
  '/dashboard': 'Esse é o painel principal do seu projeto 👋',
}
const DEFAULT_HINT = 'Toque para falar com o assistente'

/**
 * Lê a última mensagem do agente do sessionStorage.
 * Retorna o conteúdo truncado em ~50 chars ou null.
 */
function getLastAgentPreview(): string | null {
  try {
    const raw = sessionStorage.getItem('ai9_flow_messages')
    if (!raw) return null
    const msgs = JSON.parse(raw) as Array<{ role: string; content: string }>
    // Filtra apenas mensagens do agente e pega a última
    const agentMsgs = msgs.filter(m => m.role === 'agent' && m.content)
    if (agentMsgs.length === 0) return null
    const last = agentMsgs[agentMsgs.length - 1].content
    // Trunca em 50 chars com "..."
    return last.length > 50 ? last.substring(0, 50) + '...' : last
  } catch {
    return null
  }
}

export function MobileChatBar({
  avatarUrl,
  agentName = 'Assistente',
  personaName,
  onExpand
}: MobileChatBarProps) {
  const { setViewMode } = useChat()
  const location = useLocation()
  const hasTrackedImpression = useRef(false)

  // Preview da última mensagem ou texto contextual por rota
  const hintText = useMemo(() => {
    const preview = getLastAgentPreview()
    if (preview) return preview
    return ROUTE_HINTS[location.pathname] || DEFAULT_HINT
  }, [location.pathname])

  // Nome exibido — usa persona do flow se disponível
  const displayName = personaName || agentName

  // Tracking: registra impression 1x por sessão de montagem
  useEffect(() => {
    if (!hasTrackedImpression.current) {
      hasTrackedImpression.current = true
      trackChatBarEvent('impression', location.pathname, {
        persona: displayName,
        preview: hintText
      })
    }
  }, [])

  // Tracking: registra mudança de rota (re-impressões)
  useEffect(() => {
    trackChatBarEvent('impression', location.pathname, {
      persona: displayName,
      preview: hintText,
      routeChange: true
    })
  }, [location.pathname])

  const handleExpand = () => {
    // Tracking: registra clique de expandir
    trackChatBarEvent('expand_click', location.pathname, {
      persona: displayName,
      preview: hintText
    })
    setViewMode('ai')
    onExpand?.()
  }

  // A esfera levava ao checkout do plano selecionado (AI9-002, removido no
  // Bloco 4). Sem planos, ela só abre o assistente.
  const handleSphere = (e: React.MouseEvent | React.TouchEvent) => {
    e.stopPropagation()
    trackChatBarEvent('sphere_click', location.pathname, {
      persona: displayName
    })
    setViewMode('ai')
    onExpand?.()
  }

  return (
    <div
      className="
        w-full
        bg-background/80 backdrop-blur-2xl
        border-t border-border/40
        shadow-e3
      "
      style={{
        // iOS safe-area: padding no bottom para home indicator
        paddingBottom: 'max(env(safe-area-inset-bottom, 0px), 8px)',
        // Evita zoom duplo-tap no iOS
        touchAction: 'manipulation',
      }}
    >
      {/* Fio de destaque no topo — sólido, sem glow neon */}
      <div className="absolute top-0 left-0 right-0 h-px bg-primary/40" />

      {/* Conteúdo da barra — altura fixa 56px */}
      <div className="w-full h-14 flex items-center gap-2 px-3">
        {/* Área principal — tap expande chat */}
        <button
          type="button"
          onClick={handleExpand}
          className="
            flex-1 h-full
            flex items-center gap-3
            active:bg-muted/50
            transition-colors
            min-w-0
            focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring
          "
          style={{ touchAction: 'manipulation' }}
          aria-label={`Abrir chat com ${displayName}`}
        >
          {/* Avatar do agente com micro-pulse de atenção */}
          <div className="relative shrink-0 animate-[chatbar-pulse_8s_ease-in-out_infinite]">
            {avatarUrl ? (
              <div className="h-9 w-9 rounded-full overflow-hidden border-2 border-primary/20 shadow-e2 bg-muted">
                <img
                  src={avatarUrl}
                  alt={displayName}
                  className="h-full w-full object-cover"
                  loading="eager"
                />
              </div>
            ) : (
              /* Fallback genérico quando não há avatar do agente */
              <div className="h-9 w-9 rounded-full bg-primary/20 border-2 border-primary/20 flex items-center justify-center">
                <span className="text-primary text-xs font-bold">
                  {displayName.charAt(0).toUpperCase()}
                </span>
              </div>
            )}
            {/* Status online indicator */}
            <div className="absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full bg-success border-2 border-card" />
          </div>

          {/* Preview de mensagem ou hint contextual */}
          <div className="flex-1 min-w-0">
            <div className="
              text-foreground/90
              text-sm
              px-4 py-2
              rounded-lg
              bg-secondary/30
              border border-border
              truncate
              shadow-e1
            ">
              {hintText}
            </div>
          </div>
        </button>

        {/* DataSphere — esfera de partículas como call-to-action visual */}
        <div
          onClick={handleSphere}
          className="shrink-0 cursor-pointer"
          style={{ touchAction: 'manipulation' }}
          aria-label="Interagir com assistente"
          role="button"
          tabIndex={0}
        >
          <DataSphere
            className="h-10 w-10"
            particleColor="hsl(var(--primary))"
          />
        </div>

        {/* Expand chevron */}
        <Button
          variant="ghost"
          size="icon"
          onClick={handleExpand}
          className="shrink-0 h-8 w-8"
          style={{ touchAction: 'manipulation' }}
          aria-label="Expandir chat"
        >
          <ChevronUp className="h-5 w-5" />
        </Button>
      </div>

      {/* CSS do micro-pulse animation — keyframes inline */}
      <style>{`
        @keyframes chatbar-pulse {
          0%, 85%, 100% { transform: scale(1); }
          90% { transform: scale(1.12); }
          93% { transform: scale(0.97); }
          96% { transform: scale(1.05); }
        }
      `}</style>
    </div>
  )
}

export default MobileChatBar
