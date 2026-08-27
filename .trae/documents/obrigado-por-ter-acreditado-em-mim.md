# GOAT LMA - Especificação Técnica v2.0

> **Operação:** GOAT (base de código para micro SaaS)  
> **Workflows:** `goat/v1/router` (ID: wpitrqLj7LL2O3jT) → `goat/v1/lma` (ID: Ou9Luh1RvbMB3slU)  
> **API Base:** https://api-goat.polemk.com  
> **Data:** 2026-01-16

---

## 1. VISÃO GERAL DO FLUXO

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           goat/v1/router                                     │
│  (ID: wpitrqLj7LL2O3jT - 87 nodes)                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ENTRADAS (webhooks):                                                        │
│  ├── on instagram    → /webhook/goat/v1/router/instagram                    │
│  ├── on facebook     → /webhook/788207ec-44fd-4a85-a7b9-0714bd005495        │
│  ├── on waba         → /webhook/goat/v1/router/waba                         │
│  ├── on whats        → /webhook/4d67dcec-7ba0-476f-8457-6ee06505f883        │
│  ├── on test         → chat trigger interno                                 │
│  └── on api          → /webhook/goat-api  (website chat)                    │
│                                                                              │
│  FLUXO:                                                                      │
│  1. webhook recebe msg → parser normaliza (*/message nodes)                 │
│  2. joy/not_self → filtra msgs do próprio bot                               │
│  3. joy/lead → POST /api/v1/leads (cria/atualiza lead)                      │
│  4. joy/parser → monta objeto com smart_id, operation_key                   │
│  5. joy/is_categorized → se já tem operation_key, segue                     │
│  6. joy/operation → POST /api/v1/operations/validate                        │
│  7. joy/categorize → define operation_key (goat|smart|tetris|unknown)       │
│  8. joy/current? → race condition check (GET /leads/{id}/executions)        │
│  9. joy/presence → envia "typing" pro canal                                 │
│  10. joy/teams → switch por operation_key                                   │
│      └── goat → joy/goat (Execute Workflow: Ou9Luh1RvbMB3slU)              │
│                                                                              │
│  SAÍDA DO LMA:                                                               │
│  11. joy/output → prepara lead + messages                                   │
│  12. joy/current?2 → race condition final                                   │
│  13. update lead → PUT /api/v1/leads/{smart_id}                             │
│  14. update msgs → POST /api/v1/leads/{id}/messages/bulk                    │
│  15. joy/answers → extrai msgs do agente                                    │
│  16. joy/each → loop por resposta                                           │
│  17. joy/answer → switch por source_type → envia resposta no canal          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            goat/v1/lma                                       │
│  (ID: Ou9Luh1RvbMB3slU - 49 nodes)                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ENTRADA (via Execute Workflow):                                             │
│  { lead: <objeto completo do lead> }                                        │
│                                                                              │
│  FLUXO INTERNO:                                                              │
│  1. on new message / unbundle → recebe lead                                 │
│  2. var session → prepara lead                                              │
│  3. fetch msgs → GET /api/v1/leads/{smart_id}/messages                      │
│  4. Aggregate → junta msgs                                                  │
│  5. parse lead w history → formata { lead, messages[], messages_str }       │
│  6. classifier (ADAM) → decide stage + next_agent                           │
│  7. Code → extrai output                                                    │
│  8. Switch → roteia para agente (discovery|enchantment|closing)             │
│  9. [AGENTE] → processa e gera resposta                                     │
│  10. response → monta { lead, messages[], extra }                           │
│                                                                              │
│  SAÍDA:                                                                      │
│  {                                                                           │
│    "lead": { ...lead atualizado },                                          │
│    "messages": [ { sender_role, content, agent_type, ... } ],               │
│    "extra": { reason, decision, proposal? }                                 │
│  }                                                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. PRODUTOS E PLANOS

> **Fonte:** `GET /api/v1/plans` (API existente)

| Plano | Preço | Tipo | Descrição |
|-------|-------|------|-----------|
| **DevOps Full Fog™ 3000** | R$ 3.000 | one_time | Infraestrutura completa, deploy automatizado, CI/CD |
| **GOAT Suporte™ 7500** | R$ 7.500 | one_time | Suporte técnico + documentação completa do código |

---

## 3. DIFERENCIAIS GOAT - 10 RECURSOS CONSTRUÍDOS

Estes são exemplos concretos de funcionalidades que a base GOAT já traz prontas:

