# Tasks: S11 — Disponibilidades (e o menu de Cobranças habilitado)

Fila de trabalho do Phase 3 para a fatia **S11**. Ordenada por camada:
**dados → backend → frontend → testes → paridade**.

**Regras desta fila** (valem para toda tarefa):

1. Uma tarefa = **um comportamento verificável**.
2. Cada tarefa cita os **IDs de inventário** que fecha. Ao marcar, virar o ID em
   `.migration-ai9/parity-ledger.md` para `implemented`.
3. **Família D-01 / D-16 / D-29 / D-76 / D-100** — o pior caso está aqui:
   > **Toda tarefa de endpoint que aceita id por parâmetro (`template_id`, `entry_id`,
   > `company_id`, `parent_id`, e o `:id` do projeto na rota de disponibilidade) leva um
   > teste explícito de que um id de OUTRO projeto é rejeitado.** Busca → **vazio**;
   > detalhe/escrita → **404**. Nunca 403.
   > O **D-01** é mais grave que os irmãos: não é "o filtro é descartado", é **não havia
   > filtro nem autenticação**. O endpoint também leva teste de requisição **sem sessão**.
4. **`project_id` do payload é sempre ignorado**; **`:id` fora do `permit`**.
5. **Escopo declarado no endpoint** por `current_project!`. **`default_scope` é proibido**.
   O catálogo **global** de padrões **não** é escopado — regra oposta, de propósito.
6. **Polling é proibido** (Princípio 10). Progresso por Action Cable invalidando query.
7. **Todo job libera o bloqueio em `ensure`**, com ou sem sucesso. Um job desta fatia sem
   `ensure` é o **D-05** de volta.
8. **Nada da base ai9 é refatorado** (Princípio 6b).
9. Uma tarefa só é marcada quando o código existe, compila e **o teste dela passa**.

**Pré-requisitos:** S0 (helpers, `ProjectScoped`, `DataTable`, `Pagination`, `MoneyInput`,
`EmptyState`/`ErrorState`, `AuditEvent`, `JobProgressChannel`/`useJobProgress`, retry do
Sidekiq) e S4 (`projects`, `companies`, `current_project!`, `useNavItems`).

**Perguntas que travam parte da fila:** **Q-07** (decaimento composto), **Q-08** (regra de
soma da consolidação), **Q-09** (feriados) e **Q-10** (definição de "total"). Elas travam
**apenas** a seção 5. As seções 1–4 podem correr antes.

---

## ⚠ O que mudou depois que esta fila foi escrita (26/08/2026)

Esta fila é do Phase 2 e foi escrita **antes** das DECs e **antes** da análise do dump de
produção. Onde divergirem, **a DEC vence a tarefa**. As sete divergências que importam:

| Onde | O que a fila dizia | O que vale |
| ---- | ------------------ | ---------- |
| **5.3 / 6.5.8** (Q-07) | "corrigir o decaimento composto; `original_value` preservado" | **DEC-24: REPLICAR.** `original_value` **é** regravado, e a correção incide sobre o valor já corrigido. O desenho de `design.md` §5.2 fica **revogado** |
| **5.4 / 5.5** (Q-08) | decidir se a consolidação respeita `is_cumulative`/`is_debit` | **DEC-26: replicar as DUAS somas**, e **rotular** cada uma na tela. O rótulo não é cosmético — ele **é** a decisão |
| **5.7 / 6.5.10** (Q-10) | "semântica única de total" | **DEC-27: as duas métricas ficam.** `value` = total bruto, `virtual_value` = saldo acumulado. O `values[:total]` do legado era **código morto** (nunca renderizado) e **não foi portado** |
| **5.6 / 6.5.9** | saldo acumulado "determinístico, desativados fora da conta" | **Anulado pelo DEC-30**, que nomeia o saldo entre as regras a replicar. `previous_level_templates` do legado **não** filtra por `is_active`, e isso foi mantido — travado por golden test |
| **1.14** (Q-01) | "`default_position` não é portada" | **DEC-79** mandou criá-la; **D-126** (dump) mostrou que ela não existe em produção e que a listagem do legado está **quebrada**. A coluna existe no ai9, mas a **ordem é a hierarquia** |
| **1.13** (Q-02) | pendente | **DC-01, como a S4 decidiu:** a marca de gestão é **derivada do projeto na leitura**, não copiada para o lançamento. Não há coluna |
| **F.3** | S11 confere `charges`/`receipts` | **DEC-63 (P-098): são da S6.** De S11 sai só o item de menu (9.5) |

### E uma qualificação do próprio DEC-30, que nasceu da análise do dump

O DEC-30 vale para o que **rodou em produção**. Em disponibilidades, isso é a maior parte —
três anos de uso, 23.674 lançamentos, 2.705 padrões, dado até 09/05/2025. **Mas três
migrations desta fatia nunca subiram:**

- `add_company_column_to_availability_entries`
- `add_original_value_column_to_availability_entries`
- `add_is_adjusted_column_to_availability_templates`

Ou seja: **multiempresa, consolidação geral e correção por dias úteis nunca executaram.**
As regras continuam implementadas (DEC-22 mantém o escopo, e as DECs do usuário estão de
pé), mas os golden tests que as cobrem estão marcados `NUNCA EXECUTADO EM PRODUÇÃO` em
`spec/models/availability_entry_spec.rb`: eles travam **a leitura do código de 2022**, não
um comportamento observado. Onde não há produção, o golden test tem uma fonte, não um
oráculo.

---

## 1. Dados — a remodelagem primeiro

> A hierarquia é a primeira tarefa e a mais consequente: toda regra de consolidação,
> obrigatoriedade e propagação lê essa estrutura. Nenhuma regra de cálculo é escrita antes
> de 1.1 e 1.2 fecharem.

- [x] 1.1 Migration `availability_templates` — **uma** estrutura hierárquica ordenável:
      `parent_template_id` (FK real, **sem** default `0`), `top_parent_id` (FK),
      `position` **inteira**, `project_id` nulo para o global. **As nove colunas
      redundantes e a `position` string saem.** `id: :uuid`, `comment:` por coluna,
      cabeçalho pt-BR. **Fecha DB-085 e DB-131.**
      Verificação: 12 irmãos ordenam `1,2,…,10,11,12` (o legado ordenava "10" antes de "2").
- [x] 1.2 FK e índices de `availability_templates` — em `project_id` e
      `parent_template_id`; booleanos de verdade. O legado tinha **zero** índice e **zero**
      FK. **Fecha DB-120.**
      Verificação: não existe linha com `top_parent_id = 0` (órfão do default do legado).
