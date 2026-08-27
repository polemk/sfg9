# Proposal: S11 — Disponibilidades e cobranças (vivas, DEC-15.1)

> Fatia **S11** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/projects-cadastros.md` (fatias internas
> **§1 S5**, **§1 S6** e **§1 S7**).
> Depende de **S0** (fundação) e **S4** (projeto, empresas, escopo).

## Why

### Estas telas estão vivas em produção — e quase não foram portadas

O legado marca `locked: true` nos itens de menu `availability`, `charges`,
`project_availabilities` e `availability_templates`. Só que o menu **lê `g[:locked]`, do
grupo**, e a marca está nos **itens** — os quatro nunca ficaram travados (**D-90**). Uma
leitura literal do código diria "feature desligada, não portar".

**O usuário confirmou (DEC-15.1) que as quatro telas estão em uso.** Produção é a verdade,
não a intenção aparente do código. Portanto: **porta-se o efeito, corrige-se o mecanismo** —
no ai9 o `locked` passa a ser lido do **item** (correto), e **nenhum dos quatro nasce
marcado**.

### É o módulo com mais dinheiro e mais defeito por linha

Painel de disponibilidade é a grade hierárquica onde o cliente lança valores por data e
empresa. Os defeitos aqui **mudam número exibido e número gravado**:

- **D-01** — `GET /api/v1/project_availability` herda de `ApplicationController` (não do
  `PubApplicationController`) e faz `Project.find(params[:id])` **sem escopo**. Qualquer
  requisição lê a disponibilidade de qualquer projeto por id. **IDOR, sem autenticação.**
  Não se replica um IDOR.
- **D-02** — decaimento composto: `original_value` é regravado a cada mudança de `value` e a
  correção por dias úteis é reaplicada **sobre o valor já corrigido**. Salvar duas vezes o
  mesmo valor produz números diferentes.
- **D-05** — os quatro jobs (ativar / desativar / remover / propagar) engoliam a exceção,
  rodavam com `destroy_failed_jobs? false`, sem retry, e chamavam `unlocked!` **só no caminho
  feliz**: uma falha deixava o padrão **bloqueado para sempre**, sem caminho de recuperação.
- **D-04 / D-33** — a guarda que impede desativar padrão obrigatório **existia e nunca era
  executada** no fluxo real.
- **D-06 / D-07 / D-20** — a busca de padrões globais usa a coluna `default_position`, que
  **nenhuma migration cria**: qualquer texto digitado derruba a requisição.
- **D-08** — a consolidação geral é soma bruta ignorando `is_cumulative`/`is_debit`,
  divergindo da regra aplicada aos nós com filhos. **Duas regras de soma na mesma tela.**

Somando: **remoção sem transação** que apagava lançamentos financeiros contornando
`restrict_with_error`, **vazamento** de `AvailabilityTemplate.all` (de todos os projetos)
serializado num atributo `data-`, e a maior tabela do módulo (`availability_entries`) **sem
nenhum índice**.

## What Changes

Três entregas encadeadas, todas sobre o escopo por projeto criado na S4:

1. **Catálogo global de padrões de disponibilidade** ("Tipos de disponibilidade") — árvore de
   3 níveis, numeração e posicionamento determinísticos, obrigatoriedade hierárquica,
   propagação para projetos como **opção do usuário**.
2. **Padrões de disponibilidade do projeto** — árvore do projeto, criar/editar, ativar/
   desativar/remover em segundo plano com bloqueio, progresso por Action Cable e **liberação
   garantida do bloqueio, inclusive na falha**.
3. **Painel de Disponibilidade e lançamentos** — grade hierárquica por data e empresa,
   consolidação geral, saldo acumulado, correção por dias úteis, indicadores e calendário.

E, de **cobranças**, o que pertence a esta fatia por DEC-15.1/DC-37: **o item de menu
"Cobranças" nasce habilitado**, junto com "Disponibilidades", "Disponibilidades do Projeto" e
"Padrões de Disponibilidade". A *feature* de cobranças e recibos é do bloco
`receivables-renegotiations` — ver "Fronteiras".

Mudanças visíveis, a registrar em `.migration-ai9/improvements-log.md` como intencionais:

1. **O endpoint de disponibilidade passa a exigir autenticação e escopo** (D-01).
2. **A busca de padrões globais volta a funcionar** (D-06/Q-01). Hoje qualquer texto quebra a
   requisição e a lista só para de atualizar, sem mensagem.
3. **Abrir a grade nunca cria registro** (DC-30). Hoje a leitura materializa derivados no
   banco, com o autor de quem abriu a tela.
4. **O valor digitado e o valor gravado ficam ambos visíveis** quando há correção por dias
   úteis (FE-134). Hoje o usuário digita X e vê Y, sem nenhuma indicação.
5. **Padrão bloqueado por job termina desbloqueado**, com ou sem sucesso (BE-147, D-05).
6. **Desativar padrão obrigatório é recusado no serviço**, antes de enfileirar (D-04/D-33).
7. **Toda obrigatoriedade escolhida no formulário é respeitada** (BE-134). Hoje todo padrão
   global nasce obrigatório (`is_mandatory |= 1`) e **toda criação propaga para todos os
   projetos**, porque `should_insert_on_existing_projects` tem default 1 e não é exposto.
8. **Paginação e ordenação passam a funcionar** (D-07/D-20).
9. **Os quatro itens de menu nascem habilitados** (DEC-15.1, D-90).
10. **Sinal negativo visível no próprio valor**, não só pela cor (FE-125).

## IDs de inventário cobertos (101)

Estratégia copiada de `.migration-ai9/map/projects-cadastros.md`. Requirements
correspondentes já existem em `openspec/specs/availability/spec.md` e
`openspec/specs/projects/spec.md` — **referenciados por ID, não recriados**.

### Backend — 38

**Padrões do projeto, pela rota de projeto (§2.6)** — BE-110 `build` `#tree` sem projeto →
erro de pré-condição, árvore ordenada, sem `1+N` · BE-111 `build` `#form` com pais válidos ·
BE-112 `build` criar/editar com **nível derivado do pai de forma determinística** (o legado
usava ` |= `, OR bit a bit) · BE-113 `build` `ActivateProjectTemplateJob` com bloqueio
liberado em `ensure` · BE-114 `build` `DeactivateProjectTemplateJob` com a guarda **no
serviço** · BE-115 `build` `RemoveProjectTemplateJob` tratando lançamentos explicitamente
(DC-20) · BE-116 `build` reordenação e recálculo em cascata sem custo quadrático (DC-21) ·
BE-117 `build` `/projects/:id/availability` **autenticado e escopado** (D-01).

