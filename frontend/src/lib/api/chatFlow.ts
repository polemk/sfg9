import { apiClient } from './client'

export interface FlowNodePayload {
    id: string
    type: 'text' | 'input' | 'end' | 'redirect' | 'image'
    content: string
    contentType?: 'text' | 'image'
    inputType?: 'text' | 'email' | 'phone'
    variable?: string
    options?: string[]
    action?: 'navigate' | 'scroll_to' | 'auth'
    url?: string
    target?: string
    auth?: {
        token: string
        refresh_token?: string
        user_name?: string
        user_email?: string
    }
}

export interface ChatSessionResponse {
    session_id: string
    first_message?: boolean
    responses: FlowNodePayload[]
    persona_name?: string
    persona_description?: string
    persona_avatar?: string
}

export interface ChatInputRequest {
    session_id: string
    input: string
}

export type FlowKind = 'chatbot' | 'ai_agent';

export interface FlowSummary {
    id: string
    name: string
    kind: FlowKind
    is_default: boolean
    keywords: string[]
}

// Bloco 8 do trim (AI9-007, DEC-13.2): as chamadas abaixo deixaram de usar
// `getPublic`/`postPublic`/`postPublicForm`.
//
// Aqueles helpers mandam `X-Skip-Auth: 1`, que faz o interceptor NAO anexar o
// access token e NAO tentar refresh no 401. Era herança do chat público de
// captação (AI9-006, removido no Bloco 6). O assistente agora é do usuário
// INTERNO e `/chat/*` saiu da allowlist pública do `Api::Root`: sem token o
// backend responde 401, e sem refresh automático a conversa morria no primeiro
// access expirado.
export const chatFlowApi = {
    // List all available flows
    getFlows: async (): Promise<FlowSummary[]> => {
        return apiClient.get<FlowSummary[]>('/api/v1/flows')
    },

    // Start or retrieve a session (uses default flow or keyword match)
    getSession: async (flowId?: string, metadata?: any): Promise<ChatSessionResponse> => {
        const params = new URLSearchParams()
        if (flowId) params.set('flow_id', flowId)
        if (metadata) params.set('metadata', JSON.stringify(metadata))
        return apiClient.get<ChatSessionResponse>(`/chat/session?${params.toString()}`)
    },

    // Start session with specific flow (for testing in builder)
    getSessionWithFlow: async (flowId: string, metadata?: any): Promise<ChatSessionResponse> => {
        const params = new URLSearchParams()
        params.set('flow_id', flowId)
        params.set('is_test', 'true')
        if (metadata) params.set('metadata', JSON.stringify(metadata))
        return apiClient.get<ChatSessionResponse>(`/chat/session?${params.toString()}`)
    },

    // Send input and get next nodes
    sendInput: async (sessionId: string, input: string, originNodeId?: string, context?: any): Promise<{
        responses: FlowNodePayload[]
        persona_name?: string
        persona_description?: string
        persona_avatar?: string
    }> => {
        const res = await apiClient.post<{
            session_id: string;
            responses: FlowNodePayload[];
            persona_name?: string;
            persona_description?: string;
            persona_avatar?: string;
        }>('/chat/input', {
            session_id: sessionId,
            input,
            origin_node_id: originNodeId,
            context,
        })

        return {
            responses: res.responses,
            persona_name: res.persona_name,
            persona_description: res.persona_description,
            persona_avatar: res.persona_avatar
        }
    },

    /** Upload an image to the AI agent for Vision processing.
     * @param sessionId - active chat session ID
     * @param file - image File (JPEG, PNG, or WebP, max 5MB)
     * @param caption - optional text description
     */
    sendImageInput: async (sessionId: string, file: File, caption?: string, context?: any): Promise<{
        responses: FlowNodePayload[]
        persona_name?: string
        persona_description?: string
        persona_avatar?: string
    }> => {
        const formData = new FormData()
        formData.append('session_id', sessionId)
        formData.append('file', file)
        if (caption) formData.append('caption', caption)
        if (context) formData.append('context', JSON.stringify(context))

        const res = await apiClient.post<{
            session_id: string;
            responses: FlowNodePayload[];
            persona_name?: string;
            persona_description?: string;
            persona_avatar?: string;
        }>('/chat/upload', formData)

        return {
            responses: res.responses,
            persona_name: res.persona_name,
            persona_description: res.persona_description,
            persona_avatar: res.persona_avatar
        }
    }
}

