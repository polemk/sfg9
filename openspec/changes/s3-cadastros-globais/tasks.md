# Tasks: S3 — Cadastros globais

Fila de trabalho do Phase 3 para a fatia **S3**. Ordenada por camada:
**dados → backend → frontend → testes → paridade**.

**Regras desta fila** (valem para toda tarefa):

1. Uma tarefa = **um comportamento verificável**. Se não dá para escrever o teste que a
   fecha, ela está grande demais.
2. Cada tarefa cita os **IDs de inventário** que fecha. Ao marcar, virar o ID em
   `.migration-ai9/parity-ledger.md` para `implemented` (o `verified` é do Phase 4).
3. **Autorização é do servidor.** Toda tarefa de endpoint de escrita leva teste de que o
   papel não autorizado recebe **403** e o `user_is_readonly` recebe **403** — não basta o
   caminho feliz. O legado tinha o gate só na view (D-23).
4. **Catálogo global não recebe escopo de projeto** (contrato **C1**, regra 4 de `§0.6`).
   Nenhum endpoint desta fatia chama `current_project!`. Onde chega id por parâmetro
   (`group_id`, `guarantee_type_id`), o teste verifica que o id **não** muda o conjunto
   autorizado — e o teste de escopo cruzado propriamente dito é das fatias S4 e S11.
5. **Nada da base ai9 é refatorado** (Princípio 6b). O que parecer errado e não bloquear vai
   para `.migration-ai9/upstream-flags.md`.
6. Uma tarefa só é marcada quando o código existe, compila e **o teste dela passa**.

**Pré-requisitos (não são tarefas desta fatia):** S0 entrega `require_role!`,
`require_not_readonly!`, `DataTable` (FE-061), `Pagination` (FE-053), `useDebouncedSearch`
(FE-052), `MoneyInput`/`PercentInput` (FE-066) e `EmptyState`/`ErrorState`/`LoadingState`
(FE-079). Não começar 3.x antes de S0 fechar.

---

## 1. Dados — as cinco tabelas

- [x] 1.1 Migration `carriers` — colunas do portador com `bank_code` **string**,
      `subordinated_accounts_percent` `decimal`, `net_worth` `decimal(14,2)`, sem a coluna
      redundante `bank_name`; `id: :uuid` com `gen_random_uuid()`; `comment:` em cada coluna;
      cabeçalho de migration em pt-BR explicando o porquê. **Fecha DB-057.**
      Verificação: `db:migrate` + `db:rollback` limpos; `schema.rb` mostra `bank_code` como `string`.
- [x] 1.2 `carrier_groups` com `carriers_count` `integer, null: false, default: 0`.
      **Fecha DB-063.**
- [x] 1.3 `carriers.group_id` — FK real para `carrier_groups` + índice. Excluir grupo com
      portador é recusado **pelo banco**, não só pela aplicação. **Fecha DB-058.**
      Verificação: `DELETE` direto no banco levanta violação de FK.
- [x] 1.4 `carriers.financial_agent` — enum string Rails 8 com conjunto fechado
      (FIDC / Securitizadora / Factoring / Cliente). **Fecha DB-059.**
- [x] 1.5 `carriers.city` / `carriers.uf` — `uf` normalizada em 2 caracteres maiúsculos por
      validação de model. **Fecha DB-060.**
- [x] 1.6 `carriers.legacy_id` — coluna preservada (DEC-12), com índice **único**.
      **Fecha DB-061 e OPS-052.** O pipeline `Legacy::execute` do legado **não** é portado.
- [x] 1.7 `Carrier#logo` por `has_one_attached`, com `active_storage_validations`
      (tipo real do arquivo, limite de tamanho) e variantes na receita de `medium.rb`.
      **Não** usar `Medium` (DC-02/Q-05) nem `assets_proxy_controller.rb`.
      **Fecha DB-062 e OPS-051.**
      Verificação: arquivo `.exe` renomeado para `.png` é **recusado** (o legado tinha
      `MediaTypeSpoofDetector#spoofed? → false`, detecção desligada).