- [x] 1.3 Escopo global — `project_id` nulo **+ marca explícita**; `has_children?` consulta a
      **classe certa** (o legado declarava `class_name: "ProjectAvailabilityTemplate"`
      **dentro** do model global). **Fecha DB-121.**
- [x] 1.4 Padrão de projeto — projeto **obrigatório**, vínculo **opcional** ao global de
      origem, índices únicos cobrindo o **3º nível** e "um por global por projeto".
      **Fecha DB-122.**
- [x] 1.5 `availability_templates.is_adjusted` **boolean** — par obrigatório com
      `original_value`. **Fecha DB-124.**
- [x] 1.6 `should_insert_on_existing_projects` **exposta** como coluna controlável pelo
      usuário (hoje default 1, fora de qualquer tela). **Fecha DB-132.**
- [x] 1.7 Bloqueio do padrão com **motivo e instante**; padrões travados no legado **migram
      desbloqueados** e o ETL os reporta. **Fecha DB-128.**
- [x] 1.8 Estado das tarefas como `enum` string (`pending`/`running`/`done`/`failed`,
      Lacuna **L-10**) com falha **estruturada**. O legado usava texto livre em pt-BR
      ("Concluido" sem acento), array Ruby em coluna de texto e referência à tabela do
      executor, que é **purgada**. **Fecha DB-129.**
- [x] 1.9 Migration `availability_entries` — FK + índices `(project_id, date)`,
      `(template_id, date)` e **único `(project_id, company_id, template_id, date)`**;
      `value` `decimal(14,2)`. **A maior tabela do módulo não tinha nenhum índice.**
      **Fecha DB-123.**
- [x] 1.10 `availability_entries.original_value` — o **valor digitado** preservado ao lado do
      corrigido. **Fecha DB-125.**
- [x] 1.11 Marca **explícita** de consolidação — **não** inferida por `company_id` nulo.
      **Fecha DB-126.**
      Nota: o legado usava `after:` (sintaxe MySQL) numa base Postgres, e a rotina
      `fix__7412` reatribuiu empresa nula à primeira empresa — o ETL precisa distinguir
      consolidação legítima de dado sujo.
- [x] 1.12 `availability_entries.virtual_value` — derivado persistido **com rotina de
      reconciliação** que reporta divergências. **Fecha DB-127.**
- [x] 1.13 Marca de gestão no lançamento. ⚠️ **Depende de Q-02 (DC-01)** — mesma decisão de
      DB-051/DB-090, tomada na S4. **Fecha DB-130.**
- [x] ~~1.14 `default_position` **não é portada**~~ — **ANULADA pela DEC-79**, e depois
      **precisada pelo D-126** (análise do dump, 26/08/2026). Duas mudanças de rumo:
      1. **DEC-79** decidiu **criar** a coluna no ai9, independentemente do que exista em
         produção. Feito: `availability_templates.default_position`, e o conversor de ETL a
         carrega quando ela existir na origem.
      2. **D-126** respondeu o Q-01 com o dump na mão: a coluna **não existe** em produção
         (zero ocorrências) e nenhuma migration a cria, então `ORDER BY default_position`
         levanta `UndefinedColumn` — **a listagem de padrões está quebrada em produção há
         anos**. Não há o que replicar (exceção 3 do DEC-30): a ordem do ai9 é a
         **hierarquia** (`sort_key`), não `default_position`.
      **Fecha DB-134**, com a estratégia trocada de `não portar` para `build + ordem própria`.
- [x] 1.15 FK, `null: false` e índices únicos **nunca aplicados sobre dado sujo**.
      **Fecha DB-133.**
      **A ordem do enunciado foi INVERTIDA de propósito, e a inversão é mais forte.** O
      enunciado do Phase 2 previa a sequência do legado: criar a tabela, carregar, limpar
      e só então apertar. O ai9 faz o contrário — as restrições nascem com a tabela
      (`add_foreign_key` para `projects`, `companies`, `availability_templates` e `users`;
      `project_id`/`availability_template_id`/`date`/`value` com `null: false`; os dois
      índices únicos parciais `…_unique_by_company` e `…_unique_consolidation`) e é a
      **carga** que é barrada antes de escrever a primeira linha suja. O intento do
      enunciado ("nenhuma restrição é aplicada sobre dado sujo") é cumprido de forma
      **mais** garantida: no desenho original a janela entre carregar e apertar é um
      período em que o banco novo está inconsistente.
      **Conferido EXECUTANDO por QA em 26/08/2026** (banco próprio, fixture com duas
      linhas partilhando a quádrupla `project_id + company_id + availability_template_id
      + date`):
      - `sfg_etl:dry_run` — **aborta**, `rc=1`, com a seção literal *"Duplicatas em
        `availability_entries` … — o índice único fica BLOQUEADO até resolver"*;
      - `sfg_etl:load` com a mesma origem — **aborta também**, e o destino ficou com
        **0 linhas** em `availability_entries` e o de-para inalterado em 20. O bloqueio é
        `Sfg::Etl::Run#run_converter`, que levanta `Blocked` **depois do `Scan` e antes do
        `load_rows`** — ou seja, antes da primeira escrita **daquela** tabela, não no meio
        dela;
      - os índices únicos existem no destino, conferidos em `pg_indexes`:
        `index_availability_entries_unique_by_company` (parcial, `company_id IS NOT NULL`),
        `…_unique_consolidation` (parcial, `company_id IS NULL`) e
        `index_availability_entries_on_legacy_id` — mais a PK.
      **O que continua sendo do dia do cutover, e não desta tarefa:** rodar isso contra o
      dado de produção e **decidir** as duplicatas que aparecerem (o dump já mediu: 2 em
      `availability_templates`, ambas com `title` vazio). Autorizar é uma linha assinada em
      `db/etl/decisions.yml`; a carga em si está adiada pela **DEC-102**, e a janela é do
      passo 5/7 do `docs/runbook-cutover.md`, não desta fila.
