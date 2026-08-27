/**
 * Content-Security-Policy do Safegold — BLOQUEANTE (DEC-48).
 *
 * O usuario recusou conscientemente o modo `report-only`, sabendo do risco: numa base
 * que nunca teve CSP, recurso bloqueado nao gera erro visivel — some. Por isso esta
 * politica e montada a partir do que a aplicacao REALMENTE carrega (varredura de
 * `frontend/src` em 25/08/2026), nao de um template, e a tarefa so fecha depois de uma
 * varredura de console em todas as telas, em light e dark.
 *
 * O front e um SPA servido estaticamente (Vite), entao a politica viaja como
 * `<meta http-equiv>` no `index.html` — o backend e `api_only` e o header dele so
 * alcancaria as respostas JSON, que nao carregam recurso nenhum.
 *
 * Limitacao conhecida do meta: `frame-ancestors`, `report-uri` e `sandbox` sao
 * ignorados em meta tag. O anti-clickjacking fica no header `X-Frame-Options` do host
 * estatico (`serve.json`) e do backend (`config/environments/production.rb`).
 */

export interface CspOptions {
  /** Modo de desenvolvimento: o Vite injeta o preambulo do react-refresh inline. */
  isDev: boolean
  /** `VITE_API_URL` — origem do backend. Vazio quando o front fala por caminho relativo. */
  apiUrl?: string
  /** `VITE_WS_URL` — origem do Action Cable. */
  wsUrl?: string
  /**
   * `VITE_GA_ENABLED`. DEC-87: o Google Analytics nasce DESLIGADO e o CSP **nao**
   * libera o dominio dele enquanto a flag estiver desligada. Sao duas travas, nao uma:
   * ligar a coleta exige mexer na flag E na politica.
   */
  gaEnabled: boolean
}

/** Reduz uma URL a `esquema://host[:porta]`, que e a forma que o CSP aceita. */
function toOrigin(url?: string): string | null {
  if (!url) return null
  try {
    return new URL(url).origin
  } catch {
    return null
  }
}

export function buildCsp(options: CspOptions): string {
  const { isDev, apiUrl, wsUrl, gaEnabled } = options

  const apiOrigin = toOrigin(apiUrl)
  const wsOrigin = toOrigin(wsUrl)

  // `connect-src` e o primeiro suspeito quando o realtime cai sem dizer nada:
  // XHR do axios (VITE_API_URL) e o WebSocket do Action Cable (VITE_WS_URL) sao
  // origens DIFERENTES da pagina em dev (:5173 -> :3000).
  const connect = new Set<string>(["'self'"])
  if (apiOrigin) connect.add(apiOrigin)
  if (wsOrigin) connect.add(wsOrigin)
  if (isDev) {
    // HMR do Vite. Sem isto a pagina carrega e para de atualizar sozinha.
    connect.add('ws://localhost:5173')
    connect.add('ws://127.0.0.1:5173')
  }

  // Os scripts do build saem de /assets (mesma origem). Em dev o
  // `@vitejs/plugin-react` injeta o preambulo do react-refresh INLINE no HTML, e o
  // Vite avalia modulos: sem estas duas fontes a tela fica branca em dev — e so em dev.
  const script = ["'self'"]
  if (isDev) script.push("'unsafe-inline'", "'unsafe-eval'")
  // DEC-87: `googletagmanager.com` entra AQUI e so aqui, e so quando a flag estiver
  // ligada. Nao mova para o bloco fixo.
  if (gaEnabled) script.push('https://www.googletagmanager.com')

  const connectList = Array.from(connect)
  if (gaEnabled) {
    connectList.push('https://www.google-analytics.com', 'https://region1.google-analytics.com')
  }

  const directives: Record<string, string[]> = {
    'default-src': ["'self'"],
    'base-uri': ["'self'"],
    'object-src': ["'none'"],
    'form-action': ["'self'"],
    'script-src': script,
    // Tailwind e as bibliotecas de UI injetam <style> em runtime; e o Google Fonts
    // serve a folha de estilo a partir de fonts.googleapis.com.
    'style-src': ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
    // ...e os arquivos .woff2 saem de fonts.gstatic.com. `font-src` mal configurado
    // derruba a tipografia inteira sem uma linha de erro na tela.
    'font-src': ["'self'", 'data:', 'https://fonts.gstatic.com'],
    'img-src': [
      "'self'",
      'data:',
      'blob:',
      ...(apiOrigin ? [apiOrigin] : []),
      'https://cdn.jsdelivr.net', // bandeiras twemoji do PhoneInputGroup
      'https://api.dicebear.com', // avatar de fallback em UsersPage
      'https://picsum.photos', // imagens de exemplo da galeria de midia
      'https://drive.google.com',
      'https://lh3.googleusercontent.com', // miniatura de arquivo do Drive
      // DEC-61/OPS-482: tiles do mapa. Se o mapa for descartado, esta linha sai.
      'https://maps.googleapis.com',
      'https://maps.gstatic.com',
    ],
    'media-src': ["'self'", 'blob:', ...(apiOrigin ? [apiOrigin] : []), 'https://drive.google.com'],
    'connect-src': connectList,
    // MediaPage embute o player do Google Drive em <iframe>.
    'frame-src': ["'self'", 'https://drive.google.com'],
    'worker-src': ["'self'", 'blob:'],
    'manifest-src': ["'self'"],
  }

  if (gaEnabled) {
    // O gtag.js grava a medicao por <img> quando o fetch falha.
    directives['img-src'].push('https://www.google-analytics.com')
  }

  return Object.entries(directives)
    .map(([name, values]) => `${name} ${values.join(' ')}`)
    .join('; ')
}
