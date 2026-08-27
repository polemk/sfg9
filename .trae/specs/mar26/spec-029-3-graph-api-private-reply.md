# Tarefa 029.3: Private Reply Automático (Graph API)

**Sprint:** 2 - Aquisição de Leads via Comentários no Instagram
**Estimativa:** 1.5 dias
**Tipo:** Backend

---

## Contexto
Parte fundamental de um "Omnichannel Gateway" em 2026 é ser capaz de ativamente responder conversas por origens de entrada públicas, engajando leads antes de perdê-los. A Meta disponibiliza um Endpoint especial na Graph API voltado não a mensagens na thread normal, mas sim a um Private Reply de resposta a um Comentário com uma DM (Direct Message). É um mecanismo diferente de usar o Chat comum WABA/Messenger porque não exige a janela padrão se feito pelo `comment_id`.

---

## Onde começa
- A `lead_message` foi gravada em banco com sucesso referenciando que ela provém de um `comment` e carrega consigo o `content_id` (Que neste caso é a String identificadora do Comentário na DB do Instagram).

## Onde termina
- Serviço de Ação final (`SendPrivateReplyService` ou `Instagram::PrivateReplyService`) que envia as strings preparadas do Payload de volta para a Graph API com o endpoint isolado da Meta.
- Criação de uma `lead_message` marcadora de `outbound` no Lead final.

---

## O que precisa ser feito

### No Backend

1. **Criar o Service Provider Call:**
   - Subir `app/services/meta/private_reply_service.rb`.
   - Obter a URL base da Meta API (ex: `https://graph.facebook.com/v22.0/{comment_id}/replies`).
   - Receber variáveis cruciais: `comment_id`, `message_string` e o `access_token` correspondente ao bot via Tabela `Integrations` (Feita lá na Sprint 1).

2. **Chamar o HTTP Client (Faraday ou Httparty):**
   - Configurar requisição POST passando no Body o `{ "message": "<message_string>" }`. Bearer Token incluído na call ou como access_token Query String.

3. **Validação do Disparo e Encerramento Operativo:**
   - Se o response vier HTTP 200 (Sucesso do Meta):
     - Usar a Service interna do AI9 para gravar a Outbound Message para o Lead. Marcá-la como `source_type: "instagram"` e `source_endpoint: "comment"`.
   - Se erro 429 ou erro de Pemissions/Expired Token:
     - Logar adequadamente na estrutura do Sidekiq usando um tratamento de erro (`raise CustomError`). Isso reintentará mais tarde ou avisará os Monitores.

---

## Observações importantes
- A permissão do app Meta `instagram_manage_comments` precisa estar concedida e o User Token gerado pelo admin/owner deve ter esses scopes.
- Erros de "Message Outside of 24 hours" teoricamente não se aplicam a comentários de posts recém feitos (a Graph ignora a janela de 24 horas nestes Private Replies de até X dias), mas Rate Limit da API do IG é muito agressivo. Cuidado para não spammar (O que será cortado na Tarefa 29.4!).

---

## Critérios de aceite
O dev deve demonstrar que:
1. Usando a classe `Meta::PrivateReplyService.call(comment_id: 'XXX', ...)` em um Rails Console para o Comment de uma página atrelada ao System Token que gerencia os Testes, um Direct message chega instantaneamente na aba de "Requests/Mensagens" daquele perfil teste.
2. A mensagem viaja de volta pro sistema sendo salva como outbound lead message para auditoria do próprio Ai9.
3. Errors 429 e Http Timeout são tratados sem causar crash no App, mas sim subindo logs de Warn/Error estruturados.

---

## Dependências
- `content_id` capturado corretamente na Tarefa 029.1.
- `Integration` com Access Token valido cadastrado (Sprint 1).

## Próxima tarefa
- **Tarefa 029.4:** Adicionar barreiras protetivas: Deduplicação e Gatilhos por Palavra-Chave.