- [x] 1.16 Etapa de introspecção do esquema de origem — **aborta com relatório** diante de
      estrutura desconhecida (DEC-04). **Fecha DB-135.**
      O mecanismo é `Sfg::Etl::Introspection` (motor da S14) e S11 é consumidora. O que S11
      entregou continua valendo: os dois conversores (`…::AvailabilityTemplates` e
      `…::AvailabilityEntries`) **toleram** a ausência das três colunas que o dump provou
      não existirem em produção (`company_id`, `original_value`, `is_adjusted`) e reportam
      anomalia por linha.
      **O que faltava era provar o ABORTO, e foi provado EXECUTANDO** (QA, 26/08/2026,
      banco próprio), nos dois formatos de surpresa que existem:
      - **tabela desconhecida** — fixture com `tabela_que_ninguem_declarou`:
        `sfg_etl:introspect` sai com `rc=1`, seção `X Surpresas na origem — 1`, e o
        relatório nomeia a tabela e a contagem de linhas, com as duas saídas escritas
        ("mapear (vira conversor) ou descartar (vira linha em `removed-features.md`, com
        evidência)");
      - **coluna desconhecida numa tabela conhecida** — `segments.coluna_que_ninguem_declarou`:
        mesmo `rc=1`, mesma seção.
      O aborto é **antes de qualquer escrita** — `introspect` não escreve nada por
      construção — e o relatório vai para arquivo (`tmp/etl/introspect-*.md`), que é o que
      se anexa ao Portão 1 do runbook.
      Contraprova de que o portão não é um "aborta sempre": a mesma tarefa contra a fixture
      versionada, sem surpresa plantada, sai **verde** — e as duas divergências conhecidas
      (`availability_templates.default_position`, D-06/D-126, e `contracts.description`,
      D-108) ficam na seção "Divergências CONHECIDAS (não abortam)".
- [x] 1.17 Declarar, para o ETL, os **cinco relatórios obrigatórios** desta fatia:
      corrigidos mais de uma vez · consolidações legítimas × resíduo do `fix__7412` ·
      padrões travados · duplicatas do único composto · órfãos de `top_parent_id = 0`.
      *(Não fecha ID — é o contrato com S14; ver `design.md` §8.)*

## 2. Backend — catálogo global de padrões

- [x] 2.1 `api/v1/availability_templates.rb#search` — busca por **substring** (não só
      prefixo) e **sem `default_position`**; catálogo vazio **não gera SQL inválido**;
      paginação e ordenação reais. **Fecha BE-132.** Fecha **D-06/D-07/D-20** — hoje
      qualquer texto digitado derruba a requisição.
- [x] 2.2 Detalhe e formulários — funcionam **também** para padrão de projeto (o legado
      chamava `.projects`, associação **inexistente** → `NoMethodError`). **Fecha BE-133.**
- [x] 2.3 `create` global — **a obrigatoriedade escolhida no formulário é respeitada**
      (`is_mandatory |= 1` sai) e a **propagação para projetos existentes é opção do
      usuário**. **Fecha BE-134.**
      Fecha o `should_insert_on_existing_projects` com default 1 **nunca exposto**, que fazia
      **toda criação** disparar job em **todos** os projetos.
- [x] 2.4 `update` global — posição recalculada também no update; **colisão de número
      impedida**; alterar `is_adjusted`/`is_cumulative` **propaga** aos derivados em segundo
      plano (DC-31). **Fecha BE-135.**
- [x] 2.5 `destroy` global — desvínculo em cascata **completo e transacional**, falha
      comunicada. Elimina a necessidade da rotina manual `fix_after_global_remove`.
      **Fecha BE-136.** Fecha **D-24**.
- [x] 2.6 Numeração e posicionamento — nível **derivado do pai de forma determinística**
      (`parent.level + 1`); pai inexistente → 422; **criação concorrente não colide**.
      **Fecha BE-137.** Fecha o ` |= ` (OR bit a bit: 2 herdando de 5 virava 7) e o
      `NoMethodError` em `ensure_top_parent`.
- [x] 2.7 Reordenação — movimento inválido **recusado no servidor**, custo **linear** (o
      legado rodava os 3 `import` dentro do laço de 1º nível). Serviço + endpoint autorizado,
      **sem tela nova** (DC-21). **Fecha BE-138.**
- [x] 2.8 Obrigatoriedade hierárquica — a cadeia superior precisa ser obrigatória.
      **Fecha BE-139.**

## 3. Backend — padrões do projeto e os quatro jobs

- [x] 3.1 Serviço **único** de bloqueio (`lock!`/`unlock!` com motivo, autor e instante),
      usado pelos quatro jobs, valendo **no servidor** e não só na UI; bloqueio **termina
      junto com a operação**, com ou sem sucesso. **Fecha BE-147.**
      Fecha **D-05** — `background_removal` nunca desbloqueava: padrão **bloqueado para
      sempre**, sem caminho de recuperação.
      Verificação: teste que **força a falha** do job e confere que o padrão fica utilizável.
- [x] 3.2 `api/v1/project_availabilities.rb#tree` — sem projeto corrente → **erro de
      pré-condição** (não `NoMethodError`); árvore ordenada por índice; **sem `1+N` por
      nível** e sem ordenação por `JOIN (VALUES …)`. **Fecha BE-110.**
- [x] 3.3 `#tree` (rota própria) — projeto zerado devolve **lista vazia** (não SQL inválido);
      `q`/`l`/`o` funcionam; inativos identificados. **Fecha BE-140.**
- [x] 3.4 `#form` — "Faz parte de" só oferece **pais válidos** para o nível pretendido.
      **Fecha BE-111.**
- [x] 3.5 Formulários da rota própria — sem projeto corrente → pré-condição explícita; campos
      imutáveis identificados **com a razão** (DC-24). **Fecha BE-141.**
- [x] 3.6 Criar/editar padrão do projeto — hierarquia limitada a **3 níveis**, título único no
      nível, nível derivado do pai. **Fecha BE-112.**
- [x] 3.7 `create` — projeto **do servidor**, `:id` fora do `permit`, erros em pt-BR,
      unicidade **inclui o 3º nível**. **Fecha BE-142.** Fecha **D-23/D-29** (criar padrão em
      projeto alheio por campo escondido) e o mass assignment de PK.
- [x] 3.8 `update` — padrão bloqueado → **409**; renomear **não renumera** (DC-32: o
      `before_validation` de posicionamento é `on: [:create]` no global mas rodava também no
      update do padrão de projeto). **Fecha BE-143.**
- [x] 3.9 `ActivateProjectTemplateJob` — bloqueio liberado em **`ensure`**, inclusive na
      falha; enfileiramento recusado → **409**. **Fecha BE-113 e OPS-082.**
