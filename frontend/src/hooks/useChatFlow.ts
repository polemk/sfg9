import { useState, useCallback, useEffect, useRef } from 'react'
import { chatFlowApi, FlowNodePayload, FlowSummary } from '@/lib/api/chatFlow'
import { nanoid } from 'nanoid'
import { useAudioPlayerStore } from '@/store/audioPlayerStore'
import { useAuthStore } from '@/store/authStore'

export interface ChatMessage {
    id: string
    role: 'user' | 'agent'
    content: string
    timestamp: Date
    type?: 'text' | 'input' | 'image'
    options?: string[]
    blocks?: any[]
    delay?: number
    imageUrl?: string
    data?: any
    persona_name?: string
    persona_avatar?: string
    persona_description?: string
    origin_node_id?: string
}

export interface ExecutionLog {
    id: string
    timestamp: Date
    type: 'info' | 'flow' | 'error' | 'system' | 'engine' | 'bridge'
    message: string
    data?: any
}

/** Storage keys for session persistence across page reloads */
const STORAGE_KEY_SESSION = 'ai9_flow_session'
const STORAGE_KEY_MESSAGES = 'ai9_flow_messages'
const STORAGE_KEY_PERSONA = 'ai9_flow_persona'

/** Safely read from sessionStorage */
function readSession<T>(key: string, fallback: T): T {
    try {
        const raw = sessionStorage.getItem(key)
        return raw ? JSON.parse(raw) : fallback
    } catch { return fallback }
}

