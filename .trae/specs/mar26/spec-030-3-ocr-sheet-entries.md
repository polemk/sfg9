# Tarefa 030.3: OCR de Folha → Lançamentos em Lote

**Sprint:** 2 — Agente Nathy Nativo
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto

No n8n (`dsl-router-v1`), quando o usuário enviava uma imagem,
o nó "Claude Vision OCR" extraía os dados. No `comandae`, o agente
Nathy recebe uma foto de folha de caixa ou extrato, **lê as linhas**,
confirma com o usuário e **lança cada linha como `Entry`**.

Este é um dos diferenciais mais importantes: foto de papel com
anotações → sistema digitaliza tudo automaticamente.

---

## Onde começa

- `AgentService.respond` já aceita `image_data: { base64, mime_type }`
- `Cmx::CreateEntry` (Spec 030.2) implementada
- Providers (Anthropic/OpenAI/Google) já suportam multimodal

## Onde termina

- Imagem de folha → agente lista entradas identificadas → confirmação → `Entry` records criados

---

## Fluxo

```
Usuário envia foto de folha (WhatsApp/Widget)
        ↓
InboundProcessor detecta imagem → passa image_data ao AgentService
        ↓
Agente (LLM multimodal) interpreta a imagem e extrai linhas:
  "Encontrei os seguintes lançamentos:
   1. Compra de insumos: R$320 (despesa) — 12/03
   2. Venda de marmitas: R$1.200 (receita) — 12/03
   Confirmo os lançamentos? (sim/não)"
        ↓
Usuário confirma → agente chama `batch_create_entries`
```

---

## O que precisa ser feito

### 1. Detecção de imagem nos webhooks

Em `messages-upsert` (Evolution), detectar `mediaType == "image"` e:
1. Baixar imagem como base64
2. Passar `image_data` para `AgentService.respond`

O `AgentService` já roteia para o provider multimodal.

### 2. Tool `Cmx::BatchCreateEntries`

```
backend/app/services/ai/tools/cmx/batch_create_entries.rb
```

```ruby
DEFINITION = {
  name: "batch_create_entries",
  description: "Cria múltiplos lançamentos de uma vez. Usado após extrair dados de uma imagem.",
  parameters: {
    type: "object",
    properties: {
      entries: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            value: { type: "number" },
            entry_type: { type: "string", enum: %w[income expense] },
            balance_date: { type: "string", description: "YYYY-MM-DD" }
          },
          required: %w[title value entry_type balance_date]
        }
      }
    },
    required: ["entries"]
  }
}.freeze
```

- Cria `Entry.create!` para cada item com `source_type: "manual"`
- Retorna sumário do que foi criado

### 3. System prompt da Nathy (instrução OCR)

Adicionar ao prompt instruções sobre como tratar imagens de folhas:
```
Quando receber uma imagem com anotações financeiras:
1. Extraia as linhas visíveis (título, valor, tipo receita/despesa, data)
2. Apresente o resumo para confirmação do usuário
3. Após confirmação, chame `batch_create_entries` com o array
```

---

## Critérios de aceite

1. Foto de papel com 3–5 linhas → agente lista e pede confirmação
2. Após "sim", `Entry` records criados com `source_type: "manual"`
3. Imagem sem dados financeiros → agente informa que não identificou
4. Teste: mock de `image_data` → verificar chamada da tool

---

## Dependências

- Spec 030.2 (`Cmx::CreateEntry` implementada)
- Provider multimodal funcionando

## Próxima tarefa → Spec 030.4
