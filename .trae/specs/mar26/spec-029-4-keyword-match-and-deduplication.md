# Tarefa 029.4: Automação (Keyword Match) e Deduplicação

**Sprint:** 2 - Aquisição de Leads via Comentários no Instagram
**Estimativa:** 1.5 dias
**Tipo:** Backend

---

## Contexto
Disparar Private Replies para TODOS os comentários de uma conta do Instagram é uma péssima prática: viola políticas antispam da Meta, gasta cota da API e irrita usuários organizais. A automação deve ser cirúrgica: só enviamos o Private Reply se o comentário contiver uma palavra-chave (Keyword) previamente configurada no Bot (Ex: "EU QUERO", "PREÇO").
Além disso, um usuário pode comentar a mesma palavra várias vezes no mesmo post (ou por erro de rede ou por ansiedade). Disparar 3 DMs iguais o baniria na Meta. A deduplicação garante que na combinação `(Usuario + Post)`, a ação de DM automatizada só ocorra **uma única vez**.

---

## Onde começa
- Tarefa 029.3 consegue atirar uma mensagem na Graph API dado um Comment ID.
- Tarefa 029.1 lê o Comentário e cria o Lead.

## Onde termina
- Duas novas tabelas adicionadas via migrations: `InstagramCommentKeyword` e `InstagramCommentReplySent`.
- Lógica injetada entre o webhoook/lead saving e a chamada do Private Reply, agindo como um Filtro/Gatilho.

---

## O que precisa ser feito

### No Backend

1. **Camada de Dados:**
   - Migration `CreateInstagramCommentKeywords`: `bot_id:references`, `keyword:string`, `exact_match:boolean` (default: false), `active:boolean` (default: true), `reply_message:string`.
   - Migration `CreateInstagramCommentReplySents`: `user_psid:string`, `media_id:string`, `bot_id:references(uuid)`. Adicionar `add_index :instagram_comment_reply_sents, [:user_psid, :media_id, :bot_id], unique: true`.
   - Criar os Models ActiveRecord correspondentes.

2. **Filtro de Palavra-chave (Match):**
   - No `ProcessMetaWebhookJob` ou `InstagramCommentHandler` (pipeline base de comentários):
   - Pegar o `Bot` vinculado àquela `Integration`. Buscar todas as `InstagramCommentKeyword` ativas deste Bot.
   - Testar o `text` do comentário contra as keywords. (Downcase string para *contains* se `exact_match` for false; Split de array de palavras se `exact_match` for true).
   - Se nenhuma palavra bater, o Job Morre aqui (com sucesso de execução, log `"No keyword matched"`).

3. **Trava de Deduplicação:**
   - Se rolou match, precisamos tentar inserir o registro na tabela `InstagramCommentReplySents` com os 3 IDs em questão.
   - Use um bloco de `rescue ActiveRecord::RecordNotUnique` na tentativa de Save.
   - Se cair no rescue, o Job Morre aqui (com sucesso de execução, log `"Already replied to this user on this media"`).

4. **Acionamento:**
   - Passando no filtro da keyword E tendo salvo na deduplicação, chamar o service `Meta::PrivateReplyService.call(comment_id, selected_keyword.reply_message, ...)`.

---

## Observações importantes
- Essa lógica garante segurança em transações concorrentes pois a restrição de unicidade está **no Banco de Dados**. Tentar checar com `.exists?` antes de `.create` pode sofrer Race Conditions severos em webhooks duplicados. Siga o fluxo de "Fire and Rescue".

---

## Critérios de aceite
O dev deve demonstrar que:
1. Comentário contendo apenas "Amei a foto!" não faz match, não salva nada na tabela de deduplicação e não dispara a Graph API.
2. Comentário com "EU QUERO" (cadastrado) faz match, insere no DB de deduplicação e dispara o Private Reply.
3. Repetir exatamente o mesmo Payload do "EU QUERO" no milissegundo seguinte cai na trava de *Unique Constraint* do Postgres e não duplica o envio na Graph API.

---

## Dependências
- Tarefas 029.1 e 029.3.

## Próxima tarefa
- **Tarefa 029.5:** A interface do usuário para gerenciar essas palavras chaves.