**Lançamentos (§2.11)** — BE-120 `build` `#search` com grade em consultas **agregadas** ·
BE-121 `build + dropped` rota `index` vestigial não portada (DC-19) · BE-122 `build` create ·
BE-123 `build` update com **uma única gravação**, consolidação não editável, padrão
bloqueado → 409 · BE-124 `build` destroy que **não cria registro** (DC-26) · BE-125 `build`
consolidação geral (DC-27) · BE-126 `build` valor de padrão com filhos (DC-27/DC-28) ·
BE-127 `build` correção por dias úteis aplicada **uma única vez** (DC-25/DC-29) ·
BE-128 `build` saldo acumulado **determinístico** · BE-129 `build` propagação em cascata
**atômica** com guarda de ciclo · BE-130 `build` materialização de derivados: **ler a grade
não cria registro** (DC-30) · BE-131 `build` model com unicidade por índice.

**Catálogo global (§2.12)** — BE-132 `build` busca por substring, **sem `default_position`**
(D-06) · BE-133 `build` detalhe que funciona também para padrão de projeto · BE-134 `build`
create com obrigatoriedade respeitada e propagação **opcional** · BE-135 `build` update com
posição recalculada e propagação de `is_adjusted`/`is_cumulative` (DC-31) · BE-136 `build`
destroy com desvínculo **transacional** · BE-137 `build` numeração determinística ·
BE-138 `build` reordenação recusada no servidor quando inválida (DC-21) · BE-139 `build`
obrigatoriedade hierárquica.