| # | Recurso | Descrição | Benefício |
|---|---------|-----------|-----------|
| 1 | **Sistema de Leads Unificado** | API completa para CRUD de leads com smart_id único | Rastreia prospects de qualquer canal num único lugar |
| 2 | **Histórico de Mensagens** | Armazenamento e busca de todas interações | Contexto completo em qualquer conversa |
| 3 | **Autenticação JWT** | Sistema de auth pronto com tokens, refresh, roles | Segurança enterprise sem reinventar a roda |
| 4 | **Webhooks Omnichannel** | Receivers prontos para WhatsApp, Instagram, Messenger, WABA | Integra qualquer canal em minutos |
| 5 | **Race Condition Prevention** | Sistema de executions para evitar processamento duplicado | Múltiplas mensagens simultâneas sem conflito |
| 6 | **Operations Classifier** | Roteamento inteligente por palavra-chave/contexto | Direciona leads para o workflow correto |
| 7 | **Checkout Tracking** | Sistema de links de pagamento rastreados | Atribui vendas ao lead correto automaticamente |
| 8 | **Multi-Source Unification** | Mesmo lead em vários canais = 1 registro | Visão 360° do cliente |
| 9 | **Swagger Auto-Generated** | Documentação API sempre atualizada | Onboarding de devs instantâneo |
| 10 | **Vector Store Integration** | Conexão pronta com PGVector para RAG | IA contextual sem setup complexo |

---

## 4. DIFERENCIAIS GOAT - 10 FACILIDADES

Estes são os ganhos práticos de usar a base GOAT:

| # | Facilidade | Do Zero | Com GOAT | Economia |
|---|------------|---------|----------|----------|
| 1 | **Setup inicial de projeto** | 2-3 dias | 10 minutos | ~95% |
| 2 | **Integração WhatsApp** | 1 semana | 1 hora | ~95% |
| 3 | **Sistema de autenticação** | 3-5 dias | Pronto | 100% |
| 4 | **API RESTful completa** | 2-4 semanas | Pronto | 100% |
| 5 | **Deploy automatizado** | 1-2 dias | Pronto | 100% |
| 6 | **Documentação Swagger** | 2-3 dias | Automático | 100% |
| 7 | **Testes de integração** | 1 semana | Parcialmente pronto | ~70% |
| 8 | **Monitoramento/Logs** | 2-3 dias | Pronto | 100% |
| 9 | **Multi-tenancy** | 1-2 semanas | Arquitetura pronta | ~90% |
| 10 | **Escala horizontal** | 1 semana | Configurado | ~95% |

**Resumo:** Projetos que levariam 2-3 meses do zero ficam prontos em 1-2 semanas com a base GOAT.

---

## 5. AGENTES - SPECS COMPLETAS

### 5.1 ADAM (Classifier)

**Função:** Decide o próximo estágio e orienta o próximo agente.

**Regras de Decisão:**
```
SE discovery_level < 3 → current_stage = "discovery", next_agent = "martha"
SENÃO SE enchantment_level < 5 → current_stage = "enchantment", next_agent = "anna"
SENÃO → current_stage = "closing", next_agent = "maju"
```

**Cálculo de Níveis:**
- `discovery_level` ∈ {0..3}: conta preenchidos em {name, ig_username, phone OU email}
  - name = 1 ponto
  - ig_username = 1 ponto (OBRIGATÓRIO)
  - phone OU email = 1 ponto
  - company_name é OPCIONAL (não conta)
  - **Precisa de 3 pontos para sair do discovery**

**Campos que ADAM edita:**
- `current_stage`
- `intention`
- `instruction`

**Output Schema:**
```json
{
  "lead": { "...lead completo com current_stage/intention/instruction ajustados" },
  "messages": [ "...cópia exata do array de entrada" ],
  "extra": {
    "reason": "1-2 linhas explicando a decisão",
    "next_agent": "martha|anna|maju"
  }
}
```

---

### 5.2 MARTHA (Discovery)

**Função:** Coleta dados mínimos do lead sem encher o saco.

**Campos OBRIGATÓRIOS para sair do Discovery:**
1. `name` - nome da pessoa
2. `ig_username` - @ do Instagram (OBRIGATÓRIO!)
3. `phone` OU `email` - precisa de pelo menos um

**Campos OPCIONAIS:**
- `company_name` - pergunta UMA vez só

**Campos que MARTHA edita:**
- `intention`, `instruction`
- `name`, `email`, `phone`, `ig_username`
- `company_name`
- `desires[]` (adiciona, nunca sobrescreve)

