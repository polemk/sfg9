# Proposal: S0 — Fundação (projeto, participação, papéis e primitivos)

> Fatia **S0** de `.migration-ai9/migration-map.md`. Bloco de origem: `projects` + `auth`.
> **Não depende de nada. Tudo depende dela.** Nenhuma das outras 16 fatias pode fechar sem
> `current_project!`, sem os 4 papéis na escala do ai9 e sem os primitivos de interface
> que hoje faltam na biblioteca compartilhada.

## Why

Três buracos, todos verificados abrindo os arquivos da base pós-trim, impedem que qualquer
tela do Safegold seja escrita de forma correta:

1. **A base ai9 é declaradamente single-tenant.** Não há `tenant_id`, `account_id` nem
   `organization_id` em nenhum dos models (`.migration-ai9/ai9-conventions.md` §4; 52
   tabelas, zero colunas de tenant). O Safegold é multi-projeto em **todas** as telas
   financeiras. O mecanismo de escopo **não existe e nasce aqui, uma vez só** — é o
   contrato **C1**, cujo desenho normativo é `.migration-ai9/map/projects-cadastros.md`
   §0.6. Se cada fatia inventar o seu, o Phase 4 encontra duas semânticas de escopo.
2. **Não há autorização.** A base só tem `require_og!` e `restrict_visitor_access!`
   (`backend/app/controllers/api/v1/controller_helpers.rb:37,44`) — nenhuma policy, nenhum
   `authorize!`, nenhum seed de `permissions`. A matriz aprovada (DEC-18, 45 recursos × 4
   papéis) não tem onde ser avaliada. E a escala de hierarquia dos dois sistemas é
   **invertida** (contrato **C3**): é o item de maior risco da migração inteira.
3. **Faltam primitivos de interface que ~40 telas do Safegold usam.** Verificado:
   `components/ui/` não tem `Checkbox`, `RadioGroup`, `Select`, `Spinner`, `DatePicker`,
   `Pagination` de desktop nem estado de erro assíncrono. Construir isso dentro da primeira
   tela que precisar produz seis cópias divergentes (Princípio 11).

Fazer S0 primeiro não é organização: é a diferença entre escopo explícito revisável e a
família de defeitos **D-01 / D-16 / D-28 / D-29 / D-76 / D-100** renascendo no ai9.

## What Changes

### Grupo A — Biblioteca compartilhada e primitivos que faltam