**Padrões do projeto, rota própria (§2.13)** — BE-140 `build` `#tree` · BE-141 `build`
formulários com campos imutáveis identificados **com a razão** (DC-24) · BE-142 `build`
create com projeto **do servidor** e `:id` fora do `permit` · BE-143 `build` update sem
renumerar (DC-32) · BE-144 `build` ativar, **idempotente** (2ª ativação → 409; DC-33) ·
BE-145 `build` desativar com guarda no serviço (D-04/D-33) · BE-146 `build` remover
**atômico**, global não removível pela rota do projeto (DC-20) · BE-147 `build` bloqueio que
**termina junto com a operação** e vale **no servidor** (D-05) · BE-148 `build` consolidação
por padrão base com **semântica única de "total"** (DC-34) · BE-149 `build`
`/projects/:id/availability` sem dupla serialização (D-01).

### Frontend — 36

**Padrões do projeto (§2.8)** — FE-107 `build` árvore de 3 níveis · **FE-108 `adapt`**
estados do padrão com motivo do bloqueio consultável e menu nunca vazio · FE-109 `build`
formulário com imutáveis explicados (DC-24) · FE-110 `build` níveis derivados do pai, com
**nenhum padrão de outro projeto no payload** · FE-111 `build` ativar/desativar com mensagem
do domínio certo · FE-112 `build` remover com confirmação.

**Painel (§2.14)** — FE-120 `build` `AvailabilityPage` · FE-121 `build` seletor de visão por
empresa · FE-122 `build` calendário pt-BR (**Lacuna L-06**) · **FE-123 `adapt`** seleção de
data em tela estreita com **uma** fonte de verdade para "é estreito" · **FE-124 `adapt`** e
**FE-125 `adapt`** indicadores (`KpiCard`), com **sinal negativo no próprio valor** ·
**FE-126 `reuse`** observação em `RichTextEditor` (modo leitura) · FE-127 `build` grade
hierárquica (DC-35) · FE-128 `build` estados da grade · FE-129 `build` campo de valor com
`MoneyInput` e natureza da operação **legível** (o legado exibia `C`/`D` cru) ·
FE-130 `build` salvamento com guarda **por célula** · FE-131 `build` excluir lançamento ·
FE-132 `build` modo somente-leitura com **mesmo critério** no cliente e no servidor (D-23) ·
FE-133 `build` marcador de não cumulativo · FE-134 `build` marcador de corrigido com **os
dois valores visíveis**.

**Catálogo global (§2.14)** — FE-135 `build` tela "Tipos de disponibilidade" ·
FE-136 `build` busca que **funciona** (Q-01) · FE-137 `build` estados da lista ·
FE-138 `build` linha de padrão global (o `_child_widget.html.erb` é código morto e **não é
portado**) · FE-139 `build` formulário com **obrigatoriedade na tela** e sem vazamento ·
FE-140 `build` detalhe que funciona para padrão de projeto · FE-141 `build` permissão de
cadastro com **mesmo critério no servidor** (D-23).

**Padrões do projeto, tela própria** — FE-142 `build` tela que nasce **habilitada**
(DEC-15.1) · FE-143 `build` estados · FE-144 `build` ligar/desligar utilizável após a
primeira ação · FE-145 `build` menu de contexto **nunca vazio** · **FE-146 `adapt`** estados
visuais com motivo, autor e data (DC-36) · FE-147 `build` formulário sem vazamento ·
FE-148 `build` pai de **outro projeto** recusado · FE-149 `build` recarregar por
`invalidateQueries`.

### Dados — 17

DB-085 `build` `availability_templates` como **uma** estrutura hierárquica ordenável (no
lugar de 3 colunas numéricas + `position` string), `top_parent_id` sem default `0` ·
DB-120 `build` FK e índices (o legado tinha **zero**) · DB-121 `build` escopo global com
`has_children?` consultando a classe certa · DB-122 `build` padrão de projeto com únicos
cobrindo o 3º nível · DB-123 `build` `availability_entries` com **único
`(project_id, company_id, template_id, date)`** e índices (a maior tabela do módulo não tinha
**nenhum**) · DB-124 `build` `is_adjusted` boolean · DB-125 `build` `original_value`
preservado (DC-25) · DB-126 `build` marca **explícita** de consolidação (não inferida por
empresa nula) · DB-127 `build` `virtual_value` com rotina de reconciliação ·
DB-128 `build` bloqueio com motivo e instante; padrões travados **migram desbloqueados** ·
DB-129 `build` estado das tarefas como `enum` string (o legado usava texto livre em pt-BR e
array Ruby em coluna de texto) · DB-130 `build` marca de gestão no lançamento (DC-01) ·
DB-131 `build` hierarquia por **uma** estrutura ordenável (fecha a `position` string ordenada
lexicograficamente — "10" antes de "2" — e **nove colunas redundantes**) ·
DB-132 `build` `should_insert_on_existing_projects` **exposta** ·
DB-133 `build` FK, `null: false` e índices únicos, com limpeza e deduplicação **antes** ·
DB-134 `build` (**não portar**) `default_position` não existe em migration nenhuma ·
DB-135 `build` introspecção do esquema de origem (DEC-04).