**Campos REMOVIDOS (não existem mais):**
- ~~has_site~~, ~~site_url~~, ~~site_scrapped_text~~

**Output Schema:**
```json
{
  "lead": { "...lead completo com campos de discovery atualizados" },
  "messages": [ "...cópia exata" ],
  "answers": [ "frase 1", "frase 2" ],
  "extra": {
    "reason": "quais campos preencheu e por quê",
    "decision": "keep_discovery|handoff_to_classifier_request_price|null"
  }
}
```

---

### 5.3 ANNA (Enchantment)

**Função:** Aprofunda interesse mostrando valor da base GOAT.

**Campos de Encantamento GOAT (novos):**
| Campo | Descrição |
|-------|-----------|
| `understands_goat_architecture` | Entende arquitetura modular |
| `understands_time_saved` | Entende economia de tempo vs do zero |
| `understands_omnichannel` | Entende que é multi-canal |
| `likes_devops_fog` | Gostou do DevOps Full Fog 3000 |
| `likes_goat_support` | Gostou do GOAT Suporte 7500 |
| `likes_some_microsaas` | Gostou de algum exemplo de micro SaaS |
| `knows_api_structure` | Conhece estrutura da API |
| `knows_documentation` | Sabe que tem documentação completa |

**Campos ANTIGOS (ignorar - eram para sites):**
- ~~knows_obj_site~~, ~~knows_pac_site~~, ~~knows_kpa_site~~
- ~~understands_smart_navigation~~
- ~~likes_some_site~~, ~~likes_some_app~~
- ~~knows_console_mod~~, ~~knows_whats_mod~~

**Campos que ANNA edita:**
- `intention`, `instruction`
- Todos os `understands_*`, `knows_*`, `likes_*` do GOAT
- `knows_own_demand`
- `desires[]`

**Output Schema:**
```json
{
  "lead": { "...lead com campos de enchantment atualizados" },
  "messages": [ "...cópia exata" ],
  "answers": [ "frase 1", "frase 2" ],
  "extra": {
    "reason": "o que atualizou e por quê",
    "decision": null,
    "proposal": null
  }
}
```

---

### 5.4 MAJU (Closing)

**Função:** Facilita fechamento quando lead já está pronto.

**Filosofia:** DO NOT SELL - WE DON'T NEED
- Não vende. Facilita.
- Trabalho pesado já foi feito por Martha e Anna.
- Objetiva, persuasiva, humor irônico leve.

**Fluxo Ideal:**
1. Confirma prontidão real
2. Apresenta plano que faz sentido
3. Mostra PREÇO antes do LINK
4. Confirma entendimento
5. Envia link de checkout

**Campos que MAJU edita:**
- `current_stage` (manter "closing")
- `intention`, `instruction`
- `validated_interest`, `understands_value`
- `received_proposal`, `gave_feedback`, `ready_to_schedule`

**Output Schema:**
```json
{
  "lead": { "...lead com campos de closing atualizados" },
  "messages": [ "...cópia exata" ],
  "answers": [ "frase 1", "frase 2" ],
  "extra": {
    "reason": "explicação da decisão",
    "decision": "send_proposal|ask_info|back_to_anna|waiting_confirmation",
    "proposal": {
      "plan_name": "DevOps Full Fog 3000|GOAT Suporte 7500",
      "price_total": 3000,
      "currency": "BRL",
      "checkout_url": "https://...",
      "discount_percent": null,
      "discount_reason": null
    }
  }
}
```

---

## 6. API ENDPOINTS UTILIZADOS

### 6.1 Endpoints Existentes (funcionando)

| Método | Endpoint | Uso |
|--------|----------|-----|
| POST | `/api/v1/leads` | Criar/buscar lead (router) |
| PUT | `/api/v1/leads/{smart_id}` | Atualizar lead (router) |
| GET | `/api/v1/leads/{smart_id}/messages` | Buscar histórico (LMA) |
| POST | `/api/v1/leads/{id}/messages/bulk` | Salvar msgs (router) |
| POST | `/api/v1/operations/validate` | Classificar operação (router) |
| GET | `/api/v1/leads/{id}/executions?execution_id={id}` | Race condition (router) |
| GET | `/api/v1/plans` | Listar planos (Maju) |

### 6.2 Endpoint Necessário (implementar)

| Método | Endpoint | Uso |
|--------|----------|-----|
| POST | `/api/v1/checkout/generate_url` | Gerar link trackeado (Maju) |

