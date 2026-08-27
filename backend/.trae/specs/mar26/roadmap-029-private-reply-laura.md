# Roadmap: Private Reply (029.3/029.4) + Chatbot Laura

**Data:** 2026-03-23
**Branches:** `pkbot` (correções crash), `feature/laura-agent` (nova feat)

---

## 1. Diagnóstico do Crash

### Root Cause Confirmado

`PG::NotNullViolation` em `instagram_comment_reply_sents.bot_id`

O campo `bot_id` foi criado com `null: false` na migration original
(`20260310102708`), mas a nova lógica Operation-based
(`InstagramCommentAutomationService`) cria registros de deduplicação
**sem** `bot_id`. A migration `20260319120001` adicionou `integration_id`
mas esqueceu de tornar `bot_id` nullable.

**Efeito colateral:** o dedup nunca é gravado → cada comentário com
keyword dispara um DM, sem proteção contra spam.

### Outros bugs encontrados

| # | Bug | Severidade | Arquivo |
|---|-----|------------|---------|
| 1 | `bot_id` NOT NULL causa `NotNullViolation` no dedup | **Crítico** | migration + `instagram_comment_automation_service.rb` |
| 2 | `trigger_comment_automation` silencia-se quando `integration.bot_id` é nil | Alto | `process_meta_webhook_job.rb:403` |
| 3 | `build_messaging_body`: explicit `quick_replies` sobrescreve botões convertidos quando ambos presentes | Médio | `send_message_service.rb` |

---

## 2. Fase 1 — Correção do Crash (Este Sprint)

### Fix 1.1 — Migration: `bot_id` nullable

```
rails g migration MakeBotIdNullableOnInstagramCommentReplySents
```

```ruby
change_column_null :instagram_comment_reply_sents, :bot_id, true
```

**Arquivo:** `db/migrate/20260323XXXXXX_make_bot_id_nullable_on_instagram_comment_reply_sents.rb`

### Fix 1.2 — Guard de `bot_id` em `trigger_comment_automation`

**Antes:**
```ruby
return unless integration&.bot_id
```
**Depois:**
```ruby
return unless integration
```

A automação de comentários NÃO depende de bot configurado na integração.
Ela usa `Operation` para configurar replies. O `bot_id` era uma herança
da lógica de `InstagramCommentKeyword` (legada) e não faz sentido aqui.

### Fix 1.3 — `build_messaging_body`: merge quick_replies

Quando `@buttons` são convertidos para `quick_replies` no Instagram e
`@quick_replies` explícitas também existem, mesclar em vez de sobrescrever.
(Atualmente o bloco `@quick_replies` vai sobrescrever o array anterior.)

---

## 3. Fase 2 — Spec 029 Revisada (Próxima semana)

### Clarificação de nomenclatura

| Service | Endpoint Meta | Visibilidade |
|---------|---------------|--------------|
| `PublicCommentReplyService` | `POST /{comment_id}/replies` | **Público** — visível no thread |
| `PrivateReplyService` | `POST /{comment_id}/replies` + `Authorization` | ⚠️ MESMO endpoint que public! |
| `SendMessageService` com `comment_id` | `POST /{ig_user_id}/messages` + `recipient.comment_id` | **Privado** — DM invisível |

**Ação:** `Meta::PrivateReplyService` deve ser renomeado ou eliminado em
favor de `Meta::SendMessageService` com `comment_id`. O nome "Private Reply"
é correto para o resultado (DM), mas o service usa endpoint errado.

**Solução adotada pelo commit anterior (correta):**
`InstagramCommentAutomationService#send_private_dm` → usa `SendMessageService`
com `comment_id:` → isso abre uma DM privada. ✅

### Validar critérios de aceite da spec 029.4

1. Comentário sem keyword → não salva dedup, não dispara API ✅ (já funciona)
2. Comentário com keyword → salva dedup, dispara private DM ✅ (após Fix 1.1)
3. Mesmo payload repetido → `RecordNotUnique` rescue → não duplica DM ✅ (após Fix 1.1)

---

## 4. Fase 3 — Chatbot Laura (Este Sprint)

### Proposta

**Laura** é uma AI Agent para o AI9 (plataforma GOAT). Ela atende leads
via Instagram DM e WhatsApp quando o usuário responde a um private reply
de comentário, guiando-os até a conversão.

### Persona

| Campo | Valor |
|-------|-------|
| Nome | Laura |
| Papel | Especialista em Soluções — AI9 / GOAT |
| Tom | Profissional, amigável, direta |
| Avatar | `/laura-avatar.svg` |
| Idioma | Português BR |

### Agent Config (estrutura)

```json
{
  "model": "gpt-4o",
  "temperature": 0.4,
  "max_tokens": 600,
  "top_p": 1,
  "presence_penalty": 0.2,
  "frequency_penalty": 0.3,
  "extract_lead": true,
  "tools_enabled": true,
  "welcome_message": "Oi! Aqui é a Laura, do time AI9. Vi que você tem interesse — posso te explicar melhor?",
  "system_prompt": "..."
}
```

### System Prompt (esboço)

Laura conhece:
- **AI9/GOAT**: SaaS omnichannel + chatbot + CRM de leads
- **Canais suportados**: Instagram DM, WhatsApp (Evolution + WABA), Messenger, Web Chat
- **Automações**: Comment-to-DM (spec 029), Flow Engine, AI Agent
- **Planos**: apresenta planos disponíveis sem citar preços (direcionar para fechar)
- **Objetivos**: qualificar lead, capturar nome/telefone/email, agendar demo

### Arquivos a criar

- `db/seeds/laura_agent.rb` — seed idempotente
- `db/seeds/laura_flow.json` — fallback chatbot simples (caso AI off)

### Ativação

Após seed:
```ruby
# No console / seed de integrations
Integration.where(platform: 'instagram').update_all(bot_id: ChatFlow.find_by(name: 'laura-ai9').id)
Integration.where(platform: ['waba', 'messenger']).update_all(bot_id: ChatFlow.find_by(name: 'laura-ai9').id)
```

---

## 5. Fase 4 — Spec 029.5: UI de Keywords (Futuro)

Interface administrativa para gerenciar `Operations` com:
- Toggle de `private_reply_enabled`
- Editor de `private_reply_dm_text` + `private_reply_dm_buttons`
- Editor de `public_reply_messages` (spin-tax)
- Preview de template de DM

**Dependência:** Fases 1–3 finalizadas e testadas em produção.

---

## Resumo de Entregas

| Fase | Entrega | Prazo |
|------|---------|-------|
| 1 | Crash fix (3 bugs) | Hoje |
| 2 | Spec 029 revisada + testes | Esta semana |
| 3 | Laura AI Agent seed + ativação | Esta semana |
| 4 | UI 029.5 | Próximo sprint |
