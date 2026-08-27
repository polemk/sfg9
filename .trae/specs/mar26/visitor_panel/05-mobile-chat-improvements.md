# Tarefa 5: MobileChatBar com Preview + Patch Visual do Chat Mobile

**Sprint:** 1 — Visitor Preview (paralela com Tarefas 1-4)
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto

O chat no mobile tem três formas: a `MobileChatBar` (barra de 56px fixa no bottom), o modo fullscreen (toma a tela toda quando expande), e o side drawer (85vw da direita). O visitor interage principalmente com a MobileChatBar e o fullscreen.

Hoje a MobileChatBar é genérica — só mostra "Pergunte algo..." e um chevron. A ideia é transformar essa barra num preview da última mensagem do chat (estilo notificação do WhatsApp), incentivando o visitor a clicar e continuar a conversa. Além disso, adicionar um botão "Comprar" direto na barra.

O fullscreen chat tem bugs conhecidos no Instagram WebView: quando o teclado abre, o header some, a largura estoura a tela, e as mensagens desaparecem. Precisa de patch.

E uma melhoria UX importante: quando o chat está expandido e o teclado fechado, mostrar uma barrinha "Voltar pro site" abaixo do input — resolve o problema de o visitor ficar "preso" no chat sem saber como voltar.

---

## Onde começa

- `MobileChatBar.tsx` (91 linhas) — barra simples com avatar + "Pergunte algo..." + chevron
- `AIChatWidget.tsx` (~1900 linhas) — widget completo com modo fullscreen
- Modo fullscreen usa `visualViewport` API para lidar com teclado iOS
- `ChatContext.tsx` com `isOpen`, `toggleChat`, `setViewMode`
- `sessionStorage.ai9_flow_messages` armazena mensagens do flow
- State `isKeyboardOpen` já existe no AIChatWidget

## Onde termina

- MobileChatBar mostra preview truncado da última mensagem do chat
- MobileChatBar tem botão "Comprar" que abre checkout
- Chat expandido tem barrinha "Voltar pro site" quando teclado fechado
- Bugs de teclado corrigidos no modo fullscreen (header, width, scroll)

---

## O que precisa ser feito

### 5A — MobileChatBar com preview de última mensagem

Arquivo: `MobileChatBar.tsx`

A barra continua sendo o AIChatWidget minimizado — clicar expande normalmente. O que muda é o conteúdo do campo de texto:

- Ler `sessionStorage.ai9_flow_messages` para pegar última mensagem do agente (não do user)
- Truncar em ~50 caracteres com "..." (estilo preview de notificação do WhatsApp)
- Se não tem mensagens ainda: mostrar texto contextual por rota via `useLocation()`:
  - `/dashboard`: "Esse é o painel principal do seu projeto 👋"
  - `/admin/leads`: "Leads são capturados automaticamente..."
  - `/admin/metrics`: "Métricas em tempo real do seu negócio"
  - Fallback: "Toque para tirar dúvidas sobre o plano"
- O preview incentiva o clique ("ih, o que ela falou?")

Adicionar mini CTA à direita da barra (antes do chevron): botão compacto "Comprar" (ícone ShoppingCart ou texto curto). Tap abre checkout inline (Tarefa 6). Separar visualmente do tap que expande o chat — são duas ações distintas na mesma barra.

A barra fica sempre visível no mobile para visitors.

### 5B — Barrinha "Voltar pro site" no chat expandido

Arquivo: `AIChatWidget.tsx` — modo fullscreen

Quando o teclado está **fechado**, mostrar barra de ~40px abaixo do campo de input:
- Texto: "↓ Voltar pro site" ou ícone chevron-down com "Minimizar"
- Tap fecha o chat e volta pro MobileChatBar minimizado
- Usar `isKeyboardOpen` (já existe no state) para mostrar/esconder
- Quando teclado **abre**: barra some (espaço é precioso)
- Quando teclado **fecha**: barra reaparece
- Touch target 40px+ (barra inteira é clicável)

### 5C — Patch de bugs visuais com teclado aberto

Arquivo: `AIChatWidget.tsx` — modo fullscreen (a partir da linha ~1055)

**Bugs identificados:**
1. **Header some** — container `fixed inset-x-0` com `containerStyle` dinâmico perde posição no Instagram WebView
2. **Width estoura tela** — `inset-x-0` insuficiente no WebView; falta constraint explícito
3. **Mensagens somem** — `scrollIntoView` rola pro lugar errado quando viewport muda rápido
4. **Barra do Instagram empurra layout** — `visualViewport.offsetTop` não compensado corretamente

**Fixes necessários:**
- Container fullscreen: adicionar `w-full max-w-[100vw] overflow-x-hidden` explícito
- Quando chat fullscreen abre: adicionar `overflow: hidden` no `<html>/<body>` (previne scroll do fundo)
- Header: usar `shrink-0` firme, não depender do containerStyle para posicionamento
- Debounce de 100ms no handler de `visualViewport resize` (Instagram dispara eventos em rajada)
- Trocar `messagesEndRef.scrollIntoView` por `messagesContainer.scrollTo({ top: scrollHeight })` — mais previsível
- Adicionar `inputmode="text"` no input para evitar teclado inesperado
- Considerar `interactive-widget=resizes-content` no meta viewport se suportado

---

## Observações importantes

- A MobileChatBar tem duas ações distintas: tap na barra expande o chat, tap no botão "Comprar" abre checkout. Cuidado com a área de toque — separar claramente para evitar taps acidentais.
- O preview de mensagem lê do `sessionStorage` que já existe — não precisa de nova API.
- A barrinha "Voltar pro site" é crucial para UX mobile. O X no header do chat fullscreen é pequeno e fica longe do polegar. A barra no bottom é thumb-zone friendly.
- Os fixes de teclado devem ser testados no Instagram WebView real (iOS e Android), não só no Chrome DevTools. O comportamento do `visualViewport` diverge entre browsers.

---

## Critérios de aceite

1. MobileChatBar mostra preview truncado da última mensagem do agente
2. Sem mensagens: mostra texto contextual que muda por rota
3. Botão "Comprar" na barra abre checkout (não abre o chat)
4. Tap na barra (fora do botão Comprar) abre o chat normalmente
5. Chat expandido mostra "Voltar pro site" quando teclado fechado
6. Barrinha some quando teclado abre, reaparece quando fecha
7. Tap na barrinha minimiza o chat de volta pra MobileChatBar
8. Com teclado aberto: header visível, width não estoura, mensagens visíveis e scrolláveis
9. Testado no Instagram WebView real (iOS + Android)

---

## Dependências

Nenhuma — pode rodar em paralelo com qualquer etapa. Só o botão "Comprar" depende do checkout (Tarefa 6) para ter destino, mas pode abrir um placeholder ou link externo temporariamente.

## Próxima tarefa → Spec 06 (Checkout Inline)
