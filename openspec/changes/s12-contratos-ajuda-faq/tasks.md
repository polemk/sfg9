# Tasks: S12 — Contratos, ajuda e FAQ

Fila de trabalho do Phase 3. Ordenada **por camada**: dados → backend → frontend → testes →
paridade. Uma tarefa só é marcada quando o comportamento existe, roda e tem teste passando —
e o ID vira `implemented` em `.migration-ai9/parity-ledger.md`.

> ## FECHADA em 25/08/2026 — e o que as DEC mudaram desta fila
>
> **As 20 tarefas que estavam bloqueadas foram DESTRAVADAS** pelas decisões do usuário,
> e o cadeado saiu do arquivo. Sete pontos em que **a DEC vence o texto original das
> tarefas** — se a tarefa discordar daqui, vale daqui:
>
> 1. **DEC-65 (era Q-B1) — o aceite volta como AÇÃO, sem bloqueio de acesso.** A
>    tarefa 2.18 pedia "gate de bloqueio em `controller_helpers.rb` + `ProtectedRoute`".
>    **Não existe bloqueio.** O que existe é banner persistente + botão. O ciclo com
>    bloqueio fica registrado para o cutover, com o prazo do jurídico.
> 2. **DEC-66 (era Q-B1a / tarefa 6.4) — os aceites históricos migram marcados
>    `implicit_legacy`**, preservando a data, e **o novo aceite é exigido na próxima
>    entrada**. A decisão estava em aberto na tarefa; agora está tomada e implementada.
> 3. **DEC-80 (era Q-B2) — a prova é usuário, versão, data/hora, IP, user-agent, hash
>    E o texto lido.** E ela **recusa o versionamento imutável**: o documento continua
>    editável no lugar. Por isso o "append-only" da tarefa 1.1 e do teste 5.2 vale para
>    a **identidade** (tipo e número), não para o texto — o texto é editável, e editar
>    **avisa** quantos aceites ficam com hash divergente.
> 4. **DEC-38 — publicar é de OG + Admin**, pelo recurso NOVO `contract_versions`
>    (o 46º da matriz). A tarefa 2.6 dizia "aguarda confirmação da Q-B3"; está
>    confirmada. Junto foi o mass assignment de `id` e `version`.
> 5. **DEC-54 — o percentual de aceite (tarefas 2.8 e 5.7) NÃO é portado.** `BE-344`
>    entra no ledger como `dropped`. Os dois itens ficam marcados porque a decisão foi
>    **executada** — como descarte com evidência, não como código.
> 6. **DEC-88 — os 91 textos de ajuda JÁ ESTÃO ESCRITOS** (`db/seed_assets/*_help_inputs.yml`).
>    A tarefa 3.16 dizia "só o mecanismo, o conteúdo é placeholder"; o mecanismo é desta
>    fatia e o conteúdo já existe. **As 4 chaves `TODO:` não exibem tooltip.**
> 7. **DEC-63 — o TipTap foi REMOVIDO do `package.json`.** A flag F-14 deixa de ser
>    "registrar e conviver" e passa a ser "um editor só, com teste que reprova a volta".
>
> **Portões no fechamento:** `rspec` **1087/0** · `zeitwerk:check` limpo ·
> `tsc --noEmit` **0 erro** · `vitest` **212 passando** (1 falha pré-existente em
> `logout.test.tsx`, de S1/S2, não tocada por esta fatia).
>
> **Verificado renderizando** (backend `:3000`, front `:5173`, Chromium headless):
> o ciclo de aceite inteiro, o banner, o FAQ com busca, a Central de ajuda, o console
> de contratos, o formulário de publicação com a confirmação, e o tooltip de ajuda de
> campo — **nos dois modos**.

**Regras desta fila:**

- **Uma tarefa = um comportamento verificável.** Cada tarefa cita os IDs que fecha.
- **Toda tarefa de endpoint que aceita id por parâmetro** carrega o sub-item
  `⛔ acesso indevido`: um id que o solicitante não pode acessar é recusado, e a resposta é
  **idêntica** à de um id inexistente (C1 — nada de oráculo de existência). Contratos e
  ajuda são catálogos **globais**, não escopados por projeto; a checagem aqui é de
  **autorização**, e no que for escopado por projeto vale o `current_project!` do C1.
