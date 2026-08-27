# Tarefa 028.2: Endpoint Unificado de Webhooks Meta

**Sprint:** 1 - Fundações Omnichannel (Hub Meta)
**Estimativa:** 1 dia(s)
**Tipo:** Backend

---

## Contexto
A Meta exige que qualquer app que receba mensagens via Instagram Direct ou WABA passe por um processo de verificação de Webhook (o famoso `hub.challenge`). Além disso, todas as mensagens, comentários, reações e menções (se habilitados no app) chegarão através dessa única porta de entrada. 
A missão dessa tarefa é criar este portão de entrada seguro e escalável no ai9, respondendo ao desafio da Meta e roteando os payloads válidos para processamento interno assíncrono.

---

## Onde começa
- Tabela de Integrações (Spec 028.1) já existe para validação de dados futuros.
- A estrutura de rotas base do Grape (`/api/v1/base.rb`) e a controller/service de Leads (`/api/v1/leads.rb`) existem, mas não expõem um Endpoint para a Meta.

## Onde termina
- Rotas `GET` e `POST` em `/api/v1/webhooks/meta` funcionando perfeitamente no Grape.
- Validação do `hub.verify_token` via variável de ambiente (ex: `META_WEBHOOK_VERIFY_TOKEN`).
- O Payload bruto de POST (`field: "messages"`) extraído com segurança e repassado para a conversão de Lead (`LeadCrossChannelService` ou afins).

---

## O que precisa ser feito

### No Backend

1. **Rota de Desafio (GET):**
   - Criar `app/controllers/api/v1/webhooks/meta.rb`.
   - Implementar `GET /api/v1/webhooks/meta`.
   - Receber os query params `hub.mode`, `hub.verify_token` e `hub.challenge`.
   - Se `hub.verify_token` bater com a ENV da aplicação e o request estiver pedindo `subscribe`, retornar `200` devolvendo EXATAMENTE a string de texto do `hub.challenge`.
   - Se o token falhar, devolver HTTP 403.

2. **Rota de Payloads (POST):**
   - Implementar `POST /api/v1/webhooks/meta`.
   - Extrair o corpo da requisição (JSON).
   - Identificar se é provindo de `page` (Messenger), `whatsapp_business_account` (WABA) ou `instagram`. O objeto Meta `entry` encapsula esses metadados.
   - Encontrar a mensagem base dentro de `changes[0].field == 'messages'`. Se for outra coisa, como 'comments' ou 'message_deliveries', retornar 200 (para a Meta saber que recebemos) mas interromper processamento interno, logando "Ignored webhook type".
   
3. **Conversão de DMs (Direct Messages):**
   - Caso `field == 'messages'`, extrair o ID do remetente (`sender.id`), o ID destino (`recipient.id`), e o `message.text`.
   - Montar o payload padronizado e injetar no fluxo do `LeadCrossChannelService` (assumindo a mesma estrutura de API de entrada de Leads que o Ai9 já usa hoje via POST `/api/v1/leads`). O `source_type` será `instagram` ou `whatsapp`.
   - IMPORTANTE: Retornar HTTP 200 *imediatamente* para a Meta não repetir a chamada. O processamento do Service DEVE ser idealmente enviado a um Job assíncrono (ex: Sidekiq) ou finalizado em tempo habil (< 1 segundo).

---

## Observações importantes
- A Meta repete o Webhook caso não receba HTTP `200 OK` rápido o suficiente (vários retries num período de horas/dias). A rota POST nunca deve estourar Timeout. Um ActionJob intermédio é fortemente recomendado (ex: `ProcessMetaWebhookJob.perform_async(params.to_h)`).
- Use `ENV['META_WEBHOOK_VERIFY_TOKEN']` (ou o sistema de Credentials do Rails) para validar o Desafio no GET.

---

## Critérios de aceite
O dev deve demonstrar que:
1. Fazendo uma chamada GET com o verify token correto via Postman, o sistema responde o `hub.challenge` esperado (string plana).
2. Chamadas POST genéricas com um JSON com `field: "messages"` criam uma entrada de Log no servidor e rodam o Job Assíncrono para integração com LeadCrossChannelService.
3. Se um webhook com `field: "message_deliveries"` chegar, o sistema responde com 200, loga `Webhook drop ou ignore`, e encerra a API sem enviar para processamento massivo.

---

## Dependências
- Arquitetura de Leads atual.

## Próxima tarefa
- **Tarefa 028.3:** UI para cadastro das chaves/Canais.