- [x] 1.8 Migration `segments` com `title` **único no banco** + `legacy_id` única.
      **Fecha DB-064 e DB-065 e OPS-053.**
- [x] 1.9 Migration `sub_segments` — catálogo **independente**, **sem** FK para `segments`
      (DC-13). **Fecha DB-066.**
- [x] 1.10 Migration `project_guarantee_types` — `title` e `integration_key` únicos no banco.
      **Fecha DB-084.**
- [x] 1.11 Conferência de FK e índices dos cadastros desta fatia: toda coluna `*_id` tem
      `add_foreign_key` e índice; `dependent:` explícito em toda associação. O legado tinha
      **zero** `add_foreign_key`. **Fecha DB-072.**
      Verificação: script que lista colunas `_id` sem FK devolve vazio para estas 5 tabelas.

## 2. Backend — endpoints, serviços e models

### 2.1 Portadores

- [x] 2.1.1 `api/v1/carriers.rb#search` — busca `ILIKE` por bind, `limit`/`offset`/ordenação
      **aplicados de fato**, `X-Total-Count` com o total **sem limite**. Sem
      `current_project!` (catálogo global). **Fecha BE-067.**
      Verificação: com 45 portadores, `l=20&o=20` devolve 20 a partir do 21º e o header diz 45.
- [x] 2.1.2 Simetria da busca: o mesmo `q` devolve o **mesmo conjunto** com e sem
      `ordering_keys`. **Fecha BE-067 (2ª metade).**
- [x] 2.1.3 `GET /carriers/:id` e `#form` respondem 200; inexistente → 404. **Fecha BE-068.**
- [x] 2.1.4 `CarrierService.create/update` — `bank_code` preservado como string (`001`
      continua `001`), `financial_agent` validado por inclusão, valores monetários nunca
      castados em silêncio. **Fecha BE-069.**
- [x] 2.1.5 `subordinated_accounts_percent` derivado **no servidor** a partir de
      `senior_accounts`/`subordinated_accounts`, sem divisão por zero, e **não** aceito do
      payload (DC-09). **Fecha BE-069 (parte) e apoia FE-065.**
- [x] 2.1.6 `app/models/carrier.rb` — só `title` obrigatório; **título duplicado continua
      permitido** (comportamento preservado de propósito); cidade formatada com fallback.
      **Fecha BE-071.**
- [x] 2.1.7 `CarrierService.destroy` — bloqueia com **422 real** quando há conexões de
      projeto ou recebíveis; `dependent: :restrict_with_error` no model, **nunca** cascata.
      **Fecha BE-070 (parcial — a parte `risk_controls` fica na 5.7).**

### 2.2 Grupos de portadores

- [x] 2.2.1 `api/v1/carrier_groups.rb#search` — ordenação por título **funciona** (o legado
      respondia 500), paginação real. **Fecha BE-072.**
- [x] 2.2.2 `CarrierGroupService.destroy` — grupo com portadores → **422 no servidor**, não
      só botão escondido. **Fecha BE-073.**
- [x] 2.2.3 `carriers_count` por `counter_cache`, sempre consistente com a lista.
      **Fecha BE-074 e OPS-058.**
      Verificação: criar e remover portador do grupo e conferir que a contagem bate com
      `group.carriers.count` — é ela que decide o botão de exclusão.

### 2.3 Segmentos e subsegmentos

- [x] 2.3.1 `api/v1/segments.rb#search` — ordenação por **título e por chave**, paginação
      real. **Fecha BE-075.**
- [x] 2.3.2 `SegmentService.create` — **a criação passa a funcionar**; `user_id` vem da
      sessão e o do corpo é ignorado. **Fecha BE-076.** Fecha **D-21**: no legado
      `user_id` estava fora do `permit` e a criação falhava 100% das vezes.
