/**
 * chatBarTracker — Registra eventos da MobileChatBar para estudo posterior.
 *
 * Armazena em localStorage como array JSON com timestamp, tipo e metadata.
 * Pode ser exportado via console: ChatBarTracker.export()
 */

export interface ChatBarEvent {
  /** Tipo do evento */
  // 'buy_click' saiu no Bloco 4 do trim junto com o checkout (AI9-002);
  // a esfera agora só abre o assistente -> 'sphere_click'.
  type: 'impression' | 'expand_click' | 'sphere_click' | 'attention_pulse' | 'scroll_near'
  /** Timestamp ISO */
  timestamp: string
  /** Rota ativa no momento do evento */
  route: string
  /** Metadata extra (persona, msg preview, etc) */
  meta?: Record<string, any>
}

const STORAGE_KEY = 'ai9_chatbar_events'
const MAX_EVENTS = 500 // Limite para não estourar localStorage

/** Lê eventos armazenados */
function getEvents(): ChatBarEvent[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? JSON.parse(raw) : []
  } catch {
    return []
  }
}

/** Salva eventos no localStorage */
function saveEvents(events: ChatBarEvent[]) {
  try {
    // Mantém apenas os últimos MAX_EVENTS
    const trimmed = events.slice(-MAX_EVENTS)
    localStorage.setItem(STORAGE_KEY, JSON.stringify(trimmed))
  } catch {
    // localStorage cheio — limpa os mais antigos
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(events.slice(-100)))
    } catch {
      // Ignora se não conseguir salvar
    }
  }
}

/** Registra um evento */
export function trackChatBarEvent(
  type: ChatBarEvent['type'],
  route: string,
  meta?: Record<string, any>
) {
  const event: ChatBarEvent = {
    type,
    timestamp: new Date().toISOString(),
    route,
    meta
  }
  const events = getEvents()
  events.push(event)
  saveEvents(events)
}

/** Exporta todos os eventos (para uso no console ou envio ao backend) */
export function exportChatBarEvents(): ChatBarEvent[] {
  return getEvents()
}

/** Limpa todos os eventos armazenados */
export function clearChatBarEvents() {
  localStorage.removeItem(STORAGE_KEY)
}

// Expõe no window para debug via console do navegador
if (typeof window !== 'undefined') {
  ;(window as any).ChatBarTracker = {
    export: exportChatBarEvents,
    clear: clearChatBarEvents,
    events: getEvents
  }
}