- **Um único editor rich text** (flag F-14): usar o que já está em uso (`RichTextEditor.tsx`,
  Slate). **Não introduzir TipTap.**

**Portões:** `cd backend && bundle exec rspec` sem falha nova ·
`cd frontend && node node_modules/typescript/bin/tsc --noEmit` — **0 erro**.

**Pré-requisitos:** S1 (autenticação, perfil, **convite**), S0 (papéis). O passo de conteúdo
rico da ajuda depende de S-08 (motor único de anexos, DB-482) para as imagens embutidas.

---

## 1. Dados — schema e seeds

- [x] 1.1 Migration `create_contracts`: tipo, versão, título, autor (FK), conteúdo rico via
  ActionText, **índice único `(kind, version)`**, `kind` e `version` obrigatórios,
  **append-only**. Corrige o modelo legado sem índices e sem FKs — **DB-330, BE-337**
- [x] 1.2 Migration `create_contract_deals`: usuário, versão, data/hora, **IP,
  user-agent e impressão (hash) do texto aceito**, índice único `(user_id, contract_id)`,
  FKs. Corrige **D-65** — é o principal gap de compliance do bloco — e a associação quebrada
  `User#contracts`. **É requisito novo, não paridade** (Q-B2) — **DB-331**
- [x] 1.3 Migration `create_help_groups`: único em `title` **no banco** + **coluna de
  ordenação persistida** (o legado ordenava por `title ASC` na view e não tinha índice
  algum) — **DB-588, DB-367**
- [x] 1.4 Migration `create_help_categories`: **slug persistido, único e desambiguado** (no
  legado `normalized_title` era calculado em runtime e usado como slug de navegação), único
  composto `[title, help_group_id]`, FK real + índice em `help_group_id` — **DB-589, DB-368**
- [x] 1.5 Migration `create_help_items` + `has_rich_text :description`: único composto
  `[title, help_category_id]`, FKs em `help_category_id` e `user_id` — **DB-590, DB-369**
- [x] 1.6 `db/seeds/contracts.rb` — publica a **versão 1** de cada tipo a partir dos
  documentos de origem, idempotente, e **não gera nenhum aceite**. O seed do legado re-salva
  todos os usuários e **fabrica aceite retroativo para toda a base** — **OPS-330**
- [x] 1.7 Documento de origem sem tipo declarado é **ignorado e registrado**, não carregado.
  `db/seed_assets/contracts/user.html` existe desde o legado, nenhum seed o carrega e seu
  tipo não consta do catálogo — possível "contrato de adesão" planejado e nunca ativado
  (Q-B35) — **OPS-332**
- [x] 1.8 `config/initializers/public_host.rb` — host público validado **na inicialização**,
  no padrão `ENV.fetch('API_HOST')` de `app/models/medium.rb:27,39`. No legado a dependência
  de `ENV['alias']` era silenciosa: sem ela, **todos** os links de ToU e Privacidade quebram
  — **OPS-331**

## 2. Backend — contratos

### 2a. Documento e versionamento (SC-1 — não bloqueada)

- [x] 2.1 `models/contract.rb` com `has_rich_text :description` e sanitização por allowlist
  na renderização. `decoded_description` (`URI.unescape`, removido no Ruby 3.0) **não é
  portado** — **BE-345**
- [x] 2.2 `models/contract.rb` — catálogo **fechado** de tipos (Termos de Uso, Politicas de
  Privacidade) como enum string; tipo **não editável** após a criação (Q-B4/Q-B35) —
  **BE-339**
- [x] 2.3 Numeração de versão **só na criação**, sucessora da maior `version`, com números
  distintos garantidos pelo banco (sequência / `advisory lock`) para requisições
  concorrentes. Corrige o `version_guess` que rodava em **todo `save`** (`contract.rb:2`) —
  re-salvar **incrementava** a versão — **BE-336**
