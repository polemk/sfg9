import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import App from './app/App'
import './styles/globals.css'
import './lib/i18n'

import { HelmetProvider } from 'react-helmet-async'
import { purgeLegacyTokenStorage } from '@/lib/api/tokenStore'

// Quem já usou o app tem access/refresh token persistidos em localStorage por
// versões antigas. Sem esta limpeza no boot, a credencial durável continuaria
// exposta a qualquer script mesmo depois da migração para cookie HttpOnly.
purgeLegacyTokenStorage()

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 0, // 5 minutes
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <HelmetProvider>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </HelmetProvider>
    </QueryClientProvider>
  </React.StrictMode>,
)
