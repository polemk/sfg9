# Proposal: S2 — Console e navegação

> Fatia **S2** de `.migration-ai9/migration-map.md`. Bloco de origem: `auth` + `data`.
> **Depende de S0.** Absorve as fatias internas **S6, S9 e S10** do
> `.migration-ai9/map/auth-admin.md` — casca do console, mensagens administrativas e
> descarte com evidência.

## Why

O console legado não tem roteador. Tem **uma** rota-mestra com três segmentos opcionais
(`resource/topic/section`), onde `topic` é polimórfico (id numérico, a palavra `new`, a
palavra `detail` ou um UUID), o estado vive só em memória num objeto global JS
(`dashHolder`) e a URL é espelhada por `replaceState` — nunca `pushState`. O resultado
observável é o **D-92**: o botão Voltar do navegador **sai do console**, e nenhuma tela é
compartilhável por link.

Do outro lado, a navegação inteira do produto está escondida num helper:
`create_console_menu` (**D-118**) é a especificação de fato de quem vê o quê — 6 grupos,
gate por projeto, por papel e por permissão. Ele precisa virar **configuração declarativa**,
não ser reescrito de memória.

E a base ai9 tem duas lacunas que só aparecem aqui: **não existe rota `*` de 404**
(`App.tsx:56-87`) — área desconhecida vira tela em branco, e o legado já tinha o vício de
rebaixar silenciosamente para o `dash` — e **`WhatsappPage.tsx` não está roteada**, que é a
tela de pareamento de que o login por WhatsApp (DEC-14) depende.

## What Changes

### Grupo A — Casca, roteamento e navegação por papel

A rota-mestra vira ~38 rotas com URL estável e compartilhável, histórico de verdade e um
404 real. O menu vira `useNavItems` declarativo, filtrado por papel + participação, com o
`locked` lido **do item** (o legado lia do grupo — D-90) e **nenhum item nascendo marcado**
(DEC-15.1: disponibilidades e cobranças estão vivas em produção).

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-390 | `adapt` | rotas React por área |
| BE-392 | `adapt` | título por rota |
| BE-393 | `adapt` | resolução de tela por rota |
| BE-394 | `drop` | — |
| BE-395 | `adapt` | `/users/:id` |
| BE-396 | `drop` | — |
| BE-397 | `adapt` | `/contracts/:id` |
| BE-398 | `adapt` | `/help/items/...` |
| BE-399 | `adapt` | `/settings/theme` (ou nada) |
| BE-400 | `adapt` | `/projects`, `/projects/new`, `/projects/:id/edit` |
| BE-401 | `adapt` | `/carriers/:id/connections` |
| BE-402 | `adapt` | `/receivables/new` |
| BE-403 | `adapt` | `/renegotiations/new` |
| BE-404 | `adapt` | `/availability`, `/availability-templates/:id` |
| BE-405 | `adapt` | `/companies/:id` |
| BE-406 | `adapt` | `/risk-operations/new` |
| BE-407 | `adapt` | `/project-guarantees/new`, `/:id/edit` |
| BE-408 | `adapt` | `/structured-operations/...` |
| BE-409 | `adapt` | `/charges/:id`, `/charges/:id/receipts` |
| BE-410 | `drop` | — |
| BE-411 | `drop` | — |
| BE-412 | `adapt` | seletor de projeto |
| BE-413 | `build` | `GET /api/v1/countries/:code/states` etc. |
| BE-414 | `adapt` | gate central |
| BE-415 | `drop` | — |
| BE-416 | `adapt` | bootstrap da SPA |
| BE-417 | `reuse` | `/` |
| BE-418 | `adapt` | `useNavItems` com filtro por papel |
| BE-419 | `adapt` | flag `locked` do item |
| BE-420 | `drop` | — |
| BE-421 | `drop` | — |
| BE-422 | `drop` | — |
| BE-423 | `adapt` | defaults de listagem |
| BE-511 | `adapt` | formatação pt-BR no cliente |
| DB-399 | `drop` | `parity-ledger` |
| FE-390 | `adapt` | `Layout` |
| FE-391 | `adapt` | `Suspense` + roteador |
| FE-392 | `adapt` | topbar |
| FE-393 | `build (front) sobre current_project! (back, bloco projects)` | seletor de projeto na topbar |
| FE-394 | `reuse` | busca global da topbar |
| FE-395 | `adapt` | sidebar |
| FE-396 | `adapt` | resumo do usuário |
| FE-397 | `adapt` | navegação entre áreas |
| FE-398 | `drop` | — |
| FE-399 | `reuse` | drawer de formulários |
| FE-400 | `adapt` | barra de ações pendentes |
| FE-402 | `drop` | — |
| FE-403 | `build` | `components/ui/Pagination.tsx` |
| FE-404 | `adapt` | `/` autenticado → redirecionador |
| FE-741 | `reuse` | `Sidebar` |
| NAV-001 | `adapt` | `useNavItems` declarativo |
| OPS-391 | `reuse` | analytics do ai9 |
| OPS-393 | `adapt` | histórico real |
| OPS-396 | `drop` | — |
| OPS-397 | `adapt` | ENV |
| OPS-399 | `drop` | — |
| OPS-508 | `drop` | — |
| OPS-509 | `drop` | — |
| OPS-749 | `drop` | `parity-ledger` |