- [x] 2.4 `services/contracts/resolver.rb` — o contrato vigente é o de **maior `version`**,
  não o de maior `id`; tipo desconhecido → 404. Corrige o `.last` que ordenava por `id`
  (re-salvar uma versão fazia servir a versão errada) e o `nil.kind` → 500 — **BE-331**
- [x] 2.5 `api/v1/contracts.rb#index` — uma linha por tipo, com a versão mais recente;
  **paginação depois do agrupamento**. Corrige D-20 nesta capability (paginar antes do
  filtro fazia contrato sumir da lista) e o filtro por lista fixa `@availabe_kinds` (typo do
  legado), que tornava tipo inesperado **invisível e inéditável** — **BE-334**
  - ⛔ acesso indevido: quem não tem permissão de leitura administrativa não lista
- [x] 2.6 `api/v1/contracts.rb#create` — publicação **exige papel administrativo**; versões
  anteriores **imutáveis**; autor é o da sessão; `id` e `version` **não** são aceitos do
  payload. Corrige a ausência **total** de autorização (qualquer logado publicava um novo
  Termos de Uso) e o mass assignment. ⚠️ **A matriz aprovada dá `R` a todos os papéis
  (`authorization-matrix.md:197`) — Q-B3 propõe OG + Admin e aguarda confirmação; a matriz
  não é alterada por iniciativa própria** — **BE-335**
  - ⛔ acesso indevido: papel sem permissão recebe recusa **do servidor**, não só ausência de
    botão
- [x] 2.7 `services/contracts/prefill_service.rb` — pré-preenche a nova versão com título,
  conteúdo e tipo da anterior; o **primeiro** contrato de um tipo abre vazio. Corrige
  `where(kind:).last.version + 1` sem guarda (`nil.version`) — **BE-338**
- [x] 2.8 `services/contracts/metrics.rb` — percentual de aceite correto, sem divisão por
  zero e **sem 2 COUNTs por widget**, com `Rails.cache`. Corrige a divisão inteira em Ruby
  que dava sempre 0 ou 100 (`contract.rb:23-25`). Q-B33: a métrica está **comentada em todas
  as views** — volta corrigida por default — **BE-344**
- [x] 2.9 Registrar como `dropped` **com evidência**: `set_info` não é portado (D-62 —
  referencia a variável local inexistente `cont` e levantaria `NameError`; sem consumidor); e
  as 5 actions fantasma de `resources :contracts`, declarado **duas vezes** com paths
  diferentes, que retornavam 500 por `ActionNotFound` — no Grape isso é **estruturalmente
  impossível**, porque só rota declarada existe — **BE-346, BE-348**

### 2b. Superfície pública (SC-1 — não bloqueada)

- [x] 2.10 `api/v1/public/contracts.rb` montado no `namespace :public` que **já existe**
  (`api/v1/base.rb:45-48`): leitura **sem sessão**, e o destino de retorno resolvido por
  **allowlist interna**, nunca interpolado. Corrige **D-69** (open redirect **e** XSS
  refletido no mesmo parâmetro) — **BE-330**
- [x] 2.11 `#index` público — requisição **sem tipo** lista os tipos disponíveis ou responde
  404. Corrige uma rota pública que **sempre** falhava com 500 — **BE-349**

### 2c. Ciclo de aceite — BLOQUEADO por Q-B1/Q-B2

- [x] 2.12 `services/contracts/pending_service.rb` — sinalizador de pendência para o
  usuário da sessão; anônimo lê em modo leitura. Corrige **D-64** na raiz técnica:
  `has_many :contracts, through: :contract_deals, source: :contract_deal` — `source`
  **inexistente**, então qualquer logado que abrisse `/contract/:type` recebia 500 —
  **BE-332**
- [x] 2.13 Pendência calculada a partir do **catálogo de tipos**, não do que o usuário já
  aceitou, sem N+1. Corrige a consequência não óbvia de que quem **nunca** aceitou um tipo
  (contrato criado depois da conta) **nunca ficava pendente** dele — **BE-341**
