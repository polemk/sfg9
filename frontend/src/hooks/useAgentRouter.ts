import { useEffect, useState } from 'react'
import { useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { useChat } from '@/contexts/ChatContext'
import { chatFlowsApi } from '@/lib/api/endpoints'

interface AgentMatch {
    id: number
    name: string
    persona_name?: string
    persona_avatar?: string
    [key: string]: any
}

/**
 * Hook que monitora a rota atual e o tipo de usuário para trocar
 * o agente de IA ativo de forma contextual.
 *
 * Quando chamado com (activeFlowId), retorna matchingAgent e shouldOverride.
 * Bloco 7 do trim (AI9-014): o parâmetro `hasOperation` saiu com o `Operation` —
 * um agente vinculado a uma operação não podia ser sobreposto pelo roteador.
 * para o AIChatWidget decidir se faz handoff.
 */
export function useAgentRouter(activeFlowId?: number | null) {
    const location = useLocation()
    const { user, isAuthenticated } = useAuthStore()
    const { setCurrentAgentId, currentAgentId } = useChat()
    const [matchingAgent, setMatchingAgent] = useState<AgentMatch | null>(null)
    const [shouldOverride, setShouldOverride] = useState(false)

    useEffect(() => {
        const updateContextualAgent = async () => {
            const typeSlug = user?.user_type_slug || 'visitor'
            const path = location.pathname

            try {
                const response = await chatFlowsApi.getFlowByContext(typeSlug, path)

                if (response && response.id !== currentAgentId) {
                    console.log(`[AgentRouter] Switching to contextual agent: ${response.name} for path ${path}`)

                    // Se chamado sem args (App-level), aplica direto
                    if (activeFlowId === undefined) {
                        setCurrentAgentId(response.id)
                    }

                    setMatchingAgent(response as AgentMatch)
                    // shouldOverride: quando o agente atual é diferente e não há operação em andamento
                    setShouldOverride(response.id !== activeFlowId)
                } else {
                    setMatchingAgent(null)
                    setShouldOverride(false)
                }
            } catch (error) {
                console.error('[AgentRouter] Failed to fetch contextual agent:', error)
                setMatchingAgent(null)
                setShouldOverride(false)
            }
        }

        updateContextualAgent()
    }, [location.pathname, user?.user_type_slug, isAuthenticated, activeFlowId])

    return { matchingAgent, shouldOverride }
}