- [x] 2.3.3 `api/v1/sub_segments.rb#search` — ordenação resolvida pelo **próprio**
      subsegmento, sem acoplamento acidental com `Segment`. **Fecha BE-077.**
- [x] 2.3.4 `SubSegmentService.destroy` — bloqueado por projetos vinculados → 422.
      **Fecha BE-078.**

### 2.4 Tipos de garantia

- [x] 2.4.1 `api/v1/project_guarantee_types.rb#search` — catálogo global com `R` ao
      Colaborador (DEC-18.4), busca/ordenação/paginação reais. **Fecha BE-700.**
- [x] 2.4.2 **Sem credencial → 401.** Montado dentro de `api/v1/base.rb`, que já roda
      `before { restrict_visitor_access! }`. **Fecha BE-700 (D-23)** — no legado
      `requires_current_user? == false` e o endpoint respondia para anônimo.
- [x] 2.4.3 `#form` de criação — sem papel autorizado → **403 no servidor**.
      **Fecha BE-701.**
- [x] 2.4.4 `#form` de edição — tipo inexistente → 404. **Fecha BE-702.**
- [x] 2.4.5 `create` — `user_id` da sessão ignorando o do corpo; título único.
      **Fecha BE-703.**
- [x] 2.4.6 `update` — **chave de integração congelada** na criação, alterável só por campo
      explícito (DC-22); renomear o título **não** recalcula a chave. **Fecha BE-704.**
- [x] 2.4.7 `destroy` — tipo em uso por alguma garantia → **422 real**. **Fecha BE-705.**
- [x] 2.4.8 `GET /project_guarantee_types(/:id)` respondem 200 (o legado dava `MissingTemplate`
      → 500). **Fecha BE-706.**

### 2.5 Transversais de backend

- [x] 2.5.1 `scope :search` nos 5 models usando `ILIKE` **com bind**, sem `Dev.ilike`
      interpolando SQL de adapter. **Fecha OPS-056.**
      Verificação: buscar por `100%` e por `a'b` devolve resultado, não erro de SQL.
- [x] 2.5.2 `api/v1/br_states.rb` com a constante `UF`, no padrão de `api/v1/countries.rb`.
      `geocoder` e `city-state` **não** são portados. **Fecha OPS-057 (Lacuna L-11).**
- [x] 2.5.3 `db/seeds/catalogos.rb` — seed **idempotente** dos 5 catálogos, separado de
      `db/seeds/demo.rb`. **Fecha OPS-054.**
      Verificação: rodar duas vezes não duplica linha nenhuma.
- [x] 2.5.4 Registrar os 6 módulos novos (`carriers`, `carrier_groups`, `segments`,
      `sub_segments`, `project_guarantee_types`, `br_states`) em `api/v1/base.rb` e conferir
      que aparecem na documentação OpenAPI (AI9-035, mantido no trim).

## 3. Frontend — as cinco telas

