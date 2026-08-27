# Proposal: S12 — Contratos, ajuda e FAQ

## Why

Duas capabilities pequenas, independentes do domínio financeiro, que compartilham a **mesma
infra reaproveitada** — ActionText para o conteúdo rico, o editor rich text do ai9, o padrão
de paginação e o design system — e por isso são entregues juntas:

- **`contracts` (40 IDs)** — Termos de Uso e Política de Privacidade: página pública de
  leitura, versionamento append-only, console administrativo e o ciclo de aceite.
- **`help-faq` (21 IDs)** — a árvore Grupo → Categoria → Item da central de ajuda e a tela
  de FAQ do usuário final. `ai9-conventions.md` §9 item 10 diz literalmente que **não existe
  modelo nem tela** de ajuda na base ai9.

Esta fatia existe por três razões:

1. **O ciclo de aceite de contrato está morto em produção, por três causas independentes
   (D-64).** O bloqueio de acesso está **inteiramente comentado**; os dois botões "ACEITAR"
   estão comentados nas views — **hoje não existe nenhuma forma de aceitar um contrato pela
   interface**; e o cálculo de pendência levanta exceção, porque
   `has_many :contracts, through: :contract_deals, source: :contract_deal` aponta para uma
   `source` **inexistente** — qualquer usuário logado que abrisse `/contract/:type` recebia
   500. O aceite real é **implícito**: um `after_create` no usuário grava os dois aceites
   sem nenhuma interação, e o seed **fabrica aceite retroativo para toda a base**. Os
   checkboxes vêm **pré-marcados** e não são lidos por nenhum controller.
2. **O rich text é reuso forte e não catalogado (C-5 / D-B15).** `action_text/engine`
   (`config/application.rb:12`), `has_rich_text` (`user.rb:18`), a tabela
   `action_text_rich_texts` (`schema.rb:30`), `RichTextEditor.tsx` (Slate) e
   `RichTextInput.tsx` já existem. O `Contract#description` legado **já é ActionText**, e o
   item de ajuda tem **dois acervos** (coluna até 04/2019, ActionText depois) que precisam
   virar um só.
3. **A superfície pública tem duas vulnerabilidades no mesmo parâmetro (D-69):** XSS
   refletido **e** open redirect no destino de retorno da página de contrato.

## What Changes

Entrega as sub-fatias **SC-1** e **SC-2** de
`.migration-ai9/map/receivables-renegotiations.md` §1, e a fatia **S-13** de
`.migration-ai9/map/data-infra.md` §1.

### Dependências

| Direção | O quê |
| ------- | ----- |
| S12 depende de | **S1** (autenticação, perfil, convite — o consentimento se ancora no fluxo de convite, DEC-18.7), **S0** (papéis e hierarquia) |
| S12 depende de infra ai9 | ActionText + `RichTextEditor.tsx`; `namespace :public` de `api/v1/base.rb:45-48`; `PublicSplitLayout.tsx`/`VisitorRoute.tsx`; `hooks/useNavItems.ts` |
| S12 depende de | **S-08** do bloco de dados (motor único de anexos) para os anexos embutidos no conteúdo rico de ajuda (DB-482) |
| S12 **não** depende de | `receivables`, `renegotiations`, `risk` — pode correr em paralelo a S6 e S9 |

### ⚠️ Bloqueio declarado

**SC-2 (página pública e ciclo de aceite) NÃO deve ser iniciada antes das respostas a
Q-B1 e Q-B2.** As duas são **jurídicas**, não técnicas:

- **Q-B1 (D-64)** — o aceite deve voltar a ser **explícito**? Reativar o fluxo é o
  comportamento **pretendido pelo código**, mas **não é o comportamento de produção** — não
  cabe em "preservar comportamento" nem em "corrigir defeito". Sub-perguntas: (a) o que
  fazer com os aceites implícitos **já existentes** — migrar como estão, marcar como
  "aceite implícito (legado)" ou descartar? (b) o consentimento passa a viver no fluxo de
  **convite**, já que o DEC-18.7 desligou o cadastro público?
- **Q-B2 (D-65)** — qual é o conjunto mínimo de **prova** exigido? Hoje `contract_deals`
  guarda apenas `user_id`, `contract_id` e `created_at`. Recomendação técnica: IP,
  user-agent e **impressão imutável do texto aceito** — mas isso é **requisito novo, não
  paridade**, e o mínimo probatório é decisão do usuário e do jurídico.

