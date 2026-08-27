# Proposal: S10 — Indicadores e séries mensais

## Why

O módulo de indicadores é o registro mensal que o cliente do Safegold preenche à mão, célula
a célula: um catálogo de indicadores (globais e específicos de projeto) e uma grade de
12 meses × indicador. É simples de descrever e **é onde estão os dois piores estados do
sistema legado**:

1. **A exclusão de um indicador apaga a série histórica inteira, em silêncio (D-66).**
   `has_many :entries, dependent: :delete_all` — **sem callbacks, sem backup**, com uma
   confirmação que só diz "A operação não pode ser desfeita" e **não menciona os
   lançamentos**. Na tela de indicadores específicos (`FE-321`) a exclusão **nem tem
   diálogo de confirmação**. É o maior risco de perda de dado do bloco inteiro.
2. **O autosave da grade falha em silêncio (`FE-329`).** Cada célula submete no `change` e
   **não há handler de erro nenhum**: se o backend responde 422, o usuário vê o campo
   destravar sem mensagem e **acredita que salvou**. Pior: `preventDoubleSubmission` marca o
   formulário como enviado e **nunca limpa a flag**, então após o primeiro auto-save o mesmo
   campo não envia de novo até a lista recarregar.

Somam-se a isso duas falhas de segurança confirmadas:

3. **`constantize` de input do usuário** (`BE-707`): `params[:owner_type].constantize` e
   `params[:connection_type].constantize` — qualquer classe Ruby pode ser instanciada.
4. **Toda a autorização é de view** (`BE-717`): nenhum dos três controllers tem
   `before_action` de permissão. Qualquer autenticado pode `POST /indicators`,
   `PUT .../connections` ou `POST /indicator_entries` direto; `user_is_readonly` só
   desabilita botões. E o `user_id` do lançamento **vem do formulário e está no permit** —
   dá para registrar lançamento em nome de outro usuário forjando o campo (`BE-326`).

A base ai9 pós-trim não tem nada disso: nenhum model de indicador, nenhuma grade. O ganho de
reuso está na infra — e há um reuso **real e verificado** aqui: **ActionText já existe na
base** (`config/application.rb:13`, `schema.rb:30` com `action_text_rich_texts`,
`user.rb:18 has_rich_text :biography`), e é por isso que `DB-313` e `FE-316` são `adapt`, não
`build`. Sem essa descoberta alguém criaria uma coluna `description_html` paralela.

## What Changes

Entrega ponta a ponta as sub-fatias **I1, I2 e I3** do mapa de bloco
(`.migration-ai9/map/risk-indicators.md` §1) e a parte de **X1** deste domínio:

- **I1 — catálogo global.** CRUD, normalização de título, as 3 regras de unicidade
  global × específico, ativar/desativar, instrução em rich text (ActionText) — e **soft
  delete** (`discarded_at`), que resolve o D-66.
- **I2 — indicadores específicos de projeto (conexões).** Conectar/desconectar global, CRUD
  do específico, e o fechamento do `constantize`.
- **I3 — grade mensal de lançamentos.** A tela que o usuário realmente usa: 12 meses ×
  indicador, autosave por célula **com feedback de erro**.
- **X1 (parte indicadores)** — 9 descartes com evidência de varredura.

**Não** entrega, por **DEC-09** e pela nota de escopo da própria
`openspec/specs/indicators/spec.md`: **série histórica calculada, variação (mês a mês, ano a
ano, percentual), acumulado, média e gráfico de indicador NÃO existem no legado e ficam fora
do escopo**. O `dash` do legado não referencia indicadores. Gráfico é a adição de escopo
`NEW-001`, que vive em **S15** e entra no ledger como `new`, nunca como paridade.

### Dependências

