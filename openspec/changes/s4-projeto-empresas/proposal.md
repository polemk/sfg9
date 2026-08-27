# Proposal: S4 — Projeto e empresas (CRUD, membros, garantias, indicadores específicos)

> Fatia **S4** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/projects-cadastros.md` (fatias internas
> **§1 S2**, **§1 S3**, **§1 S4** e a parte de garantias da **§1 S8**).
> Depende de **S0** (fundação) e **S3** (catálogos globais).
> Desbloqueia **S5** (limites de risco), **S9** (renegociações), **S10** (indicadores) e
> **S11** (disponibilidades).

## Why

**`Project` é o tenant do Safegold inteiro.** Recebíveis, renegociações, risco, operações
estruturadas, indicadores, contratos e disponibilidades são todos escopados por projeto — e
a base ai9 é **declaradamente single-tenant**: zero `tenant_id`/`account_id`/
`organization_id` em `backend/app/models/`, com `blog_intake_session.rb` dizendo isso em
comentário. O mecanismo de escopo **não existe e nasce aqui** (contrato **C1**, desenho
normativo em `§0.6` do mapa).

O nome `projects` está **livre** na base: nenhum `app/models/project.rb`, nenhuma
`create_table "projects"` em `schema.rb`, zero referências no frontend. (Existe uma tabela
`work_projects` órfã, já registrada em `upstream-flags.md §7`; o `Project` do ai9 pré-trim
era projeto de entrega de conteúdo e saiu no Phase 1b.)

Esta fatia carrega **os dois defeitos mais graves do legado**:

- **D-28** — o projeto corrente vivia num **cookie**. Trocar o cookie trocava de tenant. E
  `memberships` permitia que **qualquer sessão se auto-adicionasse a qualquer projeto** e
  ganhasse o grupo "Gestão" inteiro (**D-34**).
- **D-29 / D-01** — sempre que chegava um id por parâmetro (`project_id`, `importing_id`,
  `company_id`, `project_guarantee_id`), **o filtro de projeto era descartado**. Não é
  hipótese: em `pub/project_guarantees_controller.rb:22` a relação escopada é
  **reatribuída**, não filtrada —
  `@project_guarantees = ProjectGuarantee.where(id: params[:project_guarantee_id])`.

Não se replica um IDOR. **Toda tarefa de endpoint desta fatia que aceita id por parâmetro
tem um teste explícito de que um id de OUTRO projeto é rejeitado.**

## What Changes

Quatro entregas que se sustentam:

1. **O projeto e o escopo** — `projects`, `memberships`, `users.current_project_id`,
   `current_project!`, CRUD, detalhe, membros, marcas Safegold/BI, limpeza do projeto de
   treinamento, logo, observação em texto rico, efeitos colaterais da criação. Daqui saem o
   gate `projects.count > 0` e o tenant do sistema inteiro.
2. **Empresas e fornecedores** — escopados por projeto, com documento CPF/CNPJ, logo e
   autopreenchimento por CNPJ.
3. **Conexões** — projeto↔portador (nos dois sentidos) e projeto↔indicador (globais e
   específicos do projeto).
4. **Garantias do projeto** — lista com filtros/ordenação/paginação e CRUD, sobre o catálogo
   de tipos entregue na S3.

Mudanças visíveis, decididas no Phase 2 e a registrar em
`.migration-ai9/improvements-log.md` como intencionais:

1. **Projeto corrente vem da sessão do servidor**, revalidado contra membership **a cada
   request** (D-28, DC-03). Cookie e campo escondido de formulário deixam de existir.
2. **`project_id` do payload é sempre ignorado**, no `create` **e** no `update` — o legado
   forçava no create e esquecia no update (BE-062, D-23).
3. **Paginação e ordenação passam a funcionar** em projetos, empresas, fornecedores e
   garantias (D-20 / DC-38). Hoje as listas voltam inteiras.
4. **Criar projeto com responsável novo envia link para a pessoa definir a própria
   credencial.** O legado **montava username e senha em texto plano** para a view (D-38).
   Nenhuma senha é montada, exibida ou enviada.
5. **Exclusão bloqueada responde 422 e a tela não navega** — o legado respondia `:ok` e o JS
   redirecionava, dizendo "removido com sucesso" sem ter removido (D-24).
6. **O criador do projeto permanece com membership própria** ao indicar um responsável
   existente (DC-14). No legado ele perdia a posse e ficava de fora.
7. **Slug imutável após a criação** (DC-17). O legado recalculava o slug em todo
   `before_validation`: renomear o projeto mudava as URLs.
8. **O detalhe de Fornecedor e o de Portador passam a existir** (D-22, DC-08).
9. **Nenhum padrão nem indicador de outro projeto viaja no payload** (a dependência
   pai↔níveis dos padrões de disponibilidade, cujos IDs são de **S11**) — o
   legado embutia `AvailabilityTemplate.all` num atributo `data-`.

## IDs de inventário cobertos (118 + 7 adotados no fechamento do Phase 2 = 125)

> Cinco IDs que esta seção listava (`current_project!`, participação, `projects`,
> `memberships`, `users.current_project_id`) passaram a ter dono em **S0** — ver
> "Fronteiras". Sete outros foram adotados aqui; ver a seção do fechamento, no fim.

Estratégia copiada de `.migration-ai9/map/projects-cadastros.md`. Requirements
correspondentes já existem em `openspec/specs/projects/spec.md` e
`openspec/specs/companies-carriers/spec.md` — **referenciados por ID, não recriados**.

### Backend — 47

**Empresas (§2.1)** — BE-050 `build` busca com escopo e paginação real · BE-051 `build`
`order_mode=dash` · BE-052 `build` resumo de limites de risco (**depende do bloco `risk`**) ·
BE-053 `build` `#form` com 422 explícito sem projeto · BE-054 `build` create com `project_id`
ignorado · BE-055 `build` update idem (DC-04) · BE-056 `build` destroy com 422 real ·
BE-057 `build` rotas que respondem · BE-058 `build` model com título único **por projeto**.

