/**
 * ChatCTA - Call-to-Action buttons that trigger AI agent interactions (Spec 4.2)
 *
 * These buttons replace traditional navigation CTAs with agent-triggering actions.
 * Instead of navigate('/contato'), they invoke chatActions.triggerFlow(AGENT_ID).
 *
 * Todos usam o `Button` canônico do Safegold. A cor vem da variante — nunca de
 * `className`; `className` aqui só carrega layout (largura, margem).
 *
 * @example
 * <ChatCTA.TriggerAgent
 *   agentId="sales-agent"
 *   intent="Ver apartamentos"
 *   className="w-full"
 * >
 *   Ver Apartamentos
 * </ChatCTA.TriggerAgent>
 */
import { ReactNode, ButtonHTMLAttributes } from 'react'
import { useChatActions } from '@/hooks/useChatActions'
import { Button } from '@/components/ui/Button'

interface BaseCTAProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode
  className?: string
}

interface TriggerAgentProps extends BaseCTAProps {
  /** The agent/flow ID to switch to */
  agentId: string
  /** Optional intent message (e.g., "User wants to see pricing") */
  intent?: string
  /** Whether to reset the session when switching */
  resetSession?: boolean
}

interface SendIntentProps extends BaseCTAProps {
  /** The intent message to send to the current agent */
  intent: string
}

/**
 * Button that triggers a specific agent with optional intent
 */
function TriggerAgent({
  children,
  agentId,
  intent,
  resetSession,
  className,
  ...props
}: TriggerAgentProps) {
  const { triggerAgent } = useChatActions()

  const handleClick = () => {
    triggerAgent(agentId, { intent, resetSession })
  }

  return (
    <Button variant="primary" onClick={handleClick} className={className} {...props}>
      {children}
    </Button>
  )
}

/**
 * Button that sends an intent to the current agent without switching
 */
function SendIntent({
  children,
  intent,
  className,
  ...props
}: SendIntentProps) {
  const { sendIntent } = useChatActions()

  const handleClick = () => {
    sendIntent(intent)
  }

  return (
    <Button variant="secondary" onClick={handleClick} className={className} {...props}>
      {children}
    </Button>
  )
}

/**
 * Pre-built CTA for contacting sales
 */
function ContactSales({
  children = 'Falar com Vendedor',
  intent,
  className,
  ...props
}: Omit<TriggerAgentProps, 'agentId'>) {
  const { actions } = useChatActions()

  return (
    <Button
      variant="primary"
      onClick={() => actions.contactSales(intent)}
      className={className}
      {...props}
    >
      {children}
    </Button>
  )
}

/**
 * Pre-built CTA for viewing pricing
 */
function ViewPricing({
  children = 'Ver Preços',
  intent,
  className,
  ...props
}: Omit<TriggerAgentProps, 'agentId'>) {
  const { actions } = useChatActions()

  return (
    <Button
      variant="secondary"
      onClick={() => actions.viewPricing(intent)}
      className={className}
      {...props}
    >
      {children}
    </Button>
  )
}

/**
 * Pre-built CTA for getting support
 */
function GetSupport({
  children = 'Preciso de Ajuda',
  intent,
  className,
  ...props
}: Omit<TriggerAgentProps, 'agentId'>) {
  const { actions } = useChatActions()

  return (
    <Button
      variant="secondary"
      onClick={() => actions.getSupport(intent)}
      className={className}
      {...props}
    >
      {children}
    </Button>
  )
}

export const ChatCTA = {
  TriggerAgent,
  SendIntent,
  ContactSales,
  ViewPricing,
  GetSupport
}

export default ChatCTA
