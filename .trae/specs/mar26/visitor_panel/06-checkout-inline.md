# Tarefa 6: Checkout Adaptado para Visitor (Pré-preenchido + Overlay ou Navigate)

**Sprint:** 2 — Preview Experience
**Estimativa:** 1 dia
**Tipo:** Frontend (+ ajuste mínimo backend se necessário)

---

## Contexto

O checkout já existe em `/checkout/:identifier` e funciona de forma transparente: coleta dados pessoais (nome, email, whatsapp, CPF), método de pagamento (PIX ou cartão), processa via Asaas, recebe webhook de confirmação, cria sessão via `CheckoutSessionService`, sincroniza permissões e redireciona pro `/dashboard`. Tudo isso já está pronto.

O problema é que o visitor já está logado no painel — nome, email e whatsapp já são conhecidos. Pedir esses dados de novo é friccção desnecessária. Além disso, no Instagram WebView, um redirect para `/checkout/:identifier` pode ser problemático (o botão "voltar" do WebView é imprevisível).

A solução é uma das duas abordagens:

**Abordagem A (preferível):** Abrir o `CheckoutPage` como overlay/modal por cima da tela atual. Evita redirect, mantém contexto. O visitor vê o checkout flutuando sobre o painel.

**Abordagem B (fallback):** Navegar normalmente para `/checkout/:identifier` via React Router (sem hard redirect), passando dados do visitor via query params ou state. Garantir que o "voltar" funciona certinho no Instagram WebView.

Em ambos os casos: o plano já é conhecido (vem do `planPreviewStore`), nome/email/whatsapp já são conhecidos (vem do `authStore`). O step "cadastro" pode ser pulado ou auto-preenchido, indo direto para o step de pagamento.

---

## Onde começa

- `CheckoutPage.tsx` existe com 4 steps: cadastro → pagamento → revisão → confirmação
- Rota `/checkout/:identifier` configurada no `App.tsx`
- `chargesApi.create()` faz `POST /asaas/v1/payments/charges`
- `authApi.checkoutSession()` faz `POST /auth/v1/checkout/session`
- Webhook via `PaymentsChannel` (Action Cable) confirma pagamento em tempo real
- Auto-redirect para `/dashboard` após confirmação com countdown de 10s
- `planPreviewStore` tem `selectedPlan` com identifier
- `authStore` tem `user` com `name`, `email`, `phone`/`whatsapp`

## Onde termina

- Visitor acessa checkout com dados pré-preenchidos (pula step cadastro ou vai direto pro pagamento)
- Checkout abre por cima da tela (overlay) OU navega com "voltar" funcional
- Após compra confirmada: permissions sincronizam, sidebar sai do preview mode
- Fluxo usa exatamente as mesmas regras e endpoints do checkout existente

---

## O que precisa ser feito

### No Frontend

**Pré-preenchimento dos dados do visitor:**

O `CheckoutPage` já tem os states `buyerName`, `buyerEmail`, `whatsappValue`. Quando o visitor está logado, pré-preencher esses values a partir do `authStore.user`:
- `buyerName` ← `user.name`
- `buyerEmail` ← `user.email`
- `whatsappValue` ← `user.phone` ou `user.whatsapp`

Se todos os campos obrigatórios do step "cadastro" já estão preenchidos (nome, email, whatsapp), o checkout pode ir direto para o step "pagamento". O CPF é o único campo que pode não estar disponível — se não tiver, mostrar apenas o campo de CPF antes de ir pro pagamento.

**Abordagem A — Overlay/Modal:**

Criar um wrapper que renderiza o `CheckoutPage` dentro de um modal/drawer por cima da tela:
- O modal pode ser fullscreen no mobile (ocupa 100% da tela como o chat fullscreen)
- Botão "Fechar" / "Voltar pro painel" no topo — claro e acessível
- O `CheckoutPage` renderiza normalmente dentro do modal, só que sem o layout externo
- Pós-compra: em vez de `window.location.href = '/dashboard'`, fecha o modal e o painel já atualiza via Action Cable + PermissionsSyncService