**Request:**
```json
{
  "lead_id": "LD-XXXXXX",
  "plan_id": 1,
  "discount_percent": 10,
  "discount_reason": "primeira compra"
}
```

**Response:**
```json
{
  "checkout_url": "https://pay.goat.polemk.com/c/abc123",
  "expires_at": "2026-01-17T00:00:00Z"
}
```

---

## 7. VECTOR STORE - CONTEÚDO GOAT

**Tabela:** `goat_enchantment_vectors`

### 7.1 Conteúdo a Popular

O vector store precisa ser alimentado com documentos sobre:

1. **Arquitetura GOAT**
   - Estrutura de pastas
   - Padrões de código (Rails)
   - Modules e concerns

2. **API Reference**
   - Todos os endpoints
   - Schemas de request/response
   - Exemplos de uso

3. **10 Recursos** (listados na seção 3)
   - Descrição detalhada de cada
   - Como usar
   - Benefícios

4. **10 Facilidades** (listadas na seção 4)
   - Comparação do zero vs GOAT
   - Casos de uso

5. **Integrações Omnichannel**
   - WhatsApp (WABA + Evolution)
   - Instagram
   - Messenger
   - Website chat

6. **DevOps Full Fog 3000**
   - O que inclui
   - Como funciona
   - Valor agregado

7. **GOAT Suporte 7500**
   - O que inclui
   - Documentação
   - Suporte técnico

### 7.2 Como Popular

Via formulário no workflow:
```
URL: /form/b2721c78-e010-4878-b8fa-924276400433
Aceita: .txt, .md, .csv, .rb, .doc, .docx, .pdf, .xls, .xlsx, .html
```

---

## 8. CORREÇÕES NECESSÁRIAS NO WORKFLOW

### 8.1 goat/v1/lma (Ou9Luh1RvbMB3slU)

| Node | Status | Problema | Solução |
|------|--------|----------|---------|
| `response` | ⚠️ | Conexão `main: [[]]` (vazio) | Este é o terminal node - OK, n8n retorna output do último node sem conexões |
| `update lead` | ❌ Disabled | Era para persistir no LMA | MANTER disabled - o ROUTER faz isso agora |
| `update msgs` | ❌ Disabled | Era para persistir no LMA | MANTER disabled - o ROUTER faz isso agora |
| `chat answer` | ❌ Disabled | Não usado | MANTER disabled - legado |
| `fetch lead` | ❌ Disabled | URL antiga | MANTER disabled - o ROUTER já traz o lead |
| `fetch msgs` | ✅ OK | URL api-goat | Busca histórico de mensagens |

**IMPORTANTE:** O node `response` com `main: [[]]` está CORRETO. No n8n, quando um sub-workflow é chamado com "Wait for Sub-Workflow", o output retornado é o último node executado que não tem conexões de saída. O `response` é esse node terminal.

**Verificar se o output do `response` está no formato correto:**
```json
{
  "lead": { "...lead completo atualizado" },
  "messages": [
    { "sender_role": "user", "content": "...", "agent_type": "..." },
    { "sender_role": "agent", "content": "...", "agent_type": "..." }
  ],
  "extra": { "reason": "...", "decision": "...", "proposal": null }
}
```

### 8.2 goat/v1/router (wpitrqLj7LL2O3jT)

| Node | Status | Observação |
|------|--------|------------|
| `joy/goat` | ✅ OK | Chama workflow correto (Ou9Luh1RvbMB3slU) |
| `joy/output__goat` | ✅ OK | Conecta à saída |
| `update lead` | ✅ OK | Habilitado, URL api-goat.polemk.com |
| `update msgs` | ✅ OK | Habilitado |
| `joy/answers` | ✅ OK | Extrai mensagens do agente |

### 8.3 Conexão Critical Fix

O node `response` no LMA precisa estar conectado para que o output chegue ao router:

```
[discovery/martha] ─┐
[enchantment/anna] ─┼──► [response] ──► [OUTPUT DO WORKFLOW]
[closing/maju] ─────┘
```

**Atualmente:** `response` conecta a nada (`[]`)
**Corrigir:** Conectar response ao output do Execute Workflow Trigger

---

## 9. CAMPOS DO LEAD - MAPEAMENTO COMPLETO

### 9.1 Campos de Identificação (READ-ONLY)
```
id, smart_id, session_uuid, source_type, source_id, target_id,
source_endpoint, all_sources, created_at, updated_at,
is_categorized, unified_from_channels, operation_id, operation_key,
sources_description, content, content_type, content_id
```

