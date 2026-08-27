# Tasks: S0 — Fundação

Fila de trabalho do Phase 3 para a fatia **S0**. Ordem por camada: **dados → backend →
frontend → testes → paridade**. Uma tarefa = **um comportamento verificável**. Só se marca
quando o código existe, o teste passa e o `parity-ledger.md` foi atualizado com os IDs da
linha.

Portões (§6 de `.migration-ai9/ai9-conventions.md`): `cd backend && bundle exec rspec`
(baseline: no máximo as 5 falhas pré-existentes, e as mesmas 5) ·
`cd frontend && node node_modules/typescript/bin/tsc --noEmit` (baseline: **0 erro**).

> **Aviso que vale para as 5 tarefas de teste de hierarquia:** um teste que só verifica que
> "a trava existe" **passa com o sinal invertido** e não vale nada. Todo teste de hierarquia
> verifica os **dois** lados (C3).

## 1. Dados

- [x] 1.1 Migration `projects` — esquema mínimo para servir de FK: nome, `slug` único,
      `user_id` (dono), `segment_id`, `is_active` `null: false`, `legacy_*` (DEC-12).
      **Sem endpoint e sem tela** (S4). `comment:` nas colunas. — **DB-080**
- [x] 1.2 Migration `memberships` — `user_id`, `project_id`, `role` como enum estável
      (`responsavel`/`participante`/`coordenador`/`gestor`), FK reais e **índice único
      `(user_id, project_id)`**. `role` é rótulo descritivo, **nunca** consultado para
      autorizar (DEC-18.6). — **DB-086, DB-011**
- [x] 1.3 Migration `users.current_project_id` — FK + índice, **nullable e aditiva** (é
      coluna nova numa tabela compartilhada da base). — **DB-087, DB-397**
- [x] 1.4 Migration `permissions` (catálogo) + `user_permissions` (concessão com
      `granted_at`/`revoked_at`). A `Ability` polimórfica do legado (17 linhas × cada papel
      **e** cada usuário) **não** é replicada. — **DB-007, DB-503**
- [x] 1.5 Garantir `users.user_type_id` como o único portador de papel: a tabela de ligação
      `livetat_auth_roles` não tem equivalente e não é criada. — **DB-005, DB-501**
- [x] 1.6 Migration da trilha genérica `audit_events` (`actor_type`, `actor_id`, `action`,
      `subject_type`, `subject_id`, `reason`, `metadata`) — molde copiado de
      `permission_audit_logs`. Ver **DS0-1** em `design.md`. — **OPS-086** (parte dados)
      > **Substituída pelo DEC-59.** Não existe `audit_events`: a trilha é o `paper_trail`
      > (tabela `versions`, `object`/`object_changes` em `jsonb`, payload completo pelo
      > DEC-78, mais `impersonated_id`/`reason`/`ip_address`). `permission_audit_logs`
      > continua sem produtor. Ver `upstream-flags.md` → "DS0-1".
- [x] 1.7 Seed **versionado e idempotente** dos 4 papéis do Safegold na escala do ai9:
      OG=1, Admin=2, Gerente=3, Colaborador=4. **Não remove** `client`/`free`/`visitor` da
      base (DS0-4). Rodar duas vezes não duplica. — **DB-006, DB-502, BE-504, OPS-507**
      > **Alterada pelo DEC-41 parte 2:** `client`, `free` e `visitor` **SÃO removidos**
      > (a DS0-4 do `design.md` dizia o contrário e foi revogada). Usuário que apontava
      > para um tipo removido vira Colaborador e sai na lista de exceções do log da
      > migration (DEC-18.8).
- [x] 1.8 Registrar no seed a **tabela de-para** do ETL (1111→1, 998→2, 888→3, 799→4,
      `""`→4 + lista de exceções) como **dado versionado, nunca fórmula**, para o ETL
      (S14) consumir. — **DB-006** (parte ETL)