Para isso, verificar se o `CheckoutPage` pode ser renderizado fora da rota `/checkout/:identifier` — se o `identifier` do plano pode ser passado via prop em vez de route param.

**Abordagem B — Navigate com state:**

Se o overlay for complexo demais, usar `navigate(`/checkout/${selectedPlan.identifier}`, { state: { fromPanel: true, prefill: { name, email, whatsapp } } })`.
- O `CheckoutPage` lê o `location.state` e pré-preenche
- Pós-compra: o redirect para `/dashboard` funciona normalmente
- Garantir que o botão "voltar" do browser/WebView volta pro painel (React Router já gerencia isso com `navigate`, não com `window.location.href`)

**Entry points para abrir o checkout:**
- CTA sticky no bottom das páginas preview (Tarefa 4)
- Botão "Comprar" na MobileChatBar (Tarefa 5)
- Botão no PlanSelector do sidebar (Tarefa 3)
- Todos passam o `selectedPlan.identifier` como parâmetro

**Pós-compra — saída do preview mode:**

Quando o `CheckoutSessionService` confirma a compra:
- O user type muda (visitor → client)
- `PermissionsSyncService` sincroniza permissões
- No frontend: o `authStore.user` atualiza (via refresh ou Action Cable)
- `isPreviewMode` no `planPreviewStore` se torna `false` (porque user_type_slug não é mais 'visitor')
- Sidebar volta ao modo normal automaticamente

Verificar se esse flow de atualização do user type já acontece naturalmente pelo `CheckoutSessionService` existente ou se precisa de um broadcast específico.

### No Backend (se necessário)

Provavelmente **nada muda** no backend. O `CheckoutSessionService` já:
- Cria/encontra user account
- Sincroniza permissões
- Retorna JWT tokens
- Muda user type baseado no plano comprado

O único ponto a verificar: quando o visitor já tem conta (está logado), o `ensure_user_account!` do purchase precisa linkar com o user existente em vez de criar um novo. Verificar se a lógica de "account existed BEFORE purchase (>2min)" funciona corretamente para visitors que já estão logados.

---

## Observações importantes

- O checkout existente já lida com PIX (QR code + webhook) e cartão (processamento + redirect). Não mexer nessa lógica.
- O countdown de 10s para redirect pós-compra faz sentido na página standalone. Se for overlay, trocar por feedback visual + fechar automaticamente.
- No Instagram WebView, o `window.location.href = '/dashboard'` funciona como redirect interno (SPA) se usar React Router. Mas se o checkout fizer hard redirect, pode dar problema. Preferir `navigate()` do React Router.
- O cupom de desconto pode vir pré-carregado do `localStorage` — o checkout existente já faz isso. Manter.

---

## Critérios de aceite

1. Visitor abre checkout com nome, email e whatsapp já preenchidos
2. Se todos os dados pessoais estão disponíveis, pula direto pro step de pagamento
3. Se falta CPF, mostra apenas campo de CPF antes do pagamento
4. Plano já vem selecionado (do `planPreviewStore`) — visitor não precisa escolher
5. Checkout usa exatamente os mesmos endpoints existentes (`chargesApi.create`, `authApi.checkoutSession`)
6. PIX funciona: QR code + webhook + confirmação
7. Cartão funciona: formulário + processamento + confirmação
8. Após compra, sidebar sai do preview mode e mostra menu real
9. "Voltar" funciona no Instagram WebView (volta pro painel, não fica preso)
10. Checkout abre a partir do CTA das páginas, MobileChatBar e PlanSelector

---

## Dependências

- Tarefa 3 (PlanSelector — para saber qual plano o visitor escolheu)
- Tarefa 4 (CTA nas páginas — entry point principal)
- CheckoutPage existente funcionando

## Próxima tarefa → Spec 07 (Testes)