export function useChatFlow(initialSessionId?: string | null, initialFlowId?: string | null) {
    // Restore session state from sessionStorage
    const storedSessionId = readSession<string | null>(STORAGE_KEY_SESSION, null)

    // We only restore state if there's a stored session and it either matches the initial one or there isn't an initial one
    const shouldRestore = storedSessionId && (!initialSessionId || initialSessionId === storedSessionId)

    const restoredSessionId = shouldRestore ? storedSessionId : (initialSessionId || null)
    const restoredMessages = shouldRestore ? readSession<ChatMessage[]>(STORAGE_KEY_MESSAGES, []) : []
    const restoredPersona = shouldRestore ? readSession<{ name: string, description?: string, avatar: string } | null>(STORAGE_KEY_PERSONA, null) : null

    const [sessionId, setSessionId] = useState<string | null>(restoredSessionId)
    const [messages, setMessages] = useState<ChatMessage[]>(restoredMessages)
    const [logs, setLogs] = useState<ExecutionLog[]>([])
    const [isTyping, setIsTyping] = useState(false)
    const [currentNode, setCurrentNode] = useState<FlowNodePayload | null>(null)
    const [currentFlowId, setCurrentFlowId] = useState<string | null>(initialFlowId || null)
    const [persona, setPersona] = useState<{ name: string, description?: string, avatar: string } | null>(restoredPersona)
    const initCounterRef = useRef(0)

    const addLog = useCallback((type: ExecutionLog['type'], message: string, data?: any) => {
        const newLog: ExecutionLog = {
            id: nanoid(),
            timestamp: new Date(),
            type,
            message,
            data
        }
        setLogs(prev => [...prev, newLog])
    }, [])

    // Persist session state to sessionStorage whenever it changes
    useEffect(() => {
        if (sessionId) {
            sessionStorage.setItem(STORAGE_KEY_SESSION, JSON.stringify(sessionId))
        } else {
            sessionStorage.removeItem(STORAGE_KEY_SESSION)
        }
    }, [sessionId])

    useEffect(() => {
        if (messages.length > 0) {
            sessionStorage.setItem(STORAGE_KEY_MESSAGES, JSON.stringify(messages))
        }
    }, [messages])

    useEffect(() => {
        if (persona) {
            sessionStorage.setItem(STORAGE_KEY_PERSONA, JSON.stringify(persona))
        }
    }, [persona])

    const [prevInitialFlowId, setPrevInitialFlowId] = useState<string | null | undefined>(initialFlowId)

    if (initialFlowId !== prevInitialFlowId) {
        setPrevInitialFlowId(initialFlowId)
        if (initialFlowId) {
            setMessages([])
            setSessionId(null)
            setCurrentFlowId(initialFlowId)
        }
    }

    // Execute node actions (scroll_to, navigate, etc.) directly
    const executeNodeAction = useCallback((node: FlowNodePayload) => {
        const nodeData = node as any

        // Process Auth (Auto-Login) FIRST if present in any action (like navigate with auto_auth)
        if (nodeData.auth) {
            try {
                useAuthStore.getState().setAuth(nodeData.auth.token,
                    {
                        id: 'visitor-' + Date.now(),
                        name: nodeData.auth.user_name,
                        email: nodeData.auth.user_email,
                        user_type: 'visitor'
                    } as any
                )

                window.dispatchEvent(new Event('auth-change'))
                addLog('system', 'Login automático realizado')

                // Se for action auth puramente e tiver url, navega também (retrocompatibilidade)
                if (nodeData.action === 'auth' && nodeData.url) {
                    if (nodeData.target === '_blank') {
                        window.open(nodeData.url, '_blank')
                    } else {
                        window.location.href = nodeData.url
                    }
                }
            } catch (e) {
                addLog('error', 'Falha no auto-login')
            }
        }

        // Action: Navigate
        if (nodeData.action === 'navigate' && nodeData.url) {
            addLog('system', `Navegando para: ${nodeData.url}`)
            if (nodeData.target === '_blank') {
                window.open(nodeData.url, '_blank')
            } else {
                window.location.href = nodeData.url
            }
        }

        // Action: Scroll To
        if (nodeData.action === 'scroll_to' && nodeData.target) {
            addLog('system', `Rolando para: ${nodeData.target}`)
            const element = document.querySelector(nodeData.target)
            if (element) {
                element.scrollIntoView({ behavior: 'smooth', block: 'start' })
            } else {
                addLog('error', `Elemento não encontrado: ${nodeData.target}`)
            }
        }

        // Action: Play Audio
        if (nodeData.action === 'play_audio' && nodeData.url) {
            addLog('system', `Iniciando áudio: ${nodeData.song_name || 'Música'}`)
            useAudioPlayerStore.getState().activatePlayer(nodeData.url, nodeData.song_name || 'Música')
        }
    }, [addLog])

    // Internal helper to process multiple responses sequentially
    const processResponses = useCallback(async (responseData: FlowNodePayload[], personaData?: { name: string, avatar: string, description?: string }) => {
        if (!responseData || responseData.length === 0) return

        setIsTyping(true)

        for (let i = 0; i < responseData.length; i++) {
            const node = responseData[i]

            // If it's the last message and it's a 'end' type without content, skip it or handle differently
            if (node.type === 'end' && !node.content) continue

            // Execute actions immediately for redirect nodes
            if (node.type === 'redirect') {
                executeNodeAction(node)
                // If redirect has no content to show, continue to next node
                if (!node.content) continue
            }

            const botMsg: ChatMessage = {
                id: `bot-${node.id}-${i}`,
                role: 'agent',
                content: node.content,
                timestamp: new Date(),
                type: node.type as any,
                options: node.options,
                blocks: (node as any).blocks,
                origin_node_id: node.id
            }

            addLog('flow', `Executando Nó: [${(node.content || '').substring(0, 10)}...] (${node.type})`, { node })

            // Add the message
            setMessages(prev => {
                // Prevent duplicate: same ID or same content as the very last message
                if (prev.some(m => m.id === botMsg.id)) return prev
                const last = prev[prev.length - 1]
                if (last && last.role === 'agent' && last.content === botMsg.content && i === 0) return prev
                return [...prev, botMsg]
            })

            setCurrentNode(node)

            // Simulate typing delay for natural flow (except for the last one if it's an input)
            if (i < responseData.length - 1) {
                const delay = node.content ? Math.min(node.content.length * 10, 1500) : 500
                await new Promise(resolve => setTimeout(resolve, delay))
            }
        }

        if (personaData) {
            setPersona(personaData)
        }

        setIsTyping(false)
    }, [addLog, executeNodeAction])

    // Initialize session (uses default flow unless initialFlowId is provided)
    // Bloco 6 do trim (AI9-006): o "resume" da conversa era pelo LEAD persistido
    // no localStorage (`ai9_chat_lead` / `ai9_lead_id`). Sem lead não há chave de
    // retomada — reatar a sessão ao USUÁRIO autenticado do console é do Bloco 8.
    const initSession = useCallback(async () => {
        // Bump counter so any previous in-flight init becomes stale
        const myInit = ++initCounterRef.current

        try {
            setIsTyping(true)
            addLog('bridge', 'Iniciando canal de comunicação...')

            // Metadata for personalization
            const metadata = {
                current_page: window.location.pathname,
                referrer: document.referrer,
                smart_id: localStorage.getItem('smart_id'),
                user_name: localStorage.getItem('user_name') || undefined
            }

            const res = await chatFlowApi.getSession(currentFlowId || undefined, metadata)

            // If a newer init was triggered while we waited, discard this result
            if (initCounterRef.current !== myInit) return

            // If the backend created a new session due to flow mismatch, clear old messages
            setSessionId(prev => {
                if (prev && prev !== res.session_id) {
                    setMessages([])
                    setPersona(null)
                    setLogs([])
                }
                return res.session_id
            })

            addLog('engine', `Sessão [${res.session_id}] ativa.`, { sessionId: res.session_id })

            await processResponses(res.responses, res.persona_name && res.persona_avatar ? { name: res.persona_name, avatar: res.persona_avatar, description: res.persona_description } : undefined)

            localStorage.setItem('ai9_chat_session', res.session_id)
            if (currentFlowId) localStorage.setItem('ai9_chat_flow', currentFlowId)
        } catch (err) {
            if (initCounterRef.current !== myInit) return
            console.error('Failed to init flow session', err)
            setIsTyping(false)
        }
    }, [currentFlowId, processResponses, addLog])

    const resetSession = useCallback(async () => {
        setMessages([])
        setLogs([]) // Clear logs
        setSessionId(null)
        setCurrentNode(null)
        localStorage.removeItem('ai9_chat_session')
        sessionStorage.removeItem(STORAGE_KEY_SESSION)
        sessionStorage.removeItem(STORAGE_KEY_MESSAGES)
        sessionStorage.removeItem(STORAGE_KEY_PERSONA)
        addLog('system', 'Sessão resetada pelo usuário.')
        await initSession()
    }, [initSession, addLog])

    // Switch to a specific flow (for testing) - resets conversation
    const switchFlow = useCallback(async (flowId: string) => {
        try {
            setIsTyping(true)
            setMessages([]) // Clear previous messages
            setCurrentFlowId(flowId)

            const res = await chatFlowApi.getSessionWithFlow(flowId)
            setSessionId(res.session_id)

            await processResponses(res.responses, res.persona_name && res.persona_avatar ? { name: res.persona_name, avatar: res.persona_avatar, description: res.persona_description } : undefined)

            localStorage.setItem('ai9_chat_session', res.session_id)
            localStorage.setItem('ai9_chat_flow', flowId)
        } catch (err) {
            console.error('Failed to switch flow', err)
            setIsTyping(false)
        }
    }, [processResponses])

    /**
     * Bloco 8 do trim (AI9-007, DEC-13.2): a sessão passou a ter DONO
     * (`chat_sessions.user_id`) e `/chat/*` passou a exigir token. Uma sessão
     * guardada no `sessionStorage` que pertença a OUTRO usuário — trocou de
     * login na mesma aba — agora recebe **404**, e sem isto o widget travava
     * para sempre num id inalcançável.
     *
     * 404 = "esta sessão não é sua (ou não existe mais)": esquece e abre outra.
     */
    const descartarSessaoInalcancavel = useCallback((err: any) => {
        if (err?.response?.status !== 404) return false

        addLog('system', 'Sessão não pertence a este usuário — abrindo uma nova.')
        setMessages([])
        setCurrentNode(null)
        setSessionId(null)
        localStorage.removeItem('ai9_chat_session')
        sessionStorage.removeItem(STORAGE_KEY_SESSION)
        sessionStorage.removeItem(STORAGE_KEY_MESSAGES)
        sessionStorage.removeItem(STORAGE_KEY_PERSONA)
        return true
    }, [addLog])

    // Send message
    const sendMessage = useCallback(async (content: string, hidden: boolean = false, originNodeId?: string) => {
        if (!sessionId) return

        const messageId = `usr-${Date.now()}`
        // Add user message only if not hidden
        if (!hidden) {
            const userMsg: ChatMessage = {
                id: messageId,
                role: 'user',
                content,
                timestamp: new Date()
            }
            setMessages(prev => [...prev, userMsg])
        }
        setIsTyping(true)

        try {
            addLog('system', `Enviando entrada: "${content}"${originNodeId ? ` (Salto Temporal: ${originNodeId})` : ''}`)

            // Context metadata for AI Agent
            const context = {
                current_page: window.location.pathname,
                user_name: localStorage.getItem('user_name') || undefined
            }

            const res = await chatFlowApi.sendInput(sessionId, content, originNodeId, context)

            await processResponses(res.responses, res.persona_name && res.persona_avatar ? { name: res.persona_name, avatar: res.persona_avatar, description: res.persona_description } : undefined)

        } catch (err) {
            if (!descartarSessaoInalcancavel(err)) {
                addLog('error', 'Falha ao processar entrada do usuário.')
            }
            console.error('Failed to send input', err)
            setIsTyping(false)
        }
    }, [sessionId, addLog, processResponses, descartarSessaoInalcancavel])

    /** Send an image file to the AI agent for Vision analysis.
     * Creates an optimistic user message with image preview.
     */
    const sendImage = useCallback(async (file: File, caption?: string) => {
        if (!sessionId) return

        // Optimistic user message with image preview
        const previewUrl = URL.createObjectURL(file)
        const userMsg: ChatMessage = {
            id: `img-${Date.now()}`,
            role: 'user',
            content: caption || '[Imagem enviada]',
            timestamp: new Date(),
            type: 'image',
            imageUrl: previewUrl
        }
        setMessages(prev => [...prev, userMsg])
        setIsTyping(true)

        try {
            addLog('system', `Enviando imagem: ${file.name} (${(file.size / 1024).toFixed(0)}KB)`)

            // Context metadata for AI Agent
            const context = {
                current_page: window.location.pathname,
                user_name: localStorage.getItem('user_name') || undefined
            }

            const res = await chatFlowApi.sendImageInput(sessionId, file, caption, context)

            await processResponses(res.responses, res.persona_name && res.persona_avatar ? { name: res.persona_name, avatar: res.persona_avatar, description: res.persona_description } : undefined)

        } catch (err) {
            if (!descartarSessaoInalcancavel(err)) {
                addLog('error', 'Falha ao enviar imagem.')
            }
            console.error('Failed to send image', err)
            setIsTyping(false)
        }
    }, [sessionId, addLog, processResponses, descartarSessaoInalcancavel])

    return {
        sessionId,
        messages,
        logs,
        isTyping,
        currentNode,
        currentFlowId,
        initSession,
        resetSession,
        switchFlow,
        sendMessage,
        sendImage,
        persona
    }
}
