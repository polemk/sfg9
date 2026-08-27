# Tasks: S4 — Projeto e empresas

Fila de trabalho do Phase 3 para a fatia **S4**. Ordenada por camada:
**dados → backend → frontend → testes → paridade**.

**Regras desta fila** (valem para toda tarefa):

1. Uma tarefa = **um comportamento verificável**.
2. Cada tarefa cita os **IDs de inventário** que fecha. Ao marcar, virar o ID em
   `.migration-ai9/parity-ledger.md` para `implemented`.
3. **A regra não negociável desta fatia** — família **D-01 / D-16 / D-29 / D-76 / D-100**:
   > **Toda tarefa de endpoint que aceita id por parâmetro (`project_id`, `importing_id`,
   > `company_id`, `provider_id`, `project_guarantee_id`, `carrier_id`, `indicator_id`,
   > `membership :id`, `user_id`) leva um teste explícito de que um id de OUTRO projeto é
   > rejeitado.** O caminho feliz passa com o código errado — foi assim que o legado errou.
   > Resultado esperado: **vazio** para busca, **404** para detalhe/escrita. Nunca 403 (não
   > se confirma a existência de registro alheio).
4. **`project_id` do payload é sempre ignorado**, no `create` **e** no `update`.
5. **`:id` fora do `permit`** em todo recurso.
6. **Escopo é declarado no endpoint** por `current_project!`. **`default_scope` é proibido**
   (contrato **C1**, `§0.6` do mapa).
7. **Nada da base ai9 é refatorado** (Princípio 6b) — achados vão para
   `.migration-ai9/upstream-flags.md`.
8. Uma tarefa só é marcada quando o código existe, compila e **o teste dela passa**.

**Pré-requisitos (não são tarefas desta fatia):** S0 (`require_role!`,
`require_not_readonly!`, `current_project!`, `ProjectScoped`, `AuditEvent`,
`ProjectProgressChannel`/`useJobProgress`, `DataTable`, `Pagination`,
`AsyncSearchableSelect`, `MoneyInput`, `EmptyState`/`ErrorState`) e S3 (`segments`,
`sub_segments`, `carriers`, `project_guarantee_types`).

---

## 1. Dados — o tenant e seus satélites

- [x] 1.1 Migration `projects` — `responsible_id` como **referência de usuário** (era
      `string`), FK e índices em `user_id`, `segment_id`, `sub_segment_id`, `slug`,
      `integration_key`; marcas como **boolean**; `is_active` com `null: false`; nome e slug
      **únicos no banco**. `id: :uuid`, `comment:` por coluna, cabeçalho pt-BR.
      **Fecha DB-080.**
      Verificação: `db:migrate` + `db:rollback` limpos; o nome `projects` está livre na base
      (conferido: nenhum model, nenhuma `create_table "projects"` em `schema.rb`).
- [x] 1.2 `projects.segment_id` / `.sub_segment_id` — FK + índice, **ambos opcionais**.
      **Fecha DB-067.** Fecha o caminho do D-26.
- [x] 1.3 Migration `memberships` — `user_id`, `project_id`, `role` como **enum string
      estável** (responsavel/participante/coordenador/gestor), índice **único**
      `(user_id, project_id)`, FKs. `role` é rótulo descritivo (DEC-18.6). **Fecha DB-086.**
- [x] 1.4 `users.current_project_id` — coluna + **FK** + índice. **Fecha DB-087.**
      Fecha **D-28** no modelo: era o tenant de fato do sistema, sem FK, sem índice e sem
      validação. Verificação: `current_project_id` apontando para projeto sem membership é
      inválido no model.
- [x] 1.5 Observação do projeto por **ActionText** — `has_rich_text :availability_note`.
      **Zero migration**: `action_text_rich_texts` já existe no `schema.rb`. **Fecha DB-088.**
- [x] 1.6 `Project#logo` por `has_one_attached` + `active_storage_validations` +
      `image_processing`, na receita de `medium.rb#optimized_url`/`small_url`. Ausência de
      logo é **explícita** (o legado tratava `"missing.jpg"` como ausência).
      **Fecha DB-089 e OPS-088.**
- [x] 1.7 Colunas `legacy_*` do projeto e das conexões, preservadas (DEC-12).
      **Fecha DB-091.**
- [x] 1.8 Migration `companies` — FK `project_id` + **índice único composto
      `(project_id, title)`**. **Fecha DB-050.**
- [x] 1.9 Migration `providers` — FK `project_id`; índices em `project_id`, `cnpj`, `cpf`,
      `integration_key`; `is_active` **boolean** de verdade. **Fecha DB-052.**
- [x] 1.10 `providers.document_type` + `providers.document` — par explícito, **documento
      opcional** (DC-11). **Fecha DB-053.**
- [x] 1.11 Campos ReceitaWS + `cnpj_fetched_at`; `abertura` e `data_situacao` como `date` de
      verdade. **Fecha DB-054.** *(Depende de Q-03 para ter uso; as colunas podem existir antes.)*
- [x] 1.12 `providers.cnaes` e `.atividades` em **um** formato: `jsonb`. **Fecha DB-055.**
      Fecha **D-25** (YAML e JSON na mesma tabela).
- [x] 1.13 `Provider#logo` por ActiveStorage — sai `public/system/logos/:id/…` do Paperclip.
      **Fecha DB-056.**
- [x] 1.14 Migration `project_to_carrier_connections` — FK + **único
      `(project_id, carrier_id)`**; é a **única ponte** projeto↔portador (os portadores da
      empresa são derivados do projeto). **Fecha DB-068 e DB-081.**
- [x] 1.15 Migration `project_indicator_connections` — FK + único; `is_active` **não é
      aceito** (o controller legado o permitia sem a coluna existir). **Fecha DB-082.**