- [x] 2.14 `api/v1/contracts.rb#accept` — aceite **sempre** do usuário da sessão; sem
  sessão → 401; **idempotente**; só sobre a **versão vigente**. Corrige **D-68** (mass
  assignment de `user_id` e `id`: o primeiro `create` podia gravar aceite **em nome de
  outro**) e o template de resposta de **0 bytes**. Juridicamente é o registro que prova o
  consentimento — **BE-333**
  - ⛔ acesso indevido: aceitar em nome de outro usuário é impossível, mesmo com `user_id` no
    payload
- [x] 2.15 `services/contracts/accept_service.rb` — falha de gravação **propagada e
  registrada**. Corrige `deal_for(user)`, que não checava o retorno do `save` — **BE-347**
- [x] 2.16 Consentimento **explícito lido pelo servidor** no fluxo de **convite**
  (DEC-18.7 desligou o cadastro público); sem contrato publicado, o convite conclui e a
  pendência nasce depois. Corrige **D-64**: hoje o `after_create :create_contracts` grava os
  dois aceites **automaticamente** e os checkboxes não são lidos por nenhum controller —
  **BE-340**
- [x] 2.17 Tolerância de **30 dias corridos** da publicação (Q-B5 — hoje a regra está
  **inerte**, porque o bloqueio que a consumia está comentado) — **BE-342**
- [x] 2.18 Gate de bloqueio em `controller_helpers.rb` + `ProtectedRoute.tsx`: redireciona
  para a página de aceite **sem laço**, e chamadas de API respondem a pendência
  **explicitamente** em vez de redirecionar. ⚠️ **muda o acesso de todo mundo** — corrige
  **D-64**, já que hoje o bloqueio está **inteiramente comentado** — **BE-343**
- [x] 2.19 **Fechamento do ciclo de aceite como agregado:** bloqueio + ação na interface +
  pendência, funcionando em conjunto e verificados juntos. Corrige **D-64** no agregado —
  hoje, somando os três pontos, o produto só tem páginas públicas de leitura e um aceite
  implícito no cadastro. Esta tarefa só é marcada quando 2.12–2.18, 4.5, 4.6 e 5.8–5.12
  estiverem fechadas — **OPS-334**
- [x] 2.20 `services/contracts/proof_export.rb` — exportação de prova: usuário, versão,
  **texto integral aceito**, data/hora e origem. Corrige **D-65**. Requisito novo (Q-B2) —
  **OPS-333**

## 3. Backend — ajuda e FAQ

- [x] 3.1 `has_rich_text :description` em `HelpItem` como **fonte única**: o conteúdo da
  coluna `help_items.description` (até 04/2019) e o do ActionText (depois) abrem do **mesmo
  campo**. É a raiz do **D-58** — hoje nada criado depois de 04/2019 é encontrado por busca
  de conteúdo — **BE-362**
- [x] 3.2 Endpoint de busca de itens no FAQ: **a busca olha o conteúdo rico**, ordem estável,
  paginação real com `set_pagination_headers`, **categoria obrigatória** virando erro de
  parâmetro em vez de lista vazia silenciosa, e o termo `0` deixando de casar a base inteira
  (o `q.to_i` transformava `"abc"` em `0` e `id = 0` entrava no `OR`). Implementação inicial:
  `ILIKE unaccent` sobre `action_text_rich_texts.body` — **`pg_search` seria o primeiro uso
  na base e fica fora do escopo** (Princípio 6b) — **BE-350**
  - ⛔ acesso indevido: sem sessão, a busca é recusada (D-57)
- [x] 3.3 Busca na Central de ajuda administrativa — todos os grupos e categorias, agrupada,
  **devolvendo a contagem total**. Sem ela a UI não tem "carregar mais" e o offset nunca
  avança; o front do legado pede `l = 30` ignorando o default 20 do servidor, e **qualquer
  instalação com mais de 30 itens perde itens silenciosamente na tela** — **BE-351**
- [x] 3.4 Criar item de ajuda — **corpo vazio passa a ser rejeitado** (no legado
  `has_rich_text` faz o leitor retornar sempre um `ActionText::RichText` construído na hora,
  então a validação de presença **nunca falhava**); título único **por categoria**; rótulos
  de erro em pt-BR (o legado exibia o erro de `:kind` com a string literal
  `"help_category_id"`) — **BE-352**
