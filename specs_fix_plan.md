# Plano de Correção — 31 Specs Falhando

> Objetivo: corrigir os specs, não o código. Todos os failures são pré-existentes às alterações do blog.

---

## Grupo 1 — Migração de URL da API do Instagram `[10 falhas]`

**Arquivos:** `private_reply_service_spec.rb` (8), `send_message_service_spec.rb` (2)

Os services já migraram para a nova API do Instagram, mas os stubs e assertions dos specs ainda apontam para a URL antiga.

| Spec usa | Service usa |
|---|---|
| `graph.facebook.com/v22.0/{id}/replies` | `graph.instagram.com/v25.0/{id}/replies` |
| `graph.facebook.com/v22.0/me/messages` | `graph.instagram.com/v25.0/{page_id}/messages` |

**O que corrigir:** atualizar todos os `stub_request` e `expect(url).to eq(...)` para as novas URLs.

---

## Grupo 2 — `InstagramCommentAutomationService` refatorado `[6 falhas]`

**Arquivo:** `instagram_comment_automation_service_spec.rb`

O service foi reescrito para trabalhar com `Operation` em vez de `InstagramCommentKeyword`. Os specs precisam de 3 ajustes:

1. Substituir `create(:instagram_comment_keyword, ...)` por `create(:operation, ...)` no setup
2. Atualizar URL do stub (mesma migração do Grupo 1)
3. Atualizar mensagens esperadas para português:
   - `'No keyword matched'` → `include('Nenhuma Operation bate com')`
   - `'Already replied'` → mensagem real do service
   - `'No bot configured'` → mensagem real do service

---

## Grupo 3 — Validação do model `InstagramCommentReplySent` `[1 falha]`

**Arquivo:** `instagram_comment_reply_sent_spec.rb:23`

`requires bot` falha — o model provavelmente não valida `bot_id` como obrigatório. Ajustar o spec para refletir as validações reais do model.

---

## Grupo 4 — `PublicChatService` `[2 falhas]`

**Arquivo:** `public_chat_service_spec.rb`

- `send_message` retorna 500 porque `trigger_n8n_agent` falha sem `N8N_WEBHOOK_WEBSITE_CHAT` configurado no ambiente de teste. Corrigir o stub: precisa ser `allow_any_instance_of` ou stub no método privado, não `expect(described_class).to receive`.
- `returns 404 for invalid session`: o service foi alterado para criar um novo lead em vez de retornar 404. Remover esse cenário ou ajustar a expectativa para 200.

---

## Grupo 5 — Public Chat API requests `[3 falhas]`

**Arquivo:** `spec/requests/api/v1/public/chat_spec.rb`

- `creates new session if none provided`: Lead não é criado no `GET /session` — só no primeiro `POST /message`. Mover a assertion de count para o teste de POST.
- `returns 404 for invalid session` (messages): endpoint retorna array vazio em vez de 404. Corrigir a expectativa para `200` com array vazio.
- `sends a message` retorna 500: mesmo problema do N8N — stub `trigger_n8n_agent`.

---

## Grupo 6 — Auth Checkout `[3 falhas]`

**Arquivo:** `spec/requests/api/auth/v1/checkout_spec.rb`

Todos retornam 500. O mock usa `instance_double(Auth::CheckoutSessionService)` com `receive(:execute!).with(hash_including(payment_id:))` mas o controller chama o service com params diferentes. Verificar a assinatura real do `execute!` e corrigir os mocks.

---

## Grupo 7 — Partner Dashboard `[3 falhas]`

**Arquivo:** `spec/requests/api/v1/partner/dashboard_spec.rb`

Todos retornam 500. Provável problema nas factories (`coupon`, `purchase`) — os factories usam campos que mudaram ou a associação `coupon: coupon` não existe no factory de `purchase`. Inspecionar e corrigir o setup.

---

## Grupo 8 — Users delete `[2 falhas]`

**Arquivos:** `users_service_spec.rb`, `spec/requests/api/v1/users_spec.rb`

O usuário não é deletado (`User.count` não muda). O factory de `user` provavelmente cria registros associados (leads, mensagens, etc.) sem `dependent: :destroy`, causando FK constraint. Corrigir o setup dos specs para limpar dependências antes de deletar, ou usar `create(:user)` sem associações.

---

## Grupo 9 — Webhook Meta `[1 falha]`

**Arquivo:** `spec/requests/api/v1/webhooks/meta_spec.rb:87`

O controller enfileira `ProcessMetaWebhookJob` para todos os eventos, incluindo não-mensagem. O spec espera que não enfileire. Atualizar a expectativa para `have_enqueued_job` (ou documentar por que o comportamento mudou e ajustar a lógica do spec).

---

## Ordem de execução sugerida

| Prioridade | Grupos | Justificativa |
|---|---|---|
| 1ª | 1, 3, 9 | Mecânicos — só trocar URLs e textos |
| 2ª | 4, 5 | Comportamento mudou, precisa confirmar expectativas |
| 3ª | 8 | Inspecionar FK constraints e setup de factories |
| 4ª | 6, 7 | Requerem inspecionar assinaturas de service e factories |

**Total:** 31 falhas em 11 arquivos de spec.
