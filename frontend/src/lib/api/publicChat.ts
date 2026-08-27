import { apiClient } from './client'

// Bloco 8 do trim (AI9-007, DEC-13.2) — este arquivo perdeu 4 dos 5 métodos.
//
// `sendMessage`, `getMessages` e `getSession` falavam com
// `/api/v1/public/chat/{message,messages,session}`, que eram o chat PÚBLICO de
// CAPTAÇÃO: criavam `Lead` na primeira mensagem e gravavam `LeadMessage`. Os três
// endpoints saíram no Bloco 6 com o AI9-006 e respondiam **404** desde então —
// o widget chamava os três e engolia o erro.
// `resolveAssets` falava com `/public/chat/resolve_assets` (shortcodes
// `[asset:XXX]` contra `OperationAsset`), removido no Bloco 7 com o AI9-014, e
// não tinha nenhum consumidor no front.
//
// O caminho vivo do assistente é `chatFlow.ts` → `/chat/{session,input,upload}`,
// agora autenticado.
//
// Sobra `getRouting`: mapeamento rota→agente, AI9-007 puro, não toca em sessão
// nem em lead — é o único que continua público no backend.

export interface AgentRouteMapping {
  id: string
  name: string
  mapped_routes: string[]
  override_active_chat: boolean
  persona_name?: string
  persona_avatar?: string
}

export const publicChatApi = {
  // Get route mapping for agents
  getRouting: async (): Promise<AgentRouteMapping[]> => {
    return apiClient.getPublic<AgentRouteMapping[]>('/api/v1/public/chat/routing')
  },
}