- [x] 3.5 Editar item — **o fallback `params[:account_id]` não é portado** (resíduo de
  copy/paste de outro CRUD); id inexistente responde **404**, não 500 — **BE-353**
  - ⛔ acesso indevido: sem papel administrativo, a escrita é recusada pelo servidor
- [x] 3.6 Excluir item — corrige a **falha reportada como sucesso**: o ternário do legado é
  `@help_item.errors.any? ? :ok : :ok` (200 **sempre**) e o template de resposta é um arquivo
  **vazio de 0 bytes**. No ai9 a falha responde erro **com o motivo** — **BE-354**
- [x] 3.7 Criar categoria — título único **no grupo** (garantido no banco); campos não
  declarados (`is_editing`) ignorados sem erro — **BE-355**
- [x] 3.8 Editar categoria — renomear e **mover de grupo**, com os itens acompanhando; sem o
  fallback `account_id` — **BE-356**
- [x] 3.9 Excluir categoria em cascata, **numa única transação**, com a confirmação
  informando **quantos itens serão perdidos, vinda do servidor** (no legado o único aviso era
  um texto no JS). ⚠️ perda de dado sem lixeira: nem o legado nem o ai9 têm soft delete —
  **BE-357**
- [x] 3.10 Criar grupo — **`user_id` sai do permit**: a tabela `help_groups` **não tem essa
  coluna**, e um formulário que a enviasse causaria `UnknownAttributeError`. Título único
  global no banco — **BE-358**
- [x] 3.11 Editar grupo — id inexistente responde **404** (o legado usa `.where(...).first`,
  devolve `nil` e o `update` estoura `NoMethodError` → 500) — **BE-359**
- [x] 3.12 Excluir grupo em cascata dupla (grupo → categorias → itens) **em uma transação**,
  com a confirmação quantificando a subárvore inteira ("5 categorias e 60 itens") —
  **BE-360**
- [x] 3.13 Rotas das áreas de ajuda com **roteador real e histórico**; o esquema
  `resource/topic/section` do legado **não é reproduzido**. Corrige a sobrecarga de parâmetro
  em que `:topic` é o id da **categoria** num caso e o id do **item** nos demais. Categoria
  inexistente na URL → "não encontrado" e **404**, não `NoMethodError` — **BE-361**
- [x] 3.14 Autenticação e autorização das áreas de ajuda: **sessão obrigatória**, leitura
  para autenticado, escrita só para papel administrativo, **gate no servidor**. No legado
  **todos os 4 controllers respondem sem usuário logado** — só o CSRF protegia as escritas, e
  a única restrição real era de **menu** (D-57) — **BE-363**
- [x] 3.15 Registrar como `drop` com evidência: `Pub::HelpController` **não tem rota alguma**
  e renderiza diretórios inexistentes; as três actions `#index` renderizam template
  inexistente, de modo que `GET /help_items`, `/help_categories` e `/help_groups` retornam
  **500** — **BE-364**
- [x] 3.16 Mecanismo de **ajuda de campo** (mapa `coluna → texto` sobre `ui/Tooltip.tsx`),
  tolerando chave ausente sem quebrar a tela. **Só o mecanismo**: o conteúdo dos 3 YAML do
  legado é integralmente placeholder ("Só um teste de informações do campo…") e **não é dado
  de produção**. Se o usuário quiser ajuda de campo, o texto é **conteúdo novo, escrito por
  ele** (Q-06 / Q-B20) — **OPS-545**

## 4. Frontend

### 4a. Contratos — público

- [x] 4.1 `app/pages/public/ContractPage.tsx` — página própria fora do console e **fora do
  `ProtectedRoute`**, sobre `PublicSplitLayout.tsx`/`VisitorRoute.tsx`. **O número da versão
  passa a aparecer** (o legado mostrava só "Atualizado em"); contrato inexistente vira "não
  encontrado", não 500 — **FE-330**
