# Roadmap: Agente CMX Nativo (n8n → ChatFlow)

**Projeto:** comandae (branch: pkbot → main)
**Estimativa:** 8–12 dias úteis
**Referência:** `dsl-router-v1` (workflow n8n) → re-implementado como `ai_agent` ChatFlow nativo

---

## Contexto

O workflow `dsl-router-v1` implementa "Nathy" — agente financeira para restaurantes —
que hoje opera via n8n + API legada DSL. O objetivo é mover toda a lógica
para dentro do `comandae` usando `ChatFlow (kind: ai_agent)` + `Ai::AgentService` + `ToolExecutor`.

---

## Mapa n8n → Código Nativo (CMX)

| Nó n8n | Equivalente CMX |
|---|---|
| Webhook Evolution | `ProcessEvolutionWebhookJob` (já existe) |
| Switch: tipo de mídia | Novo: detecção `mediaType` antes do InboundProcessor |
| Download + Whisper STT | `Ai::AudioTranscriptionService` (novo) |
| Download + Claude OCR | `Ai::ImageOcrService` (novo) |
| goat AI Agent (LangChain) | `ChatFlow (ai_agent)` + `Ai::AgentService` (já existe) |
| Postgres Chat Memory | `LeadMessage` history (já existe) |
| dsl/v1/mcp (toolbox) | `Ai::Tools::Cmx::*` (novo — ver tabela abaixo) |
| Respond | `Omnichannel::DispatchService` (já existe) |

---

## Modelo de Contexto do Agente

O agente **não depende de operação como contexto obrigatório**.
A resolução ocorre automaticamente pelo número de telefone:

```
Mensagem chega (WhatsApp / IG / Widget)
        ↓
Buscar usuário pelo número de telefone/conta
        ↓
  ┌─ Usuário encontrado ──→ usa dados do restaurante daquele usuário
  └─ Não encontrado ────→ trata como Lead → tenta converter para conta
```

`Operation` serve apenas como **base de configuração para múltiplos agentes** —
ex: uma operação "FAQ Comandae" com agente explicando como usar o app.
Não é mencionada ao usuário nem necessária para o funcionamento base.

---

## UX: Agentic Mode (sem esfera flutuante)

- **Remover** a esfera/botão flutuante do lado direito
- **Adicionar item "Modo Agente"** no menu principal (igual ao implementado no `pkbot`)
- **Chat sidebar persistente** disponível enquanto o usuário navega no desktop

---

## Tools CMX: mapeamento das APIs reais

### `entries` (write + read) — fluxo de caixa pontual

| Tool | Operação |
|---|---|
| `Cmx::ListEntries` | Listar por período (`date_start`, `date_end`) |
| `Cmx::CreateEntry` | Lançar entrada (`title`, `value`, `entry_type`, `balance_date`) |
| `Cmx::UpdateEntry` | Editar lançamento manual |
| `Cmx::DeleteEntry` | Remover lançamento manual |

### `balances` (read-only) — consolidado

| Tool | Operação |
|---|---|
| `Cmx::GetDailyBalance` | Saldo de um dia |
| `Cmx::GetMonthlyBalance` | Saldo do mês |
| `Cmx::GetYearlyBalance` | Saldo anual |
| `Cmx::GetPeriodBalance` | Período customizado (até 6 meses) |
| `Cmx::GetExpensesByDescription` | Despesas agrupadas por descrição |

### `products` (read-only) + OCR

| Tool | Operação |
|---|---|
| `Cmx::ListProducts` | Listar produtos |
| `Cmx::OcrSheetToEntries` | Foto de folha → Claude Vision → `CreateEntry` em lote |

> **Regra:** agente trabalha com `entries` e `balances`. Nunca consulta `sales` do PDV.

---

## Sprint 1 — Suporte a Áudio em TODOS os Canais (3–4 dias)

Canais: WABA/Evolution, Instagram DM, Messenger, **AI Chat Widget**

1. `Ai::AudioTranscriptionService` — download + Whisper STT
2. Detecção de áudio nos webhooks (Evolution + Meta)
3. Endpoint `POST /api/v1/public/chat/audio` para o widget

---

## Sprint 2 — Agente Nathy + CMX Tools (4–5 dias)

1. CMX Tool Registry (Entries CRUD + Balances read-only)
2. OCR de folha → lançamentos em lote (`Cmx::OcrSheetToEntries`)
3. Resolução de contexto: telefone → usuário/restaurante ou fluxo de lead
4. Seed do ChatFlow "Nathy" com system prompt + context injection

---

## Sprint 3 — Agentic Mode + Widget de Voz (2–3 dias)

1. Remover esfera flutuante; adicionar "Modo Agente" no menu
2. Chat sidebar persistente no desktop
3. Microfone no widget (`MediaRecorder API` → upload)

---

## Specs (geradas sob demanda)

| Spec | Tema | Estimativa |
|---|---|---|
| **030.1** | AudioTranscriptionService + 4 canais | 1 dia |
| **030.2** | CMX Tool Registry (Entries + Balances) | 1.5 dias |
| **030.3** | OCR Sheet → CreateEntry em lote | 1 dia |
| **030.4** | Context Resolution: telefone → usuário ou lead | 0.5 dia |
| **030.5** | ChatFlow Nathy: seed + system prompt | 0.5 dia |
| **030.6** | Agentic Mode: menu item + sidebar persistente | 1 dia |
| **030.7** | Widget de Voz: endpoint + MediaRecorder | 1 dia |