- [x] 1.16 `indicators.scope` explícito — global × de projeto **sem depender de campo nulo**.
      **Fecha DB-092.** Coluna `scope` (`global`/`project`) + **CHECK** que a amarra a
      `project_id`, índice `(scope, title)`, model/entities lendo a coluna. O bloqueio "por S10"
      era **fóssil**: a tabela existe desde `20260826210000` e a S10 fechou 80/80.
- [x] 1.17 Migration `project_guarantees` — `observation` **text** (era `string(255)` com
      `textarea` na tela), `value` `decimal(14,2)`, FKs e índices. **Fecha DB-083.**
- [x] 1.18 Registrar o **contrato** das FKs que pertencem a outros blocos —
      `risk_controls.company_id`/`.carrier_id` (**bloquear, nunca cascatear**),
      `receivable_entries.company_id`/`.carrier_id`, `renegotiations.company_id`/`.provider_id`
      — no `design.md` do change do bloco dono, e abrir a tarefa de teste correspondente
      (7.6). **Fecha DB-069, DB-070, DB-071 na parte que é desta fatia.**
- [x] 1.19 Marca de gestão (`has_safegold_management`) — coluna em `projects` (DB-051 no
      `companies` e DB-090 nas filhas). **DEC-112**: a "Q-02" era citação errada; a pergunta
      certa (Q-17/F-10/P-019) o **DEC-30 respondeu** — opção **(b), manter o carimbo**.
      Colunas criadas em `companies`, `availability_entries`, `risk_controls` e `risk_entries`
      (`receivable_entries` e `renegotiations` já as tinham); `before_validation` **sem `on:`**
      em todas; `update_all` de ressincronização **só em `companies`** (D-30 replicado).
      **Fecha DB-051 e DB-090.**

## 2. Backend — o escopo (o que tudo depende)

- [x] 2.1 `current_project!` em `api/v1/controller_helpers.rb` — resolve por
      `users.current_project_id`, **revalida membership a cada request**, aceita
      `X-Project-Id` **só** se houver membership (duas abas). **Fecha BE-098.**
      *(A peça é da S0; aqui é a aplicação e o contrato. Se a S0 entregou, esta tarefa é a
      conferência do contrato.)*
- [x] 2.2 Projeto inexistente e projeto sem membership respondem **o mesmo status**.
      Distinguir 403 de 404 vira oráculo de existência de id. **Fecha BE-098 (2ª condição).**
- [x] 2.3 Concern `ProjectScoped` aplicado a `Company`, `Provider`, `ProjectGuarantee` e às
      conexões: `belongs_to :project` + `scope :for_project` + presença obrigatória.
      **Nenhum `default_scope`.** *(A peça é da S0; aqui é a aplicação.)*
- [x] 2.4 Revisão dirigida: `grep` por `default_scope` em `backend/app/models/` devolve
      **vazio** para os models desta fatia. *(Portão de contrato, não fecha ID.)*

## 3. Backend — projeto

- [x] 3.1 `api/v1/projects.rb#search` — escopo por **membership**, busca `ILIKE`, ordenação e
      paginação **aplicadas**. **Fecha BE-080.**
      Verificação: usuário membro de 3 de 50 projetos recebe 3.
- [x] 3.2 `order_mode=dash` — ordena por `updated_at` asc. e ignora `q`. **Fecha BE-081.**
- [x] 3.3 Filtros `importing_id` / `project_id` aplicados **dentro** do membership.
      **Fecha BE-082.** Fecha **D-29** — no legado qualquer autenticado lia qualquer projeto
      por id. **Teste de id de outro projeto obrigatório (7.1).**
- [x] 3.4 `#autocomplete` com `ILIKE` (o legado usava `LIKE` cru, case-sensitive no Postgres)
      **e com limite**. **Fecha BE-083.**
- [x] 3.5 `#form` — lista de responsáveis filtrada por hierarquia de papel, via
      `UserType.hierarchy_level` (escopos `higher_than`/`lower_than`), não por decorator.
      **Fecha BE-084.**
- [x] 3.6 `ProjectService.create_with_new_owner` — cria projeto + usuário responsável em
      **transação atômica** e **envia link para a pessoa definir a própria credencial**.
      **Nenhuma senha é montada, exibida ou enviada.** **Fecha BE-085.** Fecha **D-38**.
- [x] 3.7 `create` sem responsável — o projeto pertence a quem criou, com membership.
      **Fecha BE-086.**
- [x] 3.8 `create` com responsável existente — responsável em branco → **422**, não 500; a
      posse vai para o responsável e **o criador permanece com membership explícita**
      (DC-14). **Fecha BE-087.**
- [x] 3.9 `ProjectCreationJob` e `SeedGlobalTemplatesJob` com **progresso próprio** (o legado
      escrevia no mesmo `job_id`) e sem criação duplicada dos vínculos padrão.
      **Fecha BE-088.**
- [x] 3.10 `ProjectService.update` — troca de responsável garante o vínculo; a marca de BI
      **não muda** por aqui. **Fecha BE-089.**
- [x] 3.11 Evento de onboarding na trilha `AuditEvent` (S0) — não é feature própria (DC-15).
      **Fecha BE-090.**
- [x] 3.12 `ProjectService.destroy` — bloqueio por dependentes responde **422 real**.
      **Fecha BE-091.** Fecha **D-24**: o legado respondia `:ok` e o JS redirecionava.
- [x] 3.13 `ProjectResetService` — segmento resolvido **por configuração**, nunca id fixo; o
      projeto de treinamento **não pode ser removido**, só limpo. **Fecha BE-092.**
      Fecha **D-26** (`segment_id = 1` codificado).
- [x] 3.14 `PATCH /projects/:id/safegold_management` — marca de gestão. ⚠️ **Depende de Q-02.**
      **Fecha BE-093.**
- [x] 3.15 `PATCH /projects/:id/bi` — marca comercial, gravada e exibida como hoje (DC-16;
      pode haver consumidor externo). **Fecha BE-094.**
- [x] 3.16 `Project#slug` + `integration_key` + cor — slug gerado do nome e **imutável após a
      criação** (DC-17, Lacuna L-09). **Fecha BE-095.**
      Verificação: renomear o projeto **não** altera o slug.
