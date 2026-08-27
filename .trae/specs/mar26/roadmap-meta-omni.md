# Sprint: Instagram Comment Lead Capture
**Projeto:** ai9 / branch: pkbot  
**Estimativa:** 4–5 dias  
**Referência de implementação:** GOAT/v1/router (n8n) — já opera esse fluxo em produção

---

## Contexto

O ai9 já processa mensagens de Instagram DM via webhook Meta e registra leads pela API interna (`POST /api/v1/leads`). O objetivo desta sprint é estender esse mesmo pipeline para um segundo tipo de entrada: **comentários em posts/reels do Instagram**.

Quando um usuário comenta com uma keyword configurada, o sistema envia um **Private Reply** (DM automático via Graph API) e registra dois eventos na API de leads — o comentário recebido e o reply enviado — para que o chatbot assuma a conversa no DM subsequente.

A feature replica o que o n8n/GOAT já faz hoje via `ig_comment` no switch `joy/answer`, mas de forma nativa no produto.

---

## Como o fluxo funciona

```
Usuário comenta no post/reel
        ↓
Meta dispara webhook → POST /webhooks/instagram
        ↓
Handler identifica field: "comments" (novo, hoje só processa "messages")
        ↓
Normaliza payload → formato padrão da API de leads:
  source_type: "instagram"
  source_endpoint: "comment"
  content_id: <comment_id>   ← usado depois para o reply
        ↓
POST /api/v1/leads  (registra o comentário como lead_message)
        ↓
Verifica keyword match na config do bot
        ↓
Se match: POST /{comment_id}/replies  (private reply via Graph API)
        ↓
POST /api/v1/leads novamente  (registra o reply como lead_message de saída)
        ↓
Chatbot assume quando usuário responder no DM
```

---

## Tarefa 1: Estender o webhook handler para comentários

**Contexto**  
O handler atual do webhook Instagram provavelmente só trata `field: "messages"`. Precisa passar a tratar também `field: "comments"` que chega no mesmo endpoint.

**O que fazer**  
Adicionar reconhecimento do campo `comments` no handler existente. Quando identificado, extrair e normalizar o payload para o formato padrão da API de leads:

```json
{
  "source_type": "instagram",
  "source_id": "<USER_PSID>",
  "source_endpoint": "comment",
  "target_id": "<PAGE_ID>",
  "content": "<texto do comentário>",
  "content_type": "text",
  "content_id": "<COMMENT_ID>",
  "name": "<ig_username>",
  "ig_username": "<ig_username>",
  "igs_id": "<USER_PSID>"
}
```

O `content_id` aqui é o `comment_id` — ele é necessário para enviar o private reply depois.

**Payload que a Meta envia:**
```json
{
  "object": "instagram",
  "entry": [{
    "id": "<PAGE_ID>",
    "changes": [{
      "field": "comments",
      "value": {
        "from": { "id": "<USER_PSID>", "username": "<username>" },
        "media": { "id": "<MEDIA_ID>", "media_product_type": "REEL" },
        "id": "<COMMENT_ID>",
        "text": "quero saber mais!"
      }
    }]
  }]
}
```

**Critério de aceite**  
Comentário em post da conta conectada chega no handler, é normalizado corretamente e resulta em `POST /api/v1/leads` com `source_endpoint: "comment"`. Verificável nos logs ou na listagem de leads.

---

## Tarefa 2: Configuração de keywords por bot

**Contexto**  
Cada bot precisa definir quais palavras-chave disparam o private reply. Sem keyword configurada, o sistema pode ignorar o comentário ou responder a todos — isso deve ser configurável.

**O que fazer**  
Criar model `InstagramCommentKeyword` associado ao bot/account existente:

- `keyword` (string, obrigatório)
- `exact_match` (boolean, default: false — `false` = contains, `true` = palavra isolada)
- `active` (boolean, default: true)
- `reply_message` (string — mensagem do private reply para essa keyword)

Se nenhuma keyword estiver cadastrada para o bot, **não envia reply** (comportamento seguro por padrão).

A lógica de match é: `false` = `text.include?(keyword)`, `true` = keyword como palavra completa no texto.

**Critério de aceite**  
Consigo cadastrar uma keyword via admin/console. Comentário com a keyword dispara o reply. Comentário sem match não dispara.

---

## Tarefa 3: Deduplicação por usuário + post

**Contexto**  
Um usuário pode comentar várias vezes no mesmo post. Enviar múltiplos private replies para a mesma pessoa no mesmo post é spam e viola as políticas da Meta.

**O que fazer**  
Antes de enviar o reply, verificar se já existe um registro de reply enviado para a combinação `(user_psid, media_id, bot_id)`. Se existir, registra o comentário como lead_message normalmente mas não envia novo reply.

Implementar com a tabela mais simples possível — um model `InstagramCommentReplySent` com unique index em `[user_psid, media_id, bot_id]` resolve.

**Critério de aceite**  
Mesmo usuário comentando 3x no mesmo post recebe apenas 1 private reply. Os 3 comentários aparecem registrados como lead_messages.

---

## Tarefa 4: Envio do private reply e registro de saída

