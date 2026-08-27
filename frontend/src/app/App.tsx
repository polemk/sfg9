// App component
import { lazy, Suspense } from 'react'
import { Routes, Route } from 'react-router-dom'
import { Toaster } from 'sonner'
import { ThemeProvider } from '@/components/ThemeProvider'
import { useTheme } from '@/hooks/useTheme'
import { useAgentRouter } from '@/hooks/useAgentRouter'
import { Layout } from '@/components/Layout'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { RoleRoute } from '@/components/RoleRoute'
import { RootRedirect } from '@/components/RootRedirect'
import { RouteErrorBoundary } from '@/components/RouteErrorBoundary'
import { VisitorRoute } from '@/components/VisitorRoute'
import { ParticlesBackground } from '@/components/ParticlesBackground'
import { LightGlassEffect } from '@/components/LightGlassEffect'
import { ChatProvider } from '@/contexts/ChatContext'
import { CONSOLE_NAV_GROUPS, HOME_AREA } from '@/app/consoleNavigation'
import { NotFoundPage } from '@/app/pages/ErrorPages'

/** Toast da casa: segue o tema do app e usa as superfícies tokenizadas. */
function BrandedToaster() {
  const { theme } = useTheme()
  return (
    <Toaster
      position="top-right"
      richColors
      theme={theme}
      toastOptions={{
        classNames: {
          toast: 'bg-popover text-popover-foreground border border-border shadow-e3 rounded-md',
          description: 'text-muted-foreground',
          actionButton: 'bg-primary text-primary-foreground',
          cancelButton: 'bg-secondary text-secondary-foreground',
        },
      }}
    />
  )
}

// Page Loader component for Suspense fallback
function PageLoader() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-pulse text-muted-foreground">Carregando...</div>
    </div>
  )
}

// Lazy-loaded pages (code-split per route)
const LoginPage = lazy(() => import('@/app/pages/LoginPage').then(m => ({ default: m.LoginPage })))
const OAuthCallbackPage = lazy(() => import('@/features/auth/OAuthCallbackPage').then(m => ({ default: m.OAuthCallbackPage })))
const MagicLinkCallbackPage = lazy(() => import('@/features/auth/MagicLinkCallbackPage').then(m => ({ default: m.MagicLinkCallbackPage })))
// S12 / FE-330 — Termos de Uso e Política de Privacidade: leitura PÚBLICA, fora
// do `ProtectedRoute`. Quem ainda não tem conta precisa ler antes de aceitar.
// A rota do servidor está na allowlist de `Api::Root` por CAMINHO.
const ContractPage = lazy(() => import('@/app/pages/public/ContractPage').then(m => ({ default: m.ContractPage })))
const ChatBuilderPage = lazy(() => import('@/features/chat-builder/ChatBuilderPage').then(m => ({ default: m.ChatBuilderPage })))
const ExecutionViewerPage = lazy(() => import('@/features/chat-builder/ExecutionViewerPage').then(m => ({ default: m.ExecutionViewerPage })))
const ExecutionDetailPage = lazy(() => import('@/features/chat-builder/ExecutionDetailPage').then(m => ({ default: m.ExecutionDetailPage })))
// Galeria dos primitivos do design system. Só existe em desenvolvimento: o
// DEC-98 exige conferência visual em claro E escuro, com cada painel ABERTO, e
// esta é a tela onde isso se faz.
// `import.meta.env.DEV` é constante em build: o Rollup poda o ramo inteiro, e
// nem a rota nem o chunk da galeria vão para produção.
const UiKitPage = import.meta.env.DEV
  ? lazy(() => import('@/app/pages/UiKitPage').then(m => ({ default: m.UiKitPage })))
  : null

/**
 * As rotas das áreas do console, geradas a partir de `consoleNavigation.tsx`.
 *
 * **Menu e roteamento vêm do MESMO registro.** É o que garante que não exista
 * item apontando para rota inexistente nem rota sem dono no menu — as duas
 * listas não podem divergir porque são uma só. Quem entrega uma tela nova troca
 * `element: null` pelo `lazy(...)` da sua página e ganha rota + item de menu no
 * mesmo commit.
 *
 * O gate de papel sai do MESMO dado (`roles`), então esconder o item e barrar o
 * endereço digitado à mão são a mesma linha de configuração. No legado eram
 * coisas diferentes, e por isso a única autorização real morava nas views
 * (D-23) enquanto as requisições fora da tela faziam tudo (D-34).
 */