**Fornecedores (§2.1)** — BE-059 `build` escopo obrigatório · BE-060 `build` `#form` com 404 ·
BE-061 `build` create · BE-062 `build` update com `title`/`integration_key` obrigatórios ·
BE-063 `build` destroy com 422 · **BE-064 `adapt`** ReceitaWS sobre `Credential` (Q-03) ·
BE-065 `build` detalhe alcançável · BE-066 `build` model com documento validado e `cnaes`/
`atividades` em **um** `jsonb`.

**Projeto (§2.5)** — BE-080 `build` busca por membership · BE-081 `build` `order_mode=dash` ·
BE-082 `build` filtros `importing_id`/`project_id` **dentro** do membership (D-29) ·
BE-083 `build` autocomplete com `ILIKE` e limite · BE-084 `build` `#form` com responsáveis
por hierarquia · BE-085 `build` criar projeto + responsável novo por link de credencial
(D-38) · BE-086 `build` create sem responsável · BE-087 `build` create com responsável
existente (DC-14) · BE-088 `build` jobs de criação com progresso próprio · BE-089 `build`
update · BE-090 `build` evento de onboarding na trilha (DC-15) · BE-091 `build` destroy com
422 real · BE-092 `build` reset do projeto de treinamento, segmento por **configuração**
(D-26) · BE-093 `build` marca "Gerido pela Safegold" (DC-01/Q-02) · BE-094 `build` marca BI
(DC-16) · BE-095 `build` slug/chave/cor com slug imutável (DC-17, Lacuna L-09) ·
BE-096 `build` model com erros em pt-BR · **BE-097 `adapt`** observação em ActionText ·
o `current_project!` e o CRUD de participação são **consumidos de S0** (ver Fronteiras) ·
BE-100 `build` projetos do usuário (DC-18) ·
BE-101 `build + dropped com evidência` rotas mortas não portadas (DC-19).

