/**
 * useChatActions - Helper hook for CTA interactions (Spec 4.2)
 *
 * Provides easy-to-use functions for site CTAs to trigger agent flows
 * and send contextual intents to the AI chat widget.
 */
import { useCallback } from 'react'
import { useChat } from '@/contexts/ChatContext'

interface CTAOptions {
  /** The intent message to send (e.g., "User clicked on Pricing") */
  intent?: string
  /** Whether to reset the chat session when switching */
  resetSession?: boolean
}

export function useChatActions() {
  const { triggerFlow, openChat, currentAgentId } = useChat()

  /**
   * Trigger a specific agent with an optional intent.
   * Use this when a CTA should switch to a specific agent.
   *
   * @example
   * const { triggerAgent } = useChatActions()
   * <button onClick={() => triggerAgent('sales-agent-id', { intent: 'Ver preços' })}>
   *   Ver Preços
   * </button>
   */
  const triggerAgent = useCallback((agentId: string, options?: CTAOptions) => {
    triggerFlow(agentId, {
      intent: options?.intent,
      resetSession: options?.resetSession
    })
  }, [triggerFlow])

  /**
   * Send an intent to the current agent without switching.
   * Use this when a CTA should provide context to the active agent.
   *
   * @example
   * const { sendIntent } = useChatActions()
   * <button onClick={() => sendIntent('Usuário clicou em Saiba Mais')}>
   *   Saiba Mais
   * </button>
   */
  const sendIntent = useCallback((intent: string) => {
    if (currentAgentId) {
      triggerFlow(currentAgentId, { intent })
    } else {
      // No agent active, just open chat with intent
      openChat()
      // Intent will be picked up by the chat widget
    }
  }, [currentAgentId, triggerFlow, openChat])

  /**
   * Create a CTA handler for a specific agent and intent.
   * Useful for generating click handlers in loops.
   *
   * @example
   * const { createCTAHandler } = useChatActions()
   * const handlePricingClick = createCTAHandler('pricing-agent', 'Ver planos')
   */
  const createCTAHandler = useCallback((agentId: string, intent?: string) => {
    return () => triggerAgent(agentId, { intent })
  }, [triggerAgent])

  /**
   * Predefined CTA actions for common use cases.
   */
  const actions = {
    /** Contact sales agent */
    contactSales: (intent?: string) => triggerAgent('sales', { intent: intent || 'Contato comercial' }),

    /** View pricing/plans */
    viewPricing: (intent?: string) => triggerAgent('pricing', { intent: intent || 'Ver preços' }),

    /** Get support */
    getSupport: (intent?: string) => triggerAgent('support', { intent: intent || 'Preciso de ajuda' }),

    /** General inquiry */
    generalInquiry: (intent?: string) => {
      openChat()
      if (intent && currentAgentId) {
        triggerFlow(currentAgentId, { intent })
      }
    }
  }

  return {
    triggerAgent,
    sendIntent,
    createCTAHandler,
    actions
  }
}

export default useChatActions
