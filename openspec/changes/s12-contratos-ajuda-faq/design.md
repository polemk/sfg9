# Design: S12 — Contratos, ajuda e FAQ em ai9

> O mapa item-a-item **não é duplicado aqui**. Contratos:
> `.migration-ai9/map/receivables-renegotiations.md` §2.9 (backend), §2.10 (frontend e
> dados), §3 (decisões D-B15), §5 (perguntas Q-B1…Q-B5, Q-B33…Q-B35), §6 (correção C-5 ao
> catálogo). Ajuda/FAQ: `.migration-ai9/map/data-infra.md` §2.5 (`help-faq`), §2.1 (DB-588…590),
> §2.2 (OPS-545), §1 (fatia S-13).

## 1. O eixo comum: ActionText já está na base (C-5 / D-B15)

O `ai9-base-catalog.md` **não menciona** rich text. Verificando os arquivos:

| Peça | Onde | Situação |
| ---- | ---- | -------- |
| Engine | `backend/config/application.rb:12` — `require 'action_text/engine'` | Ativo |
| Uso existente | `backend/app/models/user.rb:18` — `has_rich_text :biography` | Ativo |
| Tabela | `backend/db/schema.rb:30` — `action_text_rich_texts` | Existe |
| Editor (front) | `frontend/src/components/RichTextEditor.tsx` (Slate) e `RichTextInput.tsx` | Existem |

Consequência de desenho: `Contract#description` e `HelpItem#description` são **`adapt`, não
`build`** — o legado já usa ActionText no contrato, e a base ai9 já tem tudo para recebê-lo.

**Decisão de fatia (flag F-14):** convivem **dois** editores rich text na base — Slate em
`RichTextEditor.tsx` e TipTap declarado no `package.json`. Esta fatia usa **um só**, o que
já está em uso (Slate), tanto no formulário de versão de contrato quanto no formulário de
item de ajuda. **Não introduzir o segundo.** A duplicidade é registrada em
`.migration-ai9/upstream-flags.md`, não corrigida (Princípio 6b).

**Sanitização é obrigatória nas duas capabilities.** O conteúdo de contrato e de ajuda é
renderizado como HTML; a allowlist de tags é aplicada na renderização, não na gravação.

## 2. Contratos

### 2.1 Versionamento — o que estava errado e como fica

| Defeito legado | Evidência | Desenho no ai9 |
| -------------- | --------- | -------------- |
| "Vigente" era o maior **`id`** | `.last` sem `order` | `services/contracts/resolver.rb` — vigente é a **maior `version`** do tipo (BE-331) |
| Re-salvar **incrementava** a versão | `contract.rb:2` — `before_save :version_guess` | Numeração atribuída **só na criação** (BE-336) |
| Concorrentes podiam receber o mesmo número | unicidade só de aplicação (`contract.rb:9`) | Sequência / `advisory lock` do PostgreSQL + **índice único `(kind, version)`** (BE-337, DB-330) |
| Publicar era efeito colateral de **digitar** | não existe botão salvar; qualquer `keyup` registra a ação na barra global | **Botão "Publicar" explícito**, com confirmação informando o número da nova versão e que **todos voltam a ter aceite pendente** (FE-342) |
| Mass assignment de `id` e `version` | `#create` | Autor é o da sessão; `id`/`version` não são aceitos do payload (BE-335) |
| `nil.version` no primeiro contrato | `where(kind:).last.version + 1` sem guarda | `prefill_service.rb`: o **primeiro** contrato de um tipo abre vazio (BE-338) |
| `kind` sem `presence` | contrato com `kind` nulo nunca aparecia na busca | `kind` e `version` obrigatórios, catálogo fechado (BE-337, BE-339) |

**Append-only** é a propriedade central: versões publicadas são **imutáveis**. É o que dá
sentido à impressão do texto aceito (DB-331) — sem imutabilidade, não existe garantia
técnica de **qual conteúdo** foi aceito, já que o texto vive em `action_text_rich_texts` e
pode ser alterado no próprio registro (D-65).

### 2.2 Superfície pública — dois problemas no mesmo parâmetro (D-69)

O destino de retorno da página pública de contrato era **interpolado** — resultando em XSS
refletido **e** open redirect na mesma variável.