### Grupo B — Mensagens administrativas e observadores (`feedback19`)

Ticket + thread + observadores por contexto. A engine `feedback19` **não vira engine**: vira
código do app (DC-12). A tela de mensagens deixa de ser órfã e ganha item de menu.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-424 | `build` | `GET /api/v1/admin_messages` |
| BE-425 | `drop` | — |
| BE-426 | `build` | `GET /api/v1/observers` |
| BE-427 | `build` | `/observers/new` |
| BE-428 | `build` | `/observers/:id/edit` |
| BE-429 | `build` | `POST/PUT/DELETE /api/v1/observers` |
| BE-525 | `adapt` | config de `admin_messages` |
| BE-526 | `build` | `AdminMessage` |
| BE-527 | `adapt` | `enum :state` + service |
| BE-528 | `build` | `MessageNote` |
| BE-529 | `adapt` | `enum` de contexto + `Observer` |
| BE-530 | `build` | `ObserverMailer` + `MessageMailer` |
| BE-531 | `build` | `api/v1/admin_messages.rb` |
| BE-532 | `drop` | — |
| DB-390 | `build` | tabela `admin_messages` |
| DB-391 | `build` | tabela `observers` |
| DB-392 | `build` | tabela `observer_contexts` |
| DB-393 | `adapt` | `enum` + seed |
| DB-394 | `adapt` | `enum` de situação |
| DB-395 | `build` | tabela `message_notes` |
| DB-508 | `build` | `admin_messages` |
| DB-509 | `adapt` | `enum` de situação |
| DB-510 | `adapt` | `enum` de contexto |
| DB-511 | `build` | `observers` |
| DB-512 | `build` | `observer_contexts` |
| DB-513 | `build` | `message_notes` |
| FE-405 | `build` | `/messages` |
| FE-406 | `build` | widget de mensagem |
| FE-407 | `build` | filtros de `/messages` |
| FE-408 | `build` | lista de observadores |
| FE-409 | `build` | drawer de observador |
| FE-523 | `build` | formulário de mensagem |
| FE-524 | `drop` | — |
| FE-525 | `drop` | — |
| FE-526 | `adapt` | `Api::Entities::AdminMessage` |
| FE-527 | `build` | telas que enviam mensagem |
| FE-528 | `build` | `/messages` |
| OPS-394 | `adapt` | `ObserverMailer` |

### Grupo C — Descarte com evidência

Não produz código: produz linhas `dropped` no `parity-ledger.md` **com a prova**.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-539 | `drop` | `parity-ledger` (`dropped`) |
| ENG-navkit | `drop` | `parity-ledger` (`dropped`) |
| FE-539 | `drop` | `parity-ledger` (`dropped`) |

