# Specification: Blog de Posts (Vídeos de Conteúdo)

**Versão:** 1.1 — Abril 2026  
**Status:** Rascunho para revisão  
**Motivação:** Estratégia de SEO e geração de conteúdo. Vídeos gravados (no carro, PC, etc.) viram publicações indexáveis no Google, com transcrição, corpo em rich text editável e chatbot especializado no contexto de cada vídeo.

---

## Visão geral da feature

O tech lead grava vídeos curtos (3–4 min, 150–300 MB) falando sobre tecnologia. Cada vídeo é cadastrado como um `Post`. O sistema:

1. Recebe o upload do vídeo
2. Extrai o áudio e transcreve via OpenAI Whisper
3. Gera o corpo do post em HTML via IA, salvo como ActionText (rich text editável)
4. Publica uma página pública em `/posts/:id` com vídeo, corpo editável, comentários e chatbot especializado na transcrição
5. Expõe a VSL mais recente (ou favorita) na home do site

**Blog "secreto" inicialmente** — sem link na navegação principal, mas URL pública e indexável pelo Google.

---

## Decisões arquiteturais

### Model separado: `Post`

O `Medium` existe e é usado em vários lugares do sistema (mosaico do site, galeria 3D, MediaPage). Extendê-lo adicionaria acoplamento desnecessário a uma entidade que serve propósitos distintos.

A decisão é **duplicar a estrutura do `Medium` num novo model `Post`**, com campos próprios e tabela própria. O `Post` tem `has_one_attached :file` e `has_one_attached :thumbnail` independentes.

### ChatFlow único para blog

Criar um `ChatFlow` por post geraria dezenas de registros e seria ingerenciável. A solução é um **único ChatFlow "Blog Agent"** (registro fixo, `kind: :ai_agent`), reutilizado para todos os posts. A transcrição do post é injetada dinamicamente no `system_prompt` no momento da requisição — o ChatFlow em si não carrega nenhuma transcrição.

### Corpo do post em ActionText

O `body` do post usa `has_rich_text :body` (ActionText do Rails). Isso permite:
- A IA gerar HTML inicial (via `post.body = html_content`)
- O admin editar o conteúdo depois — inclusive inserir imagens no meio do texto
- O frontend receber o HTML renderizado e exibir diretamente

No frontend admin, usar um editor rich text (TipTap ou similar) para edição.

---

## Sprint 1 — Core da Publicação (Backend)

### Tarefa 1.1: Model `Post` e migration

**Sprint:** 1 — Core da Publicação  
**Estimativa:** 0.5 dia  
**Tipo:** Backend

---

#### Contexto

Criar o model `Post` do zero, baseado na estrutura do `Medium` mas com campos específicos de publicação. A tabela `posts` é independente de `media`.

---

#### Onde começa

Nenhum model ou tabela `Post` existe ainda.

#### Onde termina

`Post` existe, migrations rodadas, model com validações/scopes, Grape Entity criada.

---

#### O que precisa ser feito

##### No Backend

**Migration:**

```ruby
create_table :posts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
  t.string   :title,                null: false
  t.text     :description
  t.string   :author_name
  t.string   :author_avatar_url
  t.boolean  :active,               default: true,      null: false
  t.boolean  :featured,             default: false,     null: false
  t.text     :transcription
  t.string   :transcription_status, default: 'pending', null: false
  # transcription_status: 'pending' | 'processing' | 'done' | 'error'
  t.timestamps
end

add_index :posts, :active
add_index :posts, :featured
add_index :posts, :transcription_status
```

**Model** `backend/app/models/post.rb`:

```ruby
class Post < ApplicationRecord
  has_one_attached :file
  has_one_attached :thumbnail
  has_rich_text :body

  validates :title, presence: true

  scope :published, -> { where(active: true).order(created_at: :desc) }
  scope :featured,  -> { where(featured: true, active: true).order(created_at: :desc) }
end
```

Implementar `file_url` e `thumbnail_url` seguindo o mesmo padrão do `Medium` (dev: `rails_blob_path`, prod: `rails_blob_url` com `API_HOST`).

**Grape Entity** `backend/app/controllers/api/entities/post.rb` expondo: `id`, `title`, `description`, `author_name`, `author_avatar_url`, `active`, `featured`, `transcription_status`, `file_url`, `thumbnail_url`, `body_html` (resultado de `post.body.to_s`), `created_at`.