- [x] 1.9 Seed do catálogo de `permissions` contendo **`user_is_readonly`** — das 17
      abilities do legado é a única que sobrevive (DEC-18 #6). É o **primeiro** seed de
      `permissions` da base ai9. — **DB-008, BE-505, OPS-009**

## 2. Backend — escopo por projeto (C1)

- [x] 2.1 Concern `ProjectScoped` em `backend/app/models/concerns/project_scoped.rb`
      (**criar o diretório**): `belongs_to :project`, `scope :for_project`, validação de
      presença. **Sem `default_scope`.** — **C1** (habilitador; sem ID próprio)
- [x] 2.2 `current_project!` em `controller_helpers.rb`: resolve `users.current_project_id`,
      aceita `X-Project-Id` **só** com participação, e **ignora sempre** o `project_id` do
      corpo da requisição. — **BE-098, BE-391**
- [x] 2.3 `current_project!` **revalida o valor armazenado a cada request** — membership
      revogada para de valer na requisição seguinte, sem logout. — **BE-098** (condição 1
      do DC-08)
- [x] 2.4 `current_project!` responde **o mesmo status (404)** para projeto inexistente e
      para projeto sem participação. — **BE-098** (condição 2 do DC-08)
- [x] 2.5 Leitura **não grava**: nenhuma requisição GET escreve `current_project_id` (o
      legado regravava o projeto padrão a cada GET). — **DB-397**
- [x] 2.6 `api/v1/memberships.rb` + `MembershipService`: criar/remover restrito a
      OG/Admin/Gerente (DEC-18.5), `:id` fora do `permit`, e as **3 condições que viviam na
      view** promovidas a regra de servidor (não-readonly · não remove o dono
      `project.user_id` · não remove a si mesmo). — **BE-099, BE-045, BE-046**
- [x] 2.7 `GET /api/v1/memberships/candidates`: autocomplete que **não lista quem já é
      membro**, paginado e escopado. Busca com termo vazio devolve lista válida. — **BE-044**
- [x] 2.8 Revogar participação limpa/recalcula o `users.current_project_id` de quem foi
      removido — o usuário não continua "dentro" do projeto. — **DB-018** (parte regra)
- [x] 2.9 Auto-participação é **impossível**: nenhuma sessão se adiciona a um projeto
      (fecha D-28 + D-34). — **BE-099** (regra)
- [x] 2.10 Job de membro padrão com **retry e falha visível**, enfileirado **só quando
      `is_default_member` muda** (não em todo `update` do usuário). — **OPS-005, OPS-006**

## 3. Backend — papéis, hierarquia (C3) e autorização

- [x] 3.1 Helper `authorize!(recurso, ação)` em `controller_helpers.rb`, alimentado pela
      tabela declarativa derivada de `.migration-ai9/authorization-matrix.md` (contrato
      DEC-18). Nenhum endpoint decide autorização sozinho. — **BE-079, BE-506**
- [x] 3.2 `require_role!(*papéis)` no mesmo arquivo, coerente com `require_og!` que já
      existe. — **BE-079**
- [x] 3.3 `require_not_readonly!` **generalizando** `restrict_visitor_access!`
      (`controller_helpers.rb:44-53`): nega verbo de escrita se `visitor?` **ou** se houver
      grant ativo de `user_is_readonly`; 403 com `code` (o front já trata). — **BE-079,
      BE-018** (parte gate)
- [x] 3.4 Exceção do readonly: o **aceite dos Termos pelo próprio usuário** nunca é
      bloqueado por `user_is_readonly` (senão o readonly fica trancado fora — DC-09). —
      **BE-506** (regra)
- [x] 3.5 Permissão resolvida **por consulta** a cada request (papel → defaults;
      `user_permissions` → override), nunca congelada no usuário. Sem
      `define_method`/metaprogramação em runtime. — **BE-042, BE-748**
- [x] 3.6 Revogar permissão de um papel **passa a ter efeito em quem já existe** (o D-35
      desaparece por construção, não por correção). — **BE-042**
- [x] 3.7 `GET /api/v1/permissions` (catálogo) e `GET /api/v1/user_types/:id/permissions`
      usando o **usuário real** (`true_user`), nunca o personificado. — **BE-041**
- [x] 3.8 `PUT /api/v1/user_types/:id/permissions/:key` com **trava de hierarquia**: o ator
      só edita papéis de hierarquia **inferior** à sua (DEC-18.2). Gerente **não** alcança.
      — **BE-042, BE-520**
- [x] 3.9 `PUT /api/v1/users/:id/permissions/:key`: o `:id` do usuário **passa a mandar**
      (o legado o descartava e alcançava qualquer linha de `Ability` — D-34, o vetor mais
      direto de escalação). — **BE-018**
- [x] 3.10 Concessão e revogação gravam na trilha (`AuditEvent`): quem, sobre quem, o quê,
      quando e por quê. — **OPS-086** (produtor), **BE-018**
      > `paper_trail` no lugar de `AuditEvent` (DEC-59). `whodunnit` grava o `true_user`
      > — verificado executando, com sessão de impersonação real.
- [x] 3.11 Endpoint de consulta da trilha **exige autorização** (a trilha é dado sensível).
      — **OPS-086**
- [x] 3.12 Configuração do módulo de auth por ENV/initializer, **sem** replicar
      `default_role_type = ""` nem `minimal_type_to_sign_up_through_web` (D-36/D-39). —
      **BE-500**
      > A parte de **rota** está feita aqui (DEC-49: as 4 rotas de auto-cadastro saíram do
      > `api/root.rb` e do `registration.rb`, e os serviços órfãos foram apagados).
      > `config/` e initializer são da fatia **S18** — não tocados.
- [x] 3.13 `ProjectProgressChannel` + fila registrada em `config/sidekiq.yml`; progresso de
      job chega por **Action Cable invalidando query**, nunca por `setInterval`
      (Princípio 10). — **OPS-087, OPS-128**
      > Nenhuma fila nova foi registrada: `<APP_NAME>_low_priority` já existe em
      > `config/sidekiq.yml` e é a fila do `ProjectProgressChannel`/`DefaultMemberJob`.
      > `config/` é da fatia S18.

## 4. Frontend — primitivos da biblioteca compartilhada

Todos entram em `frontend/src/components/ui/`, com tokens de marca em **light e dark** e
variante mobile onde couber. **Nunca peça de uma tela só** (Princípio 11).

- [x] 4.1 `Checkbox` + `RadioGroup` — lacuna verificada: não existe nenhum dos dois na
      biblioteca. — **FE-418**
- [x] 4.2 `Select` de design system, aposentando o `<select>` cru com classe
      `glass-select`. — **FE-417**
- [x] 4.3 `Spinner` (tamanhos + variantes) e `Button` com prop `loading` — o `Button` da
      base não tem estado de carregamento. — **FE-428, FE-412, FE-411**
- [x] 4.4 `Pagination` de desktop alimentada por `X-Total-Count` (o backend já emite; a
      única paginação da base é `MobilePagination`). Controles **alteram de fato** a
      consulta e o total é o real. — **FE-053, FE-403** (componente)
- [x] 4.5 `DataTable` com cabeçalho ordenável que **ordena de verdade**; coluna não
      ordenável não parece ordenável. Variantes de coluna (data, moeda). — **FE-061,
      FE-416**
- [x] 4.6 `AsyncSection` com **4 estados** (carregando / vazio / **erro** / conteúdo) +
      `EmptyState`/`ErrorState`/`LoadingState`. O legado tinha 3 estados e **nenhum de
      erro**; a base trata erro só por `toast`. — **FE-401, FE-079**
- [x] 4.7 `DatePicker` pt-BR (locale, formato `dd/mm/aaaa`, faixa). **Crítico**: quase toda
      tela financeira do Safegold filtra por período. — **FE-745**
- [x] 4.8 `MoneyInput` / `PercentInput` pt-BR: exibem formatado, **enviam número**, avisam
      separador duplo. — **FE-066**
- [x] 4.9 `SearchInput` + `useDebouncedSearch` (300 ms; entrada só de espaços ignorada) — o
      padrão "input + ícone + debounce" se repete em ~40 telas. — **FE-420, FE-052**
- [x] 4.10 Consolidar as duas implementações de autocomplete numa só + `ResultItem` (ícone,
      título, spinner por item). — **FE-421, FE-422**
- [x] 4.11 `Card` + subcomponente `DetailList` (`label`/`content`) para o card denso de
      detalhe; `Card` de listagem mapeado com `MobileCard` no mobile. — **FE-414, FE-415**
- [x] 4.12 `Tabs` com overflow horizontal e conteúdo por aba (sem o truque
      `visibility:hidden; opacity:0; height:0`). — **FE-423, FE-424**
- [x] 4.13 `Badge` com variante **clicável para remover** (usada em seleção múltipla). —
      **FE-425**
- [x] 4.14 `Avatar` por imagem ou iniciais, com **cor derivada do id** (determinística — o
      legado gerava cor nova a cada render e a inicial "piscava"). — **FE-427**
- [x] 4.15 `Tooltip` cobrindo as 4 posições, aposentando o tema Tippy.js (uma dependência a
      menos). — **FE-426**
- [x] 4.16 `Dialog` da base no lugar do `vendor/dialog` proprietário (DEC-10) — a aparência
      muda, o comportamento não. — **FE-743**
- [x] 4.17 `PageHeader` + `SearchInput` no lugar das 751 linhas de
      `ContextToolbar`/`Toolbar`/`SearchBar`. — **FE-740**
- [x] 4.18 Ícones da biblioteca no lugar do `app_arrow` em CSS puro; `Switch` da base no
      lugar do `app_switch_toggle`. — **FE-413, FE-419**
- [x] 4.19 `RechartsPie` no lugar do `vendor/doughnut` (DEC-10) — preservar séries, rótulos
      e legenda. **Nota:** o legado **não instancia nenhum gráfico** (achado #1 do
      `migration-map.md`); isto é o componente ficando disponível, não uma tela. — **FE-744**
- [x] 4.20 Utilitários vivos (`today_start`/`today_end`, sentinelas de faixa de data,
      formatação pt-BR de data no cliente) em `lib/utils/`. — **FE-742, BE-538**
- [x] 4.21 Toasts do design system mapeando `M.SUCCESS`/`M.ERROR`/`M.HELP`. — **FE-410**
- [x] 4.22 `Rating`: construir **só se houver uso real** (Q-B13); o override do PhotoSwipe
      cai. Se não houver uso, fecha como `dropped` com evidência. — **FE-429**
      → **`dropped`.** Não há uso real: a fonte do dado é `Random.rand`
      (`user_decorator.rb:62`), a única referência em view está **comentada**
      (`console/parts/users/helper/_body.js.erb:106`) e o `generic_rating.scss`
      não é aplicado por view nenhuma. Evidência em `frontend-legacy-modules.md` §4.
- [x] 4.23 Inventário dos 13 módulos JS legados importados de fato, com o equivalente ai9
      de cada um — é o insumo direto das tarefas acima. — **FE-538**
      → `openspec/changes/s0-fundacao/frontend-legacy-modules.md`.
- [x] 4.24 `useJobProgress` (Action Cable) consumindo o `ProjectProgressChannel`: percentual
      avança na tela **sem recarregar**. — **OPS-087** (frontend)

## 5. Testes

### 5.1 Hierarquia (C3) — **sempre os dois lados**

- [x] 5.1.1 Admin **NÃO** edita ability de OG **e** Admin **EDITA** ability de Colaborador.
      — **BE-042, DB-006**
- [x] 5.1.2 Admin **NÃO** edita ability de outro Admin (lateral) **e** OG edita a de todos.
      — **BE-042**
- [x] 5.1.3 Gerente **NÃO** alcança a tela/endpoint de Permissões (DEC-18.2) **e** Admin
      alcança. — **BE-040, BE-041**
- [x] 5.1.4 O filtro de usuários de um Gerente **NÃO** devolve OG nem Admin **e** devolve
      Colaborador. — **BE-504**
- [x] 5.1.5 O de-para do ETL **falha alto** com um `hierarchy` desconhecido (nunca produz
      nível plausível por fórmula). — **DB-006**

### 5.2 Escopo por projeto (C1)

- [x] 5.2.1 Filtro por id de registro de **outro** projeto devolve **vazio**, não 403 — não
      se confirma a existência de registro alheio. — **BE-098**
- [x] 5.2.2 `project_id` no corpo da requisição é **ignorado** no `create` **e** no
      `update`. — **BE-098**
- [x] 5.2.3 Membership revogada **para de valer na requisição seguinte**, com
      `current_project_id` ainda gravado. — **BE-098** (condição 1)
- [x] 5.2.4 Projeto inexistente e projeto sem participação devolvem **o mesmo status**
      (nenhum oráculo de existência de id). — **BE-098** (condição 2)
- [x] 5.2.5 `X-Project-Id` de projeto **com** participação troca o escopo; **sem**
      participação, não troca. — **BE-098**
- [x] 5.2.6 Job/seed que cruza projetos funciona recebendo `project_id` explícito (prova de
      que não há `default_scope`). — **OPS-005**
- [x] 5.2.7 Nenhuma requisição GET grava `current_project_id`. — **DB-397**

### 5.3 Participação e readonly

- [x] 5.3.1 As 3 condições de servidor da remoção de membro: não-readonly · não remove o
      dono · não remove a si mesmo — cada uma com o par permitido/negado. — **BE-046,
      BE-099**
- [x] 5.3.2 Nenhuma sessão se auto-adiciona a um projeto. — **BE-099**
- [x] 5.3.3 `user_is_readonly` nega POST/PUT/PATCH/DELETE **e** permite GET/HEAD, com 403 e
      `code`. — **BE-079**
- [x] 5.3.4 `user_is_readonly` **não** bloqueia o aceite dos Termos pelo próprio usuário
      (DC-09). — **BE-506**
- [x] 5.3.5 Revogar permissão do papel **afeta usuário já existente** (regressão do D-35).
      — **BE-042**

### 5.4 Frontend

- [x] 5.4.1 Testes de `Pagination` e `DataTable` (Vitest, em `__tests__/` ao lado do
      código): mudar de página muda a consulta; cabeçalho ordena. — **FE-053, FE-061**
- [x] 5.4.2 `AsyncSection` renderiza os 4 estados, inclusive **erro**. — **FE-401**
- [x] 5.4.3 `MoneyInput`/`PercentInput` enviam número e exibem formatado em pt-BR. —
      **FE-066**
- [x] 5.4.4 Cor do `Avatar` é **estável entre renders** para o mesmo id. — **FE-427**

## 6. Paridade e registro

- [x] 6.1 Ledger: os 6 `dropped` com a evidência da linha do mapa — **BE-043, DB-396,
      DB-398, DB-516, OPS-392, OPS-398**
- [x] 6.2 Ledger: os demais 71 IDs de S0 para `migrated` (e `verified` só depois do Phase 4).
      > Feitos os **42 IDs de dados e backend** (+ os 6 `dropped` de 6.1). Os `FE-*` de S0
      > ficam com o agente de frontend, que fecha as próprias linhas.
- [x] 6.3 `improvements-log.md`: IMP-A10, IMP-A18 (**observável**), IMP-A19, IMP-A21,
      IMP-A22, IMP-A25, IMP-A31 (**observável**) — para o QA não ler melhoria como
      regressão.
- [x] 6.4 `upstream-flags.md`: apensar U1, U2, U3, U8, U9, U14, U15 e a decisão **DS0-1**
      (`permission_audit_logs` segue sem produtor). **Não corrigir a base nesta fatia.**
- [x] 6.5 Conferir com S1..S16: nenhuma outra fatia criou um segundo mecanismo de escopo,
      de papel ou de paginação. Um `grep` por `default_scope` em `backend/app/models`
      precisa voltar **vazio**.


## Fechamento de órfãos do Phase 2 — papéis, abilities e membership

Cinco IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Migration `memberships` (`user_id`, `project_id`, `role`) com único
      `(user_id, project_id)`. **Fecha: DB-545.**
- [x] F.2 Semear `user_types` a partir dos `RoleType` do Safegold por **tabela de-para
      explícita**, com a escala do ai9 (menor = mais poder, `user_type.rb:38-41`).
      Verificável: o de-para é um literal legível, e **não** há nenhuma aritmética
      convertendo `1111`/`998`/`888`/`799` em nível. **Fecha: DB-730.**
- [x] F.3 Teste de hierarquia que verifica **os dois lados**: "Admin **não** edita ability de
      OG" **e** "Admin **edita** ability de Colaborador". Um teste que só verifica que a
      trava existe passa com o sinal invertido. **Fecha: DB-730 (parte), C3.**
- [x] F.4 Mapear as abilities do legado para `permissions` + `user_permissions`, incluindo a
      origem de `user_is_readonly`. **Fecha: DB-731.**
- [x] F.5 Registrar que a tabela de junção usuário↔papel do legado **não é criada** — o papel
      é `users.user_type_id` —, com a evidência da contagem de linhas na origem (o ETL conta
      antes de descartar). **Fecha: DB-542.**
- [x] F.6 Seed de referência **idempotente** de `user_types` + `permissions` em
      `db/seeds/reference/`. Verificável: rodar duas vezes não duplica nem reescreve papel
      já atribuído. **Fecha: OPS-541.**