### 9.2 Campos de Contato (MARTHA edita)
```
name, email, phone, ig_username, igs_id, fb_username, fb_id, company_name
```

### 9.3 Campos de Progresso (controlados por estágio)
```
current_stage, intention, instruction, desires[],
discovery_level, enchantment_level, closing_level
```

### 9.4 Campos de Encantamento GOAT (ANNA edita)
```
understands_goat_architecture, understands_time_saved, understands_omnichannel,
likes_devops_fog, likes_goat_support, likes_some_microsaas,
knows_api_structure, knows_documentation, knows_own_demand
```

### 9.5 Campos de Closing (MAJU edita)
```
validated_interest, understands_value, received_proposal,
gave_feedback, ready_to_schedule
```

### 9.6 Campos Contadores (calculados)
```
enchantment_criteria_count, closing_criteria_count
```

### 9.7 Campos DEPRECADOS (ignorar)
```
has_site, site_url, site_scrapped_text,
understands_smart_navigation, understands_thats_exclusive, understands_thats_memorable,
likes_some_site, likes_some_app,
knows_obj_site, knows_pac_site, knows_kpa_site,
knows_console_mod, knows_whats_mod
```

---

## 10. CHECKLIST DE IMPLEMENTAÇÃO

### 10.1 Alta Prioridade

- [ ] **API:** Adicionar campos GOAT ao model Lead (migration)
  - understands_goat_architecture
  - understands_time_saved
  - understands_omnichannel
  - likes_devops_fog
  - likes_goat_support
  - likes_some_microsaas
  - knows_api_structure
  - knows_documentation

- [ ] **API:** Implementar endpoint `POST /api/v1/checkout/generate_url`

- [ ] **Workflow:** Conectar output do node `response` no LMA

- [ ] **Vector Store:** Popular `goat_enchantment_vectors` com:
  - 10 recursos (seção 3)
  - 10 facilidades (seção 4)
  - Documentação da API
  - Docs do DevOps Full Fog
  - Docs do GOAT Suporte

### 10.2 Média Prioridade

- [ ] **API:** Verificar/criar planos (DevOps Fog 3000, GOAT Suporte 7500)

- [ ] **Workflow:** Ativar goat/v1/lma (`active: true`)

- [ ] **Workflow:** Testar fluxo completo:
  1. Enviar msg via webhook goat-api
  2. Verificar lead criado
  3. Verificar classifier funcionando
  4. Verificar agente respondendo
  5. Verificar update lead/msgs

### 10.3 Baixa Prioridade

- [ ] **API:** Deprecar campos antigos (mark as legacy)
- [ ] **Workflow:** Limpar nodes não usados
- [ ] **Docs:** Documentar endpoints no Swagger

---

## 11. TESTE DO FLUXO

### 11.1 Payload de Teste (via webhook goat-api)

```json
POST /webhook/goat-api
{
  "session_uuid": "test-123",
  "content": "oi, quero saber mais sobre a base goat",
  "content_type": "text",
  "lead_info": {
    "name": "Teste",
    "phone": "5549999350244"
  }
}
```

### 11.2 Fluxo Esperado

1. `on api` recebe webhook
2. `api/message` normaliza payload
3. `joy/not_self` deixa passar
4. `joy/lead` cria lead via API
5. `joy/parser` monta objeto
6. `joy/is_categorized` → false (novo lead)
7. `joy/operation` → valida "goat" na msg
8. `joy/categorize` → operation_key = "goat"
9. `joy/current?` → OK (nova execução)
10. `joy/presence` → api/presence (typing_on)
11. `joy/teams` → roteia para `joy/goat`
12. **LMA executa:**
    - ADAM classifica → discovery (lead novo)
    - Martha responde → pede ig_username
13. Router recebe output
14. `update lead` → persiste
15. `update msgs` → salva mensagens
16. `joy/answers` → extrai respostas
17. `api/answer` → callback pro frontend

---

## 12. RESUMO EXECUTIVO

**O que temos:**
- Router funcionando com todos os canais
- LMA com 4 agentes (Adam, Martha, Anna, Maju)
- API com CRUD de leads e mensagens
- Vector store configurado

**O que falta:**
1. Campos GOAT na API (migration simples)
2. Endpoint de checkout tracking
3. Conectar output do `response` node
4. Popular vector store com conteúdo GOAT
5. Ativar workflow e testar

**Estimativa:** 2-4 horas para ficar funcional.

---

*Spec gerada por Claude em 2026-01-16*