function AreaRoutes() {
  return (
    <>
      {CONSOLE_NAV_GROUPS.flatMap(group =>
        group.items
          .filter(item => item.element !== null)
          .flatMap(item => {
            const Page = item.element!
            const roles = item.roles ?? group.roles
            const guard = (node: React.ReactNode) =>
              roles ? <RoleRoute roles={roles}>{node}</RoleRoute> : <>{node}</>

            return [
              <Route key={item.path} path={item.path.replace(/^\//, '')} element={guard(<Page />)} />,
              ...(item.children ?? []).map(child => {
                const Child = child.element
                return (
                  <Route
                    key={`${item.path}/${child.path}`}
                    path={`${item.path.replace(/^\//, '')}/${child.path}`}
                    element={guard(<Child />)}
                  />
                )
              }),
            ]
          }),
      )}
    </>
  )
}

function AgentRouterInit() {
  useAgentRouter()
  return null
}

function App() {
  const HomePage = HOME_AREA.element

  return (
    <ThemeProvider>
      <ChatProvider>
        <AgentRouterInit />
        <ParticlesBackground />
        <LightGlassEffect />
        <div
          className="min-h-screen font-sans antialiased relative"
        >
          <div className="relative z-10">
            <RouteErrorBoundary>
              <Suspense fallback={<PageLoader />}>
                <Routes>
                  {/* DEC-13.3: a raiz do Safegold é a tela de login (sistema
                      interno). Com sessão viva ela deixa de ser login e vira o
                      **redirecionador por papel** (FE-404) — que é tudo o que o
                      `dash` do legado era. Não existe dashboard (DC-15). */}
                  <Route path="/" element={<RootRedirect fallback={<LoginPage />} />} />
                  <Route path="/login" element={<LoginPage />} />
                  <Route path="/auth/callback" element={<OAuthCallbackPage />} />
                  <Route path="/magic-login" element={<MagicLinkCallbackPage />} />
                  {/* `:kind` aceita o slug (`termos-de-uso`) e a string literal
                      do legado (`Politicas%20de%20Privacidade`) — Q-B34: os
                      links externos antigos continuam abrindo. */}
                  <Route path="/contract/:kind" element={<ContractPage />} />
                  {UiKitPage && <Route path="/ui-kit" element={<UiKitPage />} />}
                  <Route
                    element={
                      <ProtectedRoute>
                        <Layout />
                      </ProtectedRoute>
                    }
                  >
                    {/* "Início". Enquanto a NEW-002 (S15) não chega, é a tela da
                        base — e o `/` autenticado só passa por aqui quando a
                        área do papel ainda não está montada. */}
                    <Route path="dashboard" element={<HomePage />} />

                    {/* As áreas do console, do registro declarativo. */}
                    {AreaRoutes()}

                    {/* Telas da base ai9 que não são área de menu. */}
                    <Route path="admin/chat/builder" element={<VisitorRoute><ChatBuilderPage /></VisitorRoute>} />
                    <Route path="admin/chat/executions" element={<VisitorRoute><ExecutionViewerPage /></VisitorRoute>} />
                    <Route path="admin/chat/executions/:sessionId" element={<VisitorRoute><ExecutionDetailPage /></VisitorRoute>} />
                  </Route>

                  {/* A ROTA CURINGA. `App.tsx` não tinha nenhuma: área
                      desconhecida virava **tela em branco**. E o legado fazia
                      pior — rebaixava em silêncio para o `dash`, e o usuário
                      achava que tinha chegado. */}
                  <Route path="*" element={<NotFoundPage />} />
                </Routes>
              </Suspense>
            </RouteErrorBoundary>
            {/* O sonner tem tema próprio e o default é claro: sem amarrar ao
                nosso, o toast saía branco sobre o app escuro. */}
            <BrandedToaster />
          </div>
        </div>
      </ChatProvider>
    </ThemeProvider>
  )
}

export default App