**SC-1 e S-13 não estão bloqueadas** e podem começar imediatamente. As tarefas bloqueadas
estão marcadas com 🔒 em `tasks.md`.

### Decisões que governam esta fatia

- **Vigente é a maior `version`, não o maior `id`.** O `.last` do legado ordenava por `id`,
  então **re-salvar** uma versão fazia o sistema servir a versão errada (BE-331). E o
  `version_guess` rodava em **todo `save`** (`contract.rb:2`), de modo que re-salvar
  **incrementava** a versão (BE-336).
- **Append-only.** Versões anteriores são imutáveis; a numeração é atribuída **só na
  criação**, com garantia do banco para concorrentes (índice único `(kind, version)`).
- **Um único editor rich text.** Convivem dois na base — Slate em `RichTextEditor.tsx` e
  TipTap no `package.json`. Esta fatia usa **um**, e não introduz o outro (flag **F-14**).
- **A matriz de autorização é contrato aprovado.** `authorization-matrix.md:197` dá
  `contracts` como **`R` para os quatro papéis**, mas publicar exige papel administrativo
  (BE-335). **Q-B3** propõe OG + Admin com `R` para os demais; a matriz **não é alterada por
  iniciativa própria**.
- **Nenhum aceite é gerado pela carga.** O seed do legado re-salva todos os usuários e
  fabrica aceite retroativo para toda a base; no ai9 o seed publica a **versão 1** de cada
  tipo e **não gera nenhum aceite** (OPS-330).

## Impact

- **Afetado:** `backend/app/{controllers/api/v1,controllers/api/v1/public,controllers/api/entities,models,services}`,
  `backend/db/{migrate,seeds}` + `schema.rb`, `backend/spec/**`,
  `frontend/src/{app/pages/public,app/pages/admin,components/contracts,components/help,hooks}`.
- **Superfície pública nova:** `api/v1/public/contracts.rb` sob o `namespace :public` que
  **já existe**; página fora do `ProtectedRoute`.
- **Item de menu novo:** a tela de contratos do legado é **órfã** (sem menu, com JS lendo um
  campo que não existe no HTML). No ai9 passa a existir, visível só a quem tem permissão.
- **Migração de dado em dois passos** para o item de ajuda: a coluna `help_items.description`
  (conteúdo até 04/2019) e a associação ActionText (conteúdo depois) viram **um campo só** —
  é a raiz do D-58, em que nada criado depois de 04/2019 era encontrado pela busca.
- **Não afetado:** o legado `sfg` (read-only), e os domínios financeiros.
- **Requirements:** já existem em `openspec/specs/contracts/spec.md` (40) e
  `openspec/specs/help-faq/spec.md` (21). **Não são recriados aqui.**

## IDs de inventário cobertos (64 + 2 adotados no fechamento do Phase 2 = 66)

> O ID das rotas mortas da central de ajuda (`drop`) passou a ter dono em **S14**, que
> registra o descarte com evidência — ver "Fronteiras", onde ele está nomeado. Dois IDs de esquema foram adotados
> aqui; ver a seção do fechamento, no fim.

**Contratos (40):** `.migration-ai9/map/receivables-renegotiations.md` §2.9–§2.10 —
27 `build` · 10 `adapt` · 3 `reuse`.
**Ajuda/FAQ (21):** `.migration-ai9/map/data-infra.md` §2.5 — 19 `build` · 1 `adapt` ·
1 `drop`.
**Tabelas da ajuda (4):** `.migration-ai9/map/data-infra.md` §2.1 e §2.2 (DB-588…590,
OPS-545) — pertencem a `data-schema`/`ops-config`, e a **fatia S-13 do mapa de dados é a
única que os reivindica**; são executados aqui porque a tabela nasce com a capability.