Desenho: `api/v1/public/contracts.rb` monta em cima do `namespace :public` que **já existe**
(`api/v1/base.rb:45-48`, hoje com `Public::Media` e `Public::Chat`); o destino de retorno
vem de uma **allowlist interna** de rotas conhecidas, nunca do parâmetro. Um destino fora da
allowlist é recusado, e a página cai no destino padrão (BE-330, FE-334).

`config/initializers/public_host.rb` valida o host público **na inicialização**, seguindo o
padrão `ENV.fetch('API_HOST')` já usado em `app/models/medium.rb:27,39`. No legado a
dependência de `ENV['alias']` era silenciosa e não documentada em lugar nenhum: **sem ela,
todos** os links de Termos de Uso e Política quebram (OPS-331).

### 2.3 O ciclo de aceite — 🔒 bloqueado por Q-B1/Q-B2

O fluxo está morto por **três causas independentes**, e nenhuma delas é a mesma coisa:

1. O bloqueio de acesso está **inteiramente comentado** — não existe bloqueio algum
   (BE-343).
2. Os dois botões "ACEITAR" (barra e rodapé) estão comentados nas views — **hoje não existe
   nenhuma forma de aceitar um contrato pela interface** (FE-332, FE-333).
3. A pendência levanta exceção:
   `has_many :contracts, through: :contract_deals, source: :contract_deal` — a `source` não
   existe, então qualquer logado que abrisse `/contract/:type` recebia 500 (BE-332).

E o aceite que **existe** é implícito: um `after_create` no usuário grava os dois aceites
sem interação; o seed fabrica aceite retroativo para toda a base; os checkboxes de cadastro
e de "Minha Conta" vêm **pré-marcados** e não são lidos por nenhum controller (D-64).

> **A consequência é jurídica: o sistema registra hoje um aceite que o usuário nunca deu
> conscientemente.** Reativar o fluxo é o comportamento **pretendido pelo código**, mas não
> é o comportamento de produção — não cabe nem em "preservar comportamento" nem em
> "corrigir defeito". Por isso as tarefas correspondentes estão marcadas 🔒 e **não devem
> ser iniciadas** antes das respostas.

Quando desbloqueado, o desenho é:

- `contract_deals` com **usuário, versão, data/hora, IP, user-agent e impressão (hash) do
  texto aceito**, índice único `(user_id, contract_id)` e FKs (DB-331). Isso é
  **requisito novo, não paridade** — a definição do mínimo probatório é do usuário (Q-B2).
- Pendência calculada a partir do **catálogo de tipos**, não do que o usuário já aceitou —
  corrige a consequência não óbvia de que quem **nunca** aceitou um tipo (contrato criado
  depois da conta) **nunca ficava pendente** dele (BE-341).
- Aceite **sempre** do usuário da sessão, idempotente, só sobre a versão vigente; sem sessão
  → 401. Corrige o mass assignment de `user_id`/`id`, em que o primeiro `create` podia gravar
  aceite **em nome de outro** (BE-333, D-68).
- Gate de bloqueio **sem laço**: chamadas de API respondem a pendência **explicitamente**,
  em vez de redirecionar (BE-343).
- Consentimento ancorado no fluxo de **convite**, porque o DEC-18.7 desligou o cadastro
  público (BE-340, FE-337, Q-B34 do bloco de auth).
- O seed publica a **versão 1** de cada tipo e **não gera nenhum aceite** (OPS-330) — o
  oposto do seed legado.
- `proof_export.rb`: usuário, versão, **texto integral aceito**, data/hora e origem
  (OPS-333).

### 2.4 Autorização — a matriz é contrato aprovado

`authorization-matrix.md:197` dá `contracts` como **`R` para os quatro papéis**. BE-335 exige
papel administrativo para publicar, e a lista/detalhe/formulário existem no console. **A
matriz não é alterada por iniciativa própria**: a proposta é **OG + Admin** para publicar,
com `R` para os demais (Q-B3), e o gate real vive no servidor — no legado **não havia
autorização nenhuma**: qualquer logado publicava um novo Termos de Uso.

Reuso: `Permission`/`UserPermission`, `api/v1/permissions.rb`, `require_og!`
(`controller_helpers.rb:37`). **Não criar mecanismo paralelo.**

## 3. Ajuda e FAQ

### 3.1 A migração de dois passos (D-58 / BE-362 / DB-369)