Na listagem pública, **não expor** `transcription` (dado pesado) — apenas no `show`.

---

#### Critérios de aceite

1. Migration roda sem erros
2. `Post.create!(title: 'Teste')` funciona com UUID como ID
3. `post.body = "<p>conteúdo</p>"` salva via ActionText e `post.body.to_s` retorna o HTML
4. `Api::Entities::Post.represent(post).as_json` inclui todos os campos listados

---

### Tarefa 1.2: Pipeline de transcrição assíncrona

**Sprint:** 1 — Core da Publicação  
**Estimativa:** 2 dias  
**Tipo:** Backend

---

#### Contexto

Vídeos de 150–300 MB precisam ter o áudio extraído e transcrito via OpenAI Whisper. O processo leva minutos — roda em background via `Thread.new` (mesmo padrão do `PublicChatService`). O admin dispara manualmente após o upload via botão no painel.

---

#### Onde começa

- `Post` com `file` anexado via ActiveStorage
- `Ai::AudioTranscriptionService` existe em `backend/app/services/ai/audio_transcription_service.rb`
- `AudioConverterService` existe mas converte apenas áudio→áudio; não extrai áudio de vídeo

#### Onde termina

- `post.transcription` preenchido com o texto completo
- `post.transcription_status` em `'done'` ou `'error'`

---

#### O que precisa ser feito

##### No Backend

**Novo service:** `PostTranscriptionService.transcribe!(post_id)`

1. Busca o `Post`, valida que tem arquivo e que `transcription_status != 'processing'`
2. Atualiza `transcription_status: 'processing'` imediatamente (antes da Thread)
3. Abre `Thread.new`:
   - Faz download do vídeo do ActiveStorage para `Tempfile.new(['video', '.mp4'])`
   - Extrai áudio via ffmpeg para `Tempfile.new(['audio', '.mp3'])`:
     ```
     ffmpeg -i {video_path} -vn -acodec libmp3lame -aq 2 -y {audio_path}
     ```
   - Chama `Ai::AudioTranscriptionService.transcribe(audio_data: File.open(audio_path))`
   - Sucesso: salva `transcription` e `transcription_status: 'done'`
   - Erro: salva `transcription_status: 'error'`
   - Cleanup: apaga ambos os tempfiles (com `ensure`)

**Endpoint admin (autenticado):**
```
POST /api/v1/posts/:id/transcribe
```
Retorna `{ status: 'processing' }` imediatamente (< 200ms). Status atualizado consultado via `GET /api/v1/posts/:id`.

---

#### Observações importantes

- Em produção (S3/R2), o download do vídeo do ActiveStorage usa `post.file.blob.download { |chunk| ... }` para streaming ao tempfile — não carrega 300MB de RAM de uma vez.
- A credencial do Whisper é buscada via `Credential.find_by(provider: 'openai_whisper')`, já implementado no `AudioTranscriptionService`.
- O `AudioConverterService` existente **não** serve aqui (é áudio→áudio). O ffmpeg é chamado diretamente para extração de áudio de vídeo.

---

#### Critérios de aceite

1. `POST /api/v1/posts/:id/transcribe` retorna `{ status: 'processing' }` em < 200ms
2. Após conclusão, `post.transcription_status` é `'done'` e `post.transcription` contém texto legível em pt-BR
3. Sem credencial Whisper, status vai para `'error'` com log descritivo
4. Tempfiles são removidos ao final (com ou sem erro)

---

### Tarefa 1.3: Geração do corpo do post via IA (ActionText)

**Sprint:** 1 — Core da Publicação  
**Estimativa:** 1 dia  
**Tipo:** Backend

---

#### Contexto

Com a transcrição pronta, a IA gera o corpo completo do post em HTML — intro, 5–6 tópicos com subtítulos, e CTA. O resultado é salvo via ActionText, o que permite ao admin editar e enriquecer o conteúdo depois (adicionar imagens, ajustar texto, etc.).

---

#### Onde começa

`post.transcription` preenchido (`transcription_status: 'done'`).

#### Onde termina

`post.body` preenchido com HTML estruturado. Admin pode regenerar e editar quando quiser.

---

#### O que precisa ser feito

##### No Backend

**Novo service:** `PostBodyGeneratorService.generate!(post_id, credential_id:)`

