# Refactor N8N: GOAT LMA Architecture

**Sprint:** 1 - Core LMA
**Estimativa:** 0.5 dia
**Tipo:** Backend (N8N/Logic)

---

## Contexto
O workflow `goat/v1/router` (agora `goat/v1/lma`) foi refatorado para operar como um **Language Model Agent (LMA)** dedicado. Ao invés de lidar com webhooks crus, ele recebe um objeto `lead` normalizado e um histórico de mensagens, executa a inteligência (Classifier -> Agente Específico) e retorna as respostas geradas.

A parte inicial (Input -> Classifier -> Switch -> Agentes) já foi estruturada. O objetivo agora é padronizar o "final" do fluxo: a persistência dos dados alterados pelos agentes no backend (Rails) e o retorno estruturado para o chamador.

---

## Onde começa
- O workflow é acionado via `Execute Workflow Trigger`.
- Recebe `{ lead, messages }`.
- O `classifier` decide o estágio.
- O `switch` encaminha para `martha` (discovery), `anna` (enchantment) ou `maju` (closing).
- Os agentes retornam um JSON contendo `{ lead, messages, answers, extra }`.
- Os agentes convergem para o node `response` (Code Node) que unifica o output.

## Onde termina
- O `lead` atualizado pelo agente deve ser salvo no backend (`PUT /api/v1/leads/:id`).
- As novas mensagens (`answers`) devem ser salvas no backend (`POST .../messages/bulk`).
- O workflow deve retornar as `answers` para que o roteador principal envie ao usuário (WhatsApp/Insta).

---

## O que precisa ser feito

### 1. Conectar Persistência
Habilitar e conectar os nodes de persistência que estão desconectados/desabilitados no workflow atual.

#### Flow
`Agente` -> `response` -> `update lead` -> `update msgs` -> `End`

### 2. Node `response` (Code)
Já existente (`32771ec9...`). Garante que a saída seja:
```json
{
  "lead": { ...lead_atualizado... },
  "messages": [ ...mensagens_para_salvar_no_banco... ], // User msg + Agent answers
  "answers": [ ...apenas_texto_respostas... ],
  "extra": { ... }
}
```

### 3. Node `update lead` (HTTP Request)
- **ID:** `5883d790-4172-45d5-9901-42f66d51bffa`
- **Ação:** Ligar após `response`.
- **Status:** Enable.
- **Config:**
  - Method: `PUT`
  - URL: `{{BASE_URL}}/api/v1/leads/{{$json.lead.smart_id}}`
  - JSON Body: `{{ $json.lead }}` (Envia o objeto lead completo atualizado)
  - Auth: `bearer joy`

### 4. Node `update msgs` (HTTP Request)
- **ID:** `7a9daced-1d90-4c0c-b577-7ce07c7a48c8`
- **Ação:** Ligar após `update lead`.
- **Status:** Enable.
- **Config:**
  - Method: `POST`
  - URL: `{{BASE_URL}}/api/v1/leads/{{$('response').item.json.lead.smart_id}}/messages/bulk`
  - JSON Body: `{{ { "messages": $('response').item.json.messages } }}`
  - Auth: `bearer joy` (ou token de sistema)

### 5. Retorno do Workflow
O workflow deve terminar retornando os dados para o caller.
- Se usar `Execute Workflow Trigger`, o retorno é automático do último node.
- O último node será `update msgs`.
- O caller receberá o output do `update msgs` (que geralmente é o response da API Rails).
- **Ajuste:** Adicionar um node `Set` ou `Code` final para limpar a saída e retornar apenas o necessário para o roteador enviar a mensagem.
  - **Node Final:** `Output`
  - **Conteúdo:** `{ "answers": $('response').item.json.answers, "lead": $('response').item.json.lead }`

---

## Dependências
- API Rails endpoints (`PUT /leads/:id`, `POST /leads/:id/messages/bulk`) devem estar funcionando.
- Credenciais `bearer joy` configuradas no N8N.

## Observações
- A lógica de retry ou tratamento de erro nas chamadas de API deve ser considerada (ex: `Continue On Fail` para o `update lead` se for não-crítico, mas geralmente é crítico).