- [x] 3.17 `app/models/project.rb` — nome único, dono, slug e situação obrigatórios; logo com
      limite; **erros em pt-BR** (o legado tinha `translate_every_key` e nunca o chamava).
      **Fecha BE-096.**
- [x] 3.18 `has_rich_text :availability_note` + param + `expose :availability_note_html`,
      copiando o caminho de `biography` (`user.rb:18` → `users.rb:190` →
      `entities/user.rb:33-49`). **Anexo bloqueado no servidor** — o ActionText os aceita por
      padrão e o legado bloqueava só no cliente. **Fecha BE-097.**
- [x] 3.19 `GET /users/:id/projects` — só o que o solicitante pode ver; aba **informativa**
      (DC-18). **Fecha BE-100.**
- [x] 3.20 `index` e `detail` de projeto respondem 200; as rotas comprovadamente mortas
      **não são portadas**, com a evidência registrada (DC-19). **Fecha BE-101.**

## 4. Backend — membership

- [x] 4.1 `api/v1/memberships.rb` + `MembershipService` — criar e remover: **OG/Admin/Gerente**;
      `:id` **fora do `permit`**; busca com termo vazio devolve lista válida.
      **Fecha BE-099 (parte 1).**
- [x] 4.2 As **três condições** da view viram regra de servidor (DEC-15.2/DEC-18.5):
      não-readonly · **não remove o dono** (`project.user_id`) · **não remove a si mesmo**.
      **Fecha BE-099 (parte 2).** Fecha **D-28 + D-34** — hoje qualquer sessão se
      auto-adiciona a qualquer projeto e ganha o grupo "Gestão" inteiro.
- [x] 4.3 `role` **nunca** é consultado para autorizar (DEC-18.6). Verificação: `grep` por
      `membership.role` em código de autorização devolve vazio. *(Portão de contrato.)*
- [x] 4.4 Remoção de membership passa por callbacks (não é `delete_all`) e reavalia
      `users.current_project_id` de quem perdeu o vínculo. **Fecha DB-087 no comportamento.**

## 5. Backend — empresas, fornecedores, conexões e garantias

### 5.1 Empresas

- [x] 5.1.1 `api/v1/companies.rb#search` — `Company.for_project(current_project!)`, `q`/`l`/`o`
      **funcionando**, total sem limite. **Fecha BE-050.**
- [x] 5.1.2 `order_mode=dash` — resumo por título asc., `q` ignorado. **Fecha BE-051.**
- [x] 5.1.3 `#form` — sem projeto corrente → **422 explícito**, não `NoMethodError`.
      **Fecha BE-053.**
- [x] 5.1.4 `CompanyService.create` — `project_id` **ignorado** do payload; erros em pt-BR
      nomeando o campo; `:id` fora do `permit`. **Fecha BE-054.** Fecha D-23/D-29.
- [x] 5.1.5 `CompanyService.update` — `project_id` **ignorado** também aqui (DC-04: mover
      empresa entre projetos não é caso de uso). **Fecha BE-055.**
- [x] 5.1.6 `CompanyService.destroy` — bloqueio por dependentes responde **422 real**.
      **Fecha BE-056.** Fecha **D-24** (o legado respondia `:ok ? :ok`).
- [x] 5.1.7 `GET /companies` e `GET /companies/:id` respondem (o legado dava
      `MissingTemplate`). **Fecha BE-057.**
- [x] 5.1.8 `app/models/company.rb` — `title` único **por projeto**, `project` obrigatório,
      agregados sem N+1. **Fecha BE-058.**
- [x] 5.1.9 `CompanyService.risk_summary` — agregados como **número**, N+1 eliminado
      (`Risk::ExposureCache`), `date` validado no `params do`, divisão por zero → 100%
      explícito, data inválida **não é 500**. **Fecha BE-052.** A S5 preencheu os números
      (BE-251). ⚠️ Verificado executando: data válida → **200**, data inválida → **400**
      (não 422: `type: Date` do Grape é o padrão de TODA a base — ver `upstream-flags.md`).

### 5.2 Fornecedores

- [x] 5.2.1 `api/v1/providers.rb#search` — escopo de projeto **obrigatório** (sem projeto →
      422, **não** catálogo geral); paginação e ordenação juntas. **Fecha BE-059.**
- [x] 5.2.2 `#form` — fornecedor inexistente → 404. **Fecha BE-060.**
- [x] 5.2.3 `ProviderService.create` — `project_id` do servidor; nada de `destroy` sobre
      registro não persistido. **Fecha BE-061.**
- [x] 5.2.4 `ProviderService.update` — `title` e `integration_key` obrigatórios **também no
      update**; `project_id` ignorado. **Fecha BE-062.** Fecha **D-23** (mover fornecedor por
      campo escondido).
- [x] 5.2.5 `ProviderService.destroy` — 422 real quando há renegociações. **Fecha BE-063.**
      *(A checagem completa depende do bloco `renegotiations`.)*
- [x] 5.2.6 `GET /providers` e `/providers/:id` respondem; a tela de detalhe passa a existir
      (D-22). **Fecha BE-065.**
- [x] 5.2.7 `app/models/provider.rb` — documento validado (CPF/CNPJ) e único **por projeto**;
      `cnaes`/`atividades` em **um** `jsonb`; `integration_key` única de verdade.
      **Fecha BE-066.**
- [x] 5.2.8 `ReceitaWsService` + `#cnpj_lookup` — token em `Credential` (nunca em ENV
      commitada), CNPJ validado **no servidor** antes de chamar o provedor, rate-limit,
      timeout, resposta **normalizada**. **Fecha BE-064 e OPS-050.**
      ⚠️ **Depende de Q-03.** Se a resposta for "não religar", o ID vira `dropped` com evidência.

### 5.3 Conexões

