# Tarefa 7: Testes e Verificação Final

**Sprint:** 2 — Preview Experience
**Estimativa:** 1 dia
**Tipo:** Backend + Frontend

---

## Contexto

Todas as peças estão no lugar: API de planos, store, sidebar dinâmica, info cards, chat melhorado, checkout. Agora precisa garantir que tudo funciona junto, especialmente no cenário end-to-end: visitor entra → seleciona plano → navega preview → compra → vira client.

O `backend.md` das rules exige RSpec com mínimo 90% de coverage. O frontend usa Vitest.

---

## Onde começa

- Tarefas 1-6 implementadas
- RSpec configurado no backend
- Vitest configurado no frontend
- Factories existentes: `plans.rb`, `orders.rb`

## Onde termina

- Testes RSpec cobrindo endpoints novos e integração de permissions
- Testes Vitest cobrindo store, componentes novos, e integração
- Teste manual documentado no Instagram WebView real
- `bundle exec rspec` e `npx vitest` verdes

---

## O que precisa ser feito

### Backend (RSpec)

**Endpoint `plans/preview`:**
- Retorna planos ativos com features e menu_keys
- Não retorna planos inativos
- Funciona sem autenticação
- Cache funciona (mock ou spy no Rails.cache)

**Endpoint `checkout/inline`:**
- Requer autenticação (401 sem token)
- Gera URL Asaas com dados do user pré-preenchidos
- Aplica cupom corretamente
- Retorna erro para cupom inválido
- Retorna erro para plan_id inexistente

**PermissionsSyncService:**
- Após purchase com status DONE, permissions do user atualizam
- User type muda de visitor para client (se aplicável)
- Verificar que o flow existente não quebrou com as mudanças

### Frontend (Vitest)

**planPreviewStore:**
- Seleção de plano persiste (mock localStorage)
- Auto-seleção do plano popular
- `activeMenuKeys()` retorna array correto
- `isPreviewMode` reflete user type

**PlanSelector:**
- Renderiza apenas quando `isPreviewMode`
- Mostra planos do store
- Chama `setSelectedPlan` ao clicar

**Sidebar com preview:**
- Filtra items por `activeMenuKeys` quando preview
- Sempre inclui Dashboard
- Usa lógica de role quando não é preview (sem regressão)

**PreviewInfoCard:**
- Renderiza colapsado e expandido
- "Leia mais" alterna estado
- `defaultExpanded` funciona

**CheckoutSheet:**
- Abre e fecha com animação
- Mostra dados do plano
- Loading state durante checkout

### Teste Manual (Instagram WebView)

Documentar checklist de teste manual:
- [ ] Abrir painel no Instagram WebView (iOS)
- [ ] Abrir painel no Instagram WebView (Android)
- [ ] Selecionar plano no sidebar
- [ ] Navegar entre páginas do plano
- [ ] Ver dados mock e info cards
- [ ] MobileChatBar mostra preview de mensagem
- [ ] Expandir chat, verificar teclado (header, width, scroll)
- [ ] Usar barrinha "Voltar pro site"
- [ ] Abrir checkout via CTA da página
- [ ] Abrir checkout via botão na MobileChatBar
- [ ] Checkout bottom-sheet funciona (scroll, cupom, botão pagamento)

---

## Observações importantes

- Priorizar testes dos cenários de regressão: a sidebar para users não-visitor NÃO pode mudar de comportamento.
- O teste manual no Instagram WebView é obrigatório — os bugs de teclado e width só aparecem lá.
- Para testar checkout end-to-end em staging, usar o modo sandbox do Asaas.

---

## Critérios de aceite

1. `bundle exec rspec` verde com novos specs
2. `npx vitest` verde com novos specs
3. Checklist de teste manual no Instagram WebView preenchido
4. Nenhuma regressão nos testes existentes
5. Coverage dos endpoints novos ≥ 90%

---

## Dependências

- Todas as tarefas anteriores (1-6)
