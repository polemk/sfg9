# Roadmap: Integrações Omnichannel & Lead Capture (Instagram Comments)

Este roadmap organiza as demandas detalhadas nas discussões anteriores e nas specs antigas (`spec-028` e `roadmap-meta-omni`) em uma sequência de Sprints e Tarefas atômicas (0.5 a 2 dias de esforço cada), de acordo com as regras de especificação otimizadas para RAG (`spec-rules.md`).

---

## 📅 Sprint 1: Fundações Omnichannel (Hub Meta)
**Objetivo:** Criar a estrutura base para receber mensagens nativas da Meta (Instagram/WhatsApp) e preparar o banco de dados, substituindo o acoplamento exclusivo do Evolution API.

### 📄 Spec 028.1: Estrutura de Dados de Integração (Integration/Channel)
- **Tipo:** Backend
- **Esforço estimado:** 1 dia
- **Escopo:**
  - Criar o model `Integration` (`provider`, `platform`, `access_token`, `external_id`, `status`).
  - Estabelecer a relação deste model com a conta/bot do usuário.
  - Remover o hardcode do `EvolutionConnection` e migrar para uma abstração genérica (`Integration`).

### 📄 Spec 028.2: Endpoint Unificado de Webhooks Meta
- **Tipo:** Backend
- **Esforço estimado:** 1 dia
- **Escopo:**
  - Rota `GET /api/v1/webhooks/meta` para validação de segurança (`hub.challenge`).
  - Rota `POST /api/v1/webhooks/meta` base para inbound DMs (`field: "messages"`).
  - Repasse das mensagens de Direct para o `LeadCrossChannelService`.

### 📄 Spec 028.3: Gerenciamento de Canais na UI
- **Tipo:** Frontend
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Tela administrativa `/admin/integrations`.
  - Formulário para o usuário/admin registrar as chaves (Tokens, ID do App Meta, Evolution API URL/Chaves).
  - Componentes de CRUD conectados à API para a tabela `Integration`.

---

## 📅 Sprint 2: Aquisição de Leads via Comentários no Instagram
**Objetivo:** Expandir o Hub Meta recém-criado para também processar os comentários em posts, gerando leads automaticamente, da mesma forma que o n8n/GOAT executa hoje.

### 📄 Spec 029.1: Captura e Normalização de Comentários (Webhook)
- **Tipo:** Backend
- **Esforço estimado:** 0.5 dia
- **Escopo:**
  - Ampliar o Handler do Webhook Meta (da Spec 028.2) para ler o `field: "comments"`.
  - Normalizar e salvar a mensagem de entrada na API de Leads, incluindo `source_endpoint: "comment"` e preservando o `content_id` e o ID da mídia/post.

### 📄 Spec 029.2: Metadados de Anúncios CTWA/CTIA no Comentário
- **Tipo:** Backend
- **Esforço estimado:** 0.5 dia
- **Escopo:**
  - Extrair o objeto `referral` do Payload do comentário quando existir.
  - Processar os parâmetros `ref`, `ad_id` e `ctwa_clid`, gravando essas UTMs/Tags no metadata do novo Lead.

### 📄 Spec 029.3: Private Reply Automático (Graph API)
- **Tipo:** Backend
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Implementar o disparo de mensagem direta por DM responsiva usando o endpoint `/{comment_id}/replies` através do Access Token do model `Integration`.
  - Registrar esse envio de volta na API de Leads como mensagem de saída, fechando o ciclo.

### 📄 Spec 029.4: Automação (Keyword Match) e Deduplicação
- **Tipo:** Backend
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Criar as tabelas `InstagramCommentKeyword` (regras e palavras chaves cadastradas no Bot) e `InstagramCommentReplySent` (para travar envios repetidos).
  - Injetar no fluxo da Spec 029.3 a condição de "apenas disparar o Private Reply se o comentário fizer Match com a palavra-chave e não tiver havido Private Reply antes neste post para o mesmo usuário".

### 📄 Spec 029.5: Interface do Usuário (Bot Rules / Keywords)
- **Tipo:** Frontend
- **Esforço estimado:** 1 dia
- **Escopo:**
  - Tela de configurações do Bot para adicionar, remover e editar as palavras-chaves de acionamento do Private Reply no painel React.

---

## 📅 Sprint 3: O Despachante Omnichannel
**Objetivo:** Permitir que, tendo as DMs e Comentários processados, a AI do ai9 ou atendentes possam **responder** os leads usando conexões Múltiplas.

### 📄 Spec 030.1: Adapter de Envio Omnichannel (DispatchService)
- **Tipo:** Backend
- **Esforço estimado:** 2 dias
- **Escopo:**
  - Criar o `Omnichannel::DispatchService`.
  - Analisar o Lead e descobrir se ele deve ser respondido via Graph API da Meta (Instagram), WABA, ou Evolution API.
  - Chamar o cliente HTTP correspondente para a saída da mensagem da plataforma ai9 até o dispositivo do usuário final.
  
---

## PRÓXIMOS PASSOS
Com a sua aprovação deste Roadmap estrutural, geraremos as **Specs individuais dos itens da Sprint 1** (cada uma virando um arquivo markdown detalhado, respeitando rigorosamente os `spec-rules.md`). Confirmando que a organização ficou clara, podemos seguir!