- [x] 3.1 `CarriersPage` — `DataTable` (S0) com Título/Grupo/Agente/Cidade/# Projetos,
      `Pagination` (S0), `PageHeader`, estados de carregando/vazio/**falha**, light e dark.
      **Fecha FE-060.**
- [x] 3.2 Busca de portadores com `useDebouncedSearch` (S0); entrada só de espaços ignorada;
      o vazio **cita o termo buscado**. **Fecha FE-062.**
- [x] 3.3 Linha de portador — fallback `-` nos campos ausentes; clique abre "Relações";
      versão estreita por `components/mobile/`. **Fecha FE-063.**
- [x] 3.4 Formulário de portador no `SideDrawer` — 13 campos, incluindo a estrutura de FIDC
      (`net_worth`, `bank_code`, `senior_accounts`, `subordinated_accounts`, `%`), com
      `MoneyInput`/`PercentInput` (S0) e vocabulário de **contraparte financiadora** nos
      rótulos. **Fecha FE-064.**
- [x] 3.5 Campo "% contas subordinadas" **somente leitura**, alimentado pelo servidor, sem
      divisão por zero. **Fecha FE-065.**
- [x] 3.6 Upload de logo do portador com `ImageCropper`/`ThumbnailPicker` + ActiveStorage;
      limite verificado **antes** de enviar. **Fecha FE-067.**
      ⚠️ **Depende de Q-04.** Default declarado: ligar. Se a resposta for "não", esta tarefa
      é `dropped` no ledger, com evidência.
- [x] 3.7 `CarrierDetailPage` — tela alcançável, abas e cartões (DC-08: HTML e SCSS já
      existem no legado e nenhuma rota chega neles). **Fecha FE-068.**
- [x] 3.8 `CarrierGroupsPage` + painel lateral de grupo; o toast se refere ao **grupo** (o
      legado dizia "O portador foi excluído"). **Fecha FE-075 e FE-076.**
- [x] 3.9 `SegmentsPage` — criação **funciona** e o bloqueio de exclusão é comunicado ao
      usuário. **Fecha FE-077.**
- [x] 3.10 `SubSegmentsPage` — textos próprios de subsegmento (o placeholder legado dizia
      "Ex: Segmento Comercial"). **Fecha FE-078.**
- [x] 3.11 Tela "Tipos de garantia" com `DataTable` (S0) — busca, ordenação por título e por
      chave, ações por papel. **Fecha FE-116.**
- [x] 3.12 Formulário de tipo de garantia no `SideDrawer`; erro de dependência **nomeia o
      campo**. **Fecha FE-117.**
- [x] 3.13 Registrar as 5 telas em `src/app/App.tsx` (lazy + `ProtectedRoute`) e em
      `useNavItems.ts` com `roles`, no ponto de extensão documentado nas linhas 27-32.
      Rotas novas em **inglês** (convenção §8). *(Não fecha ID — é o encaixe das telas.)*
- [x] 3.14 Conferir que **nenhuma** das 5 telas repete texto herdado de outro domínio. Some
      "Essa construtora não pode ser alterada" das cinco entidades. *(Apoia FE-079, que é da S0.)*

## 4. Testes — cada um fecha um comportamento, não um caminho feliz

### 4.1 Autorização (a família D-23)

- [x] 4.1.1 Request spec: `GET /api/v1/project_guarantee_types` **sem credencial** → **401**.
      É o defeito literal do legado. **Cobre BE-700.**
- [x] 4.1.2 Request spec: Colaborador **lê** os 5 catálogos (200) e **não escreve** em
      nenhum dos 5 (403 em `POST`, `PUT`, `DELETE`). **Cobre BE-067..078, BE-700..706, DEC-18.4.**
- [x] 4.1.3 Request spec: usuário com `user_is_readonly` recebe **403** em todo verbo de
      escrita dos 5 catálogos, **mesmo sendo Admin**. **Cobre a regra de `require_not_readonly!`.**
- [x] 4.1.4 Request spec de **hierarquia nos dois sentidos** (contrato **C3** — a escala é
      invertida entre os sistemas): Admin **escreve** no catálogo **e** Colaborador **não**
      escreve. Um teste que só verifique "a trava existe" passa com a comparação de sinal
      errada. **Cobre a aplicação de `require_role!` nesta fatia.**

### 4.2 Escopo — o que vale para catálogo global (contrato C1)

- [x] 4.2.1 Request spec: nenhum endpoint desta fatia chama `current_project!`, e um usuário
      **sem projeto corrente** consegue **ler** os 5 catálogos (200). Catálogo global não é
      escopado — o menu esconde a tela de administração, não o dado. **Cobre `§0.6` regra 4.**
- [x] 4.2.2 Request spec: `carriers#search?group_id=<id>` filtra **dentro** do conjunto
      autorizado e um `group_id` inexistente devolve **vazio**, não 500 nem lista inteira.
      **Cobre BE-067.**

### 4.3 Os defeitos que não se replicam

- [x] 4.3.1 Spec: criar segmento **funciona** com `user_id` ausente do payload, e o autor
      gravado é o da sessão. Fecha **D-21**. **Cobre BE-076.**
- [x] 4.3.2 Spec: ordenar `carrier_groups` por título responde 200 (o legado dava 500).
      Fecha **D-21**. **Cobre BE-072.**
- [x] 4.3.3 Spec: excluir portador com `project_to_carrier_connections` responde **422** e o
      portador **continua existindo**. Fecha **D-24**. **Cobre BE-070.**
- [x] 4.3.4 Spec: excluir grupo com portadores → 422 e o `group_id` dos portadores
      **permanece**, sem órfão. Fecha **D-24**. **Cobre BE-073.**
- [x] 4.3.5 Spec: excluir subsegmento vinculado a projeto → 422. Fecha **D-24**.
      **Cobre BE-078.**
- [x] 4.3.6 Spec: excluir tipo de garantia em uso → 422. Fecha **D-24**. **Cobre BE-705.**
- [x] 4.3.7 Spec de paginação para os 5 `search`: `l`/`o` são **aplicados** e o total do
      header é o total **sem limite**. Fecha **D-20/DC-38**. **Cobre BE-067, BE-072, BE-075,
      BE-077, BE-700.**
- [x] 4.3.8 Spec: `bank_code = "001"` sobrevive a criação, leitura, edição e serialização —
      não vira `1` em nenhum ponto. Fecha **DC-12**. **Cobre BE-069 e DB-057.**
- [x] 4.3.9 Spec: renomear tipo de garantia **não** altera a `integration_key`. Fecha
      **DC-22**. **Cobre BE-704.**
- [x] 4.3.10 Spec: busca por `100%` e por `a'b` devolve resultado, sem erro de SQL. Fecha o
      `Dev.ilike`. **Cobre OPS-056.**
- [x] 4.3.11 Spec de anexo: arquivo com extensão de imagem e conteúdo de executável é
      **recusado**. Fecha a detecção de spoof desligada do legado. **Cobre OPS-051.**
- [x] 4.3.12 Spec: dois portadores com **o mesmo título** são aceitos — o comportamento é
      preservado de propósito. **Cobre BE-071.** *(Teste de não-regressão da preservação.)*

### 4.4 Frontend

- [x] 4.4.1 Teste de componente: `CarriersPage` renderiza os três estados (carregando /
      vazio / **falha**) e a falha **aparece** — no legado o callback de erro era vazio.
      **Cobre FE-060.**
      ⚠️ `vitest` não roda neste ambiente (falta `@rollup/rollup-win32-x64-msvc`) —
      limitação **anterior** a esta fatia, registrada no `tasks.md` do trim. O portão real é
      o type-check. Escrever o teste mesmo assim e marcar a tarefa quando ele existir e o
      type-check estiver limpo.
- [x] 4.4.2 Teste: o critério do botão "Remover" é o **mesmo** critério do servidor nas 5
      telas — botão visível ⇒ a exclusão passa; botão oculto ⇒ 422 se forçado por API.
      **Cobre FE-075, FE-077, FE-078, FE-116.**
- [x] 4.4.3 Type-check limpo (`node node_modules/typescript/bin/tsc --noEmit`) e eslint limpo
      após as 5 telas. Baseline pós-trim: **0 erro** — qualquer erro é desta fatia.

## 5. Paridade e fechamento

- [x] 5.1 Conferir os **51 IDs** contra `.migration-ai9/parity-ledger.md`: todos em
      `implemented` (ou `dropped` com evidência, no caso de FE-067 se Q-04 disser não).
      Nenhum ID desta fatia pode ficar sem estado.
- [x] 5.2 Registrar em `.migration-ai9/improvements-log.md` as **7 mudanças visíveis** da
      seção "What Changes" do `proposal.md`, para o QA do Phase 4 não as ler como regressão.
- [x] 5.3 Conferir os requirements de `openspec/specs/companies-carriers/spec.md`
      correspondentes a BE-067..078, FE-060..078, DB-057..066, DB-072, OPS-051..058 — cada
      cenário tem um teste que o exerce. Cenário sem teste = tarefa reaberta.
- [x] 5.4 Conferir os requirements de `openspec/specs/projects/spec.md` correspondentes a
      BE-700..706, FE-116, FE-117 e DB-084 — idem.
- [x] 5.5 `rspec` do backend: **nenhuma falha nova** em relação ao baseline registrado no
      `tasks.md` do trim (as falhas conhecidas são um subconjunto das 6 originais). Registrar
      a **lista** das falhas, não só a contagem.
- [x] 5.6 Rodar `db:seed` num banco limpo e conferir que os 5 catálogos ficam utilizáveis
      sem nenhum passo manual. **Fecha OPS-054 na prática.**
- [x] 5.7 **FECHADA em 26/08/2026 — o bloqueio era fóssil.** `risk_controls` existe desde a
      S5 (tabela, model, FK `NO ACTION`), então `Carrier` ganhou
      `has_many :risk_controls, dependent: :restrict_with_error` — a associação REAL, ao
      lado do registro por nome de `blocking_dependents`, que continua sendo quem escreve a
      mensagem em pt-BR do 422. Fecha **BE-070** e desbloqueia **DB-069** (os dois passam a
      `verified` no ledger). **A assimetria mais perigosa do legado** — `dependent: :destroy`,
      em que excluir portador **apagava os limites de risco** — está provada nos dois lados
      (C3), com quatro exemplos que rodam em `spec/requests/api/v1/carriers_spec.rb`:
      1. `DELETE /api/v1/carriers/:id` com limite → **422**, a mensagem NOMEIA
         "limite(s) de risco", o limite PERMANECE (valor conferido) e o portador também;
      2. o limite **sozinho** bloqueia — a conexão projeto↔portador é removida antes, senão
         o 422 poderia estar vindo só dela;
      3. `delete_all` por fora do model levanta `ActiveRecord::InvalidForeignKey` (a terceira
         camada, o Postgres);
      4. **o outro lado**: removido o limite, a exclusão volta a responder 200.
      Medido: 453 exemplos verdes em `carriers` + `risk_controls` + `models` + conexões.
- [x] 5.8 Anotar em `.migration-ai9/upstream-flags.md` qualquer achado da base ai9 encontrado
      durante a fatia — **não** consertar (Princípio 6b).


## Fechamento de órfãos do Phase 2 — tabelas dos catálogos e o arcabouço de seed

Seis IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir que as migrations de `segments`, `sub_segments`, `carriers`,
      `carrier_groups` e `project_guarantee_types` cobrem o que o inventário de
      `data-schema` descreve — e que **não** existe uma segunda família de tabelas para os
      mesmos recursos. **Fecha: DB-550, DB-551, DB-552, DB-553, DB-558.**
- [x] F.2 Seed **obrigatório** de `project_guarantee_types` (sem ele, garantia de projeto não
      pode ser cadastrada). **Fecha: DB-558 (parte).**
- [x] F.3 Criar `backend/db/seeds/reference/` como **arcabouço idempotente**: cada catálogo é
      um arquivo, o carregador é um só, e rodar duas vezes não duplica nem sobrescreve
      alteração feita pelo usuário. **Fecha: OPS-540.**
- [x] F.4 Ligar o arcabouço ao deploy e documentar, em uma linha, como as fatias seguintes
      (S5, S6, S8, S17) plugam os seus catálogos — para nenhuma delas inventar um segundo
      mecanismo. **Fecha: OPS-540 (parte).**
- [x] F.5 Teste de idempotência do arcabouço: rodar `reference` duas vezes seguidas e
      comparar as contagens.