1. Busca o `Post` e valida `transcription` presente
2. Usa o provider da `Credential` informada (prefira Anthropic ou OpenAI)
3. Prompt do sistema:
   > "Você transforma transcrições de vídeo em artigos de blog profissionais em HTML. Gere HTML limpo com: um parágrafo introdutório `<p>`, de 5 a 6 seções com `<h2>` e `<p>`, e um parágrafo final de chamada para ação em `<blockquote>`. Retorne APENAS o HTML, sem markdown fence nem explicações."
4. Envia a transcrição como mensagem de usuário
5. Salva o HTML retornado em `post.body = html_content`

**Endpoint admin (autenticado):**
```
POST /api/v1/posts/:id/generate_body
body: { credential_id: "uuid" }
```

---

#### Observações importantes

- A IA pode retornar o HTML envolto em markdown fence (` ```html `) — fazer strip antes de salvar.
- Usar os providers diretamente (`Ai::Providers::AnthropicProvider` ou `OpenaiProvider`) — sem o overhead do `AgentService`, pois é um call único sem histórico.
- Regenerar sobrescreve o conteúdo anterior. O admin deve salvar qualquer edição manual antes de regenerar.

---

#### Critérios de aceite

1. `POST /api/v1/posts/:id/generate_body` retorna `{ status: 'ok' }` e `post.body.to_s` contém HTML com `<h2>` e `<p>`
2. Se `transcription` for vazio, retorna 422 com mensagem clara
3. Regenerar sobrescreve o conteúdo anterior corretamente
4. O HTML gerado é renderizável no frontend sem XSS (garantir que o editor ActionText sanitiza)

---

### Tarefa 1.4: Endpoints públicos de posts

**Sprint:** 1 — Core da Publicação  
**Estimativa:** 1 dia  
**Tipo:** Backend

---

#### Contexto

As rotas do blog são públicas e indexáveis. O padrão de URL é `/posts/:id` onde `:id` é o UUID do post — comprido o suficiente para não ser adivinhável.

---

#### Onde começa

Model `Post` e tabela `posts` existem. `Comment` model existe com suporte polimórfico e `author_name`/`author_email`.

#### Onde termina

Endpoints públicos disponíveis e funcionais.

---

#### O que precisa ser feito

##### No Backend

Criar `Api::V1::Public::Posts` em `backend/app/controllers/api/v1/public/posts.rb`:

```
GET  /api/v1/public/posts              # Lista de posts ativos (sem transcription, sem body_html)
GET  /api/v1/public/posts/featured     # Post featured ou mais recente
GET  /api/v1/public/posts/:id          # Post completo (inclui body_html, inclui transcription)
GET  /api/v1/public/posts/:id/adjacent # { prev: {id, title, thumbnail_url}, next: {...} }
GET  /api/v1/public/posts/:id/comments # Comentários threadados
POST /api/v1/public/posts/:id/comments # Criar comentário público
POST /api/v1/public/posts/:id/chat     # Chatbot contextualizado (Tarefa 1.5)
```

**Listagem:** só posts com `active: true`, ordenados por `created_at: desc`. Na listagem, não incluir `transcription` nem `body_html` (dados pesados).

**Featured:** retorna o primeiro `Post.featured.first`. Se nenhum estiver marcado como featured, retorna `Post.published.first` (mais recente).

**Adjacent:** busca imediatamente mais novo (`created_at > post.created_at`) e mais antigo (`created_at < post.created_at`), com `active: true`. Retorna apenas `id`, `title`, `thumbnail_url`.

**Comentários:** usar `CommentsService` existente com `commentable_type: 'Post'`, `commentable_id: post.id`. Endpoint público sem autenticação; `author_name` e `author_email` são obrigatórios.

---

#### Critérios de aceite

1. `GET /api/v1/public/posts` retorna lista sem `transcription` e sem `body_html`
2. `GET /api/v1/public/posts/:id` retorna `body_html` e `transcription`
3. `GET /api/v1/public/posts/featured` retorna exatamente um post
4. `GET /api/v1/public/posts/:id/adjacent` retorna `{ prev, next }` (cada um null se inexistente)
5. `POST /api/v1/public/posts/:id/comments` sem `author_name` ou `author_email` retorna 422

---

### Tarefa 1.5: Chatbot do blog — ChatFlow único + endpoint

**Sprint:** 1 — Core da Publicação  
**Estimativa:** 1 dia  
**Tipo:** Backend

---

#### Contexto

O chatbot de cada post é especializado na transcrição daquele vídeo. Criar um `ChatFlow` por post geraria dezenas de registros sem necessidade. A solução é um único ChatFlow "Blog Agent" (registro fixo no banco), cujo `system_prompt` é **sobrescrito dinamicamente** no momento da requisição com a transcrição do post específico.

---

#### Onde começa

`ChatFlow` model e `AgentService` existem. `PublicChatService` mostra o padrão de sessão/Lead.

#### Onde termina

Endpoint `POST /api/v1/public/posts/:id/chat` funcional. Visitante consegue conversar sobre o conteúdo do vídeo.

---

#### O que precisa ser feito

##### No Backend

**Seed/setup do ChatFlow "Blog Agent":**

Criar via seed (ou rake task) um único `ChatFlow` com:
```ruby
ChatFlow.create!(
  name: 'Blog Agent',
  kind: :ai_agent,
  published: true,
  agent_config: {
    model: 'claude-sonnet-4-5', # ou o padrão do projeto
    temperature: 0.5,
    max_tokens: 1024
  }
)
```
O `credential_id` é preenchido pelo admin após o setup. Esse ChatFlow não é exibido no chat builder do site — é interno.

**Endpoint:**
```
POST /api/v1/public/posts/:id/chat
body: { session_id: string, message: string }
```

Lógica:
1. Busca o `Post` (`active: true`)
2. Valida que `transcription` não é vazio
3. `lead = PublicChatService.find_or_create_lead(session_id)`
4. Busca ou cria `ChatSession` para `lead + blog_chat_flow` com `context: { post_id: post.id }`
5. Monta o `system_prompt` dinamicamente:
   ```
   "Você é um assistente especializado no vídeo '#{post.title}'. Responda SOMENTE com base na transcrição abaixo. Se a pergunta estiver fora do tema, diga educadamente que só pode falar sobre este vídeo.\n\n<knowledge>\n#{post.transcription}\n</knowledge>"
   ```
6. Chama `Ai::AgentService.respond(session, message, context: { system_prompt_override: ... })`  
   — ou, mais simples: usar o provider diretamente sem o AgentService se não houver suporte a `system_prompt_override`
7. Retorna `{ responses: [...], session_id: "..." }`

---

#### Observações importantes

- O histórico de chat é mantido por `Lead + ChatSession`. Como a sessão é vinculada ao `blog_chat_flow` com `context: { post_id }`, não há vazamento de histórico entre posts diferentes de um mesmo visitante — cada post gera uma sessão diferente.
- A credential usada é a do ChatFlow "Blog Agent" (`blog_chat_flow.credential`). Se não estiver configurada, retornar 503 com mensagem orientando o admin.

---

#### Critérios de aceite

1. Visitar `/posts/:id` e enviar uma pergunta retorna resposta baseada na transcrição
2. Recarregar a página mantém o histórico de conversa (mesmo `session_id` no localStorage)
3. Pergunta fora do tema recebe resposta educada de redirecionamento
4. Sem transcrição, endpoint retorna 422 (não 500)
5. Sem credential configurada no ChatFlow, retorna 503 com mensagem clara

---

### Tarefa 1.6: Painel admin de Posts

**Sprint:** 1 — Core da Publicação  
**Estimativa:** 1 dia  
**Tipo:** Backend + Frontend

---

#### Contexto

O admin precisa de uma interface para criar, editar e gerir posts. Como `Post` é um model separado de `Medium`, recebe sua própria página admin — similar em estrutura à `MediaPage` existente.

---

#### Onde começa

`Post` model e endpoints admin autenticados existem. `MediaPage` é a referência de padrão visual e de comportamento.

#### Onde termina

Admin consegue criar/editar posts, disparar transcrição e geração de corpo.

---

#### O que precisa ser feito

##### No Backend

Endpoints admin autenticados (`Api::V1::Posts`):
```
GET    /api/v1/posts          # Listar todos (com paginação)
POST   /api/v1/posts          # Criar post
GET    /api/v1/posts/:id      # Buscar post
PUT    /api/v1/posts/:id      # Atualizar post
DELETE /api/v1/posts/:id      # Deletar post
POST   /api/v1/posts/:id/transcribe      # Disparar transcrição
POST   /api/v1/posts/:id/generate_body   # Gerar corpo via IA
```

##### No Frontend

**Nova rota** admin (protegida como `OgRoute` ou `VisitorRoute`):
```tsx
<Route path="posts" element={<OgRoute><PostsPage /></OgRoute>} />
```

**Novo arquivo:** `frontend/src/app/pages/PostsPage.tsx`

Estrutura similar à `MediaPage`:
- Grid de cards com thumbnail, título, status de transcrição, badge "Featured"
- Drawer lateral para criar/editar: título, descrição, autor, avatar URL, toggle active/featured
- Upload de arquivo (vídeo) e thumbnail
- Seção "Pipeline IA":
  - Badge de `transcription_status` com polling a cada 10s quando `'processing'`
  - Botão "Transcrever vídeo" (desabilitado se sem arquivo ou status `processing`)
  - Botão "Gerar corpo" (desabilitado se `transcription_status !== 'done'`; abre modal para escolher `credential_id`)
- Área de edição do `body` (rich text): usar TipTap ou similar para editar o HTML do `body`

---

#### Critérios de aceite

1. Admin cria um post com título e vídeo — post aparece na grid
2. Admin dispara transcrição e o badge muda para "Processando" sem recarregar
3. Após conclusão, badge muda para "Concluído" automaticamente (polling)
4. Admin dispara geração de corpo e o rich text editor é preenchido com o HTML
5. Admin edita o corpo no rich text editor e salva — alteração persiste
6. Admin marca um post como "Featured" e o toggle é salvo

---

## Sprint 2 — Experiência do Blog (Frontend)

### Tarefa 2.1: Página de detalhe do post (`/posts/:id`)

**Sprint:** 2 — Experiência do Blog  
**Estimativa:** 2 dias  
**Tipo:** Frontend

---

#### Contexto

Página pública com layout inspirado no Medium/Quora: vídeo em destaque, metadados, corpo rich text, navegação e espaços para comentários e chatbot. Usa o design system da E9 (cores e fontes já no Tailwind config).

---

#### Onde começa

Endpoint `GET /api/v1/public/posts/:id` disponível. Design system E9 no Tailwind config.

#### Onde termina

Rota `/posts/:id` pública, com vídeo, corpo, navegação e slots para comentários e chatbot.

---

#### O que precisa ser feito

##### No Frontend

**Nova rota pública** em `App.tsx`:
```tsx
<Route path="/posts" element={<PostListPage />} />
<Route path="/posts/:id" element={<PostPage />} />
```

**Novo arquivo:** `frontend/src/app/pages/posts/PostPage.tsx`

Layout:

```
┌─────────────────────────────────────────┐
│  <Topbar /> (já existente)              │
├─────────────────────────────────────────┤
│  <video> — full width, aspect-video     │
│  controles nativos                      │
├───────────────────────┬─────────────────┤
│  Título (text-3xl+)   │                 │
│  [Avatar] Autor · Data│  <BlogChatbot>  │
│  ─────────────────────│  (sidebar       │
│  Corpo rich text      │   fixa no       │
│  (post.body_html      │   desktop lg:)  │
│   renderizado via     │                 │
│   dangerouslySetInner │                 │
│   HTML)               │                 │
│                       │                 │
│  [← Anterior | Próx→] │                 │
│  [Lista de índice]    │                 │
│  <BlogComments />     │                 │
├───────────────────────┴─────────────────┤
│  <BlogChatbot /> (mobile: abaixo tudo)  │
├─────────────────────────────────────────┤
│  <PublicFooter /> (já existente)        │
└─────────────────────────────────────────┘
```

No mobile, layout em coluna única. No desktop (`lg:`), grid de 2 colunas: conteúdo (70%) + chatbot sidebar (30%).

---

#### Observações importantes

- `body_html` vem do ActionText via `post.body.to_s` (HTML). Renderizar com `dangerouslySetInnerHTML`. ActionText já sanitiza o HTML no backend — não há risco de XSS se o conteúdo for gerado pelo sistema.
- Se `body_html` for vazio, renderizar apenas o campo `description` como fallback em `<p>`.
- Player de vídeo: `<video controls>` nativo, sem biblioteca. Range headers do ActiveStorage já suportam streaming.
- Data formatada em pt-BR: "28 de abril de 2026".

---

#### Critérios de aceite

1. `/posts/:id` exibe o vídeo reproduzível no topo
2. Título, autor (com avatar se existir) e data aparecem logo abaixo
3. Corpo rich text é renderizado com formatação (h2, p, blockquote)
4. Sem `body`, página não quebra — exibe só vídeo e metadados
5. Layout responsivo: mobile coluna única, desktop com chatbot sidebar
6. Página carrega em < 3s (excluindo buffering de vídeo)

---

### Tarefa 2.2: Seção de comentários públicos

**Sprint:** 2 — Experiência do Blog  
**Estimativa:** 1 dia  
**Tipo:** Frontend

---

#### Contexto

Comentários públicos com threads aninhadas, sem necessidade de conta. O `Comment` model já suporta `author_name` e `author_email` (campos existentes na tabela).

---

#### Onde começa

Endpoints `GET` e `POST` de comentários em `/api/v1/public/posts/:id/comments` disponíveis.

#### Onde termina

Visitante lê e posta comentários na página do post.

---

#### O que precisa ser feito

##### No Frontend

**Novo componente:** `frontend/src/app/pages/posts/PostComments.tsx`

- Lista comentários: `author_name`, `body`, data. Replies com indent visual (padding-left).
- Formulário: campos Nome (obrigatório), E-mail (obrigatório), Comentário (obrigatório). Botão "Publicar".
- Após sucesso: refetch dos comentários. Toast de confirmação.

Sem moderação, edição ou exclusão neste escopo.

---

#### Critérios de aceite

1. Comentários listados do mais antigo para o mais recente
2. Visitante comenta com nome + e-mail + texto — aparece na lista imediatamente
3. Sem nome ou e-mail, botão fica desabilitado
4. Replies aparecem indentados abaixo do comentário pai

---

### Tarefa 2.3: Chatbot contextualizado no post

**Sprint:** 2 — Experiência do Blog  
**Estimativa:** 1 dia  
**Tipo:** Frontend

---

#### Contexto

Interface de chat para o visitante interagir com o "Blog Agent" especializado no vídeo. O backend já está pronto (Tarefa 1.5); aqui é só o componente React.

---

#### Onde começa

Endpoint `POST /api/v1/public/posts/:id/chat` disponível. `PostPage` existe.

#### Onde termina

Chatbot funcional na sidebar do post.

---

#### O que precisa ser feito

##### No Frontend

**Novo componente:** `frontend/src/app/pages/posts/PostChatbot.tsx`

- Histórico de mensagens + input + botão enviar
- `session_id` persistido no `localStorage` com chave `post_chat_${postId}`
- Visual glassmorphic alinhado com o design da E9 (dark/light theme)
- Enquanto carrega a resposta: indicador de "digitando..." (três pontos animados)

---

#### Critérios de aceite

1. Pergunta sobre o conteúdo do vídeo retorna resposta baseada na transcrição
2. Sessão persiste ao recarregar a página
3. Pergunta fora do tema recebe resposta educada
4. Funciona em mobile (seção abaixo dos comentários)

---

### Tarefa 2.4: Navegação entre posts e listagem `/posts`

**Sprint:** 2 — Experiência do Blog  
**Estimativa:** 1 dia  
**Tipo:** Frontend

---

#### Contexto

Navegação clássica de blog: anterior/próximo em cronologia simples (sem "smart" — só troca de página). Mais uma listagem geral em `/posts` para SEO e indexação.

---

#### Onde começa

Endpoint `GET /api/v1/public/posts/:id/adjacent` disponível. `PostPage` existe.

#### Onde termina

Navegação funcional e rota `/posts` com lista de cards.

---

#### O que precisa ser feito

##### No Frontend

**Navegação em `PostPage`:**
```
← [Título do anterior]        [Título do próximo] →
```
Links React Router. Se não houver anterior ou próximo, o lado some (não desabilitado).

**Índice** abaixo da navegação: lista de todos os posts (`GET /api/v1/public/posts`) com thumbnail pequena + título + data. Post atual destacado visualmente.

**Nova página** `frontend/src/app/pages/posts/PostListPage.tsx`:
- Grid de cards: thumbnail, título, data, trecho do `description`
- Rota: `/posts`

---

#### Critérios de aceite

1. Clicar "Próximo" leva ao post imediatamente mais antigo
2. No post mais antigo, "Anterior" não aparece; no mais recente, "Próximo" não aparece
3. Índice lista todos os posts com o atual destacado
4. `/posts` exibe grid clicável de todos os posts publicados

---

## Sprint 3 — Integração com a Home e SEO

### Tarefa 3.1: VSL da home apontando para o post featured

**Sprint:** 3 — Integração e SEO  
**Estimativa:** 0.5 dia  
**Tipo:** Frontend

---

#### Contexto

O `MediaShowcase` na `HomePage` já exibe a VSL com `identifier: 'demo'`. Com o blog ativo, clicar na VSL deve levar para `/posts/:id` do post featured.

---

#### Onde começa

`MediaShowcase` em `frontend/src/components/campfire/MediaShowcase.tsx`. Endpoint `GET /api/v1/public/posts/featured` disponível.

#### Onde termina

Clicar na VSL navega para `/posts/:id` do post featured (ou mais recente).

---

#### O que precisa ser feito

##### No Frontend

Modificar `MediaShowcase`:
1. Fazer fetch adicional de `GET /api/v1/public/posts/featured`
2. Se houver post featured, ao clicar navegar para `/posts/:id` via `useNavigate`
3. Se não houver post featured, manter comportamento atual (modal de vídeo)

---

#### Critérios de aceite

1. Com post featured cadastrado, clicar na VSL navega para `/posts/:id`
2. Sem post featured, comportamento da home permanece inalterado

---

### Tarefa 3.2: SEO — Meta tags e Open Graph

**Sprint:** 3 — Integração e SEO  
**Estimativa:** 0.5 dia  
**Tipo:** Frontend

---

#### Contexto

Cada post precisa de meta tags para ser indexável pelo Google. O componente `SEO` já existe e é usado na `HomePage`.

---

#### Onde começa

`PostPage` existe. `SEO` component em `frontend/src/components/seo/SEO.tsx`.

#### Onde termina

Posts com meta tags corretas.

---

#### O que precisa ser feito

##### No Frontend

Em `PostPage`:
```tsx
<SEO
  title={`${post.title} | Blog`}
  description={post.description?.slice(0, 160) || ''}
  image={post.thumbnail_url || post.file_url}
  type="article"
/>
```

Garantir que o corpo do post usa `<h2>` para seções — conteúdo semântico além do vídeo.

Em `PostListPage`: meta description genérica sobre o blog.

---

#### Critérios de aceite

1. `<title>` inclui o título do post
2. `<meta name="description">` tem o description do post (truncado em 160 chars)
3. `<meta property="og:image">` aponta para a thumbnail
4. HTML da página tem `<h1>` para título e `<h2>` nos tópicos do corpo

---

## Dependências entre tarefas

```
T1.1 → T1.2 → T1.3
T1.1 → T1.4
T1.1 → T1.5 (ChatFlow setup pode ser feito em paralelo)
T1.1 → T1.6 (admin page)
T1.4 + T1.5 → T2.1 → T2.2, T2.3, T2.4
T2.1 → T3.1, T3.2
```

---

## Riscos e decisões de design

| Risco | Decisão |
|---|---|
| Medium usado em muitos lugares | Model `Post` separado — sem acoplamento |
| ChatFlow por post = dezenas de registros | Um único ChatFlow "Blog Agent", transcription injetada dinamicamente |
| Corpo de post como jsonb (editável mas limitado) | ActionText (`has_rich_text`) — editável com rich text editor, suporta imagens |
| Vídeos 150-300MB travam o request | Transcrição em Thread assíncrona, polling de status no admin |
| Chatbot sem transcrição | Endpoint retorna 422; botão só aparece com `transcription_status === 'done'` |
| SEO em SPA React | Google crawla JS. HTML semântico nos tópicos reforça indexação textual |

---

## Regras de Execução

1. **Padrões visuais:** toda interface nova deve seguir o design system do ai9 — usar os componentes existentes (`Button`, `SideDrawer`, `PageHeader`, `glass-panel`, variáveis CSS de tema), nunca inventar estilos do zero
2. **Git:** apenas commits locais, sem `git push` em nenhum momento da implementação
3. **Abordagem incremental:** planejar cada tarefa antes de implementar, dividir em partes pequenas e commitar ao final de cada parte funcional — nunca implementar tudo de uma vez
4. **Ordem de implementação:** backend primeiro, frontend depois — cada endpoint deve estar funcional e testável antes de iniciar o componente React correspondente

---

## Estimativa total

| Sprint | Tarefas | Estimativa |
|---|---|---|
| Sprint 1 — Backend | 6 tarefas | ~6.5 dias |
| Sprint 2 — Frontend | 4 tarefas | ~5 dias |
| Sprint 3 — Integração | 2 tarefas | ~1 dia |
| **Total** | **12 tarefas** | **~12.5 dias** |

Buffer recomendado: +15% = ~14 dias de trabalho efetivo.