Os 19 recicláveis do console legado viram membros de `frontend/src/components/ui/`, **nunca
peça de uma tela só**. As três peças proprietárias (`vendor/dialog`, `vendor/doughnut`,
Tippy) caem por equivalente do ai9 (DEC-10).

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-538 | `adapt` | `lib/utils/` |
| DB-398 | `drop` | tokens CSS |
| DB-516 | `drop` | `parity-ledger` |
| FE-401 | `adapt` | estados de bloco assíncrono |
| FE-410 | `reuse` | toasts |
| FE-411 | `reuse` | `<Button>` |
| FE-412 | `adapt` | `<Button loading>` |
| FE-413 | `reuse` | `<ChevronLeft/Right>` |
| FE-414 | `adapt` | `<Card>` + `<DetailList>` |
| FE-415 | `reuse` | `<Card>` |
| FE-416 | `adapt` | `<Table>` + ordenação |
| FE-417 | `reuse` | `<SearchableSelect>` |
| FE-418 | `build` | `components/ui/Checkbox.tsx` + `RadioGroup.tsx` |
| FE-419 | `reuse` | `<Switch>` |
| FE-420 | `adapt` | `components/ui/SearchInput.tsx` |
| FE-421 | `adapt` | `<Autocomplete>` |
| FE-422 | `build` | `components/ui/ResultItem.tsx` |
| FE-423 | `reuse` | `<Tabs>` |
| FE-424 | `reuse` | `<TabsContent>` |
| FE-425 | `adapt` | `<Badge removable>` |
| FE-426 | `reuse` | `<Tooltip>` |
| FE-427 | `reuse` | `<Avatar>` |
| FE-428 | `build` | `components/ui/Spinner.tsx` |
| FE-429 | `adapt + drop` | `components/ui/Rating.tsx`; lightbox |
| FE-538 | `adapt` | biblioteca do ai9 |
| FE-740 | `adapt` | `<PageHeader>` |
| FE-742 | `adapt` | `lib/utils/` |
| FE-743 | `reuse` | `<Dialog>` |
| FE-744 | `reuse` | `<RechartsPie>` |
| FE-745 | `build` | `components/ui/DatePicker.tsx` |
| OPS-390 | `reuse` | Vite |
| OPS-398 | `drop` | — |
| FE-052 | `build` | `useDebouncedSearch` (compartilhado, S0) |
| FE-053 | `build (lado servidor é reuse de KAM)` | `components/ui/Pagination.tsx` (**novo, compartilhado**); `MobilePagination` f… |
| FE-061 | `build` | `components/ui/DataTable.tsx` (**novo, compartilhado**) |
| FE-066 | `build` | `components/ui/MoneyInput.tsx` + `PercentInput.tsx` (**novos, compartilhados**… |
| FE-079 | `build` | `components/ui/{EmptyState,ErrorState,LoadingState}.tsx` (**novos, compartilha… |

### Grupo B — Papéis, hierarquia (C3) e autorização declarativa

Seed versionado dos 4 papéis do Safegold na escala do ai9, catálogo de `permissions`,
`user_is_readonly` promovida de flag de view a checagem de servidor, e o helper
`authorize!(recurso, ação)` que avalia a matriz do DEC-18.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-079 | `adapt` | `controller_helpers.rb` ganha `require_role!(*roles)`, `require_not_readonly!`… |
| BE-018 | `adapt` | `PUT /api/v1/users/:id/permissions/:key` |
| BE-040 | `build` | `/permissions` |
| BE-041 | `adapt` | `GET /api/v1/permissions` (catálogo) + `GET /api/v1/user_types/:id/permissions… |
| BE-042 | `adapt` | `PUT /api/v1/user_types/:id/permissions/:key` |
| BE-043 | `drop` | — |
| BE-500 | `adapt` | ENV + initializers |
| BE-504 | `adapt` | `UserType` + `users.user_type_id` |
| BE-505 | `adapt` | seed de `permissions` |
| BE-506 | `adapt` | `authorize!(recurso, acao)` |
| BE-520 | `adapt` | `PUT /api/v1/users/:id/permissions/:key` |
| BE-748 | `adapt` | herança de permissão como **dado** |
| DB-005 | `adapt` | `users.user_type_id` |
| DB-006 | `adapt` | seed de `user_types` |
| DB-007 | `adapt` | `permissions` + `user_permissions` |
| DB-008 | `adapt` | seed de `permissions` |
| DB-501 | `adapt` | `users.user_type_id` |
| DB-502 | `adapt` | `user_types` |
| DB-503 | `adapt` | `permissions` + `user_permissions` |
| OPS-009 | `build` | seed versionado de papéis + permissões |
| OPS-507 | `adapt` | seed idempotente |

### Grupo C — Projeto, participação e escopo (C1)

As quatro peças do §0.6: tabela `memberships`, `users.current_project_id`, helper
`current_project!` e concern `ProjectScoped` (o diretório
`backend/app/models/concerns/` **não existe** hoje — verificado). A tabela `projects` nasce
aqui **como esquema**; o CRUD, as telas e os efeitos colaterais de criação são da fatia
**S4**.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-098 | `adapt` | `current_project!` em `controller_helpers.rb` + `users.current_project_id` |
| BE-099 | `build` | `api/v1/memberships.rb` + `MembershipService` |
| DB-080 | `build` | `projects` |
| DB-086 | `build` | `memberships` |
| DB-087 | `adapt` | `users.current_project_id` (FK + índice) |
| BE-044 | `reuse` | `GET /api/v1/memberships/candidates` |
| BE-045 | `reuse` | `POST /api/v1/memberships` |
| BE-046 | `reuse` | `DELETE /api/v1/memberships/:id` |
| BE-391 | `reuse` | `current_project!` |
| DB-011 | `reuse` | `memberships` |
| DB-018 | `drop + build` | `parity-ledger` + `memberships` |
| DB-396 | `drop` | — |
| DB-397 | `reuse` | `users.current_project_id` |
| OPS-005 | `adapt` | `InsertProjectsOnDefaultMemberJob` |
| OPS-006 | `adapt` | mesmo job |
| OPS-392 | `drop` | — |

### Grupo D — Infra transversal consumida por todas as fatias

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| OPS-086 | `build` | trilha de auditoria genérica (`AuditEvent`) + `api/v1/audit_events.rb` |
| OPS-087 | `adapt` | `ProjectProgressChannel` + `useJobProgress` |
| OPS-128 | `reuse` | registrar a fila do módulo em `sidekiq.yml` |

### Contagem

| Grupo | IDs |
| ----- | --- |
| A — biblioteca e primitivos | 37 |
| B — papéis, hierarquia, autorização | 21 |
| C — projeto, participação, escopo | 16 |
| D — infra transversal | 3 |
| **Total** | **77** (63 do bloco `auth-admin`, 14 do bloco `projects`) |

### Fronteiras — o que **não** está aqui, e onde está

- **CRUD de projeto, telas de projeto, efeitos colaterais da criação** (BE-080…BE-097,
  FE-080…FE-119): fatia **S4**. S0 entrega o esquema e o escopo, não o produto.
- **Telas de permissões** (FE-024, FE-026, FE-027, FE-043, FE-513): fatia **S1**, junto com
  a tela de contas de que elas dependem. O servidor que elas comandam nasce aqui.
- **Aba "Membros" do projeto** (FE-040, FE-041): fatia **S4** — dependem da tela de detalhe
  do projeto, que não existe antes de lá. **São os únicos 2 IDs do bloco `auth-admin` que
  não caem em S0/S1/S2**, e estão registrados aqui para não sumirem.
- **FE-062, OPS-125, OPS-126, OPS-127**: apesar de listados no S0 interno do bloco
  `projects`, pertencem a domínios específicos (catálogo de portadores, disponibilidades) e
  ficam com S3/S6-S7 daquele bloco.

## Impact

- **Afetado (backend):** `backend/db/migrate/**` + `schema.rb`, `app/models/{user,user_type,
  permission,membership,project}.rb`, `app/models/concerns/` (**novo**),
  `app/controllers/api/v1/controller_helpers.rb`, `api/v1/{memberships,permissions,
  user_types,audit_events}.rb`, `app/services/`, `db/seeds/`.
- **Afetado (frontend):** `frontend/src/components/ui/**` (primitivos novos),
  `lib/utils/`, `hooks/`.
- **Não afetado:** nenhuma tela de domínio financeiro — S0 não entrega feature de usuário
  final. O que ela entrega é medível por teste, não por captura de tela.
- **Contratos que nascem aqui:** **C1** (escopo no endpoint, nunca `default_scope`, com as
  duas condições do DC-08) e **C3** (hierarquia invertida, teste dos dois lados).
- **Risco principal:** inverter o sinal da comparação de hierarquia **dá poder de OG a um
  Colaborador** e **passa** em qualquer teste que só verifique que "a trava existe". Por
  isso toda tarefa de teste de hierarquia desta fatia exige o par positivo **e** negativo.
- **Paridade:** 6 IDs entram no ledger como `dropped` com evidência (BE-043, DB-396,
  DB-398, DB-516, OPS-392, OPS-398); os demais como `to-migrate` → `migrated` → `verified`.


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-542 | reuse | `livetat_auth_roles` — a tabela de junção usuário↔papel **não é criada**: no ai9 o papel já é `users.user_type_id` | S0 é dona de papéis e hierarquia (**C3**) |
| DB-730 | adapt | `livetat_auth_role_types` → `user_types` **resemeada**, com a escala **invertida** do ai9 (menor = mais poder) | idem |
| DB-731 | adapt | `livetat_auth_abilities` → `permissions` + `user_permissions`; é a origem de `user_is_readonly` | idem |
| DB-545 | build | `memberships` + `Membership` | **C4**: `Membership` nasce em projects/S0 |
| OPS-541 | adapt | O seed da engine `auth19` (papéis + habilidades) vira **seed de referência idempotente** de `user_types` + `permissions` | quem constrói os papéis semeia os papéis |

**O ponto de atenção destes cinco é `DB-730`.** A conversão de hierarquia é o item de maior
risco da migração (**C3**): a escala é invertida entre os dois sistemas, e uma fórmula de
conversão sobrevive a valor inesperado e produz nível **plausível e errado**. É **tabela
de-para explícita**, nunca fórmula — e o seed de `OPS-541` é onde a tabela de-para vive.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`BE-098`, `BE-099`, `DB-080`, `DB-086`, `DB-087` são de S0** — disputados com S4.
  `current_project!`, o CRUD de participação, e as tabelas `projects`, `memberships` e a
  coluna `users.current_project_id` **nascem aqui**: é a definição da fatia de fundação, e o
  contrato **C1** (escopo por projeto no endpoint, nunca `default_scope`) depende de elas
  existirem antes de qualquer feature. **S4 consome e referencia** — a aba "Membros"
  (`FE-040`/`FE-041`) e o CRUD de projeto são de lá, sobre estes.
