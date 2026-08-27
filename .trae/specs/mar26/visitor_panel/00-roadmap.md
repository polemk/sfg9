# Roadmap: Experiência de Planos no Console (Visitor Preview)
sfsdjfdsa
## Objetivo
Adaptar o **painel admin existente** para que visitantes (vindos do Instagram, WebView mobile) possam selecionar um plano, ver o menu filtrado com apenas os recursos daquele plano, navegar pelas páginas existentes com dados fake explicativos, e ser guiados até a compra. Sem inventar telas do zero — reutilizar o que já existe.

## Stack
- Backend: Ruby / Rails 8 (API-only, Grape)
- Frontend: React + TypeScript + Vite + Tailwind + shadcn/ui
- Design: Stitch + DESIGN.md (para componentes novos pontuais)
- Database: PostgreSQL
- Testes: RSpec (backend), Vitest (frontend)
- Integrações: Asaas (pagamentos), Action Cable (realtime)
- Arquitetura: Monorepo (backend/ + frontend/)

## Contexto: Instagram WebView
- Touch-only, sem hover, tela 375-414px
- Performance limitada — componentes leves
- `dvh` ao invés de `vh`, fallback para `backdrop-filter`
- Touch targets ≥ 48px, fontes ≥ 16px
- `window.location.href` ao invés de `window.open()`

## Resumo das Etapas

| Etapa | Spec | Ação | Tipo | Skill |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `01-api-plans-preview.md` | API de planos/features com `menu_key` | Backend | `rails-8-patterns` |
| 2 | `02-store-preview-mode.md` | Store Zustand + preview mode | Frontend | `react-components` |
| 3 | `03-plan-selector-sidebar.md` | Seletor de plano no sidebar + menu dinâmico | Frontend | `design-md` + `shadcn-ui` |
| 4 | `04-info-cards-mock-data.md` | Info cards explicativos + dados mock nas páginas | Frontend | `frontend-design` |
| 5 | `05-mobile-chat-improvements.md` | MobileChatBar preview + barrinha voltar + patch teclado | Frontend | `mobile-design` |
| 6 | `06-checkout-inline.md` | Checkout pré-preenchido (overlay ou navigate) | Frontend | `frontend-design` |
| 7 | `07-tests.md` | Testes backend + frontend | Full-stack | `testing-patterns` |

## Ordem de Execução

```
1. Etapa 1 + Etapa 5 — API + Melhorias chat (paralelas, sem dependências)
2. Etapa 2 — Store (depende de 1)
3. Etapa 3 — Seletor + Menu dinâmico (depende de 2)
4. Etapa 4 — Info cards + dados mock (depende de 3)
5. Etapa 6 — Checkout bottom-sheet (depende de 1-4)
6. Etapa 7 — Testes (depende de tudo)
```

## Filosofia: Reaproveitar, Não Reinventar

### O que NÃO estamos criando
- Tela de boas-vindas fullscreen nova
- Bottom navigation custom
- Onboarding multi-step
- Redesign do painel
- Novas páginas de preview
- ChatFlow novo (o chat existente já serve)

### O que estamos REAPROVEITANDO
- Sidebar existente (adiciona PlanSelector + filtro de items)
- Páginas do admin existentes (dados mock + info cards, sem recriar)
- MobileChatBar existente (evolui pra preview de última msg + texto contextual)
- AIChatWidget existente (patch de teclado + barrinha "voltar pro site")
- Checkout service existente (novo endpoint inline reutilizando lógica)
- PermissionsSyncService + Action Cable (já sincroniza permissões)
- Plan/PlanFeature models (apenas adiciona `menu_key`)

## Critérios de Aceite Globais

- [ ] Visitor vê seletor de planos no sidebar ao logar
- [ ] Trocar plano filtra o menu (só mostra recursos do plano selecionado)
- [ ] Páginas existentes mostram dados fake com info cards explicativos
- [ ] Info cards têm "Leia mais" expansível, um vem aberto por padrão
- [ ] CTA sticky no bottom de cada página preview leva ao checkout
- [ ] MobileChatBar mostra preview truncado da última mensagem do chat (estilo WhatsApp)
- [ ] MobileChatBar mostra texto contextual por rota quando não tem mensagens
- [ ] MobileChatBar tem botão "Comprar" que abre checkout direto
- [ ] Chat expandido tem barrinha "voltar pro site" abaixo do input (some com teclado aberto)
- [ ] Chat fullscreen funciona com teclado aberto (header visível, width ok, mensagens ok)
- [ ] Checkout funciona como bottom-sheet sem sair do painel
- [ ] Após compra, permissões sincronizam e sidebar atualiza para modo real
- [ ] Funciona no Instagram WebView mobile (testado manualmente)
- [ ] Todos os testes passam (RSpec + Vitest)

## Instagram WebView — Armadilhas Conhecidas
- `window.location.href` em vez de `window.open()`
- `position: sticky` em vez de `position: fixed` quando possível
- Fallback de cor sólida para `backdrop-filter: blur()`
- `dvh` em vez de `vh`
- `font-display: swap` + system fonts fallback
- `interactive-widget=resizes-content` no meta viewport
- Debounce nos `visualViewport` events (Instagram dispara múltiplos)