- [x] 3.10 Ativar padrão do projeto — **idempotente** (segunda ativação → 409); falha ao
      enfileirar é **erro**, não sucesso; **ativar padrão com pai inativo é recusado (422)**,
      com orientação (DC-33). **Fecha BE-144.**
- [x] 3.11 Ativação sem desligar o logger global — a restauração fica **fora** do bloco
      protegido. No legado uma falha deixava o **logger desligado para o worker inteiro**.
      **Fecha OPS-122.**
- [x] 3.12 `DeactivateProjectTemplateJob` — **a regra roda no serviço, antes de enfileirar**:
      padrão obrigatório e padrão com dependentes obrigatórios **não desativam**.
      **Fecha BE-114, BE-145 e OPS-083.** Fecha **D-04/D-33** — a guarda existia e **nunca
      era executada** no fluxo real (e ainda filtrava por `project_id: self.id`).
- [x] 3.13 Desativação — pai **sem lançamento na data** conclui normalmente (o legado fazia
      `recalculate_entry.id` sem checar nulo); recálculo dos somatórios. **Fecha OPS-123.**
- [x] 3.14 `RemoveProjectTemplateJob` — lançamentos vinculados tratados **explicitamente**: o
      servidor **recusa 422** a remoção de padrão com lançamentos (DC-20); remoção
      **atômica**; global **não removível** pela rota do projeto.
      **Fecha BE-115, BE-146 e OPS-084.**
      Fecha a divergência entre `is_deletable?` (dica de UI) e `background_removal`, que
      apagava `entries.destroy_all` contornando `restrict_with_error`.
- [x] 3.15 Remoção — **nada permanece** em falha; reexecução depois de concluída termina
      **sem erro**; nenhum estado é gravado sobre registro já destruído. **Fecha OPS-124.**
- [x] 3.16 Reordenação e recálculo em cascata — posições consistentes após criar, ativar,
      desativar, remover e mover; custo **não quadrático**. **Fecha BE-116.**
- [x] 3.17 `SeedGlobalTemplatesJob` — **atômico e idempotente**, hierarquia preservada,
      **`is_adjusted` copiado** (o legado não copiava: todo padrão de projeto nascia não
      ajustado, mesmo derivando de global ajustado); projeto não fica silenciosamente
      incompleto. **Fecha OPS-081 e OPS-120.**
- [x] 3.18 `PropagateGlobalTemplateJob` — progresso **por projeto** (não se atropelam);
      atributos copiados **fielmente** (o legado **forçava obrigatoriedade a 1** aqui,
      divergindo do seed). **Fecha OPS-121.**

## 4. Backend — lançamentos e painel

- [x] 4.1 `api/v1/availability_entries.rb#search` — `q`/`l`/`o` passam a **existir de fato**;
      empresa inválida → **422** (não cai em "consolidação geral" calado); grade montada em
      consultas **agregadas**, sem uma consulta por padrão. **Fecha BE-120.**
      Fecha **D-07/D-20** e o N+1.
- [x] 4.2 A rota `index` vestigial **não é portada** (DC-19/DEC-09, com evidência).
      **Fecha BE-121 (`build + dropped`).**
- [x] 4.3 `AvailabilityEntryService.create` — duplicidade → 422; **sem resíduo em falha**;
      nada de `destroy` sobre registro não persistido. **Fecha BE-122.**
- [x] 4.4 `.update` — **uma única gravação** (o legado fazia `update` **e** `save`);
      consolidação geral **não é editável nem por envio direto**; padrão bloqueado → **409**.
      **Fecha BE-123.**
- [x] 4.5 `.destroy` — a exclusão **não cria registro** (no legado `parent_entry` era chamado
      **antes** do destroy e **criava** o pai); reconsolidação sem efeito colateral (DC-26).
      **Fecha BE-124.**
- [x] 4.6 `app/models/availability_entry.rb` — unicidade
      `(project, company, template, date)` **garantida por índice**; título derivado do
      padrão. **Fecha BE-131.**
- [x] 4.7 `api/v1/projects/:id/availability` — **autenticado e escopado** por
      `current_project!`; empresa inexistente → 422; mês inválido → 422; JSON **sem dupla
      serialização**. **Fecha BE-117 e BE-149.**
      Fecha **D-01** — o IDOR sem autenticação que dá nome à família. **Não se replica um IDOR.**

## 5. Backend — o motor de números

> ⚠️ **Esta seção fica atrás de Q-07, Q-08, Q-09 e Q-10.** As tarefas 5.1 e 5.2 estão
> decididas e podem ir na frente; 5.3 a 5.7 esperam. Cada uma **muda número exibido**.

- [x] 5.1 **Ler a grade nunca cria registro** — derivados materializados por gravação
      explícita e **identificáveis como derivados**; não herdam o autor de quem abriu a tela
      (DC-30). **Fecha BE-130.** *(Decidido, sem pergunta.)*
- [x] 5.2 `is_credit?`/`is_debit?` comparam o **código** `C`/`D`, não a string traduzida;
      `operation_type` vira `enum` de conjunto fechado (DC-28). **Fecha BE-126 (parte).**
      *(Decidido.)* No legado qualquer `operation_type` fora de `C`/`D`/`S`/`M` era tratado
      como **crédito**.
- [x] 5.3 ⏳ Correção por dias úteis — aplicada **uma única vez**, função de `original_value`
      e nunca do valor já corrigido; valor digitado preservado; cálculo **no servidor**.
      **Fecha BE-127.** ⚠️ **Depende de Q-07 (D-02, DC-25) e Q-09 (D-03, DC-29).**
      Default declarado: corrigir o decaimento; manter seg–sex **sem feriados**.
- [x] 5.4 ⏳ Consolidação geral (mirror) — projeto sem empresas devolve **zero**, sem erro.
      **Fecha BE-125.** ⚠️ **Depende de Q-08 (D-08, DC-27):** respeitar ou não
      `is_cumulative`/`is_debit`.
- [x] 5.5 ⏳ Valor de padrão **com filhos** — sinal de débito em nó intermediário; filho
      bloqueado tratado de forma consistente com a tela. **Fecha BE-126 (resto).**
      ⚠️ **Depende de Q-08 (DC-27).**
- [x] 5.6 ⏳ Saldo acumulado no 1º nível — **determinístico**: não depende de quais células
      já foram preenchidas; desativados **fora** da conta. **Fecha BE-128.**
      ⚠️ Depende de 5.4/5.5.