**Conexões (§2.6)** — BE-102 `build` projeto↔portador sem `constantize` de parâmetro e sem
N+1 · BE-103 `build` lote com resultado por item · BE-104 `build` **um** endpoint de
candidatos · BE-105 `build` remover conexão isolada · BE-106 `build` projeto↔indicador ·
BE-107 `build` candidatos globais + do projeto · BE-108 `build` lote de indicadores ·
BE-109 `build` excluir indicador específico (global → 422).

**Garantias (§2.6)** — BE-118 `build` busca com `project_guarantee_id` que **não fura** o
escopo (D-29/D-32) · BE-119 `build` CRUD com só portadores conectados.

### Frontend — 45

**Empresas** — FE-051, FE-054 (DC-05: filtros fantasmas descartados), FE-055, FE-056,
FE-057, FE-058, FE-059 (DC-06: aba vazia não portada) — todos `build`.

**Fornecedores** — FE-069, FE-070 (DC-07: código morto não portado), FE-071, FE-072,
FE-073 `build`; **FE-074 `adapt`** (`ImageCropper` + ActiveStorage).

**Projeto** — FE-080, FE-081, FE-082, FE-084, FE-085, FE-088, FE-089 (DC-23: sem autosave),
FE-090, FE-091, FE-092, FE-093, FE-094, FE-095, FE-097, FE-098 `build`;
**FE-083 `adapt`** (Action Cable, D-86); **FE-086 `adapt`** e **FE-096 `adapt`**
(`AsyncSearchableSelect`); **FE-087 `adapt`** (`ImageCropper`); **FE-099 `reuse`**
(`RichTextEditor` — os contratos com ActionText já batem, zero componente novo).

**Conexões** — FE-100, FE-101, FE-102, FE-103, FE-104 `build`.

**Projeto corrente e menu** — FE-105 `build` (seletor na barra do console);
**FE-106 `adapt`** (resolução pela sessão, D-28); FE-118 `build` (aba "Projetos" do usuário,
DC-18); **FE-119 `adapt`** (menu do domínio com gate `projects.count > 0`; Disponibilidades
nasce visível, DEC-15.1).

**Garantias** — FE-113, FE-114, FE-115 `build`.

### Dados — 20

DB-050 `build` `companies` com único composto `(project_id, title)` · DB-051 `build` marca de
gestão (DC-01/Q-02) · DB-052 `build` `providers` com índices · DB-053 `build` par
`(document_type, document)` (DC-11) · DB-054 `build` campos ReceitaWS + `cnpj_fetched_at` ·
DB-055 `build` `cnaes`/`atividades` em **um** `jsonb` (D-25) · **DB-056 `adapt`**
`Provider#logo` por ActiveStorage · DB-067 `build` `projects.segment_id`/`.sub_segment_id`
(D-26) · DB-068 `build` `project_to_carrier_connections` como **única** ponte ·
DB-069 `build` FKs de `risk_controls` com política **simétrica** (bloquear, nunca cascatear)
· DB-070 `build` FKs de `receivable_entries` · DB-071 `build` FKs de `renegotiations` ·
a tabela `projects` (com `responsible_id` como referência de usuário de verdade) nasce em
**S0** (ver Fronteiras) · DB-081 `build` conexões com único `(project_id, carrier_id)` · DB-082 `build`
`project_indicator_connections` · DB-083 `build` `project_guarantees` com `observation` text
e `value` `decimal(14,2)` · `memberships` e `users.current_project_id` nascem em **S0**
(ver Fronteiras) · **DB-088 `reuse`** ActionText — **zero migration** · **DB-089 `adapt`** `Project#logo` ·
DB-090 `build` marca de gestão nas tabelas filhas (DC-01) · DB-091 `build` colunas `legacy_*`
(DEC-12) · DB-092 `build` `indicators.scope` explícito.