### Operação — 10

OPS-081 `build` `SeedGlobalTemplatesJob` com hierarquia preservada · OPS-082 `build` ativação
com bloqueio liberado em `ensure` · OPS-083 `build` desativação · OPS-084 `build` remoção ·
OPS-120 `build` seed **atômico e idempotente**, com **`is_adjusted` copiado** (o legado não
copiava) · OPS-121 `build` `PropagateGlobalTemplateJob` com progresso **por projeto** e
atributos copiados fielmente (o legado **forçava obrigatoriedade a 1** aqui) ·
OPS-122 `build` ativação sem desligar o logger global do worker · OPS-123 `build` desativação
com pai sem lançamento concluindo normalmente · OPS-124 `build` remoção em que **nada
permanece** em falha · OPS-129 `build` `lib/tasks/fix_availability_data.rake` com **proteção
contra execução destrutiva** (o `destroy_existing` do legado apagava **todos** os lançamentos
e **todos** os padrões, sem guarda).

**Placar:** 94 `build` (1 `build + dropped`, 1 `build (não portar)`) · 6 `adapt` ·
1 `reuse` (FE-126).

## Fronteiras — o que este change **não** cobre

- **A feature de cobranças e recibos.** Os IDs (**BE-187, BE-188, BE-189, DB-162, DB-163,
  DB-164, DB-165, FE-179..FE-186**) pertencem ao bloco `receivables-renegotiations`, fatia
  **SR-6** daquele mapa, e dependem de `risk` e `structured-operations` (remunerações). O que
  desta fatia toca "Cobranças" é **exclusivamente** o item de menu nascer habilitado
  (DEC-15.1/DC-37), coberto pela tarefa 5.7 e por FE-119, que é da **S4**.
  **Ver "Ambiguidade" no relatório.**
- **Projeto, empresas, membros e garantias** — **S4**. Esta fatia consome
  `current_project!`, `Company` e `Project`.
- **Peças compartilhadas** BE-079, FE-052, FE-053, FE-061, FE-066, FE-079, OPS-086
  (`AuditEvent`), OPS-087, OPS-125 (infra das tarefas), OPS-126 (trilha do módulo),
  OPS-127 (progresso na tela), OPS-128 (retry do Sidekiq — **`reuse` puro**) — **S0**.
- **DB-073 / DB-074** — S14. **DB-135** está aqui porque o mapa o coloca na fatia, mas sua
  execução é coordenada com o ETL (S14).

## Dependências

| Depende de | Para quê |
| ---------- | -------- |
| **S0** | `require_role!`, `require_not_readonly!`, `current_project!`, `ProjectScoped`, `DataTable`, `Pagination`, `MoneyInput`, `EmptyState`/`ErrorState`, `AuditEvent`, `JobProgressChannel`/`useJobProgress`, retry do Sidekiq |
| **S4** | `projects`, `companies`, escopo por projeto, `useNavItems` com `requiresProject` |
| **bloco `data-schema` / S14** | DB-133 e DB-135 — limpeza e deduplicação **antes** das restrições; introspecção que aborta com relatório (DEC-04) |

**É dependência de:** nada bloqueia atrás dela dentro deste bloco. O bloco
`structured-operations` consome `receipts`/`charges`, que são do bloco de recebíveis, não
desta fatia.

## Perguntas em aberto — **as quatro que mudam número financeiro**