- [x] 5.7 ⏳ Consolidação por padrão base — **semântica única de "total"** (o legado usa
      `value` no total geral e `virtual_value` nos cards: mesma palavra, duas métricas).
      **Fecha BE-148.** ⚠️ **Depende de Q-10 (DC-34), subordinado a Q-08.**
- [x] 5.8 Propagação em cascata **atômica**, em `AR transaction`, com **guarda de ciclo**.
      **Fecha BE-129.** O legado fazia saves recursivos + upsert em massa **sem transação** e
      com `validate: false`. *(Independente das perguntas.)*

## 6. Testes de backend

### 6.1 D-01 — o IDOR que dá nome à família

- [x] 6.1.1 Request spec: `GET /api/v1/projects/:id/availability` **sem credencial** → **401**.
      No legado o controller herdava de `ApplicationController` e respondia a qualquer um.
      **Cobre BE-117, BE-149.**
- [x] 6.1.2 Request spec: com credencial válida, o `:id` de um projeto de que o usuário
      **não** é membro → **404**; nenhum valor financeiro do outro projeto é devolvido.
      **Cobre BE-117, BE-149.**

### 6.2 Escopo cruzado — um caso por endpoint com id por parâmetro

- [x] 6.2.1 `availability_entries#search` com `company_id` de outro projeto → **422**, e com
      `entry_id` de outro projeto → **vazio**. **Cobre BE-120.**
- [x] 6.2.2 `availability_entries` update/destroy com `entry_id` de outro projeto → **404** e
      o lançamento **permanece**. **Cobre BE-123, BE-124.**
- [x] 6.2.3 `project_availabilities#tree`/`#form` com `template_id` de outro projeto →
      vazio / 404. **Cobre BE-110, BE-140, BE-141.**
- [x] 6.2.4 Criar padrão do projeto com `parent_id` de **outro projeto** → operação
      **recusada**. **Cobre BE-142 e FE-148 pelo lado do servidor.**
- [x] 6.2.5 Ativar / desativar / remover padrão de **outro projeto** → 404, e **nenhum job é
      enfileirado**. **Cobre BE-144, BE-145, BE-146.**
- [x] 6.2.6 `create`/`update` de lançamento com `project_id` no corpo apontando outro projeto
      → gravado no **projeto corrente**. **Cobre BE-122, BE-123.**
- [x] 6.2.7 O **catálogo global** de padrões é legível sem projeto corrente e **não** é
      escopado — regra oposta à das entidades de projeto, e de propósito.
      **Cobre BE-132, `§0.6` regra 4.**

### 6.3 Os quatro jobs (D-05, D-04/D-33)

- [x] 6.3.1 Spec que **força a exceção** dentro de cada um dos quatro jobs e confere que o
      padrão fica **desbloqueado** e utilizável. **Cobre BE-147, OPS-082, OPS-083, OPS-084.**
      É o teste que fecha o "padrão bloqueado para sempre".