`HelpItem` tem **dois acervos**:

- a coluna `help_items.description`, escrita até **04/2019**;
- a associação ActionText, usada depois — `has_rich_text` **sobrescreveu o leitor** da
  coluna, então nada criado depois de 04/2019 é encontrado por busca de conteúdo.

Desenho: um único `has_rich_text :description`, alimentado em **dois passos** no ETL —
primeiro o acervo ActionText, depois o conteúdo da coluna para os itens que não têm registro
rico. O **dry-run lista quantos vieram de cada origem**. Conteúdo de 2018 e de 2024 passam a
abrir do mesmo campo, e a busca cobre os dois acervos.

**Risco alto (dado):** depende de os anexos embutidos no conteúdo do editor migrarem
(DB-482, fatia S-08 do bloco de dados). Imagem dentro do conteúdo tem de continuar visível
depois da migração.

### 3.2 Busca — o que muda

| Defeito legado | Desenho no ai9 |
| -------------- | -------------- |
| Sem `ORDER BY` e sem paginação | Ordem estável + paginação real com `set_pagination_headers` |
| `q.to_i` transformava `"abc"` em `0`, e `id = 0` entrava no `OR` — o termo `0` casava a base inteira | Termo textual e filtro por id são parâmetros distintos, declarados no Grape |
| Categoria ausente devolvia lista vazia em silêncio | Categoria obrigatória vira **erro de parâmetro** |
| O front pede `l = 30` ignorando o default 20 do servidor — **qualquer instalação com mais de 30 itens perde itens silenciosamente na tela** | O servidor devolve a **contagem total**, e a UI tem "carregar mais" com offset que avança |

**Decisão de implementação (risco médio, mapa §2.5):** indexar rich text exige escolher
entre `ILIKE unaccent` sobre `action_text_rich_texts.body` e `pg_search`. **`pg_search` seria
o primeiro uso na base** — por Princípio 6b e proporcionalidade, começar por
`ILIKE unaccent`, que não introduz dependência. Se o volume exigir, `pg_search` vira
proposta própria, não efeito colateral desta fatia.

### 3.3 Paginação — reusar o padrão vivo, não estrear o Kaminari

O ai9 pagina com `limit`/`offset` + `set_pagination_headers(total, page, per_page)`
(`backend/app/controllers/api/v1/controller_helpers.rb:18`, `users_service.rb:79`).
`kaminari` está no `Gemfile:85` e **não é usado em lugar nenhum** — usá-lo seria o primeiro
uso na base. **Esta fatia reusa o padrão existente**, que já devolve o total. Mesma decisão
tomada em S6, pelo mesmo motivo.

### 3.4 Modelo de dados

| Tabela | Decisão |
| ------ | ------- |
| `help_groups` (DB-588 / DB-367) | Único em `title` **no banco** + **coluna de ordenação persistida**. O legado não tem índice nenhum além da PK, e a ordem era `title ASC` computada na view |
| `help_categories` (DB-589 / DB-368) | **Slug persistido, único e desambiguado**. No legado `normalized_title` era calculado em runtime, sem persistência nem garantia de unicidade, e era usado como slug de navegação — renomear outra categoria quebrava deep-links |
| `help_items` (DB-590 / DB-369) | Único composto `[title, help_category_id]`, FKs em `help_category_id` e `user_id`, busca reindexada sobre o campo rico único |

### 3.5 Autorização e rotas mortas

**Todos os 4 controllers de help do legado respondem sem usuário logado** — não sobrescrevem
`requires_current_user?`. Só o CSRF protegia as escritas, e a única restrição real era de
**menu** (D-57). No ai9: sessão obrigatória, leitura para autenticado, escrita só para papel
administrativo, **gate no servidor** (BE-363).

`Pub::HelpController` **não tem rota alguma** e renderiza diretórios inexistentes; as três
actions `#index` renderizam template inexistente, de modo que `GET /help_items`,
`/help_categories` e `/help_groups` retornam **500**. Entram como `drop` com evidência
(BE-364).

### 3.6 Ajuda de campo (OPS-545) — mecanismo, não conteúdo