| Direção | O quê |
| ------- | ----- |
| Consome de **S0** | `current_project!`, `ProjectScoped`, papéis + hierarquia (C3), `user_is_readonly` |
| Consome de **S0/S5 (DS)** | `DataTable`, `Pagination`, `MoneyInput`, `EmptyState`/`ErrorState` |
| Consome de **S4** | `Project` — a grade e as conexões são por projeto |
| Consome da **base ai9** | **ActionText** (já instalado e em uso) e `ui/accordion.tsx`, `ui/switch.tsx` do Radix |
| Entrega para **S15** | a série mensal que `NEW-001` (gráfico, Recharts) vai plotar — **feature nova, não paridade** |

### Decisões que governam esta fatia

| Decisão | Efeito prático aqui |
| ------- | ------------------- |
| **C1** | Escopo por projeto **no endpoint** para lançamentos e conexões; o **catálogo global** (`indicators.project_id IS NULL`) é **sem escopo**, leitura liberada ao Colaborador (DEC-18.4) |
| **C2** | A montagem da grade e o autosave da célula passam pelo **mesmo serviço** (`Indicators::EntryService`) — o valor exibido e o gravado nunca divergem |
| **C3** | Hierarquia do ai9; todo teste de autorização verifica **os dois lados** |
| **D-66** (corrigir) | Exclusão lógica (`discarded_at`, o padrão vivo da base) + confirmação que **diz quantos lançamentos** serão afetados |
| **DEC-09** | Nada de série calculada, variação, acumulado, média, gráfico, lembrete, fechamento de mês, import, export ou API pública |
| **DEC-10** | Formatação por `Intl`/`date-fns` do ai9 |
| **Princípio 6b** | O que parecer errado na base e não bloquear vira linha em `upstream-flags.md` — em especial a **UF-1** |

## Impact

- **Afetado:** `backend/db/migrate` (3 tabelas), `backend/app/models/{indicator,indicator_entry,project_indicator_connection}.rb`,
  `backend/app/services/indicators/`, `backend/app/controllers/api/v1/{indicators,indicator_entries,indicator_connections}.rb` + entities,
  `frontend/src/features/indicators/`, `frontend/src/components/ui/` (promoção de **um** componente de rich text a membro da biblioteca), `useNavItems.ts`.
- **Não afetado:** o legado `sfg` (read-only); `risk`; `structured-operations`.
- **Mudanças visíveis** (registrar em `improvements-log.md`):
  a lista de indicadores globais **passa a paginar** — hoje o front manda `l=50, o=0` fixos e
  nunca incrementa o offset, então **a lista trunca em 50 indicadores sem aviso nenhum**;
  a grade passa a **distinguir "não lançado" de "lançado como zero"** (hoje os dois aparecem
  como `0`), sujeito a **Q-R34**.
- **Risco principal:** o ponto crítico do ETL em `DB-313`. A "Instrução" do indicador **não
  vive** na tabela `indicators` — vive em `action_text_rich_texts`. Qualquer export/import
  precisa levar essa tabela junto, ou **o conteúdo se perde**. E os corpos podem estar
  **URL-escapados** (daí o `CGI.unescape` nas views de contrato do legado), então a
  codificação precisa ser validada **item por item**.

## IDs de inventário cobertos (62)

Estratégia copiada de `.migration-ai9/map/risk-indicators.md` §2.5.
**Placar: 39 `build` · 5 `build?` · 9 `drop` · 5 `adapt` · 4 `reuse`.**