### `contracts` — backend (§2.9)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-330 | **adapt** | `api/v1/public/contracts.rb` sobre o `namespace :public` existente; destino de retorno por **allowlist interna** |
| BE-331 | build | `services/contracts/resolver.rb` — vigente = **maior `version`**, não maior `id` |
| BE-332 | build | `services/contracts/pending_service.rb` — sinalizador de pendência 🔒 |
| BE-333 | build | `api/v1/contracts.rb#accept` — sempre do usuário da sessão, idempotente 🔒 |
| BE-334 | build | `#index` — uma linha por tipo, paginação **depois** do agrupamento |
| BE-335 | build | `#create` — publicação exige papel administrativo (Q-B3) |
| BE-336 | build | `models/contract.rb` — numeração **só na criação**, com garantia do banco |
| BE-337 | build | Migration com **índice único** `(kind, version)`; `kind` e `version` obrigatórios |
| BE-338 | build | `services/contracts/prefill_service.rb`; o primeiro contrato abre vazio |
| BE-339 | build | `models/contract.rb` — catálogo fechado de tipos (Q-B4/Q-B35) |
| BE-340 | **adapt** | `services/contracts/accept_service.rb` no fluxo de **convite** (DEC-18.7) 🔒 |
| BE-341 | build | Pendência calculada a partir do **catálogo de tipos** 🔒 |
| BE-342 | build | Tolerância de 30 dias corridos da publicação (Q-B5) 🔒 |
| BE-343 | build | Gate em `controller_helpers.rb` + `ProtectedRoute.tsx`, **sem laço** 🔒 |
| BE-344 | build | `services/contracts/metrics.rb` — percentual sem divisão inteira (Q-B33) |
| BE-345 | **adapt** | `has_rich_text :description` + sanitização por allowlist |
| BE-346 | **reuse** → `dropped` | `set_info` não é portado (D-62: `NameError` garantido) |
| BE-347 | build | Falha de gravação do aceite **propagada e registrada** 🔒 |
| BE-348 | **reuse** → `dropped` | Grape só expõe rota declarada; as 5 actions fantasma somem |
| BE-349 | build | `api/v1/public/contracts.rb#index` — sem tipo, lista os disponíveis ou 404 |

### `contracts` — frontend e dados (§2.10)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| FE-330 | **adapt** | `app/pages/public/ContractPage.tsx` fora do `ProtectedRoute` |
| FE-331 | **adapt** | `components/contracts/ContractBody.tsx` — conteúdo rico sanitizado |
| FE-332 | build | Ação de aceitar na barra, quando há pendência 🔒 |
| FE-333 | build | Aceite no rodapé com progresso de leitura 🔒 |
| FE-334 | build | Confirmação de sucesso; destino hostil **recusado** (D-69) |
| FE-335 | **adapt** | Links de ToU e Política com **URL corretamente codificada** |
| FE-336 | **adapt** | `ProfilePage.tsx` — caixa **desmarcada**, histórico de aceites 🔒 |
| FE-337 | **adapt** | Consentimento no fluxo de **convite**, validado no servidor 🔒 |
| FE-338 | build | `app/pages/admin/ContractsPage.tsx` — **passa a ter item de menu** e busca |
| FE-339 | build | `components/contracts/ContractCard.tsx` — ações conforme o papel |
| FE-340 | build | `app/pages/admin/ContractDetailPage.tsx` — histórico completo |
| FE-341 | **reuse** | `ui/accordion.tsx` com `type="multiple"` |
| FE-342 | **adapt** | `ContractVersionFormPage.tsx` — **botão "Publicar" explícito** |
| DB-330 | build | `create_contracts` — índice único `(kind, version)`, **append-only** |
| DB-331 | build | `create_contract_deals` — IP, user-agent e impressão do texto (D-65) 🔒 |
| OPS-330 | build | `db/seeds/contracts.rb` — versão 1 de cada tipo, **nenhum aceite gerado** 🔒 |
| OPS-331 | **adapt** | `config/initializers/public_host.rb` — host validado **na inicialização** |
| OPS-332 | build | Documento de origem sem tipo declarado é **ignorado e registrado** (Q-B35) |
| OPS-333 | build | `services/contracts/proof_export.rb` — exportação de prova 🔒 |
| OPS-334 | build | Agregado de SC-2: bloqueio + ação na interface + pendência 🔒 |

