// Layout component
import { Outlet, useSearchParams, useLocation } from 'react-router-dom'
import { Sidebar } from '@/components/Sidebar'
import { useState, useEffect } from 'react'
import { AIChatWidget } from './chat/AIChatWidget'
import { useChat } from '@/contexts/ChatContext'
import { useAuthStore } from '@/store/authStore'
import { MouseTracker } from '@/components/MouseTracker'
import { MobileTopBar } from '@/components/mobile/MobileTopBar'
import { MobileBottomBar } from '@/components/mobile/MobileBottomBar'
import { RouteErrorBoundary } from '@/components/RouteErrorBoundary'
// DEC-13.2 — o que o assistente do console sabe sem perguntar: a tela em que a
// pessoa está, o projeto selecionado e o menu que o papel dela alcança. Mora
// AQUI porque é a moldura do console: o widget também é montado na tela pública
// e no builder, e nenhum dos dois tem menu nem projeto para descrever.
import { useAssistantContext } from '@/hooks/useAssistantContext'
// S12 / DEC-65 — o banner de aceite pendente. Fica AQUI, e não em cada tela,
// porque "persistente até aceitar" quer dizer em todo o console: um banner que
// só aparece em algumas telas é um banner que a pessoa aprende a evitar. É a
// única linha que a S12 acrescenta ao Layout (Regra de fronteira).
import { TermsBanner } from '@/components/contracts/TermsBanner'
// S1 / FE-037 — a faixa de "Vendo como". Mesma razão do banner acima: um aviso de
// ESTADO da sessão tem de aparecer em todo o console e em todas as larguras. Antes
// ele vivia só dentro da barra lateral, que nasce recolhida e não existe no
// telefone — quem personificava no celular não via nada.
import { ImpersonationBanner } from '@/features/auth/ImpersonationBanner'

export function Layout() {
  const location = useLocation()
  const [searchParams, setSearchParams] = useSearchParams()

  // Hide global chat widget on builder page (builder has embedded preview)
  const isBuilderPage = location.pathname.startsWith('/admin/chat/builder')

  const { isOpen, closeChat, toggleChat, sessionId, openChat, currentAgentId, pendingIntent, clearPendingIntent } = useChat()
  const assistantContext = useAssistantContext()
  const [initialMsg, setInitialMsg] = useState<string | undefined>(undefined)
  
  // Determinamos uma chave única para o widget para forçar o reset ao trocar de agente
  // Isso garante que a persona (Nathy/Isa) mude instantaneamente na UI
  const widgetKey = `chat-${currentAgentId || 'default'}-${sessionId || 'new'}`

  // Limpa pendingIntent após ser consumido pelo widget (via key change)
  useEffect(() => {
    if (pendingIntent) {
      clearPendingIntent()
    }
  }, [widgetKey])

  useEffect(() => {
    if (searchParams.get('welcome') === 'true') {
      setInitialMsg("Bem-vindo ao seu painel! Eu sou o assistente IA do Safegold. Como posso, ajudar você hoje?");
      openChat();
      const newParams = new URLSearchParams(searchParams);
      newParams.delete('welcome');
      setSearchParams(newParams);
    }
  }, [searchParams])



  return (
    <div className="flex bg-background h-[100dvh] overflow-hidden text-foreground relative">
      <MouseTracker />

      {/* Barra de navegação mobile */}
      <MobileTopBar />

      {/* Sidebar — oculta no mobile, visível a partir de md */}
      <div className="hidden md:block">
        <Sidebar />
      </div>

      {/* **O respiro da `MobileTopBar` fica na COLUNA, não no `main`.**

          Ele estava só no `main`, e as duas faixas (impersonação e aceite) são
          IRMÃS do `main`, acima dele: no telefone nasciam ATRÁS da barra fixa.
          Medido em 390×844, no topo da página, com a conta da apresentação — a
          primeira linha do aviso ("Você ainda não aceitou os documentos
          vigentes.") ficava escondida, e a faixa começava no meio da frase, em
          TODAS as telas.

          Na coluna o respiro é reservado uma vez só: some quando as duas faixas
          não aparecem, e nenhuma delas precisa saber que existe uma barra fixa
          por cima. */}
      <div className="flex-1 flex flex-col h-full overflow-hidden relative pt-[calc(4rem+env(safe-area-inset-top))] md:pt-0">
        <ImpersonationBanner />
        <TermsBanner />

        {/* O respiro do RODAPÉ do telefone é reservado aqui, na moldura — e não
            em cada tela. (O do topo subiu para a coluna, acima: as faixas de
            impersonação e de aceite ficam fora do `main` e também precisam
            dele.)

            Antes, `main` reservava só o topo (`pt-16`) e **nada** para o rodapé:
            a `MobileBottomBar` é `fixed`, então os últimos ~4rem de toda lista
            ficavam escondidos atrás das abas. O `MobilePageLayout` já fazia essa
            conta, mas só as telas que o usam eram protegidas — e a maioria monta
            o próprio `div`. Reservar na moldura protege todas.

            O topo soma `env(safe-area-inset-top)` porque a `MobileTopBar` também
            soma: instalado como PWA num aparelho com entalhe, a barra fica mais
            alta que 4rem e o `pt-16` fixo deixava o começo do conteúdo embaixo
            dela. */}
        <main className="flex-1 overflow-auto bg-muted/20 px-4 pb-[calc(5rem+env(safe-area-inset-bottom))] md:p-6 md:pt-6 md:pb-6 lg:p-8">
          {/* Sem a fronteira de erro, uma exceção em QUALQUER tela desmonta a
              árvore inteira e o usuário fica com tela branca — o mesmo sintoma
              do 404 que a rota curinga resolveu, por outra causa. */}
          <RouteErrorBoundary>
            <Outlet />
          </RouteErrorBoundary>
        </main>
      </div>

      <MobileBottomBar />

      <AIChatWidget
        key={widgetKey}
        isOpen={isOpen}
        onClose={closeChat}
        sessionId={sessionId || undefined}
        flowId={currentAgentId || undefined}
        initialMessage={initialMsg}
        pendingIntent={pendingIntent || undefined}
        extraContext={assistantContext}
        mode="flow"
      />
    </div>
  )
}