### Contagem

| Grupo | IDs |
| ----- | --- |
| A — casca, roteamento, navegação | 59 |
| B — mensagens e observadores | 38 |
| C — descarte com evidência | 3 |
| **Total** | **100** (todos do bloco `auth-admin`) |

### Fronteiras

- **Consome de S0:** `current_project!` (para o seletor de projeto e o gate
  `projects.count > 0`), papéis (para o menu), `Pagination`, `DataTable`, `AsyncSection`,
  `PageHeader`, toasts.
- **Não está aqui:** **não existe dashboard** (D-87, DB-399, DEC-09). O `dash` do legado é
  **só um redirecionador por papel**, e é isso — e só isso — que vira spec (FE-404). Um
  dashboard de verdade é a adição de escopo `NEW-002`, fatia **S15**.
- **PWA** (decidido **SIM** no Phase 0, `project-options.md`) **não está em nenhuma fatia
  deste mapa** — a base não tem nada de PWA. É a fatia **S16** (`NEW-003`), e está
  registrado aqui porque é na casca do console que ele se ancoraria (DC-18 / Q-B20).

## Impact

- **Afetado (frontend):** `app/App.tsx` (rotas + **rota curinga**), `components/Layout.tsx`,
  `components/Sidebar.tsx`, `hooks/useNavItems.ts`, `app/pages/**` (áreas do console),
  novas telas de mensagens e observadores.
- **Afetado (backend):** `api/v1/{admin_messages,observers}.rb` + models e migrations,
  `ObserverMailer`/`MessageMailer`, opções encadeadas de formulário
  (`GET /api/v1/countries/:code/states`).
- **Mudanças observáveis:** IMP-A11 (deep-link e histórico do navegador por área e por
  registro) — é a mudança mais visível desta fatia.
- **Risco principal:** o menu é a especificação de quem vê o quê. Portar a **intenção** do
  código legado (marcar os 4 itens `locked`) **desligaria disponibilidades e cobranças** —
  telas que o usuário confirmou estarem vivas. Porta-se o **efeito**, não a intenção
  (DEC-15.1). O risco é simétrico e está registrado nos dois sentidos.


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| FE-441 | adapt | `create_console_menu` — **a maior regra de autorização de UI do legado**: o menu lateral inteiro montado por papel e permissão. Vira `CONSOLE_NAV_ITEMS` estendido com `roles?` e gate de membership | S2 é dona de `useNavItems.ts` |
| FE-050 | adapt | As entradas de menu das 6 entidades de cadastro, com `roles?: string[]` e `requiresProject?: boolean` | idem |
| OPS-634 | build | Páginas de erro 404 / 422 / 500 | S2 é dona do 404 e dos estados de erro do console |
| DB-594 | build | `livetat_feedback_messages` → a tabela de mensagens administrativas | S2 é dona de `feedback19` (Grupo B) |
| DB-595 | build | `livetat_feedback_states` → tabela + seed de 8 estados | idem |
| DB-732 | build | `livetat_feedback_contexts` → tabela + seed (Outros, Problema, Contato, Sugestão) | idem |
| DB-733 | build | `livetat_feedback_observers` | idem |
| DB-734 | build | `livetat_feedback_observer_contexts` (junção) | idem |
| DB-735 | build | `livetat_feedback_notes` | idem |
| OPS-542 | build | Seed da engine `feedback19` (estados + contextos) vira seed de referência + **uma migração de dados verificável** | idem |

**Os seis `DB-59x`/`DB-73x` são a mesma coisa que o Grupo B já constrói**, vistos pelo
inventário de `data-schema` em vez do de `auth-admin`: `DB-594`↔`DB-508`, `DB-595`↔`DB-509`,
`DB-732`↔`DB-510`, `DB-733`↔`DB-511`, `DB-734`↔`DB-512`, `DB-735`↔`DB-513`. **Não são
tabelas novas** — são as mesmas tabelas, e o trabalho é o mesmo. Ficam aqui para que o ledger
feche pelos dois lados.