- [x] 6.3.2 Spec: job falho é **reexecutado** pelo Sidekiq e, ao esgotar, fica visível na
      dead set. **Cobre OPS-128 (S0) aplicado aqui.**
      **FEITO em `spec/jobs/availability_template_sidekiq_retry_spec.rb` — 6 exemplos, 0
      falhas, sem um único estube.**
      O argumento que mantinha a tarefa aberta ("um spec aqui estubaria o Sidekiq e provaria
      o estube") estava certo sobre estubes e errado sobre a única saída. O Sidekiq expõe a
      própria máquina de retentativa como classe pública — `Sidekiq::JobRetry` é exatamente
      o que o worker chama. O spec chama **a mesma classe**, com **o mesmo payload** que o
      worker montaria (`Sidekiq::ActiveJob::Wrapper` embrulhando o job, com `wrapped`
      preenchido), contra um **Redis de verdade**, e lê o resultado pela API pública
      (`Sidekiq::RetrySet` / `Sidekiq::DeadSet`) — a mesma que o painel lê.
      O que ficou provado, executando:
      - a **primeira falha vira retentativa**: entra no retry set com `retry_count = 0`,
        `error_class`/`error_message` preservados, `wrapped = ActivateProjectTemplateJob`
        (é `wrapped` que faz o painel nomear o job de negócio em vez de mostrar quatro
        embrulhos idênticos) e `score` **no futuro** — reagendado, não perdido;
      - a falha seguinte **incrementa** o contador em vez de abrir um segundo registro;
      - esgotadas as 25 tentativas, sai do retry e **entra no dead set**, nomeando job e
        causa, e o registro **é reenfileirável** (`respond_to?(:retry)`, fila correta) —
        visível sem ação possível seria metade da correção;
      - a retenção declarada em `config/sidekiq.yml` (OPS-624) está carregada:
        `dead_max_jobs = 10.000`, `dead_timeout_in_seconds = 15.552.000` (6 meses).
      ⚠ **Isolamento obrigatório, e ele está escrito no cabeçalho do spec:** os conjuntos
      `retry` e `dead` são **globais por banco Redis** e **não** levam o prefixo `APP_NAME`
      das filas. Rodar isto no banco 0 escreveria no dead set compartilhado com o **apl9**
      (`platform-runbook.md` §4.2). O spec troca para o banco **15** e apaga **só as duas
      chaves que cria** — nunca `FLUSHDB`. Conferido depois da execução: banco 15 vazio,
      `dead` do banco 0 em zero e os dois crons do apl9 intactos.
      O que **não** é exercitado, e fica dito no arquivo: o agendador que tira o job do
      `retry` na hora marcada, que vive dentro do processo `sidekiq`. Prova-se que ele
      **entra** com hora marcada, não que o relógio dispara.
- [x] 6.3.3 Spec: desativar padrão **obrigatório** é recusado **no serviço**, antes de
      enfileirar — nenhum job entra na fila. **Cobre BE-114, BE-145.** Fecha **D-04/D-33**.
- [x] 6.3.4 Spec: desativar padrão com **dependente obrigatório** é recusado. **Cobre BE-145.**
- [x] 6.3.5 Spec: segunda ativação do mesmo padrão → **409**, não um segundo job.
      **Cobre BE-144.**
- [x] 6.3.6 Spec: ativar padrão com **pai inativo** → 422 com orientação (DC-33).
      **Cobre BE-144.**
- [x] 6.3.7 Spec: remover padrão **com lançamentos** → **422** e os lançamentos
      **permanecem**. **Cobre BE-115, BE-146, DC-20.** É o dado financeiro que o legado
      apagava.
- [x] 6.3.8 Spec: falha no meio da remoção deixa **nada** persistido (transação); reexecutar
      depois de concluída termina sem erro. **Cobre OPS-124.**
- [x] 6.3.9 Spec: `SeedGlobalTemplatesJob` é **idempotente** e **copia `is_adjusted`**.
      **Cobre OPS-081, OPS-120.**
- [x] 6.3.10 Spec: `PropagateGlobalTemplateJob` **não força** obrigatoriedade a 1 — copia o
      valor do global; progresso é **por projeto**. **Cobre OPS-121.**
- [x] 6.3.11 Spec: uma falha na ativação **não** deixa o logger global desligado para o
      worker. **Cobre OPS-122.**

### 6.4 Hierarquia, catálogo e busca

- [x] 6.4.1 Spec: 12 irmãos ordenam `1,2,…,10,11,12`. **Cobre DB-131, BE-137.**
- [x] 6.4.2 Spec: nível é `parent.level + 1` — um filho de nível 2 com pai de nível 5 é
      **recusado** (limite de 3 níveis), nunca vira 7 por OR bit a bit. **Cobre BE-137, BE-112.**
- [x] 6.4.3 Spec: criação concorrente de irmãos **não colide** em posição. **Cobre BE-137.**
- [x] 6.4.4 Spec: busca de padrões globais com texto **funciona** e **não** referencia
      `default_position`; catálogo vazio devolve lista vazia, sem SQL inválido.
      **Cobre BE-132, DB-134.** Fecha **D-06**.
- [x] 6.4.5 Spec: criar global com `is_mandatory = false` **grava false**, e a propagação só
      acontece quando o usuário a pede. **Cobre BE-134, DB-132.**
- [x] 6.4.6 Spec: alterar `is_adjusted` de um global **propaga** aos derivados (DC-31).
      **Cobre BE-135.**
- [x] 6.4.7 Spec: cadeia de obrigatoriedade — filho obrigatório exige pai obrigatório.
      **Cobre BE-139.**
- [x] 6.4.8 Spec: excluir global desvincula em cascata **numa transação**; falha comunicada e
      nada parcialmente aplicado. **Cobre BE-136.**
- [x] 6.4.9 Spec: reordenação inválida recusada no servidor; custo **linear** (contagem de
      queries não cresce com o quadrado dos nós). **Cobre BE-138, BE-116.**

### 6.5 Lançamentos e números

- [x] 6.5.1 Spec: **abrir a grade não cria nenhum registro** — contagem de
      `availability_entries` antes e depois da leitura é igual. **Cobre BE-130, DC-30.**
- [x] 6.5.2 Spec: excluir lançamento de 1º nível **não cria** o pai. **Cobre BE-124, DC-26.**
- [x] 6.5.3 Spec: `update` faz **uma** gravação, não duas. **Cobre BE-123.**
- [x] 6.5.4 Spec: consolidação geral **não é editável**, nem por envio direto ao endpoint.
      **Cobre BE-123.**
- [x] 6.5.5 Spec: lançar em padrão **bloqueado** → **409**. **Cobre BE-123, BE-147.**
- [x] 6.5.6 Spec: unicidade `(project, company, template, date)` é garantida pelo **índice** —
      duas gravações concorrentes não criam duplicata. **Cobre BE-131, DB-123.**
- [x] 6.5.7 Spec: `operation_type` fora do conjunto fechado é **recusado**, não tratado como
      crédito. **Cobre BE-126, DC-28.**
- [x] 6.5.8 ⏳ **Golden test da correção por dias úteis**: salvar o mesmo valor **duas vezes**
      produz **o mesmo** resultado; `original_value` não muda. **Cobre BE-127.**
      ⚠️ **Depende de Q-07.** É o teste que prova que o decaimento composto acabou.
- [x] 6.5.9 ⏳ Golden test do saldo acumulado: o resultado **não depende da ordem** de
      preenchimento das células. **Cobre BE-128.** ⚠️ Depende de Q-08.
- [x] 6.5.10 ⏳ Golden test de "total": a mesma definição vale no total geral e nos cards.
      **Cobre BE-148.** ⚠️ **Depende de Q-10.**
- [x] 6.5.11 Spec: propagação em cascata é **atômica** e a guarda de ciclo impede recursão
      infinita. **Cobre BE-129.**

## 7. Frontend

### 7.1 Painel de disponibilidade

- [x] 7.1.1 `AvailabilityPage` — duas colunas; URL coerente com a seção; **a falha dos
      indicadores aparece** (o callback de erro do legado era vazio). **Fecha FE-120.**
- [x] 7.1.2 Seletor de visão por empresa — a troca recarrega indicadores **e** grade.
      **Fecha FE-121.**
- [x] 7.1.3 `components/ui/Calendar.tsx` sobre `react-day-picker`, pt-BR, com **dias que têm
      lançamento marcados** e faixa consistente (Lacuna **L-06**). **Fecha FE-122.**
- [x] 7.1.4 Seleção de data em tela estreita por `components/mobile/`, com **uma** fonte de
      verdade para "é estreito" (`hooks/useMobile.ts`, no cliente). **Fecha FE-123.**
      No legado o servidor decidia por *user agent* e o cliente por detecção própria — podiam
      discordar.
- [x] 7.1.5 Indicador de quantidade com `KpiCard` — conta lançamentos com valor ≠ 0.
      **Fecha FE-124.**
- [x] 7.1.6 Indicadores por padrão base — **sinal negativo visível no próprio valor**, além
      da cor. **Fecha FE-125.** O legado exibia em módulo e sinalizava só por vermelho:
      ambíguo e inacessível.
- [x] 7.1.7 Bloco de observação com o `RichTextEditor` em modo leitura (**`reuse`** — mesmo
      componente do FE-099, da S4); some quando vazio. **Fecha FE-126.**
- [x] 7.1.8 Grade hierárquica de 3 níveis com indentação — folha editável, nó com filhos
      mostra total; **sempre expandida** (DC-35: o colapsar/expandir está comentado no legado;
      entra como comportamento novo do `DataTable`, não como paridade). **Fecha FE-127.**
- [x] 7.1.9 Estados da grade — carregando / sem data / sem padrões / sem resultado / **falha**;
      português corrigido ("Você", "possui"). **Fecha FE-128.**
- [x] 7.1.10 Campo de valor com `MoneyInput` (S0) — vírgula ou ponto, 2 casas, aviso de
      separador duplo; **natureza da operação legível** (o legado exibia `C`/`D` cru).
      **Fecha FE-129.**
- [x] 7.1.11 Salvamento na grade com guarda de envio duplo **por célula**, não em `$('form')`
      global; a mensagem distingue **criado** de alterado. **Fecha FE-130.**
- [x] 7.1.12 Excluir lançamento — oferecido só onde se aplica. **Fecha FE-131.**
- [x] 7.1.13 Modo somente-leitura e consolidação com **o mesmo critério no cliente e no
      servidor**. **Fecha FE-132.** Fecha **D-23** — no legado o bloqueio era
      **exclusivamente de interface**.
- [x] 7.1.14 Marcador de não cumulativo, com explicação consultável. **Fecha FE-133.**
- [x] 7.1.15 Marcador de corrigido — **valor digitado e valor gravado, ambos visíveis**.
      **Fecha FE-134.** Hoje o usuário digita X e vê Y, sem indicação.

### 7.2 Catálogo global de padrões

- [x] 7.2.1 Tela "Tipos de disponibilidade" com `DataTable` (S0), na **ordem hierárquica**.
      **Fecha FE-135.**
- [x] 7.2.2 Busca de padrões globais **funcionando**, com debounce (S0). **Fecha FE-136.**
      Hoje qualquer texto quebra a requisição e a lista só para de atualizar, sem mensagem.
- [x] 7.2.3 Estados da lista global — a falha deixa de ser silenciosa. **Fecha FE-137.**
- [x] 7.2.4 Linha de padrão global — indentação e ações por permissão. O
      `_child_widget.html.erb` (usa `default_position`, sem emissor) **não é portado**.
      **Fecha FE-138.**
- [x] 7.2.5 Formulário de padrão global — **a obrigatoriedade aparece na tela** (não existia)
      e **nenhum padrão de outro projeto vai no payload**. **Fecha FE-139.**
      Fecha o vazamento do `AvailabilityTemplate.all` serializado num atributo `data-`.
- [x] 7.2.6 Detalhe do padrão — funciona **também** para padrão de projeto. **Fecha FE-140.**
- [x] 7.2.7 Permissão de cadastro no catálogo com **o mesmo critério no servidor** (403 por
      API). **Fecha FE-141.** Fecha **D-23**.

### 7.3 Padrões do projeto

- [x] 7.3.1 Tela "Disponibilidades" do projeto — árvore de 3 níveis com indentação e ordem
      por posição. **Fecha FE-107.**
- [x] 7.3.2 Estados do padrão na lista — bloqueado / inativo / específico visíveis, **motivo
      do bloqueio consultável**, atualizados por Action Cable; **menu nunca vazio** (o legado
      deixava o menu de "global + com filhos" sem nenhum item). **Fecha FE-108.**
- [x] 7.3.3 Formulário de padrão — na edição, o que não pode mudar aparece **somente leitura
      com a razão** (DC-24). **Fecha FE-109.**
- [x] 7.3.4 Níveis derivados do pai por **busca sob demanda no servidor**; **nenhum padrão de
      outro projeto no payload**. **Fecha FE-110.**
- [x] 7.3.5 Ativar/desativar pela lista — a mensagem fala em **padrão de disponibilidade**
      (o legado dizia "Indicador ativado/deasativado", texto de outro módulo, com erro de
      grafia); ação reutilizável. **Fecha FE-111.**
- [x] 7.3.6 Remover padrão pela lista — confirmação; o padrão fica **bloqueado até concluir**
      (o legado usava `M.SUCESS`, constante inexistente, e renderizava `data-deletable` sem
      nunca lê-lo). **Fecha FE-112.**
- [x] 7.3.7 Tela "Disponibilidades do Projeto" com `DataTable` (S0) — **nasce habilitada**
      (DEC-15.1). **Fecha FE-142.**
- [x] 7.3.8 Estados da lista do projeto — a falha aparece; some a mensagem de "busca sem
      resultado" inalcançável. **Fecha FE-143.**
- [x] 7.3.9 Ligar/desligar — controle **utilizável após a primeira ação** (o
      `preventDoubleSubmit` do legado nunca era restaurado). **Fecha FE-144.**
- [x] 7.3.10 Menu de contexto do padrão — **nunca vazio**, mesmo para global bloqueado;
      clicar na linha abre o detalhe (fecha o `ReferenceError` de `openDetail`).
      **Fecha FE-145.**
- [x] 7.3.11 Estados visuais do padrão — bloqueado / desativado / específico, com **motivo,
      autor e data**. O estado "concluído" **não é portado** (DC-36: estilos sem emissor).
      **Fecha FE-146.**
- [x] 7.3.12 Formulário de padrão do projeto — textos do domínio; nenhum padrão de outro
      projeto no payload; some "Essa construtora não pode ser alterada". **Fecha FE-147.**
- [x] 7.3.13 Pai de **outro projeto** → operação **recusada** na tela e no servidor.
      **Fecha FE-148.**
- [x] 7.3.14 Recarregar a lista por `invalidateQueries` — **um** controle, funcional (o
      legado registrava dois handlers, um para seletor inexistente). **Fecha FE-149.**

### 7.4 Testes de frontend

- [x] 7.4.1 Teste: **nenhum payload** das telas desta fatia contém padrão de outro projeto.
      **Cobre FE-110, FE-139, FE-147, FE-148.** É o vazamento do `data-templates`.
- [x] 7.4.2 Teste: o critério de somente-leitura na grade é o **mesmo** do servidor — célula
      editável ⇒ o `PUT` passa; célula bloqueada ⇒ 409/403 se forçada por API.
      **Cobre FE-132.**
- [x] 7.4.3 Teste: o menu de contexto **nunca** renderiza vazio, em nenhuma combinação de
      estado do padrão. **Cobre FE-145, FE-108.**
- [x] 7.4.4 Teste: valor negativo mostra **o sinal**, não só a cor. **Cobre FE-125.**
- [x] 7.4.5 Teste: valor digitado e valor corrigido aparecem **ambos**. **Cobre FE-134.**
- [x] 7.4.6 Teste: a grade não dispara `setInterval` nem refetch periódico — o progresso vem
      do canal. **Cobre o Princípio 10 e OPS-127 (S0) aplicado aqui.**
- [x] 7.4.7 Type-check limpo e eslint limpo. Baseline pós-trim: **0 erro**.
      ⚠️ `vitest` não roda neste ambiente (falta `@rollup/rollup-win32-x64-msvc`) — limitação
      **anterior** à fatia. Escrever os testes mesmo assim; o portão é o type-check.

## 8. Operação

- [x] 8.1 `lib/tasks/fix_availability_data.rake` — idempotente, auditada por `AuditEvent`,
      com pré-visualização e **proteção contra execução destrutiva**. **Fecha OPS-129.**
      O `destroy_existing` do legado apagava **todos** os lançamentos e **todos** os padrões
      sem nenhuma guarda.
- [x] 8.2 Registrar a fila do módulo em `config/sidekiq.yml` (as filas, inclusive
      `_low_priority`, já existem). *(Encaixe; o retry é `reuse` e vem da S0/OPS-128.)*
- [x] 8.3 Rotina de reconciliação de `virtual_value` — reporta divergências entre o derivado
      persistido e o recalculado. **Fecha DB-127 na prática.**

## 9. Paridade e fechamento

- [x] 9.1 Conferir os **101 IDs** contra `.migration-ai9/parity-ledger.md`: todos em
      `implemented`, `dropped` com evidência (BE-121, DB-134) ou `blocked` com a pergunta
      nomeada (BE-125, BE-126, BE-127, BE-128, BE-148 — Q-07/Q-08/Q-09/Q-10).
- [x] 9.2 Registrar em `.migration-ai9/improvements-log.md` as **10 mudanças visíveis** da
      seção "What Changes" do `proposal.md` — em especial as que **mudam número exibido**,
      para o QA do Phase 4 não as ler como regressão.
- [x] 9.3 Conferir os requirements de `openspec/specs/availability/spec.md` (BE-120..149,
      FE-120..149, DB-120..135, OPS-120..129) — cada cenário tem um teste que o exerce.
- [x] 9.4 Conferir os requirements de `openspec/specs/projects/spec.md` correspondentes a
      BE-110..117, FE-107..112, DB-085, OPS-081..084 — idem.
- [x] 9.5 **Confirmar que os quatro itens de menu nascem habilitados** —
      `availability`, `charges`, `project_availabilities`, `availability_templates`
      (DEC-15.1 / DC-37 / D-90). O mecanismo `locked` continua existindo, lido do **item**
      (não do grupo), mas **nenhum item nasce marcado**. O item "Cobranças" aponta para a
      tela entregue pelo bloco `receivables` (SR-6) — **esta tarefa habilita o menu, não
      implementa a tela**.
- [x] 9.6 `rspec` do backend: **nenhuma falha nova** em relação ao baseline. Registrar a
      **lista** das falhas.
- [x] 9.7 Portão de contrato **C1**: revisão dirigida de todos os endpoints da fatia — cada
      um declara `current_project!` ou é catálogo global declarado; `grep` por
      `default_scope` devolve vazio.
- [x] 9.8 Portão do **D-05**: revisão dirigida dos quatro jobs — cada um libera o bloqueio em
      **`ensure`**. Um job sem `ensure` é o defeito de volta.
- [x] 9.9 Anotar em `.migration-ai9/upstream-flags.md` os achados da base ai9 — **sem
      consertar** (Princípio 6b).


## Fechamento de órfãos do Phase 2 — esquema de disponibilidades e cobranças

Quatro IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 `availability_templates` com STI `GlobalAvailabilityTemplate` /
      `ProjectAvailabilityTemplate`. **Fecha: DB-566.**
- [x] F.2 `availability_entries` herdando a base de lançamento construída em S6 — **sem**
      redefinir o `enum` de situação. Verificável: o valor persistido é o mesmo dos
      recebíveis. **Fecha: DB-567.**
      **DESBLOQUEADA E FECHADA em 26/08/2026.** A S6 entregou `app/models/entry.rb`, e a
      herança foi exatamente a linha que esta tarefa previa: `class AvailabilityEntry <
      Entry`. `Entry` é `abstract_class`, então **não** entra STI nem coluna `type` — a
      tabela continua sendo `availability_entries`.
      Provado em `spec/models/availability_entry_spec.rb`, bloco *"F.2 / DB-567 — herda
      `Entry` sem redefinir a situação (contrato C4)"*, **3 exemplos** (suíte do arquivo:
      **20 exemplos, 0 falhas**):
      - herda de `Entry`, que é abstrata, sem `type` e sem trocar de tabela;
      - **usa o MESMO objeto** de de-para que `ReceivableEntry` — a asserção é `equal?`, não
        `eq`: tem de ser o mesmo objeto congelado, não um igual. É isto que a tarefa quer
        dizer com *"o valor persistido é o mesmo dos recebíveis"*: não existe uma segunda
        tabela de tradução que possa divergir da primeira no dia em que alguém renomear um
        rótulo. `status_from_legacy('OK') == 'ok'` pelos dois caminhos;
      - **não** define situação própria: sem coluna `status`, `defined_enums` vazio, e as
        constantes `STATUSES`/`LEGACY_STATUS_LABELS` **não** declaradas na própria classe
        (`const_defined?(…, false)` falso) — é a segunda cópia que o contrato C4 existe para
        impedir.
      **O que deliberadamente NÃO foi feito:** criar coluna `status` em
      `availability_entries` para "usar a herança". A célula da grade é valor, não título a
      conferir; inventar situação aqui seria feature nova travestida de paridade (DEC-09), e
      o enunciado manda o contrário — herdar **sem** redefinir situação.
- [x] ~~F.3 Conferir `charges` e `receipts` contra a descrição de `data-schema`~~ —
      **ANULADA pela DEC-63 (P-098): `charges` e `receipts` são da S6.**
      Era o achado **A-3**: a seção "Fronteiras" do `proposal.md` já dizia que a feature não
      é de S11, e a seção "IDs adotados" do **mesmo arquivo** reivindicava `DB-583`/`DB-584`
      — as mesmas duas tabelas com IDs de inventário diferentes. Vale a Fronteira.
      **`DB-583`/`DB-584` = "mesma tabela, fechada por S6".**

      **Achado novo da análise do dump (26/08/2026), que muda o fundamento da tarefa:**
      `20220707164909_create_charges.rb` está no repositório e **nunca rodou em produção** —
      a última migration aplicada é de 25/05/2022. A tabela `charges` **nunca existiu**.
      Logo, quando a S6 escrever a tela, ela **não tem comportamento validado para
      replicar**: o DEC-30 não alcança código que nenhum usuário jamais executou.
      Registrado aqui porque o item de menu "Cobranças" é de S11 — ver tarefa 9.5.