- [x] 5.3.1 `api/v1/project_carrier_connections.rb` — tipo de entidade de **conjunto fechado**
      (nunca `constantize` de parâmetro); estado "conectado" em **consulta única** (sem
      `o.carriers.include?(t)` por linha). **Fecha BE-102.**
- [x] 5.3.2 Conectar/desconectar **em lote** — lote vazio → 400; resultado **por item**;
      desconectar o que não está conectado não dá 500. Corrige a condição invertida
      (`unless errors.blank?`) que só avaliava o último item. **Fecha BE-103.**
- [x] 5.3.3 **Um** endpoint de candidatos (os dois quase idênticos do legado viram um).
      **Fecha BE-104.**
- [x] 5.3.4 Remover conexão isolada — action que **funciona** (o `before_action` legado
      preenchia `@connections`, plural → `NoMethodError`). **Fecha BE-105.**
- [x] 5.3.5 Conexões projeto↔indicador sem `constantize` de parâmetro. **Fecha BE-106.**
      Entregue como `api/v1/indicator_connections.rb` (a S10 nomeou assim; é o mesmo
      controller legado `Pub::ProjectIndicatorConnectionsController`, com as 6 chamadas a
      `constantize` eliminadas). Coberto por `spec/requests/api/v1/indicator_connections_spec.rb`.
- [x] 5.3.6 Candidatos = indicadores **globais + do projeto**; nenhum específico de outro
      projeto aparece. **Fecha BE-107.** Verificado executando: `GET /indicator_connections`
      → **200** com o global e o do projeto, e **sem** o específico do outro projeto.
- [x] 5.3.7 Conectar/desconectar indicadores em lote — os mesmos 4 defeitos do BE-103,
      corrigidos. **Fecha BE-108.** Verificado executando: lote bom → **200** com resultado
      por item; lote vazio → **422**; lote com id de outro projeto → **422** nomeando o item
      e **nada gravado**; desconectar duas vezes → **200** idempotente.
- [x] 5.3.8 Excluir indicador específico — indicador **global** não pode ser excluído: **422**,
      não 500. **Fecha BE-109.** Verificado executando: global → **422** (e continua vivo);
      de outro projeto → **404** (nunca 403); id malformado → **404**; o específico do
      projeto → **200** com exclusão lógica e `entries_preserved`.

### 5.4 Garantias

- [x] 5.4.1 `api/v1/project_guarantees.rb#search` — ordenar por "Título" funciona (o legado
      ordenava por `risk_operations.title`, tabela fora do join → erro SQL, D-32);
      paginação real; **`project_guarantee_id` aplicado DENTRO do escopo**. **Fecha BE-118.**
      Fecha **D-29/D-32**. **Teste de id de outro projeto obrigatório (7.1).**
- [x] 5.4.2 CRUD de garantias — `edit` funciona (o legado fazia `@companies.first.id` com
      `@companies` nunca definido); só portadores **conectados ao projeto** são oferecidos;
      remoção bloqueada responde 422. **Fecha BE-119.**

## 6. Frontend

### 6.1 Projeto

- [x] 6.1.1 `ProjectsPage` — cards com nome, chave, progresso e menu; estados de carregando /
      vazio / **falha**. **Fecha FE-080.**
- [x] 6.1.2 Busca incremental com `useDebouncedSearch` (S0); só-espaços ignorado; o vazio
      cita o termo. **Fecha FE-081.**
- [x] 6.1.3 Card + menu de contexto — editar/remover **só** para papel autorizado; o critério
      do menu **é** o critério do servidor. **Fecha FE-082.**
- [x] 6.1.4 Progresso do projeto por **Action Cable** (`useJobProgress` da S0), avançando
      sozinho. **Polling é proibido** (Princípio 10). **Fecha FE-083.** Fecha **D-86**.
- [x] 6.1.5 Remoção pela lista — o erro do servidor **aparece** e o projeto **permanece** na
      lista (no legado o tratamento de erro estava comentado). **Fecha FE-084.**
- [x] 6.1.6 Formulário de projeto no `SideDrawer` — nome, chave, situação, segmento,
      subsegmento, endereço, observação, responsável, data de baixa, logo. **Fecha FE-085.**
- [x] 6.1.7 Escolha do responsável com `AsyncSearchableSelect` (S0): criar novo, indicar
      existente ou nenhum, com **busca server-side**. **Fecha FE-086.**
- [x] 6.1.8 Upload e preview do logo com `ImageCropper`/`ThumbnailPicker` + ActiveStorage; a
      escolha **sobrevive** a erro de validação em outro campo (o legado resetava o input em
      qualquer `ajax:error`). **Fecha FE-087.**
- [x] 6.1.9 Campo de data de baixa em `dd/mm/aaaa` com `date-fns`, enviado correto.
      **Fecha FE-088.**
- [x] 6.1.10 Salvamento com **uma** requisição por clique em "Salvar" — **sem autosave**
      (DC-23: o legado registrava salvamento a cada `keyup`); o sucesso mantém o usuário no
      formulário. **Fecha FE-089.**
- [x] 6.1.11 Toasts distinguem "cadastrado" de "**atualizado**", com campos em pt-BR e sem a
      chave técnica em negrito. **Fecha FE-090.**
- [x] 6.1.12 `ProjectDetailPage` — abas e cartões; data de criação bem formatada (o legado
      exibia `dd/mm/aaaa- HH:MM`). **Fecha FE-091.**
- [x] 6.1.13 Interruptor "Gerido pela Safegold" — bloqueado para readonly, com aviso.
      **Fecha FE-092.**
- [x] 6.1.14 Interruptor "BI contratado" com **id HTML distinto** (o legado usava
      `id="is_active_{project.id}"` nos dois — clicar no rótulo do BI alterava o outro).
      **Fecha FE-093.**
- [x] 6.1.15 Ações rápidas do detalhe — projeto de treinamento oferece "limpar", não
      "remover". **Fecha FE-094.**
- [x] 6.1.16 Lista de membros — dono do projeto e o próprio usuário **sem** ação de remover;
      as 3 condições do DEC-15.2 espelhadas no front. **Fecha FE-095.**