| # | Pergunta | Default declarado |
| - | -------- | ----------------- |
| **Q-01** | A coluna `default_position` existe no banco de produção? (D-06, DB-134) | Trato como inexistente e removo o uso; confirmar contra produção é uma das 2 provas do DEC-04 |
| **Q-07** | O decaimento composto da correção por dias úteis: corrigir ou replicar? (D-02, DC-25) | **Corrigir** — `original_value` preservado, correção aplicada **uma única vez** |
| **Q-08** | A consolidação geral deve respeitar `is_cumulative` e `is_debit`? (D-08, DC-27) | Ver `§6` do mapa. **Muda número exibido.** |
| **Q-09** | Dias úteis passam a considerar feriados? (D-03, DC-29) | **Manter seg–sex sem feriados** nesta entrega |
| **Q-10** | "Total" no painel: soma bruta ou saldo acumulado? (DC-34) | Subordinado ao Q-08 — a mesma resposta resolve os dois |

> **Nenhuma delas bloqueia o início da fatia.** As camadas de dados, catálogo global e
> padrões do projeto (seções 1 a 4 do `tasks.md`) são independentes das quatro. O que fica
> atrás delas são as tarefas de **cálculo** (5.x), marcadas na fila.

## Capabilities

### New Capabilities

Nenhuma. Os requirements desta fatia já existem em `openspec/specs/` desde o Phase 1 e são
referenciados por ID.

### Modified Capabilities

- `availability`: acréscimo de **um** requirement transversal (contrato **C1** aplicado ao
  módulo de disponibilidade) que o spec por ID não cobre de forma sistemática — o endpoint
  `/projects/:id/availability` era um **IDOR sem autenticação** (D-01) e todo id por
  parâmetro do módulo (`template_id`, `entry_id`, `company_id`, `parent_id`) precisa ser
  aplicado **dentro** do escopo.

## Impact

- **Backend**: `api/v1/{availability_templates,project_availabilities,availability_entries}.rb`
  e `api/v1/projects/:id/availability`; `app/services/availability/`;
  `app/models/{availability_template,project_availability_template,availability_entry}.rb`;
  jobs de seed, propagação, ativação, desativação e remoção; canal de progresso.
- **Dados**: 3 tabelas novas (`availability_templates`, o padrão de projeto e
  `availability_entries`) com a remodelagem da hierarquia — 9 colunas redundantes e a
  `position` string **saem**. `availability_entries` é a maior tabela do módulo e ganha
  índices pela primeira vez.
- **Frontend**: `src/app/pages/availability/`, `availability-templates/`,
  `project-availabilities/`; `components/ui/Calendar.tsx` (Lacuna L-06, sobre
  `react-day-picker`).
- **A base ai9 não é refatorada** (Princípio 6b).


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-566 | build | `availability_templates` + STI `GlobalAvailabilityTemplate` / `ProjectAvailabilityTemplate` | S11 é dona das disponibilidades |
| DB-567 | build | `availability_entries` (herda de `Entry`, cuja base é construída em S6) | idem |
| DB-583 | build | `charges` | S11 é dona das cobranças (DEC-15.1: **vivas**) |
| DB-584 | build | `receipts` | idem |

**`DB-567` consome `Entry` de S6** (contrato **C4**: quem constrói é dono; quem consome
referencia). A base abstrata e o `enum` que substitui as strings em pt-BR nascem em S6, com
`ReceivableEntry`; `AvailabilityEntry` herda.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`FE-110` e `FE-148` são de S11**, disputados com S4. A dependência pai↔níveis e o
  auto-preenchimento dos níveis derivados do pai pertencem aos padrões de disponibilidade,
  que são desta fatia. S4 cita a regra ("nenhum padrão de outro projeto viaja no payload")
  porque ela vale nas duas telas, mas a tarefa é aqui.
- **`OPS-125` e `OPS-127` são de S13.** A infraestrutura de fila e o mecanismo de progresso
  ao vivo são construídos lá; S11 é o **primeiro consumidor**. Eles apareciam nas tarefas
  desta fatia apenas por notação de intervalo, sem dono em nenhum `proposal.md` — e foi assim
  que ficaram órfãos. **`OPS-126`** (a auditoria do módulo) é de **S19**, dona da trilha.
- **`Entry`, a base dos lançamentos, é de S6.** `AvailabilityEntry` (`DB-567`) herda dela e
  **não** redefine o `enum` de situação.
