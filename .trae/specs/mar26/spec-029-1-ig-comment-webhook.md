# Tarefa 029.1: Captura e Normalização de Comentários (Webhook)

**Sprint:** 2 - Aquisição de Leads via Comentários no Instagram
**Estimativa:** 0.5 dia
**Tipo:** Backend

---

## Contexto
O novo Hub Omnichannel Meta desenvolvido na Sprint 1 já é capaz de processar mensagens diretas (`field: "messages"`). Para aumentar o volume de leads do negócio, o sistema também deve reagir automaticamente aos comentários públicos deixados pelos seguidores nos posts ou reels, trazendo a mesma jornada de captura de Inbox (Private Reply).
Para isso, o webhook atual precisa ser instruído a aceitar objetos do tipo `field: "comments"`, validá-los e normalizá-los em um formato compreensível pelo `LeadCrossChannelService`.

---

## Onde começa
- Servidor Webhook Meta (`app/controllers/api/v1/webhooks/meta.rb` ou equivalente) já recebe POSTs e valida seguranças.

## Onde termina
- Quando um Payload do Instagram contendo comentários for despachado para a nossa API, os dados essenciais do usuário e comentário são extraídos.
- A requisição para criar/atualizar um Lead no sistema interno ocorre usando `source_endpoint: "comment"`.
- A mensagem fica pendente na fila para ser analisada e engatilhada para Resposta Privada nas tarefas seguintes.

---

## O que precisa ser feito

### No Backend

1. **Atualizar Lógica do Handle Principal (`meta.rb` ou `ProcessMetaWebhookJob`):**
   - No recebimento via `POST /api/v1/webhooks/meta`, checar o evento da Meta (`changes[0][:field] == 'comments'`).
   - Se os comentários vierem da própria página do usuário (ex: a conta comentando no próprio post), deve ser **ignorado** para não gerar autoreplicações infinita. `return if from.id == page.id`.

2. **Normalização dos Dados do Comentário:**
   - Extrair a chave de remetente `from.id` (que será o Psid do Lead) e o `from.username`.
   - Extrair a identificação do comentário `id` e o conteúdo `text`.
   - Extrair o post original através do block `media.id`.

3. **Interagir com o Service de Leads (`LeadCrossChannelService`):**
   - O Payload para a API base de Leads ganha:
     - `source_type: "instagram"`
     - `source_id: <page_id_recebedora>`
     - `source_endpoint: "comment"`
     - `content: <conteudo_do_texto>`
     - `content_id: <comment_id>` (Esse campo é FUNDAMENTAL para a Spec 029.3, ele servirá como o marcador de resposta via DM).
     - `name: <username>`
   - Acionar o serviço de gravação de mensagens usando os metadados normalizados para consolidar o Comentário como uma nova mensagem na timeline do Lead.

---

## Observações importantes
- A permissão do app Meta `instagram_manage_comments` e a assinatura explícita do campo de Webhooks `comments` deve estar aplicada na conta de Developer do Admin. Em modo desenvolvimento, isso não afeta os Testes Locais, mas impactará na Homologação Oficial.

---

## Critérios de aceite
O dev deve demonstrar que:
1. Recebendo do Facebook um JSON mockado de comentário no console RSpec ou via Curl/Postman, o webhook retorna http status 200.
2. É criado/atualizado um `Lead` daquele `from.id`.
3. Uma `LeadMessage` é gerada com o atributo contendo `comment_id`.

---

## Dependências
- Sprint 1 Webhooks.

## Próxima tarefa
- **Tarefa 029.2:** Melhorar essa captura incluindo as tags de Ad Referral provindos do click-to-messenger no mesmo payload de Webhook.