- [x] 6.1.17 Adicionar membro com `AsyncSearchableSelect`; o campo **some** para quem não
      pode. **Fecha FE-096.**
- [x] 6.1.18 Remover membro — a mensagem se refere ao **projeto** (o legado dizia "O membro
      foi removido da empresa"). **Fecha FE-097.**
- [x] 6.1.19 Cartão "Portadores" — ordem alfabética, com grupo; vazio explícito.
      **Fecha FE-098.**
- [x] 6.1.20 Cartão "Observação - Disponibilidade" com o `RichTextEditor` da base
      (**`reuse` puro** — `value: string`/`onChange` e HTML dos dois lados casam com o
      `*_html` do ActionText). Some quando vazio. **Fecha FE-099.**
      Verificação: **nenhum componente novo** foi escrito para isto.

### 6.2 Projeto corrente e menu

- [x] 6.2.1 Seletor de projeto na barra do console — só os projetos do usuário, em ordem
      alfabética. **Fecha FE-105.**
- [x] 6.2.2 Resolução do projeto corrente **pela sessão**, no padrão de `tokenStore.ts`;
      nenhum cookie, nenhum estado de navegador. **Fecha FE-106.** Fecha **D-28** no front.
- [x] 6.2.3 Aba "Projetos" no detalhe do usuário — **informativa**, listando só os projetos
      dos quais ele participa (DC-18). **Fecha FE-118.**
- [x] 6.2.4 Menu do domínio de projetos em `useNavItems.ts` — gate `projects.count > 0` +
      papel; **Disponibilidades nasce visível** (DEC-15.1). O `locked` continua existindo
      como mecanismo, lido do **item** (não do grupo), mas **nenhum item nasce marcado**.
      **Fecha FE-119.** Fecha **D-90** pelo efeito.

### 6.3 Empresas e fornecedores

- [x] 6.3.1 `CompaniesPage` — `DataTable` + `Pagination` (S0); colunas
      Empresa/Portadores/Controles; estados de carregando, vazio e **falha**.
      **Fecha FE-051.**
- [x] 6.3.2 Barra de filtros com **só os filtros que existem** — `kind` e `state` são
      descartados (DC-05: os selects não existem no HTML e o backend os ignora).
      **Fecha FE-054.**
- [x] 6.3.3 Linha + menu de contexto — ações por papel/readonly; "Remover" coerente com
      **todos** os bloqueios, não só `risk_controls`. **Fecha FE-055.**
- [x] 6.3.4 Painel lateral de Empresa no `SideDrawer` — erros em pt-BR nomeando o campo;
      some o texto herdado "Essa construtora não pode ser alterada". **Fecha FE-056.**
- [x] 6.3.5 Exclusão a partir da lista reflete o resultado **real** (o 422 aparece).
      **Fecha FE-057.**
- [x] 6.3.6 `CompanyDetailPage` — abas e cartões, data formatada corretamente.
      **Fecha FE-058.**
- [x] 6.3.7 A aba "Controles de Risco" **não é portada** (DC-06: parcial vazio, não listada,
      sem action); a informação aparece no cartão-resumo do FE-058. **Fecha FE-059.**
- [x] 6.3.8 `ProvidersPage` — colunas Título/Projeto/# Renegociações/avatar; permissão do
      botão "Cadastrar" alinhada à matriz. **Fecha FE-069.**
- [x] 6.3.9 Linha de fornecedor — iniciais quando não há logo; **sem ação inerte** (DC-07:
      "relações de fornecedor" é código morto); clicar abre o detalhe. **Fecha FE-070.**
- [x] 6.3.10 Alternância CPF/CNPJ — os campos do bloco não escolhido **não são enviados** (no
      legado "desabilitar" era só CSS). **Fecha FE-071.**
- [x] 6.3.11 Máscara e validação de documento — avisa documento **incompleto**, não só
      inválido. **Fecha FE-072.**
- [x] 6.3.12 Autopreenchimento por CNPJ — o recurso volta a existir. **Fecha FE-073.**
      ⚠️ **Depende de Q-03.**
- [x] 6.3.13 Upload de logo do fornecedor com `ImageCropper` + ActiveStorage; limite
      verificado **antes** de enviar. **Não portar paperclip.** **Fecha FE-074.**

### 6.4 Conexões e garantias

- [x] 6.4.1 Tela de conexões projeto↔portador — título coerente com o sentido; "voltar"
      retorna à **origem**. **Fecha FE-100.**
- [x] 6.4.2 Item de conexão — estado **confirmado pelo servidor**; a falha **reverte** o item
      (o legado era otimista e divergia em erro parcial). **Fecha FE-101.**
- [x] 6.4.3 Tela "Indicadores específicos" — o botão de cadastrar some para readonly.
      **Fecha FE-102.** Verificado renderizando em `/indicator-connections`: com
      `user_is_readonly` o botão "Novo indicador do projeto" **não existe** e o aviso de modo
      somente leitura aparece; sem ele, o botão abre o `SideDrawer` e **salvar cria a linha**.
- [x] 6.4.4 Item global × específico — global: conectar/desconectar; específico: editar/
      ativar/excluir; inativo visualmente distinto. **Fecha FE-103.** Verificado
      renderizando: 6 interruptores nos globais, `Editar`/`Ativar`/`Excluir` nos específicos,
      selo "Inativo". **Correção nesta fatia:** em readonly o interruptor dependia de
      `e.preventDefault()` sobre o Radix Switch — que **não desfaz** o `aria-checked` já
      escrito no DOM. Agora o `Switch` é `disabled` e o aviso vem do `span` que o envolve:
      medido em readonly, o estado **não muda** (`true → true`) e o aviso aparece.
- [x] 6.4.5 Ações do indicador específico **continuam utilizáveis** após a primeira execução
      (o `preventDoubleSubmit` do legado era ativado e nunca restaurado). **Fecha FE-104.**
      Verificado renderizando com **dois cliques em sequência**: `Desativar X` → `Ativar X` →
      `Desativar X`, e o interruptor global `false → true → false`. Zero erro de console.
- [x] 6.4.6 Tela "Garantias do Projeto" com `DataTable` + `Pagination` (S0) — **uma** consulta
      por interação (o legado executava o proxy duas vezes por clique de ordenação).
      **Fecha FE-113.**
- [x] 6.4.7 Item de garantia — valor em reais; ações por permissão. **Fecha FE-114.**
- [x] 6.4.8 Formulário de garantia no `SideDrawer` com `MoneyInput` (S0) — **um único
      critério** de "o projeto tem portador" (o legado usava
      `active_risk_controls_carriers` no botão e `project.carriers` no formulário).
      **Fecha FE-115.**

## 7. Testes

### 7.1 Escopo cruzado — o teste que define esta fatia

> Um caso por endpoint que aceita id por parâmetro. Cenário: dois projetos, usuário membro
> **só** do A, id pertencente ao B. Resultado esperado: **busca devolve vazio**;
> **detalhe e escrita devolvem 404** (nunca 403 — não se confirma existência alheia).

- [x] 7.1.1 `projects#search` com `project_id` e com `importing_id` de projeto de que o
      usuário **não** é membro → vazio. **Cobre BE-082.** Fecha **D-29**.
- [x] 7.1.2 `companies#search` com `company_id` de outro projeto → vazio; `companies#show`
      → 404; `PUT`/`DELETE` → 404. **Cobre BE-050, BE-055, BE-056, BE-057.**
- [x] 7.1.3 `providers#search`/`#show`/`update`/`destroy` com `provider_id` de outro projeto
      → vazio / 404. **Cobre BE-059, BE-060, BE-062, BE-063, BE-065.**
- [x] 7.1.4 `project_guarantees#search` com `project_guarantee_id` de outro projeto →
      **vazio**. É o defeito literal do legado
      (`project_guarantees_controller.rb:22` reatribui a relação). **Cobre BE-118.**
      Fecha **D-29**.
- [x] 7.1.5 `project_guarantees` create/update com `carrier_id` **não conectado** ao projeto
      corrente → 422. **Cobre BE-119.**
- [x] 7.1.6 Conexões: conectar `carrier_id` válido a partir de um projeto de que o usuário
      não é membro → 404; lote com um item de outro projeto → o item é recusado e os demais
      não são afetados. **Cobre BE-102, BE-103, BE-104, BE-105.**
- [x] 7.1.7 Indicadores: candidatos **não** trazem indicador específico de outro projeto;
      excluir indicador de outro projeto → 404. **Cobre BE-107, BE-109.**
      `spec/requests/api/v1/indicator_connections_spec.rb` (13 exemplos).
- [x] 7.1.8 `memberships`: adicionar-se a um projeto de que não se é membro → 404/403 e
      **nenhuma** membership criada. **Cobre BE-099.** Fecha **D-28 + D-34**.
- [x] 7.1.9 `GET /users/:id/projects` de outro usuário devolve só o que o solicitante pode
      ver. **Cobre BE-100.**
- [x] 7.1.10 `create` e `update` de `Company`, `Provider` e `ProjectGuarantee` com
      `project_id` de outro projeto **no corpo** → o registro é criado/atualizado **no
      projeto corrente**, nunca no do payload. **Cobre BE-054, BE-055, BE-061, BE-062.**
- [x] 7.1.11 `:id` no corpo de qualquer `create` desta fatia é ignorado (mass assignment de
      PK). **Cobre a regra 5 desta fila.**

### 7.2 O projeto corrente (D-28)

- [x] 7.2.1 Spec: `current_project!` **revalida membership a cada request** — revogar a
      membership e repetir a requisição devolve erro, sem novo login. **Cobre BE-098.**
- [x] 7.2.2 Spec: projeto **inexistente** e projeto **sem membership** respondem o **mesmo
      status**. **Cobre BE-098.**
- [x] 7.2.3 Spec: `X-Project-Id` é aceito **só** com membership; sem membership, o projeto
      corrente **não muda**. **Cobre BE-098, DC-03.**
- [x] 7.2.4 Spec: remover a membership do projeto corrente reavalia
      `users.current_project_id`. **Cobre DB-087.**

### 7.3 Autorização e hierarquia (contrato C3 — verificar os DOIS lados)

- [x] 7.3.1 Spec: Admin **cria/remove membership** e Colaborador **não** (403). Os dois
      sentidos — um teste que só verifique que "a trava existe" passa com o sinal da
      hierarquia invertido, e o sinal invertido **dá poder de OG a um Colaborador**.
      **Cobre BE-099, DEC-18.5.**
- [x] 7.3.2 Spec: `user_is_readonly` recebe **403** em todo verbo de escrita da fatia, mesmo
      sendo Admin. **Cobre BE-054..056, BE-061..063, BE-089, BE-091, BE-099, BE-119.**
- [x] 7.3.3 Spec: o dono do projeto **não** é removível e o usuário **não** se remove.
      **Cobre BE-099, DEC-15.2.**
- [x] 7.3.4 Spec: `membership.role` **não** é consultado por nenhuma decisão de autorização.
      **Cobre DEC-18.6.**

### 7.4 Os defeitos que não se replicam

- [x] 7.4.1 Spec: criar projeto com responsável novo — a resposta, o log e o e-mail **não
      contêm** senha nem username em texto plano; a pessoa recebe **link** para definir a
      credencial. Fecha **D-38**. **Cobre BE-085.**
- [x] 7.4.2 Spec: indicar responsável existente mantém a membership do **criador** (DC-14).
      **Cobre BE-087.**
- [x] 7.4.3 Spec: renomear projeto **não** altera o slug (DC-17). **Cobre BE-095.**
- [x] 7.4.4 Spec: `destroy` de projeto/empresa/fornecedor/garantia com dependentes responde
      **422** e o registro **permanece**. Fecha **D-24**. **Cobre BE-091, BE-056, BE-063, BE-119.**
- [x] 7.4.5 Spec de paginação: `l`/`o` aplicados e total sem limite em projetos, empresas,
      fornecedores e garantias. Fecha **D-20/DC-38**. **Cobre BE-050, BE-059, BE-080, BE-118.**
- [x] 7.4.6 Spec: `reset` do projeto de treinamento resolve o segmento por **configuração** e
      não por id fixo; o projeto de treinamento **não** é removível. Fecha **D-26**.
      **Cobre BE-092.**
- [x] 7.4.7 Spec: `constantize` não é chamado sobre parâmetro em nenhuma conexão — tipo de
      entidade fora do conjunto fechado → 400. **Cobre BE-102, BE-106.**
- [x] 7.4.8 Spec: lote de conexões vazio → 400; lote com um item inválido devolve resultado
      **por item** e os demais são aplicados. **Cobre BE-103, BE-108.**
- [x] 7.4.9 Spec: ActionText da observação **recusa anexo no servidor**. **Cobre BE-097.**
- [x] 7.4.10 Spec: job falho é **reexecutado** pelo Sidekiq e, ao esgotar, fica visível na
      dead set; `LinkDefaultUserToProjectsJob` **registra** o erro e preserva os demais
      vínculos (o `rescue` do legado era vazio). Fecha **D-05**. **Cobre OPS-080, OPS-085.**
- [x] 7.4.11 Spec: `ProjectCreationJob` e `SeedGlobalTemplatesJob` têm progresso **separado**
      e não criam vínculo padrão duplicado. **Cobre BE-088.**
- [x] 7.4.12 Spec de anexo: arquivo com extensão de imagem e conteúdo de executável é
      **recusado** nos três logos. **Cobre DB-056, DB-089, OPS-088.**

### 7.5 Frontend

- [x] 7.5.1 Teste: nenhum payload de tela desta fatia contém padrão, indicador ou projeto de
      **outro** projeto (o legado embutia `AvailabilityTemplate.all` num atributo `data-`).
      **Cobre FE-103, FE-110 (S11), FE-148 (S11) pelo lado do contrato.**
- [x] 7.5.2 Teste: o critério de exibição de cada ação **é** o critério do servidor — botão
      visível ⇒ a ação passa; botão oculto ⇒ 403/422 se forçada por API.
      **Cobre FE-055, FE-082, FE-095, FE-102, FE-114.**
- [x] 7.5.3 Teste: os dois interruptores do detalhe do projeto têm **ids distintos** e cada
      rótulo altera o seu. **Cobre FE-093.**
- [x] 7.5.4 Teste: salvar o formulário do projeto dispara **uma** requisição (sem autosave
      por `keyup`). **Cobre FE-089.**
- [x] 7.5.5 Type-check limpo (`node node_modules/typescript/bin/tsc --noEmit`) e eslint limpo.
      Baseline pós-trim: **0 erro**.
      ⚠️ `vitest` não roda neste ambiente (falta `@rollup/rollup-win32-x64-msvc`) — limitação
      **anterior** a esta fatia. Escrever os testes mesmo assim; o portão é o type-check.

### 7.6 Contratos com outros blocos

- [x] 7.6.1 Spec: excluir empresa com `risk_control` → **422** e o limite **permanece**
      (política **simétrica**: bloquear, nunca cascatear). **Cobre DB-069.**
      Verificado executando no dev: **422** nomeando "4 limite(s) de risco" e
      `RiskControl.count` inalterado.
- [x] 7.6.2 Spec: excluir empresa com `receivable_entries` → 422. **Cobre DB-070.**
      Verificado executando: **422** nomeando "124 recebível(is)"; a empresa permanece.
- [x] 7.6.3 Spec: excluir fornecedor com renegociações → 422. **Cobre DB-071 e BE-063.**
      Verificado executando: **422** nomeando "1 renegociação(ões)"; `Renegotiation.count`
      inalterado.

## 8. Operação

- [x] 8.1 `lib/tasks/fix_company_links.rake` — **idempotente**, com pré-visualização e log
      persistente. O legado rodava `update_all` a mão no console, sem log. **Fecha OPS-055.**
- [x] 8.2 `lib/tasks/fix_project_data.rake` — idempotente, auditada por `AuditEvent`, com
      pré-visualização. O legado rodava `fix_after_global_remove` e `fix__7412` a mão.
      **Fecha OPS-089.**
- [x] 8.3 Registrar a fila desta fatia em `config/sidekiq.yml` (as filas, inclusive
      `_low_priority`, já existem). *(Não fecha ID — é o encaixe.)*

## 9. Paridade e fechamento

- [x] 9.1 Conferir os **123 IDs** contra `.migration-ai9/parity-ledger.md`: todos em
      `implemented`, `dropped` com evidência (BE-101 e as rotas mortas do DC-19) ou
      `blocked` com o bloco dono nomeado (BE-052, DB-069, DB-070, DB-071).
- [x] 9.2 Registrar em `.migration-ai9/improvements-log.md` as **9 mudanças visíveis** da
      seção "What Changes" do `proposal.md`.
- [x] 9.3 Conferir os requirements de `openspec/specs/projects/spec.md` (BE-080..101,
      BE-102..109, BE-118, BE-119, FE-080..106, FE-113..115, FE-118, FE-119, DB-080..092,
      OPS-080, OPS-085, OPS-088, OPS-089) — cada cenário tem um teste que o exerce.
- [x] 9.4 Conferir os requirements de `openspec/specs/companies-carriers/spec.md`
      (BE-050..066, FE-051..074, DB-050..056, DB-067..071, OPS-050, OPS-055) — idem.
- [x] 9.5 `rspec` do backend: **nenhuma falha nova** em relação ao baseline. Registrar a
      **lista** das falhas, não só a contagem.
- [x] 9.6 Portão de contrato **C1**: revisão dirigida de **todos** os endpoints da fatia —
      cada um declara `current_project!` em uma linha visível, ou é catálogo global
      declarado. `grep` por `default_scope` devolve vazio. **Um endpoint sem a linha é um
      vazamento de tenant esperando acontecer.**
- [x] 9.7 Anotar em `.migration-ai9/upstream-flags.md` os achados da base ai9 — **sem
      consertar** (Princípio 6b).


## Fechamento de órfãos do Phase 2 — esquema do projeto e aba de membros

Sete IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir que as migrations de `companies`, `providers`, `project_guarantees` e
      `project_to_carrier_connections` cobrem o que o inventário de `data-schema` descreve, e
      que não existe uma segunda família de tabelas para os mesmos recursos. **Fecha:
      DB-554, DB-555, DB-556, DB-557.**
- [x] F.2 Conferir que as colunas de domínio de `projects` (e os índices que o legado não
      tinha) estão na migration desta fatia, e que a tabela em si vem de S0 — **sem** segunda
      migration criando `projects`. **Fecha: DB-549.**
- [x] F.3 Aba "Membros" → adicionar membro com autocomplete de usuários, consumindo o
      serviço de participação de S0. Verificável: a tela **não** implementa nenhuma das três
      condições de servidor; ela as recebe. **Fecha: FE-040.**
- [x] F.4 Aba "Membros" → lista e remoção, com a mesma resposta para "projeto inexistente" e
      "projeto sem membership" (contrato **C1**: distinguir 403 de 404 vira oráculo de
      existência de id). **Fecha: FE-041.**


---

## Fechamento da S4 — 26/08/2026

**Portões, todos verdes:** `bundle exec rspec` **1258 exemplos / 0 falhas** (baseline de entrada:
1118/0) · `bin/rails zeitwerk:check` **All is good!** · `tsc --noEmit` **0 erros** ·
`vitest` **34 arquivos / 266 testes / 0 falhas** (a suíte do front voltou a rodar neste
ambiente; a limitação do `@rollup/rollup-win32-x64-msvc` registrada na tarefa 7.5.5 **não se
aplica mais**).

**Verificado renderizando**, em claro e escuro (DEC-98) e em 390×844 (DEC-100): empresas,
fornecedores, garantias, portadores do projeto, projetos, detalhe de projeto (com a aba Membros),
detalhe de empresa, detalhe de fornecedor, os três painéis laterais e a folha de ações do
telefone. Três coisas foram verificadas **executando**, não só olhando: o lote de conexão
(selecionar → conectar → estado confirmado pelo servidor), a criação de projeto pelo formulário
(slug e chave derivados, empresa padrão criada) e a exclusão bloqueada (422 com a frase nomeando
o vínculo, e o projeto permanece na lista).

### O que fica ABERTO, e por quê

Nenhuma tarefa ficou aberta por tempo (DEC-101). As de baixo dependem de tabela que outra fatia
ainda não entregou, ou de resposta do usuário.

| Tarefa | Motivo |
| ------ | ------ |
| 1.19, 5.1.9 (parcial) | **Q-02 sem resposta.** A marca de gestão foi criada **só em `projects`**; as 6 tabelas filhas não. `Company#has_safegold_management` é **derivada** do projeto, então não há coluna para divergir. Se a resposta for "carimbo histórico", a coluna volta com backfill — o caminho contrário (remover 6 colunas em uso) seria mais caro |
| 5.1.9 | **S5** — `CompanyService.risk_summary` depende de `risk_controls`. A **forma** da resposta já está decidida e escrita; enquanto a tabela não existe o endpoint devolve o resumo vazio (a mesma forma, com zeros), nunca 500 |
| 1.16, 5.3.5..5.3.8, 6.4.3..6.4.5, 7.1.7 | **S10** — dependem do catálogo `indicators`. A tabela-ponte `project_indicator_connections` **já foi criada** por esta fatia (DB-082), sem a FK: ela entra na migration da S10, junto com `indicators.scope` (DB-092) |
| 7.6.1, 7.6.2, 7.6.3 | **S5 / S6 / S9** — os testes de exclusão bloqueada por `risk_control`, `receivable_entry` e `renegotiation`. As três já estão declaradas em `Company.blocking_dependents` e `Provider.blocking_dependents` **por nome**, e passam a valer sozinhas no dia em que a tabela existir |

### O que a S5 precisa saber

1. **`Company` está de pé** (`companies`, id `uuid`, FK real para `projects`, único composto
   `(project_id, title)`). `RiskControl` pendura em `companies.company_id`.
2. **`ProjectToCarrierConnection` está de pé** e é a **única** ponte projeto↔portador. Os
   portadores que a S5 pode oferecer num limite são
   `Carrier.where(id: ProjectToCarrierConnection.for_project(projeto).select(:carrier_id))` —
   **um critério só**. Não invente `active_risk_controls_carriers`.
3. **O molde de serviço é `ProjectScopedService`** (irmão do `CatalogService` da S3). Herdar dele
   dá escopo, 404 para id alheio, `project_id` do corpo ignorado nos dois verbos e 422 real na
   exclusão. `RiskControlService < ProjectScopedService` deve ser quase só configuração.
4. **`Company.blocking_dependents` já declara `RiskControl`.** Quando a tabela nascer, excluir
   empresa com limite passa a responder 422 sozinho — **não acrescente `dependent:`**, e não crie
   um segundo mecanismo de bloqueio: ele é `app/models/concerns/blocking_dependents.rb`.
5. **A FK `risk_controls.company_id` é da migration da S5**, com política **`NO ACTION`**
   (bloquear, nunca cascatear — é o D-24, e no legado excluir portador APAGAVA os limites dele).
6. **O molde de tela é o `CatalogScreen`**, agora com `T extends ScreenRow` (`{id, title}`) —
   serve a recurso escopado. `writeRoles={ALL_ROLES}` para o grupo "Projeto".
7. **`ProjectGuarantee` está de pé** e usa `carrier_id` com a validação "conectado ao projeto".
   O mesmo par (empresa, portador) é o eixo do limite de risco.