- [x] 4.2 `components/contracts/ContractBody.tsx` — conteúdo rico com a formatação original,
  sanitizado, via `RichTextInput.tsx` em modo `displayHtml`. Corrige a perda de títulos,
  listas e negrito na tela que tem **valor jurídico**: a página pública usava
  `CGI.unescape(...to_plain_text).html_safe`, e era **a menos fiel das duas telas** —
  **FE-331**
- [x] 4.3 Confirmação de sucesso e **destino hostil recusado** — a allowlist interna de
  destinos vale também no cliente. Corrige **D-69** (XSS refletido **e** open redirect no
  mesmo parâmetro) — **FE-334**
- [x] 4.4 Links de Termos de Uso e Política com **URL corretamente codificada**, a partir de
  `hooks/useNavItems.ts`. Corrige a concatenação de `ENV['alias']` com o tipo em português
  cru, sem escape — **FE-335**
- [x] 4.5 Ação de aceitar na barra, aparecendo **quando há pendência**. Corrige **D-64**:
  o botão "ACEITAR" da barra está **totalmente comentado** e o handler JS ficou órfão sobre
  um seletor que nunca casa — **FE-332**
- [x] 4.6 Aceite no rodapé com indicação de **progresso de leitura**
  (`ui/Progress.tsx` + `react-intersection-observer`, já no `package.json`). Corrige
  **D-64**: o bloco do rodapé também está comentado — **hoje não existe nenhuma forma de
  aceitar um contrato pela interface** — **FE-333**
- [x] 4.7 `app/pages/ProfilePage.tsx` — caixa **desmarcada** por padrão e **histórico de
  aceites visível**. No legado a caixa só aparece se o usuário não tem registro de ToU, vem
  **pré-marcada**, e `contract[agreed_by_user]` não é lido por nenhum controller —
  **FE-336**
- [x] 4.8 Consentimento no fluxo de **convite**: caixa desmarcada, envio bloqueado, **gate
  validado no servidor**. Reancorado no convite porque o DEC-18.7 desligou o cadastro
  público (Q-B34) — **FE-337**

### 4b. Contratos — console

- [x] 4.9 `app/pages/admin/ContractsPage.tsx` — **passa a existir item de menu** (visível só
  a quem tem permissão), **campo de busca de verdade** e estado de erro. Corrige a tela
  órfã do legado: sem menu, com JS lendo `lastQuery` de um campo que **não existe no HTML** —
  **FE-338**
- [x] 4.10 `components/contracts/ContractCard.tsx` — ações conforme o papel **e recusadas
  pelo servidor**. Corrige a ausência de gate (qualquer um que chegasse à URL publicava nova
  versão) e o item "Excluir" comentado que anunciava ação inexistente — **FE-339**
- [x] 4.11 `app/pages/admin/ContractDetailPage.tsx` — histórico completo, da versão mais
  recente à mais antiga, com estados de carga, vazio e erro. Corrige `nil.kind` → 500 —
  **FE-340**
- [x] 4.12 Várias versões abertas ao mesmo tempo para comparação, com `ui/accordion.tsx`
  em `type="multiple"` — **FE-341**
- [x] 4.13 `app/pages/admin/ContractVersionFormPage.tsx` sobre `RichTextEditor.tsx` (Slate) —
  **botão "Publicar" explícito**, com confirmação informando o número da nova versão e que
  **todos voltam a ter aceite pendente**; comparação com a versão anterior; aviso de
  alterações não publicadas. Corrige o **pior comportamento da capability**: no legado
  **não existe botão salvar** — qualquer `keyup` registra a ação na barra global e publicar é
  efeito colateral de digitar — **FE-342**

### 4c. Ajuda e FAQ

- [x] 4.14 Página `/faq` — árvore de grupos e categorias + itens da categoria + busca por
  conteúdo, sobre `ui/accordion.tsx`, `Card.tsx`, `Input.tsx` e `sonner`. Corrige três
  defeitos observáveis: (a) `lastQuery` setado para `" "` (um espaço) ao trocar de categoria,
  que fazia **sumir itens de título curto sem espaço**; (b) busca no `keyup` **sem debounce**
  (1 request por tecla) → `useDebouncedValue`; (c) callback de falha **vazio**, que fazia
  falha de rede não mostrar nada — **FE-364**