Porta-se **só o mecanismo** (mapa `coluna → texto`, sobre `ui/Tooltip.tsx`, tolerando chave
ausente sem quebrar a tela). O conteúdo dos 3 YAML do legado é **integralmente placeholder**
— as ~60 chaves de recebíveis dizem literalmente "Só um teste de informações do campo…".
**Não é dado de produção; não há nada a migrar.** Se o usuário quiser ajuda de campo, o
texto é **conteúdo novo, escrito por ele** (Q-06 do bloco de dados, Q-B20 do bloco de
recebíveis). Por isso o ID está marcado `build?` no mapa.

## 4. Frontend

| Grupo | Alvo | Equivalente ai9 reaproveitado |
| ----- | ---- | ----------------------------- |
| Página pública de contrato | `app/pages/public/ContractPage.tsx` | `components/layouts/PublicSplitLayout.tsx`, `components/VisitorRoute.tsx` — **fora do `ProtectedRoute`**. O número da versão **passa a aparecer** (o legado mostrava só "Atualizado em"); contrato inexistente vira "não encontrado", não 500 |
| Corpo do contrato | `components/contracts/ContractBody.tsx` | `RichTextInput.tsx` em modo `displayHtml`. Corrige a divergência mais grave da capability: a página pública usava `CGI.unescape(...to_plain_text).html_safe` — **a tela que o usuário juridicamente lê era a menos fiel das duas** |
| Console de contratos | `app/pages/admin/{ContractsPage,ContractDetailPage,ContractVersionFormPage}.tsx` | `ui/{Table,Input,Card,Badge,accordion}.tsx`, `hooks/useNavItems.ts`. A tela do legado é **órfã**: sem item de menu, com JS lendo `lastQuery` de um campo que não existe no HTML |
| Aceite no perfil | `app/pages/ProfilePage.tsx` | Caixa **desmarcada** por padrão e histórico de aceites visível — no legado a caixa só aparecia se o usuário não tinha registro de ToU, vinha **pré-marcada**, e `contract[agreed_by_user]` não era lido por controller nenhum 🔒 |
| FAQ | página `/faq` | `ui/accordion.tsx`, `Card.tsx`, `Input.tsx`, `sonner`. Corrige: `lastQuery` setado para `" "` (um espaço) ao trocar de categoria, que fazia **sumir itens de título curto sem espaço**; busca no `keyup` **sem debounce** (1 request por tecla) → `useDebouncedValue`; e o callback de falha **vazio**, que fazia falha de rede não mostrar nada |
| Central administrativa | página admin | `Table.tsx`, `accordion.tsx`, `dialog.tsx`. Corrige `setEmpty(false)` nos **dois** ramos do `if` (o estado vazio **nunca** aparecia) e o `focusout` de 200 ms que **revertia** a edição inline competindo com o Enter — no ai9 o resultado é **determinístico, sem temporizador** |
| Item de ajuda | página de item | `RichTextEditor.tsx`. Corrige: `user_id` em campo escondido sempre com o `current_user`, de modo que **editar item de outro autor reescrevia a autoria**; o toast que dizia "Item criado" na edição; e o avatar de fallback com `random_color`, que **mudava de cor a cada render** |

## 5. O que fica registrado, não corrigido (Princípio 6b)

- **F-14** — dois editores rich text na base (Slate em uso, TipTap declarado). Esta fatia
  usa um; a duplicidade é registrada em `.migration-ai9/upstream-flags.md`.
- **C-5** — o `ai9-base-catalog.md` não menciona rich text, apesar de engine, tabela, uso e
  dois componentes de front existirem. Transcrever a correção.
- **Q-B34** — as URLs públicas de contrato carregam o tipo em português, com espaço e com
  typo consolidado (`Politicas de Privacidade`, sem acento), e **existem em links externos**.
  Adotar slug com redirect permanente é decisão do usuário, não desta fatia.

## 6. Ordem de execução e critério de pronto

1. **SC-1** (documento, versionamento, console) — **não bloqueada**, pode começar já.
2. **S-13** (ajuda e FAQ) — **não bloqueada**; corre em paralelo a SC-1, com a exceção do
   passo de conteúdo rico, que depende de S-08 (anexos) para as imagens embutidas.
3. **SC-2** (página pública e ciclo de aceite) — 🔒 **não iniciar** antes de Q-B1 e Q-B2.

**Portões:** `rspec` sem falha nova em relação ao baseline do Phase 1b; type-check do front
em **0 erro**.