**Contexto**  
O private reply é enviado via Graph API usando o `comment_id`. Após o envio, o reply precisa ser registrado na API de leads como uma mensagem de saída, para o histórico da conversa ficar completo.

**O que fazer**  
Após keyword match e verificação de deduplicação:

1. `POST https://graph.facebook.com/v22.0/{comment_id}/replies` com `{ "message": "<reply_message>" }` usando o token da conta
2. Se sucesso, registrar o reply na API de leads:

```json
{
  "source_type": "instagram",
  "source_id": "<PAGE_ID>",
  "source_endpoint": "comment",
  "target_id": "<USER_PSID>",
  "content": "<reply_message>",
  "content_type": "text",
  "content_id": "<comment_id>"
}
```

3. Registrar em `InstagramCommentReplySent` para deduplicação futura

Em caso de erro na Graph API (rate limit, permissão negada), logar o erro e não registrar em `ReplySent` — para poder tentar novamente se necessário.

**Critério de aceite**  
Após o private reply ser enviado, ele aparece tanto no Instagram (DM do usuário) quanto registrado como lead_message na API. Erro 429 da Meta é logado sem quebrar o fluxo.

---

## Tarefa 5: Assinatura do campo `comments` no App Meta

**Contexto**  
Mesmo com o código pronto, o webhook só recebe eventos de comentários se o campo `comments` estiver assinado no App Dashboard da Meta. Hoje provavelmente só `messages` está assinado.

**O que fazer**  
No Meta App Dashboard → Webhooks → Instagram → adicionar campo `comments` à assinatura. Isso não requer review da Meta para apps já em modo Live — é só configuração.

A permissão `instagram_manage_comments` ainda está pendente de review, mas a assinatura do campo pode ser feita antes para validar o recebimento do webhook em ambiente de teste.

**Critério de aceite**  
Após assinar o campo, um comentário em post da conta conectada aparece nos logs do servidor como payload recebido.

---

## Pontos que o desenvolvedor precisa validar antes de começar

1. **Interface do handler atual** — como o webhook Instagram está estruturado hoje no pkbot? Se já tem um `InstagramWebhooksController` ou similar, a Tarefa 1 é só adicionar um branch. Se não existe, precisa criar do zero.

2. **Token por conta** — o System User Token é único ou por page_id? Isso define como o `MetaApiService` (ou equivalente) é inicializado para chamar `/{comment_id}/replies`.

3. **Associação do bot** — o model de bot/account existente tem `instagram_page_id` mapeado? Se sim, a busca do bot config na Tarefa 2 é direta por `page_id`.

---

## Tarefa 6: Captura de parâmetros de atribuição de anúncios (CTWA)

**Contexto**  
Quando um usuário comenta em um post/reel que é patrocinado ou chega via anúncio Click-to-Instagram (CTIA), a Meta inclui um objeto `referral` no payload do webhook com dados de atribuição. Esses campos são essenciais para rastrear quais campanhas estão gerando leads e conversas — sem capturá-los na entrada, a informação é perdida para sempre.

**Campos que chegam no payload (quando originados de anúncio):**
```json
{
  "field": "comments",
  "value": {
    "from": { "id": "...", "username": "..." },
    "id": "<COMMENT_ID>",
    "text": "quero saber mais!",
    "referral": {
      "ref": "<valor_customizado_do_anuncio>",
      "source": "ADS",
      "type": "OPEN_GRAPH",
      "ad_id": "<AD_ID>",
      "ads_context_data": {
        "ad_title": "Nome do Anúncio",
        "photo_url": "https://...",
        "video_url": null,
        "post_id": "<POST_ID>",
        "product_id": null
      },
      "ctwa_clid": "<CTWA_CLICK_ID>"
    }
  }
}
```

O `ctwa_clid` é o identificador de clique — permite cruzar com dados do Ads Manager. O `ad_id` identifica o criativo. O `ref` é um parâmetro customizável no anúncio, útil para segmentar campanhas dentro do mesmo bot.

**O que fazer**  
Na normalização do payload (Tarefa 1), extrair o objeto `referral` quando presente e mapear os campos para a API de leads. Verificar quais campos a API já aceita e, se necessário, adicionar os campos de atribuição ao modelo de lead ou à tabela de metadados existente:

- `ctwa_clid` — ID de clique CTWA
- `ad_id` — ID do anúncio
- `ad_title` — título do criativo
- `ref` — parâmetro customizado do anúncio
- `referral_source` — origem (`ADS`, `UNKNOWN`, etc)

O payload normalizado para a API de leads deve incluir esses campos adicionais quando presentes, sem quebrar o fluxo quando ausentes (comentários orgânicos não têm `referral`).

**Critério de aceite**  
Comentário originado de anúncio tem `ctwa_clid` e `ad_id` registrados no lead. Comentário orgânico (sem `referral`) é processado normalmente sem erro. Os campos ficam disponíveis para filtro/relatório na listagem de leads.

---

## O que esta sprint não cobre (próxima sprint)

- Interface admin para cadastro de keywords (Tarefa 2 assume console/seeds por ora)
- Suporte a comentários em Stories (media_product_type diferente)
- Reply com mídia (imagem/vídeo) — apenas texto nesta sprint
- Relatório de conversões comentário → conversa ativa