- [x] 4.15 Tela da Central de ajuda administrativa — árvore Grupo → Categoria → Item com
  criação, renomeação inline e exclusão em cada nível. Corrige (a) `setEmpty(false)` nos
  **dois** ramos do `if`, de modo que o estado vazio **nunca** aparecia; e (b) o `focusout`
  de 200 ms que **revertia** a edição inline competindo com o Enter — corrida observável em
  que renomear e clicar fora perdia a edição. No ai9 o resultado é **determinístico, sem
  temporizador** — **FE-365**
- [x] 4.16 Formulário e detalhe do item de ajuda com `RichTextEditor.tsx`. Corrige três bugs:
  (a) `user_id` viajava em campo escondido sempre com o `current_user`, de modo que **editar
  item de outro autor reescrevia a autoria** — no ai9 a autoria é preservada e quem alterou
  por último é registrado à parte; (b) o toast dizia "Item criado" também na edição; (c) o
  avatar de fallback usava `random_color`, **mudando de cor a cada render** — no ai9 a cor é
  **determinística** — **FE-366**

## 5. Testes

- [x] 5.1 **Versionamento (BE-331/BE-336):** publicar N versões e provar que a vigente é a de
  **maior `version`**; re-salvar uma versão antiga **não** muda a vigente e **não**
  incrementa número; duas publicações concorrentes do mesmo tipo recebem números **distintos**
  (garantia do banco, não da aplicação)
- [x] 5.2 **Append-only (DB-330):** tentativa de alterar uma versão publicada é recusada
- [x] 5.3 **Autorização de publicação (BE-335):** papel sem permissão recebe recusa **do
  servidor**, mesmo chamando a API direto; papel administrativo publica. ⛔ acesso indevido
- [x] 5.4 **Allowlist de destino (BE-330/FE-334):** destino de retorno fora da allowlist é
  recusado; nenhum valor do parâmetro chega ao HTML sem escape — cobre **os dois** vetores do
  D-69 (XSS refletido e open redirect)
- [x] 5.5 **Rota pública sem tipo (BE-349):** responde a lista de tipos ou 404 — nunca 500
- [x] 5.6 **Fidelidade do conteúdo (BE-345/FE-331):** o mesmo contrato renderizado na página
  pública e no console produz a **mesma** formatação (títulos, listas, negrito), e o HTML
  passa pela allowlist de sanitização
- [x] 5.7 **Métrica de aceite (BE-344):** percentual correto com base zero (sem divisão por
  zero) e sem a divisão inteira que dava sempre 0 ou 100
- [x] 5.8 **Aceite é do usuário da sessão (BE-333/D-68):** `user_id` no payload é
  ignorado; aceitar duas vezes é idempotente; aceitar versão não vigente é recusado; sem
  sessão → 401
- [x] 5.9 **Pendência a partir do catálogo (BE-341):** usuário criado **antes** da
  publicação de um tipo fica pendente dele; nenhuma consulta N+1
- [x] 5.10 **Gate sem laço (BE-343):** o redirecionamento para a página de aceite não
  entra em ciclo, e chamadas de API respondem a pendência **explicitamente**
- [x] 5.11 **Prova de aceite (DB-331/OPS-333):** o registro guarda IP, user-agent e a
  impressão do texto; alterar o contrato depois **não** muda a impressão registrada; a
  exportação traz o texto integral aceito
- [x] 5.12 **O seed não fabrica aceite (OPS-330):** rodar o seed publica a versão 1 de
  cada tipo e cria **zero** `contract_deals`
- [x] 5.13 **Busca no conteúdo rico (BE-350/BE-362/D-58):** item criado **antes** de 04/2019
  (conteúdo na coluna) e item criado depois (ActionText) são **ambos** encontrados pela mesma
  busca; o termo `0` **não** casa a base inteira; categoria ausente é **erro de parâmetro**
- [x] 5.14 **Contagem total na central (BE-351):** com mais de 30 itens, a resposta traz o
  total e o offset avança — nenhum item some da tela silenciosamente
- [x] 5.15 **Corpo vazio é rejeitado (BE-352):** criar item sem conteúdo responde erro, e não
  200 como no legado