### `indicators` — catálogo global (I1)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-311 | build | `SVC/indicators/indicator_service.rb#index`; `EP/indicators.rb` — filtra só globais; **paginação real** |
| BE-312 | build | allowlist de ordenação (`title`, `key`) — corrige 3 bugs, incluindo `PG::UndefinedColumn` |
| BE-314 | build | `EP/indicators.rb` (drawer) — com `project_id` cria específico, sem cria global |
| BE-315 | build | `#show` → 404 estruturado; o formulário continua **sem** `value_type` e `is_active` |
| BE-316 | build | `#create` — transacional com a `ProjectIndicatorConnection`; `created_by` do servidor (**Q-R24**) |
| BE-317 | build | `#update` — um save; trocar `project_id` passa a **sincronizar a conexão** |
| BE-318 | build | `#destroy` → **exclusão lógica** (`discarded_at`). **Corrige D-66** |
| BE-319 | build | `#activate` — `is_active` boolean; id inexistente deixa de dar 500 |
| BE-320 | build | `MOD/indicator.rb` — as **3 regras de unicidade** global × específico, replicadas |
| BE-321 | **build?** | normalização de título e derivação da `key`. **Q-R25**, ver "Como cada `build?` foi resolvido" |
| BE-322 | **build?** | denormalização nos lançamentos. **Q-R27**, ver "Como cada `build?` foi resolvido" |
| BE-715 | build | `enum :value_type` com **um** valor ("Dinheiro"), extensível sem migração de dados (**Q-R32**) |
| DB-310 | build | `MIG/*_indicadores.rb` — índices em `project_id`, `title`, `key`; FK; `discarded_at` |
| DB-313 | adapt | `has_rich_text :description` — **ActionText já existe na base**. Ponto crítico do ETL |
| FE-310 | build | `FE/indicators/pages/IndicatorsPage.tsx` — menu "Cadastro › Indicadores" |
| FE-311 | build | `IndicatorSearch.tsx` — debounce 300 ms, requisição anterior cancelada, botão de limpar |
| FE-312 | build | `DS/DataTable.tsx` — ordenação por "Chave" **passa a funcionar**; estado na URL |
| FE-313 | **reuse** | `ui/accordion.tsx` (Radix) — accordion exclusivo, teclado e ARIA de graça |
| FE-314 | build | dropdown Editar / Excluir, escondido inteiro para readonly, com gate no servidor |
| FE-315 | build | confirmação que **diz quantos lançamentos** serão afetados. **Corrige D-66 na copy** |
| FE-316 | adapt | `IndicatorDrawer.tsx` + `DS/RichTextField.tsx` — promover **um** componente a membro da biblioteca |
| FE-317 | **reuse** | `react-router-dom` — deep-links `/indicators/add` e `/indicators/:id/edit` |
| FE-318 | adapt | policy AUTH.S3 no front — **nada disso é reforçado no backend hoje** |
| FE-322 | build | estado ativo/inativo exibido **nas duas** telas (hoje só na de específicos) |
| OPS-311 | build | `backfill_service.rb` (rake idempotente com log) no lugar de `Indicator.fix_titles` |
| OPS-312 | **build?** | a "Chave de Integração". **Q-R26**, ver "Como cada `build?` foi resolvido" |
| OPS-313 | build | `discarded_at` + job de purga — o **único** padrão de exclusão lógica da base |
| OPS-314 | build | `spec/services/indicators/` — **zero cobertura** hoje para 5 models, 4 controllers e ~40 views |