### `help-faq` (data-infra §2.5)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-350 | build | Endpoint de busca de itens no FAQ — **busca no conteúdo rico** (D-58) |
| BE-351 | build | Busca na central administrativa, agrupada, **com contagem total** |
| BE-352 | build | Criar item — **corpo vazio passa a ser rejeitado** |
| BE-353 | build | Editar item — sem o fallback `params[:account_id]`; 404 em vez de 500 |
| BE-354 | build | Excluir item — corrige a **falha reportada como sucesso** |
| BE-355 | build | Criar categoria — título único **no grupo** |
| BE-356 | build | Editar categoria — renomear e **mover de grupo**, itens acompanham |
| BE-357 | build | Excluir categoria em cascata, **numa transação** |
| BE-358 | build | Criar grupo — `user_id` **sai do permit** (a coluna não existe) |
| BE-359 | build | Editar grupo — 404 em vez de `NoMethodError` |
| BE-360 | build | Excluir grupo em cascata dupla, numa transação |
| BE-361 | build | Rotas com **histórico real**; fim da sobrecarga de `:topic` |
| BE-362 | build | `has_rich_text :description` em `HelpItem` — **fonte única** |
| BE-363 | **adapt** | Sessão obrigatória; escrita só para papel administrativo (D-57) |
| — | **drop** | `Pub::HelpController` e as 3 actions `#index` que retornam 500 — o ID é **de S14**, que registra o descarte com evidência (ver Fronteiras) |
| FE-364 | build | Página `/faq` — árvore + itens + busca por conteúdo |
| FE-365 | build | Central de ajuda administrativa — árvore com CRUD em cada nível |
| FE-366 | build | Formulário e detalhe do item, com `RichTextEditor.tsx` |
| DB-367 | build | Grupo — único em `title` **no banco** + ordenação persistida |
| DB-368 | build | Categoria — **slug persistido, único e desambiguado** |
| DB-369 | build | Item + conteúdo rico — migração de **dois passos** |

### Tabelas da ajuda (data-infra §2.1/§2.2 — reivindicadas só pela fatia S-13)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-588 | build | Tabela `help_groups` |
| DB-589 | build | Tabela `help_categories` (FK real, único em `slug`) |
| DB-590 | build | Tabela `help_items` + `has_rich_text :description` |
| OPS-545 | build? | Ajuda de campo é **mecanismo**, não conteúdo — o texto do legado é placeholder |

## Perguntas em aberto que afetam esta fatia

| # | Assunto | Situação |
| - | ------- | -------- |
| **Q-B1** (D-64) | O aceite deve voltar a ser explícito? E o que fazer com os aceites implícitos existentes? | **BLOQUEIA SC-2** — jurídica |
| **Q-B2** (D-65) | Conjunto mínimo de prova do aceite (IP, user-agent, impressão do texto) | **BLOQUEIA SC-2** — jurídica |
| Q-B3 | Quem publica nova versão? A matriz dá `R` a todos os papéis (`authorization-matrix.md:197`) | Proposta: OG + Admin. Aguarda confirmação |
| Q-B33 | O percentual de aceite está comentado em **todas** as views — desligado por performance ou por estar errado? | Default: volta corrigido |
| Q-B34 | URLs públicas carregam o tipo em português, com espaço e typo consolidado (`Politicas de Privacidade`) e existem em links externos | Default: preservar a string literal; slug + redirect permanente é a alternativa |
| Q-B35 / Q-B4 | Tipos de contrato configuráveis pela UI? Existe `db/seed_assets/contracts/user.html` que nenhum seed carrega | Default: catálogo fechado; o documento órfão é **registrado**, não carregado |
| Q-06 (data-infra) | Ajuda de campo: o usuário quer? Se sim, **o texto é conteúdo novo, escrito por ele** — não há nada a migrar | Default: portar só o mecanismo |
| F-14 | Convivem dois editores rich text no ai9 (Slate e TipTap) | Decisão desta fatia: usar **um**; registrar o outro como flag de upstream |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-546 | build | `contracts` | S12 é dona de contratos |
| DB-547 | build | `contract_deals` | idem |

**Os dois são as mesmas tabelas que a fatia já constrói**, vistas pelo inventário de
`data-schema`. Ficam aqui para o ledger fechar pelos dois lados.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`BE-364` é de S14**, não desta fatia. As rotas e actions mortas da central de ajuda (as
  3 `#index` que retornam 500) são `drop`, e S12 **não tem tarefa de código** para elas — a
  evidência é registrada em S14, junto dos demais descartes com prova. S12 apenas as cita,
  para não parecerem esquecidas.
- **`OPS-545` é de S12**, disputado com S13 e S14. A ajuda de campo é **mecanismo** (mapa
  `coluna → texto`), e o mecanismo nasce nesta fatia; o texto do legado é placeholder. S13 e
  S14 apenas a citam.
- **`OPS-477`** (leitor de arquivo, de S13) só é construído se esta fatia semear HTML de
  arquivo. Se semear, **S12** escreve o leitor com limite de tamanho; se não, S13 não o
  constrói. A decisão precisa sair daqui.