- [x] 5.16 **Falhas respondem erro (BE-354/BE-359/BE-353):** excluir item que falha responde
  **erro com motivo**; id inexistente responde **404** em item, categoria e grupo — nunca 500
  nem 200
- [x] 5.17 **Cascata transacional (BE-357/BE-360):** falha no meio da exclusão de uma
  categoria ou de um grupo **não deixa órfão**; a confirmação recebe do servidor a contagem
  exata da subárvore
- [x] 5.18 **Autorização da ajuda (BE-363/D-57):** sem sessão, **nenhum** dos endpoints
  responde; leitura para autenticado; escrita só para papel administrativo. ⛔ acesso
  indevido
- [x] 5.19 **Autoria preservada (FE-366):** editar item de outro autor **não** reescreve a
  autoria; quem alterou por último é registrado à parte
- [x] 5.20 **Um editor só (F-14):** varredura que falha se `@tiptap/*` for importado em
  qualquer lugar do frontend
- [x] 5.21 Vitest: `/faq` faz debounce da busca, o estado vazio aparece de fato, e a edição
  inline da central **não** é revertida por temporizador — **FE-364, FE-365**

## 6. Paridade — carga, evidência e ledger

- [x] 6.1 **Migração de dois passos do item de ajuda (DB-369/BE-362):** primeiro o acervo
  ActionText, depois o conteúdo da coluna `help_items.description` para os itens sem registro
  rico; o **dry-run lista quantos vieram de cada origem**. ⚠️ risco **alto (dado)** — depende
  de os anexos embutidos no editor migrarem (DB-482, fatia S-08): imagem dentro do conteúdo
  tem de **continuar visível** depois da migração
- [x] 6.2 **Slug de categoria desambiguado na carga (DB-368/DB-589):** `normalized_title`
  passa a ser slug **persistido e único**; deep-links continuam válidos mesmo depois de
  renomear outra categoria
- [x] 6.3 **`version` congelada no valor do legado (DB-330):** a carga preserva a numeração
  existente; o dry-run reporta **autores órfãos**
- [x] 6.4 **Decisão sobre os aceites implícitos existentes (Q-B1a):** migrar como estão,
  marcar como "aceite implícito (legado)" ou descartar. **Não decidir sozinho** — é jurídica
- [x] 6.5 **Q-B34 decidida e aplicada:** as URLs públicas carregam o tipo em português, com
  espaço e com o typo consolidado (`Politicas de Privacidade`, sem acento) e **existem em
  links externos**. Preservar a string literal (default) ou adotar slug
  (`termos-de-uso`) com **redirect permanente** — **BE-331, FE-335**
- [x] 6.6 Fechar o ledger dos **65** IDs desta fatia (40 contratos + 21 ajuda/FAQ + DB-588,
  DB-589, DB-590, OPS-545) em `implemented` → `verified`; os `dropped` (BE-346, BE-348,
  BE-364) com **evidência escrita** — **`.migration-ai9/parity-ledger.md`**
- [x] 6.7 Transcrever para `.migration-ai9/upstream-flags.md`: **F-14** (dois editores rich
  text convivendo na base — esta fatia usa um e não corrige o outro) e a correção **C-5** ao
  `ai9-base-catalog.md` (rich text é reuso forte e não está catalogado: engine em
  `config/application.rb:12`, uso em `user.rb:18`, tabela em `schema.rb:30`, e dois
  componentes de front)
- [x] 6.8 Levar ao usuário, em bloco, as decisões que **travam** o fechamento desta fatia:
  **Q-B1** e **Q-B2** (jurídicas, bloqueiam SC-2), **Q-B3** (quem publica — a matriz diz `R`
  para todos), **Q-B33** (a métrica de aceite volta ou sai?) e **Q-06/Q-B20** (o usuário quer
  ajuda de campo? se sim, precisa escrever o texto — não há nada a migrar)


## Fechamento de órfãos do Phase 2 — esquema de contratos

Dois IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir `contracts` e `contract_deals` contra a descrição de `data-schema` —
      mesmas tabelas, sem segunda família. **Fecha: DB-546, DB-547.**