### Operação — 6

**OPS-050 `adapt`** `Credential` "receitaws" + `ReceitaWsService` (chave nunca no código) ·
OPS-055 `build` `lib/tasks/fix_company_links.rake` idempotente · OPS-080 `build`
`LinkDefaultMembersJob` com retry e falha visível (D-05) · OPS-085 `build`
`LinkDefaultUserToProjectsJob` com erro registrado (o `rescue` do legado era **vazio**) ·
**OPS-088 `reuse`** derivados do logo por `image_processing`, receita já pronta em
`medium.rb` · OPS-089 `build` `lib/tasks/fix_project_data.rake` idempotente e auditada.

**Placar:** 108 `build` (2 deles `build + dropped com evidência`) · 12 `adapt` · 3 `reuse`
(DB-088, FE-099, OPS-088) · 0 `build?` · 0 `drop` puro.

## Fronteiras — o que este change **não** cobre

- **Catálogos globais** (portadores, grupos, segmentos, subsegmentos, tipos de garantia) — **S3**.
- **Padrões e lançamentos de disponibilidade** (BE-110..117, BE-120..149, FE-107..112,
  FE-120..149, DB-085, DB-120..135, OPS-081..084, OPS-120..124, OPS-129) — **S11**.
  BE-117 é o endpoint `/projects/:id/availability`, e vai com o domínio dele.
- **Peças compartilhadas** BE-079, FE-050, FE-052, FE-053, FE-061, FE-066, FE-079,
  OPS-086 (trilha `AuditEvent`), OPS-087 (`ProjectProgressChannel` + `useJobProgress`) — **S0**.
  Esta fatia é a maior consumidora delas.
- **DB-073 / DB-074** (introspecção e volumetria do ETL) — **S14**.
- **BE-052** (resumo de limites de risco por empresa) e as contagens de "controles de risco"
  nas telas de Empresa e Portador **não fecham** sem `risk_controls`, do bloco `risk` (S5).
  A tarefa existe e fica pendente marcada.

## Dependências

| Depende de | Para quê |
| ---------- | -------- |
| **S0** | `require_role!`, `require_not_readonly!`, `DataTable`, `Pagination`, `AsyncSearchableSelect`, `MoneyInput`, `EmptyState`/`ErrorState`, `AuditEvent`, `ProjectProgressChannel`/`useJobProgress` |
| **S3** | `segments`, `sub_segments`, `carriers`, `project_guarantee_types` (FK) |
| **bloco `auth-users`** | papéis e hierarquia (**C3**), `Auth::MagicLoginService` para o BE-085 |
| **bloco `indicators`** | catálogo de `indicators` para BE-106..109 e DB-092 |
| **bloco `risk`** | `risk_controls` para BE-052, DB-069 e as contagens |
| **bloco `renegotiations`** | checagem de dependentes em BE-063 e DB-071 |

**É dependência de:** S5, S6, S7, S8, S9, S10, S11 — todas escopadas pelo `current_project!`
que nasce aqui (contrato **C1**, `§0.6`).

## Perguntas em aberto

| # | Pergunta | Default se não houver resposta |
| - | -------- | ------------------------------ |
| **Q-02** | `has_safegold_management` é carimbo histórico ou derivado do projeto? (DC-01, D-30) | Ver `§6` do mapa — **decisão mais consequente da fatia**, afeta DB-051, DB-090, DB-130, BE-093 |
| **Q-03** | O autopreenchimento por CNPJ (ReceitaWS) volta a funcionar? (BE-064, D-27) | Ver `§6` do mapa; afeta BE-064, FE-073, DB-054, OPS-050 |
| **Q-05** | Logos em `Medium`? (DC-02) | **Não** — `has_one_attached` direto; `media` não tem dono nem escopo |
| **Q-06** | `paper_trail` na base compartilhada ou `AuditEvent` só do Safegold? (L-05) | `AuditEvent`; ativar `paper_trail` é decisão de plataforma → `upstream-flags.md` |
| **Q-11** | Quem gerencia membership, sem o dono do projeto? (DEC-18.5) | OG/Admin/Gerente; o dono **não** vira papel com poder |

