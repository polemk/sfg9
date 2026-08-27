import { defineConfig, loadEnv, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import { buildCsp } from './csp.config'

// Backend alvo do proxy dev — parametrizavel para rodar varias arvores (o
// worktree do GOAT roda em paralelo com o checkout da fly9) contra backends
// distintos sem disputar a :3000. Estava fixo, e um backend noutra porta
// recebia zero evento: a pagina carregava, o /api caia no vazio e o rastreio
// parecia quebrado quando o quebrado era o proxy.
const BACKEND = process.env.VITE_BACKEND_URL || 'http://localhost:3026'
const BACKEND_WS = BACKEND.replace(/^http/, 'ws')

/**
 * Injeta no `index.html`, na ordem em que o navegador precisa:
 *   1. o CSP BLOQUEANTE do DEC-48, montado a partir do que a aplicacao carrega de fato
 *      (`csp.config.ts`) e das origens de API/WebSocket deste build;
 *   2. o snippet GA4 do DEC-87 — **so** quando `VITE_GA_ENABLED=true`. O default e
 *      desligado, por ENV, nunca por hardcode.
 *
 * O CSP entra como `<meta http-equiv>` logo depois do `<meta charset>`: precisa vir
 * antes de qualquer recurso, senao a politica so vale para o que carregar depois dela.
 */
function securityHeadersPlugin(mode: string): Plugin {
  return {
    name: 'sfg-security-headers',
    transformIndexHtml: {
      order: 'pre',
      handler(html) {
        const env = loadEnv(mode, process.cwd(), '')
        const isDev = mode !== 'production'
        const gaEnabled = env.VITE_GA_ENABLED === 'true'
        const gaId = env.VITE_GA_MEASUREMENT_ID || ''

        const csp = buildCsp({
          isDev,
          apiUrl: env.VITE_API_URL,
          wsUrl: env.VITE_WS_URL,
          gaEnabled: gaEnabled && Boolean(gaId),
        })

        const tags = [`<meta http-equiv="Content-Security-Policy" content="${csp}" />`]

        if (gaEnabled && gaId) {
          tags.push(`<script src="/analytics-ga4.js" data-measurement-id="${gaId}"></script>`)
        } else {
          // Deixa rastro no HTML de que a coleta esta desligada por decisao, nao por
          // esquecimento — e de onde se liga.
          tags.push('<!-- DEC-87: Google Analytics desligado (VITE_GA_ENABLED=false). Ligar exige tambem liberar o dominio no csp.config.ts. -->')
        }

        return html.replace('<meta charset="UTF-8" />', `<meta charset="UTF-8" />\n  ${tags.join('\n  ')}`)
      },
    },
  }
}

export default defineConfig(({ mode }) => ({
  plugins: [react(), securityHeadersPlugin(mode)],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5185,
    // Hosts aceitos pelo dev server. So os CURINGAS de tunel — o subdominio
    // que o ngrok sorteia muda a cada execucao, entao dominio escrito na mao
    // aqui nasce vencido (havia dois, ambos ja mortos). `.ngrok-free.app`
    // casa qualquer subdominio daquele dominio: nao precisa mexer neste
    // arquivo a cada tunel novo.
    allowedHosts: [
      'localhost',
      '.ngrok-free.dev',
      '.ngrok-free.app',
      '.ngrok.app',
      '.ngrok.io'
    ],
    proxy: {
      // API calls (Grape)
      '/api': {
        target: BACKEND,
        changeOrigin: true,
      },
      // Chat Flow API (public)
      '/chat': {
        target: BACKEND,
        changeOrigin: true,
      },
      // Public API (unauthenticated endpoints)
      '/public': {
        target: BACKEND,
        changeOrigin: true,
      },
      // Swagger docs
      '/docs': {
        target: BACKEND,
        changeOrigin: true,
      },
      '/swagger_doc': {
        target: BACKEND,
        changeOrigin: true,
      },
      // WebSocket (Action Cable)
      '/cable': {
        target: BACKEND_WS,
        ws: true,
        changeOrigin: true,
      },
      // OAuth callbacks
      '/auth': {
        target: BACKEND,
        changeOrigin: true,
      },
      // WhatsApp / Evolution API. O backend monta `Api::Whats::V1::Base` em
      // `/whats/v1/*` — o prefixo é a EXPRESSÃO, não a string, porque `/whats`
      // solto casa por prefixo e engolia a rota `/whatsapp` da SPA: a tela de
      // pareamento devolvia `Routing Error` do Rails em vez de abrir.
      '^/whats/': {
        target: BACKEND,
        changeOrigin: true,
      },
      // Asaas (pagamentos: charges, subscriptions, pix)
      '/asaas': {
        target: BACKEND,
        changeOrigin: true,
      },
      '/users/auth': {
        target: BACKEND,
        changeOrigin: true,
      },
      // ActiveStorage and Rails internal routes
      '/rails': {
        target: BACKEND,
        changeOrigin: true,
      },
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          'react-vendor': ['react', 'react-dom'],
          'router-vendor': ['react-router-dom'],
          'ui-vendor': ['lucide-react', 'sonner'],
          'query-vendor': ['@tanstack/react-query'],
          'animation-vendor': ['framer-motion'],
          'state-vendor': ['zustand'],
          'i18n-vendor': ['i18next', 'react-i18next'],
          'http-vendor': ['axios'],
        },
      },
    },
  },
}))