### `indicators` — conexões e específicos (I2)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-707 | build | `connection_service.rb#connectable` — **fecha o `constantize` de input do usuário** |
| BE-709 | build | `#connect` — transação + relatório por item (hoje o erro **não é agregado**) |
| BE-710 | build | `#disconnect` — par inexistente vira 404/no-op idempotente, não 500 (**Q-R31**) |
| BE-711 | build | `#destroy_specific` — corrige o ramo que **deletava o indicador errado** (FIXME/issue #7102) |
| DB-312 | build | `MIG/*_conexoes_projeto_indicador.rb` — join pura, único (`project_id`, `indicator_id`) |
| FE-319 | build | `ProjectIndicatorsPage.tsx` — passa pelo `current_project!` em vez do projeto padrão hardcoded |
| FE-320 | **reuse** | `ui/switch.tsx` (Radix) + `sonner` — React Query `isPending` no lugar do `preventDoubleSubmit` |
| FE-321 | build | menu do específico — **ganha a confirmação informada que hoje não existe** |
| FE-323 | build | mensagem explicativa no clique sem permissão — **o padrão certo, generalizado** |

### `indicators` — grade mensal (I3)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-324 | build | `entry_service.rb#grid` — **corrige N+1 severo** (12 queries por indicador) sem mudar resultado |
| BE-326 | build | `#upsert` — **`user_id` passa a vir do servidor**; upsert por (projeto, indicador, ano, mês) |
| BE-327 | build | `#update` — `indicator_id` nil → 422, não 500; auditoria de mudança de período (**Q-R28**) |
| BE-328 | **build?** | `#destroy`. **Q-R29**, ver "Como cada `build?` foi resolvido" |
| BE-329 | **build?** | `MOD/indicator_entry.rb` — identidade e faixa de mês. **Q-R30** |
| BE-716 | build | portar **só** as 4 consultas que existem; nada de variação, acumulado, média ou gráfico |
| DB-311 | build | `MIG/*_lancamentos_de_indicador.rb` — único (`project_id`, `indicator_id`, `year`, `month`) + CHECK |
| FE-324 | build | `IndicatorEntriesPage.tsx` — grade + card FILTROS; rótulos de menu distintos (**Q-R33**) |
| FE-325 | build | `EntryFilters.tsx` — indicador (só ativos, com "Todos"), mês e ano; filtros na URL |
| FE-326 | build | `MonthlyGrid.tsx` — **distingue "não lançado" de "zero"** (**Q-R34**) |
| FE-327 | build | modo mês único: uma linha por indicador, **com a instrução exibida** (hoje some) |
| FE-328 | build | `DS/MoneyInput.tsx` — pt-BR, 2 casas, **negativos permitidos** |
| FE-329 | build | autosave com `onError` — **corrige o pior estado de UI do bloco inteiro** |
| FE-718 | adapt | readonly com a mensagem explicativa, e o backend passa a **impedir** o POST |
| FE-719 | **reuse** | `ui/accordion.tsx` — no modo mês único não há título clicável; replicar |

### `indicators` — descartes com evidência (X1)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-310 | **drop** | rota `GET /indicators` → template inexistente (500). A **tela** vive em I1 |
| BE-313 | **drop** | `GET /indicators/:id` → diretório inexistente; o `#show` nem carrega `@indicator` (**Q-R23**) |
| BE-323 | **drop** | `GET /indicator_entries` → diretório inexistente. A tela real é o console |
| BE-325 | **drop** | `new`/`edit` de lançamento: o partial `helper/_body` **não existe** |
| BE-708 | **drop** | endpoint de conexões **sem escopo nenhum** e sem autorização, **sem nenhum chamador** |
| BE-712 | **drop** | `GET /project_indicator_connections` → template inexistente |
| BE-713 | **drop** | `GET /project_indicator_connections/:id/edit` → diretório inexistente |
| BE-714 | **drop** | `DELETE /project_indicator_connections/:id` → `@connection` **nunca é setado**; `create`/`update` **comentados** |
| OPS-310 | **drop** | **não existe nenhuma rotina automática** para indicadores no legado |

### `indicators` — autorização

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-717 | adapt | policy AUTH.S3 nos 3 endpoints — **corrige gap de segurança confirmado** |

## Como cada `build?` foi resolvido (5)

> Um deles é **conflito entre o mapa e a spec aprovada**. Onde os dois divergem, esta fatia
> segue a **spec** — é o requirement aprovado no Phase 1 — e leva a divergência ao usuário
> como tarefa de decisão.

| ID | Pergunta | Resolução nesta fatia |
| -- | -------- | --------------------- |
| **BE-321** | O título continua em CAIXA ALTA sem acento? (**Q-R25**) | **Conflito mapa × spec.** O mapa manda replicar (`I18n.transliterate(title).upcase` em todo save); `openspec/specs/indicators/spec.md` → `BE-321` já resolve: *"o título aparece como digitado, e a comparação de unicidade continua ignorando acentos e caixa"*. Adotada a **spec**: normalização **só para comparação**, o dado guarda o que o usuário digitou. `title` nil deixa de dar 500 e passa a 422; a `key` continua derivada no create. Tarefa de decisão **T-D10**. **Atenção do ETL**: os acentos do dado legado **já se perderam** — "re-humanizar" seria adivinhação, então o dado migrado chega em caixa alta e só o que for digitado depois preserva a forma |
| **BE-322** | A denormalização de `title`/`key`/`value_type` no lançamento é "foto do momento" ou bug? (**Q-R27**, D-70) | **Replicar**, com uma correção de forma que a spec já pede: o `update_all` síncrono dentro do request vira **job** quando passar de N linhas (indicador com 20.000 lançamentos não pode travar a edição do título). O **resultado** é idêntico — o histórico continua sendo reescrito. Tarefa de decisão **T-D11** |
| **BE-328** | Excluir lançamento é feature viva ou resíduo? (**Q-R29**) | **Construir**, como a spec já especifica: remoção com confirmação e autorização, e a célula voltando ao estado "não lançado". **Nenhuma tela do legado chama esta rota** — a grade só cria e atualiza, e zerar grava `0` —, mas a rota existe e o DEC-09 manda portar o que existe. Tarefa de decisão **T-D12**: se o negócio disser que é resíduo, vira `dropped` com evidência |
| **BE-329** | `month`/`year` como inteiros soltos ou como `date`? (**Q-R30**) | **Inteiros + CHECK `1..12`**, como a spec já resolve. Preserva a chave de unicidade e o payload da API, e fecha o buraco de mês 13 / ano 0 passando pela validação e explodindo depois em `Date.new(year, month)`. `value` continua obrigatório com default 0 — **zero é válido, `nil` não** — e **aceita negativos** |
| **OPS-312** | A "Chave de Integração" tem consumidor **fora** do repositório? (**Q-R26**) | **Não mexer.** Dentro do repo, **nada** lê `indicator.key`: nem API, nem job, nem export. Enquanto a resposta não vier, a chave **não** vira única, **não** muda de formato e **não** some — permanece exatamente como está, obrigatória e derivada do título. Tarefa de decisão **T-D13** (pergunta direta ao usuário) |

## `drop` — motivo registrado (9)

Cada um vira linha `dropped` no `parity-ledger.md` **com a evidência da varredura**, nunca
por omissão. Oito são **rota morta**; um é ausência de feature.

| ID | Motivo | Evidência |
| -- | ------ | --------- |
| **BE-310** | Rota morta: `GET /indicators` renderiza `pub/indicators/index`, **template que não existe** → `ActionView::MissingTemplate` (500) em toda chamada. Não há autorização: qualquer autenticado bate na rota | A **tela** real é servida pelo console e vive em I1 como rota React de verdade (D-92) |
| **BE-313** | Rota morta: `GET /indicators/:id` renderiza `pub/console/parts/indicators/detail/body` — **o diretório não existe** → 500. E o `#show` **nem carrega `@indicator`** (`fetch_indicator` só roda em edit/update/destroy) | Há CSS órfão para essa tela: houve um detalhe/série histórica planejado e abandonado (**Q-R23**). Fora por DEC-09; registrado caso o negócio sinta falta |
| **BE-323** | Rota morta: `GET /indicator_entries` → o diretório `pub/indicator_entries/` **não existe** → 500 | A tela real é `/u/console/indicator_entries` e vive em I3 |
| **BE-325** | Código morto: `new`/`edit` de `indicator_entries` só têm `helper/handle.js.erb`; **o partial `helper/_body` não existe** → 500 | O cadastro e a edição acontecem **inline na grade**, nunca por drawer |
| **BE-708** | Endpoint órfão **e perigoso**: `GET .../connections` usa `@connection_type.all` → **todos os indicadores de todos os projetos**, sem escopo e sem autorização | **Nenhuma view do console chama esta rota** — o front usa a de `search`. Se algum consumidor externo aparecer, volta **com escopo** |
| **BE-712** | Rota morta: `GET /project_indicator_connections` → template inexistente (só há `_body.*` e `list/*`) → 500 | A tela vive em I2 |
| **BE-713** | Rota morta: `GET /project_indicator_connections/:id/edit` → diretório `new/` inexistente → 500 | Varredura do diretório |
| **BE-714** | Código morto: `DELETE /project_indicator_connections/:id` → diretório `destroy/` inexistente, e `@connection` **nunca é setado** (o `before_action` seta `@connections`, plural) → `NoMethodError` antes do template. `#create`/`#update` estão **inteiramente comentados** | idem |
| **OPS-310** | Ausência de feature: **não existe nenhuma rotina automática** para indicadores — nenhum lembrete de lançamento pendente, nenhum fechamento de mês, nenhum import/export, nenhuma API pública. Todo lançamento é manual, célula a célula | `sidekiq` + `sidekiq-cron` existem na base e o bloco de cron ficou **vazio** após o trim. Nada a portar (DEC-09); registrado que a infra existe se o negócio pedir lembrete depois |

## Perguntas em aberto que afetam esta fatia

| # | Assunto | Default adotado | Muda o que o usuário vê? |
| - | ------- | --------------- | ------------------------ |
| **Q-R25** | Título em CAIXA ALTA sem acento? | **Não** — preservar o que foi digitado; normalizar só para comparação (spec) | **sim** |
| **Q-R27** | A denormalização é "foto do momento" ou bug? | Replicar (o histórico continua sendo reescrito), com o `update_all` fora do request | não |
| **Q-R29** | Excluir lançamento é feature viva? | Construir, com confirmação e autorização | não |
| **Q-R30** | `month`/`year` inteiros ou `date`? | Inteiros + CHECK `1..12` | não |
| **Q-R26** | A "Chave de Integração" tem consumidor externo? | **Não mexer** na chave até a resposta | não |
| **Q-R34** | "Não lançado" e "lançado como zero" devem ser distinguíveis? | **Sim** — hoje os dois aparecem como `0`, e é a leitura mais usada do módulo | **sim** |
| **Q-R31** | "Reconectar recupera o histórico" é o desejado? | Sim — replicar. É conservador e não perde dado | não |
| **Q-R24** | `is_active` está no permit mas não no formulário — algum cliente externo posta isso? | Manter no permit, sem campo | não |
| **Q-R28** | O `user_id` do lançamento é "quem lançou" ou "quem alterou por último"? | Separar em `created_by`/`updated_by` | não |
| **Q-R32** | O indicador precisa de tipos além de "Dinheiro"? | Um valor só, modelado como `enum` extensível | não |
| **Q-R33** | Dois itens de menu chamados "Indicadores" | Rótulos distintos: "Indicadores" (catálogo) e "Lançamentos de indicadores" | **sim** |
| **Q-R23** | Houve um detalhe/série histórica planejado e abandonado | Fora por DEC-09; registrado | não |
| **Q-R1** | A grade ganha um gráfico? | **Fora desta fatia.** É a adição de escopo `NEW-001`, em **S15**, e entra no ledger como `new` | não |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-585 | build | `indicators` | S10 é dona dos indicadores |
| DB-586 | build | `project_indicator_connections` | idem |
| DB-587 | build | `indicator_entries` | idem |

**Os três são as mesmas tabelas que a fatia já constrói**, vistas pelo inventário de
`data-schema`. Ficam aqui para o ledger fechar pelos dois lados.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`BE-324` e `BE-716` são de S10**, disputados com S15. A grade mensal
  (`entry_service#grid`, que corrige um N+1 severo de 12 consultas por indicador) e as 4
  consultas de lançamento por período nascem aqui. **S15 consome**: os gráficos de `NEW-001`
  leem exatamente estas consultas, e nenhuma agregação nova nasce no cliente.