## Capabilities

### New Capabilities

Nenhuma. Os requirements desta fatia já existem em `openspec/specs/` desde o Phase 1 e são
referenciados por ID.

### Modified Capabilities

- `projects`: acréscimo de **um** requirement transversal (contrato **C1**) que o spec por ID
  não cobre de forma sistemática — nenhum id chegado por parâmetro fura o escopo de projeto,
  em **nenhum** dos endpoints da fatia. É a família de defeitos D-01 / D-16 / D-29 / D-76 /
  D-100, e o spec por ID só a cobre em alguns pontos.

## Impact

- **Backend**: `api/v1/{projects,companies,providers,memberships,project_carrier_connections,project_indicator_connections,project_guarantees}.rb`;
  `controller_helpers.rb` ganha `current_project!` (de S0); `app/models/concerns/project_scoped.rb`
  (a pasta está **vazia** hoje); `app/models/{project,membership,company,provider,project_guarantee}.rb`;
  `app/services/{project,company,provider,membership}_service.rb`, `project_reset_service.rb`,
  `receita_ws_service.rb`; jobs `project_creation_job.rb`, `link_default_members_job.rb`,
  `link_default_user_to_projects_job.rb`; `app/models/user.rb` ganha `current_project`.
- **Dados**: 7 tabelas novas + 1 coluna em `users` + FKs em tabelas de outros blocos
  (`risk_controls`, `receivable_entries`, `renegotiations`, `indicators`), coordenadas com
  os changes daqueles blocos. **Zero migration** para a observação (ActionText já existe).
- **Frontend**: `src/app/pages/projects/`, `companies/`, `providers/`, `guarantees/`;
  seletor de projeto no shell; `useNavItems.ts` com `requiresProject`.
- **A base ai9 não é refatorada** (Princípio 6b). `MobilePagination`, `SearchableSelect`,
  `medium.rb` e `assets_proxy_controller.rb` ficam **intocados**; o que pareceu errado está
  em `.migration-ai9/upstream-flags.md`.


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-549 | build | `projects` visto por `data-schema` — a tabela nasce em S0; **as colunas de domínio do projeto** (e os índices que o legado não tinha) são desta fatia | S4 é dona do CRUD de projeto |
| DB-554 | build | `project_to_carrier_connections` | idem |
| DB-555 | build | `companies` | idem |
| DB-556 | build | `providers` | idem |
| DB-557 | build | `project_guarantees` | idem |
| FE-040 | build | Projeto → adicionar membro (autocomplete de usuários) | a aba "Membros" é desta fatia (já registrado na Fronteiras de S1) |
| FE-041 | build | Projeto → lista de membros e remoção | idem |

**`FE-040`/`FE-041` são a tela; `Membership` é de S0.** A distinção é o contrato **C4**: quem
constrói a coisa é dono, quem consome referencia. O serviço e as três condições de servidor
vêm de S0; a aba é daqui.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`BE-098`, `BE-099`, `DB-080`, `DB-086`, `DB-087` são de S0**, não desta fatia.
  `current_project!`, o serviço de participação e as tabelas `projects`/`memberships` (mais
  `users.current_project_id`) nascem na fundação. S4 **consome**: constrói o CRUD de projeto
  e a aba "Membros" (`FE-040`, `FE-041`) **sobre** eles, e não repete nem o gate nem as três
  condições de servidor.
- **`FE-110` e `FE-148` são de S11.** A dependência pai↔níveis e o auto-preenchimento dos
  níveis derivados do pai pertencem aos padrões de disponibilidade, que são da fatia de
  disponibilidades e cobranças. S4 os cita porque a regra "nenhum padrão de outro projeto
  viaja no payload" vale nas duas telas — mas a tarefa é de lá.
