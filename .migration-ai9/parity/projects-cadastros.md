# Phase 4 — paridade do bloco **projetos, empresas/portadores e disponibilidades**

> 287 IDs de 3 capacidades: `openspec/specs/projects` (110) · `companies-carriers` (94) ·
> `availability` (86). Verificação executada em **26/08/2026** contra o app de
> desenvolvimento no ar (`puma` em `:3000`, `vite` em `:5173`) com o **seed de demonstração**.
>
> **A regra desta passada: verificar EXECUTANDO.** Nenhuma linha abaixo diz `verified`
> por leitura de código. Cada uma cita a resposta HTTP, a tela renderizada ou o job
> rodado que a sustenta. Onde não deu para executar, o motivo está escrito na linha —
> e o ID **fica onde estava**.

## Resultado

| | |
| --- | --- |
| IDs do bloco | **287** |
| `migrated` → `verified` | **118** |
| `pending` → `verified` | **5** (FE-052, FE-053, FE-061, FE-066, FE-079 — existiam, compartilhados e testados) |
| já eram `verified`, **re-conferidos executando** | **2** (BE-070, DB-069) |
| **`verified` ao fim** | **125** |
| continuam `migrated`, com o motivo escrito na linha | **158** |
| `dropped` / `blocked` (decisão anterior, re-conferida) | 2 / 2 |
| **defeitos achados** | **5** (§6) |

Portões que rodei, e que **não** foram o critério de `verified`:

- `rspec` **271 exemplos, 0 falhas**, em **banco próprio** (`sfg9_test_qapj`, criado e
  apagado por mim via `DATABASE_URL` — o `sfg9_test` compartilhado é derrubado por
  `db:test:purge` alheio no meio da corrida).
- `vitest` **85 testes, 0 falhas** (9 arquivos: availability, CatalogScreen, projectScopeState,
  DataTable, Pagination, MoneyInput, NumericInput, dataTableArraste, dataTableTransbordo).

Portão verde prova que o código carrega. O que está na coluna **Prova** é o que
prova que ele funciona.

## 1. O código de cada prova

| Código | O que significa | Onde |
| ------ | --------------- | ---- |
| **E1** | **Escopo §0.6 por HTTP.** Membro `200`, não-membro `404`, inexistente `404` — **corpo idêntico** nos dois últimos | `/tmp/qa-pj/scope1.sh`, `leak.sh`, `leak2.sh` |
| **E2** | **Membership por HTTP.** As 3 condições e os papéis que criam/removem | `/tmp/qa-pj/memb.sh`, `memb2.sh` |
| **E3** | **Matriz de autorização por HTTP.** 6 catálogos × 5 papéis na leitura; escrita papel a papel | `/tmp/qa-pj/cat.sh`, `ro.sh`, `ro2.sh` |
| **E4** | **D-24 — exclusão bloqueada responde 422 de verdade**, em 7 recursos, e nada é apagado | `/tmp/qa-pj/behav.sh`, `behav3.sh` |
| **E5** | **D-20 — paginação real**: o limite chega ao servidor e `X-Total-Count` traz o total sem limite | `/tmp/qa-pj/behav.sh` |
| **E6** | **D-21 — ordenação por cabeçalho** responde 200 nas chaves que davam 500 no legado | `/tmp/qa-pj/behav.sh` |
| **E7** | **Validação**: campo obrigatório `400`, duplicata `422` com o campo nomeado | `/tmp/qa-pj/behav.sh` |
| **E8** | **Tela renderizada** a 1440×900, em **light e dark**, com dado real | PNG em `/tmp/qa-pj/shots/adm-*.png` |
| **E9** | **Tela renderizada a 390×844** (o telefone da DEC-100) | PNG em `/tmp/qa-pj/shots/m-*.png` |
| **E10** | **Regra de disponibilidade executada**: DC-30, índice único, obrigatório, BE-139, posição | `/tmp/qa-pj/avail.sh`, `avail2.sh`, `round3.sh` |
| **E11** | **Job rodado** (`perform_now`): trava posta, trava liberada, totais reconsolidados e restaurados | `/tmp/qa-pj/runjob.rb`, `runjob2.rb` |
| **E12** | `rspec` 271/0 em banco próprio + `vitest` 85/0 | `/tmp/qa-pj/rspec.sh` |
| **E13** | **Trilha**: a alteração gerou versão no `paper_trail`, com autor | `/tmp/qa-pj/trail2.sh` |
| **E14** | **Estado vazio na tela**, citando o termo buscado | `/tmp/qa-pj/vazio.js` |

E os motivos de **não** promover:

| Código | Motivo |
| ------ | ------ |
| **M1** | Só o **número** prova, e o número depende da **carga** do dump (DEC-102). Dono: usuário |
| **M2** | Exige **interação** que não executei: abrir drawer, enviar formulário, arrastar, subir arquivo |
| **M3** | Exige **credencial ou rede externa** que esta máquina não tem |
| **M4** | É **destrutivo** no banco compartilhado (criar/remover/limpar projeto, remover padrão) |
| **M5** | Exige **worker Sidekiq de pé** — e não há nenhum (§3, defeito P4-02) |
| **M6** | É **schema**: a prova é a migration + o spec; paridade de dado depende da carga |

## 2. A prioridade #1 — o escopo por projeto, provado nos dois lados

O contrato §0.6 do `map/projects-cadastros.md` é a fundação do bloco. É a família de
defeitos **D-01 / D-16 / D-29 / D-76 / D-100** do legado: sempre que chegava um id por
parâmetro, o filtro de projeto era descartado. **Está fechada.**

**Ator:** Gerente (Gustavo), membro de 6 dos 12 projetos, com o projeto corrente em
*Grupo Aliança Metalúrgica*. **Alvo:** ids reais de *Comercial Porto Belo*, do qual ele
**não** é membro. **Controle:** um uuid que não existe.

```
endpoint                                membro   alheio   fantasma
GET    /companies/:id                   200      404      404
PUT    /companies/:id                    -       404      404
DELETE /companies/:id                    -       404      404
GET    /providers/:id                   200      404      404
PUT    /providers/:id                    -       404      404
DELETE /providers/:id                    -       404      404
GET    /project_guarantees/:id          200      404      404
PUT    /project_guarantees/:id           -       404      404
DELETE /project_guarantees/:id           -       404      404
PUT    /availability_entries/:id         -       400      400
DELETE /availability_entries/:id         -       404      404
GET    /charges/:id                     200      404      404
GET    /charges/:id/statement           200      404      404
GET    /charges/:id/receipts            200      404      404
PUT    /charges/:id                      -       404      404
DELETE /charges/:id                      -       404      404
GET    /project_availabilities/:id       -       404      404
GET    /projects/:id                    200      404      404
X-Project-Id em /companies              200      404      404
```

**O corpo é o mesmo nos dois últimos**, palavra por palavra:

```json
{"error":"not_found","message":"Projeto não encontrado.","code":"PROJECT_NOT_FOUND"}
```

Não-membro e inexistente são **indistinguíveis**. O endpoint não vira oráculo de id.
Na tela, idem: o Gerente abrindo `/projects/<alheio>` e `/projects/<fantasma>` recebe
a mesma página, **"Projeto não encontrado"**.

**As 5 regras do §0.6, uma a uma:**

1. **`project_id` do cliente é sempre ignorado.** `POST /companies` com
   `{"title":…, "project_id":"<outro projeto>", "id":"<uuid escolhido>"}` respondeu `201`
   com `project_id` = **projeto corrente** e um uuid **novo**. Os dois furos — o escopo e o
   mass assignment de chave primária (família D-60/D-68) — fechados na mesma requisição.
2. **Filtro por id nunca sobrepõe o escopo.** `charges?charge_id=<de outro projeto>` →
   `200` com **lista vazia**, igual ao id fantasma; com o id do próprio projeto, 1 item.
3. **`:id` fora do `permit`** — provado por 1.
4. **Catálogo global não recebe escopo.** Os 6 catálogos respondem `200` para os **cinco**
   papéis, inclusive Colaborador e somente-leitura (DEC-18.4). E o menu esconde a tela:
   o Colaborador que digita `/carriers`, `/segments` ou `/projects` **cai em `/dashboard`**.
5. **Job/seed/rake não usam `current_project!`** — os jobs que rodei recebem
   `template_id` e `actor_id` explícitos.

**A visão global de OG e Admin (DEC-99) está viva e é exceção de PARTICIPAÇÃO, não de
existência:** OG e Admin veem os 12 projetos e entram em qualquer um por `X-Project-Id`
— mas o uuid inexistente devolve `404` **para eles também**.

| papel | projetos que enxerga | participações reais |
| --- | --- | --- |
| OG | 12 | 1 |
| Admin | 12 | 12 (é o dono) |
| Gerente | 6 | 6 |
| Colaborador (Camila) | 4 | 4 |
| Colaborador (Rafael) | 6 | 6 |
| Somente leitura | 2 | 2 |

## 3. A prioridade #2 — membership virou regra de servidor

O **D-28** está fechado. No legado o `pub/memberships_controller.rb` tinha **zero**
autorização e a regra vivia numa view (`_widget.html.erb:23-24`), como CSS. Executando:

**Quem cria (DEC-18.5):**

```
og        POST /memberships -> 201
admin     POST /memberships -> 201
gerente   POST /memberships -> 201
colab     POST /memberships -> 403  {"code":"ROLE_REQUIRED"}
readonly  POST /memberships -> 403  {"code":"READONLY_RESTRICTED"}
```

**As três condições da remoção, agora no servidor:**

```
readonly remove qualquer um -> 403  READONLY_RESTRICTED
colab remove (sem papel)    -> 403  ROLE_REQUIRED
gerente remove o DONO       -> 403  OWNER_PROTECTED   "O dono do projeto não pode ser removido."
admin (que É o dono)        -> 403  OWNER_PROTECTED   — nem o próprio dono se remove
gerente remove A SI MESMO   -> 403  SELF_REMOVAL      "Você não pode remover a própria participação."
participação de OUTRO proj. -> 404  igual ao id inexistente
```

**A remoção legítima faz o que promete e limpa atrás de si:** o Gerente removeu a Camila
(`204`); na requisição seguinte ela passou a enxergar **3** projetos em vez de 4, e o
`current_project_id` dela — que apontava para o projeto de onde saiu — foi **zerado**
(`nil`), em vez de virar um 409 que vazaria que o id guardado deixou de valer.
Reposta a participação, tudo voltou (`201`, 4 projetos, coluna restaurada).

## 4. A prioridade #3 — disponibilidades e cobranças estão VIVAS

**DEC-15.1 confirmada na tela.** Os quatro itens que o `locked: true` do legado *tentava*
travar (e nunca travou, D-90) nascem habilitados e são alcançáveis:

- **`/availability`** — Painel de Disponibilidade, com árvore de 3 níveis, calendário
  pt-BR marcando com ponto os dias que têm lançamento, e os indicadores.
- **`/project-availabilities`** — os padrões do projeto, com "Mostrar desativados" ligado
  por padrão, que é o que o spec pede (linhas 416 e 437-440: *"ativos e inativos"*).
- **`/availability-templates`** — o catálogo global, 16 padrões em 3 níveis.
- **`/charges`** — no menu e respondendo `200` para os cinco papéis.

**As duas semânticas de soma (DEC-26/DEC-27) coexistem com rótulo, e o rótulo está na
tela.** Conferi a aritmética do painel contra a árvore:

- nó 1 `Disponibilidades` = 1.600.830,81 + 4.547.819,61 = **6.148.650,42** ✓
- nó 1.2 = 4.056.460,20 + 491.359,41 = **4.547.819,61** — deixando de fora os
  2.668.605,80 da *Carteira cedida*, que está marcada **"Não soma"** ✓
- o cartão sob **SALDO ACUMULADO** mostra 13.326.438,66 para *Compromissos*, que é
  `virtual_value` e **não** o total da grade — e o rótulo diz isso.

Essa última divergência **parece** defeito e não é: `virtual_value` de nó base é
`signed_value + soma dos anteriores`, e como `recompute_value` já grava o `value` do nó
pai **com o sinal**, o sinal é aplicado duas vezes. Fui ao legado antes de reportar:
`sfg/app/models/availability_entry.rb:186-223` faz **exatamente isso** (`update_value`
linha 191 aplica o sinal do filho; `update_virtual_value` linha 216 aplica o do próprio
nó de novo). É réplica fiel, amparada pela **DEC-30**. Registrado aqui para que o
próximo que olhar não "conserte".

## 5. Mobile e dark — critério por tela, não amostra

**17 telas do bloco**, cada uma capturada em **light**, **dark** e **390×844**:

`/projects` · `/projects/:id` · `/companies` · `/companies/:id` · `/providers` ·
`/providers/:id` · `/carriers` · `/carriers/:id` · `/carrier-groups` · `/segments` ·
`/sub-segments` · `/project-guarantee-types` · `/project-guarantees` ·
`/project-carrier-connections` · `/availability` · `/project-availabilities` ·
`/availability-templates`

**Nenhum erro de console e nenhum `pageerror` em nenhuma das 17**, nos três modos.
No telefone as listas viram `MobileCard` (não tabela espremida), os indicadores viram
`MobileKPI` e a navegação é a `MobileBottomBar` — é a DEC-100 cumprida, não "responsivo
por breakpoint". Um achado de acabamento na barra inferior está em §6 (P4-05).

## 6. Os defeitos

Cinco. Nenhum aparece em `tsc`, em `rspec` ou em `vitest` — os três estão verdes.

---

### P4-01 — `carriers_count` está **7× inflado**, e é ele que decide o botão de excluir

**Gravidade: alta.** Número errado na tela, num sistema de gestão de risco.

`/carrier-groups` mostra na coluna **PORTADORES**: `7`, `7`, `7`, `14`. Os valores reais
são `1`, `1`, `1`, `2` — há **5 portadores no banco inteiro**, e a tela declara 35.

```
Bancos de médio porte      carriers_count=7    real=1    <<< DIVERGE
Cooperativas               carriers_count=7    real=1    <<< DIVERGE
Factorings independentes   carriers_count=7    real=1    <<< DIVERGE
Fundos multicedentes       carriers_count=14   real=2    <<< DIVERGE
```

**Como reproduzir**

```bash
cd backend && rvm use 3.2.3
bundle exec rails runner 'CarrierGroup.order(:title).each { |g|
  puts "#{g.title}: counter=#{g.carriers_count} real=#{Carrier.where(group_id: g.id).count}" }'
```

**Causa, e ela é nomeável em uma linha:**

- `backend/app/models/carrier.rb:36-37` — `belongs_to :group, …, counter_cache: :carriers_count`
- `backend/db/seeds/demo/reset.rb:152` — `::Carrier.where(bank_code: …).delete_all`

`delete_all` **não dispara callback**, então o `counter_cache` nunca é decrementado. O
seed seguinte recria os 5 portadores com `save!`, que **incrementa**. Cada ciclo
`reset` + `seed` soma +1 por portador. Sete ciclos, sete pontos.

**Por que isso importa mais do que um número torto:** o próprio
`backend/app/models/carrier_group.rb:5` diz *"`carriers_count` é `counter_cache`, e é ele
que decide o botão"*, e o front obedece —
`frontend/src/app/pages/catalogs/CarrierGroupsPage.tsx:53` usa
`usageCount={(g) => g.carriers_count}` para decidir entre a lixeira e o cadeado.
Com o contador inflado, **um grupo genuinamente vazio continua parecendo ocupado** e a
exclusão some da interface para sempre. E a docstring do mesmo arquivo (linha 14)
descreve como **defeito do legado** exatamente este sintoma — ele voltou por outra porta.

**O que salva hoje:** a guarda do **servidor** não usa o contador. `carrier_group.rb:21`
faz a contagem real, e o `422` que recebi disse *"tem **2** portador(es) vinculado(s)"* —
o número certo. Ou seja: o servidor está certo, a tela está errada.

**Correção sugerida:** trocar o `delete_all` de `reset.rb:152` por `destroy_all`
(é o que o próprio arquivo já faz nas linhas 143, 186 e 197, e o comentário da linha 24
diz que a escolha é deliberada — aqui ela escapou), e rodar
`CarrierGroup.find_each { |g| CarrierGroup.reset_counters(g.id, :carriers) }` uma vez
para curar a base atual. **Vale para o cutover:** qualquer `delete_all` sobre `carriers`
no ETL reproduz isto.

**Efeito no razão:** `BE-074` e `OPS-058` **não** foram promovidos — os dois dizem
"`carriers_count` consistente" e ele não está.

---

### P4-02 — a interface oferece ao **somente-leitura** todos os botões que o servidor recusa

**Gravidade: média.** É o "critério do botão = critério do servidor" do FE-055, invertido.

A conta somente-leitura (`tereza.machado@safegold.test`) abre `/companies` e vê
**"Nova empresa"**; abre `/project-availabilities` e vê **"Novo padrão"**, o menu de
contexto, o botão de ativar/desativar. Clicar leva a `403`:

```
POST /api/v1/companies              -> 403 {"code":"READONLY_RESTRICTED"}
POST /api/v1/providers              -> 403 {"code":"READONLY_RESTRICTED"}
POST /api/v1/project_guarantees     -> 403 {"code":"READONLY_RESTRICTED"}
PUT  /api/v1/project_carrier_connections/batch -> 403
POST /api/v1/project_availabilities -> 403
POST /api/v1/availability_entries   -> 403
POST /api/v1/availability_templates -> 403
```

**O servidor está certo em todos.** É a tela que oferece o que não pode.

**Como reproduzir:** `node .migration-ai9/tools/browser.js /companies --as=readonly --text`
e procurar "Nova empresa".

**Causa:** o gate existe e **não é chamado**. `frontend/src/hooks/useMyPermissions.ts:82`
exporta `useIsReadonly()` (a concessão `user_is_readonly`), e nove telas de outros blocos
o usam — renegociações, indicadores, operações estruturadas, recibos. Mas
`frontend/src/app/pages/catalogs/CatalogScreen.tsx:161` decide só por papel:

```ts
const podeEscrever = papel !== null && writeRoles.includes(papel)
```

A conta somente-leitura tem papel `colaborador`, que **está** em `writeRoles`.

**Alcance — e ele passa do meu bloco.** `CatalogScreen` é o molde de **14 telas**:
`CompaniesPage`, `ProvidersPage`, `ProjectGuaranteesPage`, `CarriersPage`,
`CarrierGroupsPage`, `SegmentsPage`, `SubSegmentsPage`, `GuaranteeTypesPage`,
`AvailabilityTemplatesPage`, `WalletsPage`, `MovementKindsPage`, `ReceivableKindsPage`,
`ResourceSourcesPage`, `RenegotiationsPage`. As quatro últimas são de outros blocos.
Fora do molde, sem gate nenhum de readonly: `ProjectAvailabilitiesPage`,
`AvailabilityPage` (a grade de lançamento) e `CarrierConnectionsPage`.

**Correção sugerida:** uma linha em `CatalogScreen.tsx` —
`const podeEscrever = papel !== null && writeRoles.includes(papel) && !useIsReadonly()` —
mais o mesmo gate nas três telas fora do molde. **É correção de bloco cruzado: quem
decide é o orquestrador**, não eu, porque toca telas de outras fatias.

---

### P4-03 — **não há worker Sidekiq de pé**, e sem ele todo padrão desativado fica travado para sempre

**Gravidade: alta em desenvolvimento; bloqueante de demonstração.**

Achei isto tentando verificar a desativação de um padrão. O `POST .../deactivate`
respondeu `202`, travou **os 6 nós da subárvore** com a mensagem
*"Este padrão foi desativado e fica bloqueado até a atualização dos lançamentos
terminar"* — e o job foi para a fila `ai9_low_priority`, onde **ficou**.

```
Sidekiq::ProcessSet.new.size  =>  0
ai9_default: 18   ai9_low_priority: 1   apl9_default: 2   ...   retry: 208
```

**Como reproduzir:** desativar qualquer padrão em `/project-availabilities` e recarregar.
A linha fica com cadeado e a tela não volta ao normal — não há quem processe a fila.

**O código está certo.** Rodei o job à mão e ele fez tudo o que promete:

```
DeactivateProjectTemplateJob.perform_now(id, actor)
  -> ativos=11 inativos=6 travados=0     # desativou, reconsolidou e LIBEROU no `ensure`
ActivateProjectTemplateJob.perform_now(id, actor)
  -> ativos=17 inativos=0 travados=0     # e o caminho de volta também
```

E os números voltaram idênticos ao ponto de partida
(`value=-7177788.24  virtual=13326438.66`). **OPS-082/083/122/123 e BE-113/114/147
estão `verified` por causa dessa execução.**

O que **não** dá para verificar sem worker, e por isso ficou `migrated`: OPS-081,
OPS-120, OPS-121 (semear e propagar padrão global), OPS-087/OPS-127 (progresso ao vivo
por Action Cable — `perform_now` não passa pelo canal) e OPS-128 (retenção/retry).

**O que preciso do usuário:** subir um worker no ambiente de desenvolvimento
(`APP_NAME=<próprio> bundle exec sidekiq`) ou dizer que fica sem, para que isto vire
item de runbook em vez de defeito. **Antes da demonstração isto precisa estar de pé** —
sem ele, desativar um padrão trava a tela na frente do cliente.

*(Limpei atrás de mim: o job órfão que a minha verificação enfileirou —
`job_id 9272f510-43fd-4c41-b514-0704ca5fe8cb` — foi removido da fila, porque se um
worker subisse depois ele desativaria os padrões sozinho. Nenhum outro job foi tocado.)*

---

### P4-04 — as mensagens de erro vazam o nome da coluna em inglês, e o `(a)` do gabarito

**Gravidade: baixa, mas está na cara do usuário e é o bloco inteiro.**

```
GET /companies/<inexistente>            -> "Empresa não encontrado(a)."
GET /providers/<inexistente>            -> "Fornecedor não encontrado(a)."
GET /project_guarantees/<inexistente>   -> "Garantia não encontrado(a)."
GET /carriers/<inexistente>             -> "Portador não encontrado(a)."
DELETE /memberships/<inexistente>       -> "Participação não encontrado"
POST /companies {}                      -> "title é obrigatório"
POST /companies {título duplicado}      -> "Title já existe neste projeto"
PUT  /availability_templates/:id        -> "Is mandatory só pode ser marcado se os níveis acima…"
```

Três problemas na mesma família: o `(a)` do gabarito genérico foi para a tela; a
concordância de "Participação" está errada; e `title` / `Is mandatory` são **nomes de
coluna**, não nomes de campo em português. O map do bloco pede, para BE-054, *"erros em
pt-BR nomeando o campo"* — a metade em pt-BR chegou, a do campo não.

Aparece na tela, não só na API: `/companies/<id de outro projeto>` renderiza
**"Empresa não encontrado(a)."** dentro do estado de erro.

**Correção sugerida:** gênero por recurso no gerador de `not_found_response` e um
`human_attribute_name` em pt-BR (`title` → "Razão social" em `Company`, "Título" nos
catálogos; `is_mandatory` → "Obrigatório").

---

### P4-05 — no telefone, a tarja de aceite come a primeira linha, e o rótulo do menu quebra no meio da palavra

**Gravidade: baixa (acabamento). Uma das duas metades é de outro bloco.**

A 390×844, em **todas** as telas do bloco:

1. A tarja *"Você ainda não aceitou os documentos vigentes"* fica **atrás da barra
   superior**: a primeira linha some e o que se lê começa em "Politicas de Privacidade e".
   A tarja é do bloco de contratos (S12), não meu — reporto porque aparece em todas as
   17 capturas.
2. Na `MobileBottomBar`, **"Painel de Disponibilidade"** quebra em três linhas com
   hífen no meio da palavra: **"Painel de Disponibili-dade"**. O rótulo é do meu bloco
   (`consoleNavigation.tsx:345`). Sugestão: rótulo curto para a barra ("Disponibilidade"),
   mantendo o longo no menu lateral.

Evidência: `/tmp/qa-pj/shots/m-companies.png`, `m-availability.png`,
`m-project-availabilities.png`.

---

## 7. O que ficou fora do alcance, e de quem é

| O que | Quantos IDs | Dono |
| --- | ---: | --- |
| **Paridade numérica contra dado real** (M1) | 6 | **usuário** — depende da data da carga (DEC-102) |
| **Interação de formulário/drawer/upload** (M2) | 96 | próxima passada de QA, ou o agente de front |
| **Credencial/rede externa** (M3) — ReceitaWS | 2 | **usuário** — provisionar a credencial `receitaws` |
| **Destrutivo no banco compartilhado** (M4) | 17 | precisa de banco descartável com seed próprio |
| **Sem worker Sidekiq** (M5) | 7 | **usuário** (P4-03) |
| **Schema sem oráculo** (M6) | 46 | a carga (DEC-102) |

Os 17 de **M4** são o buraco que mais dói: criar projeto (BE-085..088, BE-095,
FE-085..090), removê-lo (BE-091), limpar o projeto de treinamento (BE-092) e remover
padrão (BE-115, BE-146, OPS-084/124) são justamente onde o legado tinha efeitos
colaterais. Não executei porque o banco de desenvolvimento é **compartilhado com outros
agentes** e criar projeto sem worker deixaria o registro pela metade (P4-03). Com um
banco descartável e um worker, fecham numa passada curta.

## 8. Duas notas de método

**Re-conferi na fonte antes de repetir justificativa alheia**, que é a lição do dia 26/08:

- Ao ver "Mostrar desativados" ligado por padrão, quase reportei defeito. Fui ao
  `openspec/specs/availability/spec.md` (linhas 416 e 437-440): o spec pede *"ativos e
  inativos"*. **Não é defeito.**
- Ao ver o Colaborador desativar padrão (`202`), quase reportei escalada de privilégio.
  Fui ao `authorization-matrix.md:140`: `project_availabilities` é `CRUD` para os quatro
  papéis. **Não é defeito.**
- Ao ver o saldo acumulado positivo num nó de débito, quase reportei erro de sinal. Fui
  ao legado (`sfg/app/models/availability_entry.rb:186-223`). **É réplica fiel (DEC-30).**

**Como me autentiquei nas capturas.** A trava de força bruta do login é **por IP**
(5 identificadores distintos em 15 min) e há outros agentes na mesma máquina — ela
disparou no meio da segunda leva. Provei o login **pela tela, de verdade**, três vezes
(o `browser.js` com `--as=admin`); dali em diante plantei o cookie `refresh_token`, que é
**o mesmo caminho que o app usa** para restabelecer sessão no boot
(`POST /auth/v1/sessions/refresh`). A tela renderizada continua sendo tela renderizada; o
que deixei de repetir foi o formulário de código, que é do bloco `auth-users`.
O script está em `/tmp/qa-pj/sweep2.js`.

**Estado do banco compartilhado, conferido no fim:** tudo o que escrevi foi desfeito e
conferido linha a linha — `Project=12 Membership=30 Company=35 Provider=61 Carrier=5
CarrierGroup=4 Segment=3 SubSegment=12 AvailabilityTemplate=220 AvailabilityEntry=4233
Charge=42 ProjectGuarantee=37 ProjectGuaranteeType=8`, todos idênticos ao ponto de
partida, com `ativos=17 inativos=0 travados=0` no Grupo Aliança, o título do padrão
global `1` restaurado para "Disponibilidades" e o `has_bi` do projeto de volta a `false`.
O banco de teste que criei (`sfg9_test_qapj`) foi apagado.

---

## 9. Tabela — uma linha por ID

### companies-carriers — backend (BE-050 … BE-079)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| BE-050 | **verified** | `E1 E5 E6 E8 E9 E12` | lista escopada por `current_project!`; `per_page=2` devolve 2 e `X-Total-Count` traz o total real; tela renderizada com as 6 empresas do projeto |
| BE-051 | migrated | `M2` | modo `order_mode=dash` (resumo do painel) nao foi exercitado: nenhuma tela do bloco o consome hoje |
| BE-052 | migrated | `M1` | resumo de limites por empresa: a coluna LIMITES aparece na tela (4/2/1/3/6/3), mas o NUMERO so bate contra o dado de producao — depende da carga (DEC-102) |
| BE-053 | migrated | `M2` | endpoint de formulario (`#form`) nao exercitado; o drawer de criar/editar nao foi aberto nesta passada |
| BE-054 | **verified** | `E1 E7 E12` | `POST /companies` com `project_id` de outro projeto E `id` no corpo: os dois IGNORADOS — o registro nasceu no projeto corrente e com uuid novo; sem titulo -> 400, titulo duplicado -> 422 |
| BE-055 | **verified** | `E1 E12` | `PUT /companies/<id de outro projeto>` -> 404, identico ao id inexistente |
| BE-056 | **verified** | `E1 E4 E12` | `DELETE` cross-project -> 404; empresa com vinculo -> 422 nomeando 6 limites, 133 recebiveis, 1 renegociacao e 119 lancamentos, e NADA foi apagado (Company=35 antes e depois) |
| BE-057 | **verified** | `E1 E8 E9 E12` | `GET /companies` e `/companies/:id` respondem; detalhe renderizado (o legado dava MissingTemplate) |
| BE-058 | **verified** | `E7 E12` | titulo unico POR PROJETO: duplicata -> 422 com `details.title`; sem titulo -> 400 |
| BE-059 | **verified** | `E1 E3 E5 E8 E9 E12` | fornecedores escopados por projeto; leitura liberada aos 5 papeis; tela renderizada com os 3 do projeto |
| BE-060 | migrated | `M2` | `#form` de fornecedor nao exercitado |
| BE-061 | migrated | `M2` | criacao de fornecedor nao exercitada com payload valido (so a recusa do readonly, 403) |
| BE-062 | migrated | `M2` | metade provada: `PUT` com id de outro projeto -> 404. A outra metade (title/integration_key obrigatorios TAMBEM no update) nao foi exercitada |
| BE-063 | **verified** | `E1 E4 E12` | `DELETE /providers/<em uso>` -> 422 «tem 1 renegociacao(oes) vinculado(s)»; cross-project -> 404; Provider=61 antes e depois |
| BE-064 | migrated | `M3` | validacao de CNPJ provada no servidor (`/api/v1/cnpj/123` -> 422 «Informe os 14 digitos») e a degradacao tambem (`33.000.167/0001-01` -> 503 «Preencha os dados manualmente»). A CONSULTA REAL exige credencial `receitaws` e rede — nao ha nesta maquina |
| BE-065 | **verified** | `E1 E8 E9 E12` | `GET /providers/:id` responde e a tela de detalhe existe e renderiza (D-22) |
| BE-066 | migrated | `M2` | validacao de documento CPF/CNPJ e `cnaes`/`atividades` em JSON unico nao exercitados por gravacao |
| BE-067 | **verified** | `E3 E5 E6 E8 E9 E12` | catalogo GLOBAL: leitura 200 para os 5 papeis (DEC-18.4); `per_page=2` devolve 2 com `X-Total-Count: 5`; tela com os 5 portadores |
| BE-068 | migrated | `M2` | `#form` nao exercitado; a tela de detalhe FOI renderizada (3 abas) — ver FE-068 |
| BE-069 | migrated | `M2` | criar/atualizar portador com payload valido nao exercitado (o `bank_code` string e a estrutura de FIDC aparecem na tela: COMPE 894/907/912/923/936 sem perda de zero) |
| BE-070 | **verified** | `E4 E12` | JA ERA `verified`, e RE-CONFERIDO executando em 26/08: `DELETE /carriers/<em uso>` -> 422 nomeando 5 conexoes, 14 limites e 400 recebiveis, e Carrier=5 antes e depois — nenhuma cascata (era a assimetria mais perigosa do legado, em que excluir portador apagava limites) |
| BE-071 | migrated | `M2` | validacoes de Carrier: a formatacao de cidade com fallback esta provada na tela («Sao Paulo, SP»), mas «titulo duplicado continua permitido» exigiria criar portador no banco compartilhado — nao executei |
| BE-072 | **verified** | `E3 E6 E8 E9 E12` | ordenacao por titulo responde 200 — e ela que dava 500 no legado (D-21) |
| BE-073 | **verified** | `E3 E4 E12` | `POST` 201 para OG/Admin/Gerente e 403 para Colaborador/readonly; `DELETE` de grupo com portadores -> 422 «tem 2 portador(es)»; CarrierGroup=4 antes e depois |
| BE-074 | migrated | `DEFEITO` | REPROVADO. `carriers_count` esta INFLADO 7x: 7/7/7/14 na tela contra 1/1/1/2 reais. Causa em `db/seeds/demo/reset.rb:152` (`delete_all` nao decrementa o counter_cache de `carrier.rb:36-37`). Ver defeito **P4-01** |
| BE-075 | **verified** | `E3 E6 E8 E9 E12` | ordenacao por titulo e por chave respondem 200; paginacao real |
| BE-076 | **verified** | `E3 E4 E12` | criacao de segmento FUNCIONA (`POST` 201 como OG) — no legado falhava 100% das vezes por `user_id` fora do permit (D-21); exclusao com projeto vinculado -> 422 «tem 7 projeto(s)» |
| BE-077 | **verified** | `E3 E8 E9 E12` | listagem de subsegmentos resolvida pelo proprio subsegmento; leitura liberada aos 5 papeis |
| BE-078 | **verified** | `E4 E12` | `DELETE /sub_segments/<em uso>` -> 422 «tem 1 projeto(s) vinculado(s)»; SubSegment=12 antes e depois |
| BE-079 | **verified** | `E1 E2 E3 E12` | o coracao do bloco. `require_not_readonly!` recusa readonly em 7 endpoints de escrita (403 READONLY_RESTRICTED); `authorize!` recusa Colaborador nos catalogos globais (403 ROLE_REQUIRED); `current_project!` devolve 404 identico para projeto alheio e inexistente |

### projects — backend (BE-080 … BE-119, BE-700 … BE-706)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| BE-080 | **verified** | `E1 E8 E9 E12` | OG 12 / Admin 12 / Gerente 6 / Colaborador 4 / outro Colaborador 6 / readonly 2 — exatamente as participacoes do seed, com a excecao DEC-99 para OG e Admin |
| BE-081 | migrated | `M2` | `order_mode=dash` nao exercitado |
| BE-082 | **verified** | `E1 E12` | o override por `project_id` — a familia D-01/D-16/D-29 — esta fechado: `project_id` no corpo e IGNORADO e `X-Project-Id` so vale com participacao. `importing_id` como filtro nao foi exercitado |
| BE-083 | migrated | `M2` | autocomplete de escolha de projeto nao exercitado (o seletor da toolbar aparece na tela) |
| BE-084 | migrated | `M2` | formulario de cadastro/edicao nao aberto |
| BE-085 | migrated | `M4` | criar projeto dispara `LinkDefaultMembersJob` e `SeedGlobalTemplatesJob`; sem worker Sidekiq de pe (medido: `Sidekiq::ProcessSet` = 0) o projeto ficaria pela metade no banco COMPARTILHADO. Nao executei de proposito |
| BE-086 | migrated | `M4` | criar projeto dispara `LinkDefaultMembersJob` e `SeedGlobalTemplatesJob`; sem worker Sidekiq de pe (medido: `Sidekiq::ProcessSet` = 0) o projeto ficaria pela metade no banco COMPARTILHADO. Nao executei de proposito |
| BE-087 | migrated | `M4` | criar projeto dispara `LinkDefaultMembersJob` e `SeedGlobalTemplatesJob`; sem worker Sidekiq de pe (medido: `Sidekiq::ProcessSet` = 0) o projeto ficaria pela metade no banco COMPARTILHADO. Nao executei de proposito |
| BE-088 | migrated | `M4` | criar projeto dispara `LinkDefaultMembersJob` e `SeedGlobalTemplatesJob`; sem worker Sidekiq de pe (medido: `Sidekiq::ProcessSet` = 0) o projeto ficaria pela metade no banco COMPARTILHADO. Nao executei de proposito |
| BE-089 | **verified** | `E13 E12` | `PATCH /projects/:id/bi` de false para true gerou a versao 27906 na trilha, `item_type: Project`, `event: update`, com autor nomeado; o no-op (false->false) NAO gerou versao |
| BE-090 | migrated | `M2` | registro de progresso de onboarding nao exercitado |
| BE-091 | migrated | `M4` | remover projeto e «limpar projeto de treinamento» sao destrutivos no banco compartilhado |
| BE-092 | migrated | `M4` | remover projeto e «limpar projeto de treinamento» sao destrutivos no banco compartilhado |
| BE-093 | migrated | `M2` | `PATCH /:id/safegold_management` nao alternado (a marca aparece na tela e nas 6 empresas por leitura derivada) |
| BE-094 | **verified** | `E13 E12` | `PATCH /projects/:id/bi` alterna e PERSISTE (`has_bi` false -> true -> false, conferido por `GET`), e entra na trilha |
| BE-095 | migrated | `M2` | geracao de `smart_id`/`integration_key`/`color` so se prova criando projeto (ver BE-085) |
| BE-096 | migrated | `M2` | upload de avatar do projeto nao exercitado |
| BE-097 | **verified** | `E8 E9 E12` | a observacao de disponibilidade (rich text) chega no `GET /api/v1/availability` como `observation_html` e e renderizada nas duas telas — painel e detalhe do projeto |
| BE-098 | **verified** | `E1 E2 E12` | `current_project!` revalidado a cada request: `X-Project-Id` de projeto alheio -> 404 `PROJECT_NOT_FOUND`, identico ao inexistente; preferencia gravada do usuario removido do projeto foi LIMPA (`current_project_id` virou nil) |
| BE-099 | **verified** | `E2 E12` | as 3 condicoes viraram regra de SERVIDOR: readonly -> 403; dono -> 403 OWNER_PROTECTED; a si mesmo -> 403 SELF_REMOVAL. Quem cria: OG/Admin/Gerente 201, Colaborador 403 ROLE_REQUIRED, readonly 403 READONLY_RESTRICTED (DEC-18.5) |
| BE-100 | migrated | `M2` | aba «Projetos» do detalhe do usuario nao exercitada (e do bloco auth-users) |
| BE-101 | **verified** | `E1 E12` | as rotas mortas do legado nao existem: id de projeto alheio e id inexistente respondem o MESMO 404, sem virar oraculo de id |
| BE-102 | **verified** | `E1 E8 E9 E12` | `GET /project_carrier_connections` 200 escopado; tela «Portadores do projeto» com os 5 conectados |
| BE-103 | migrated | `M2` | conectar/desconectar (`PUT batch`) so foi exercitado pela recusa do readonly (403) |
| BE-104 | **verified** | `E1 E12` | `GET /project_carrier_connections/candidates` 200, escopado por `current_project!` |
| BE-105 | migrated | `M2` | `DELETE` de uma conexao isolada nao exercitado |
| BE-106 | migrated | `M2` | conexoes projeto<->indicador: a tela e do bloco `indicators` (S10); nao exercitadas aqui |
| BE-107 | migrated | `M2` | conexoes projeto<->indicador: a tela e do bloco `indicators` (S10); nao exercitadas aqui |
| BE-108 | migrated | `M2` | conexoes projeto<->indicador: a tela e do bloco `indicators` (S10); nao exercitadas aqui |
| BE-109 | migrated | `M2` | conexoes projeto<->indicador: a tela e do bloco `indicators` (S10); nao exercitadas aqui |
| BE-110 | **verified** | `E1 E8 E9 E12` | arvore do projeto corrente, ordenada, em UMA consulta; projeto zerado nao produz SQL invalido (`current_project!` aborta antes) |
| BE-111 | migrated | `M2` | `available_parents` nao exercitado |
| BE-112 | migrated | `M2` | criar/editar padrao do projeto com payload valido nao exercitado |
| BE-113 | **verified** | `E10 E11 E12` | ativar e desativar rodados de verdade: o `POST .../deactivate` respondeu 202 e TRAVOU os 6 nos da subarvore; o job executado (`perform_now`) desativou, reconsolidou os totais e LIBEROU a trava (`travados=0`); o `activate` devolveu os 17 ativos e os valores originais (`value=-7177788.24 virtual=13326438.66`) |
| BE-114 | **verified** | `E10 E11 E12` | ativar e desativar rodados de verdade: o `POST .../deactivate` respondeu 202 e TRAVOU os 6 nos da subarvore; o job executado (`perform_now`) desativou, reconsolidou os totais e LIBEROU a trava (`travados=0`); o `activate` devolveu os 17 ativos e os valores originais (`value=-7177788.24 virtual=13326438.66`) |
| BE-115 | migrated | `M5` | remover padrao (assincrono) nao executado: e destrutivo e o banco e compartilhado |
| BE-116 | **verified** | `E10 E11 E12` | o recalculo em cascata rodou nos dois sentidos e os numeros voltaram identicos ao ponto de partida — e o que prova que a cascata e reversivel e nao «gruda» estado |
| BE-117 | **verified** | `E1 E8 E9 E12` | `GET /api/v1/availability` autenticado e escopado — o D-01, que no legado era IDOR sem sessao nenhuma. Sem credencial: 401. Projeto alheio: 404 |
| BE-118 | **verified** | `E1 E8 E9 E12` | garantias escopadas; `available_carriers` 200; tela com as 2 garantias do projeto e valores em pt-BR |
| BE-119 | **verified** | `E1 E7 E12` | `GET/PUT/DELETE /project_guarantees/<de outro projeto>` -> 404 identico ao inexistente; `POST` sem os campos -> 400 nomeando `carrier_id`, `guarantee_type_id` e `value` |
| BE-700 | **verified** | `E3 E6 E8 E9 E12` | `GET /project_guarantee_types` com ordenacao 200; tela com os 8 tipos, a marca «provisorio» (DEC-86) e a coluna EM USO |
| BE-701 | migrated | `M2` | drawer e create/update de tipo de garantia nao exercitados |
| BE-702 | migrated | `M2` | drawer e create/update de tipo de garantia nao exercitados |
| BE-703 | migrated | `M2` | drawer e create/update de tipo de garantia nao exercitados |
| BE-704 | migrated | `M2` | drawer e create/update de tipo de garantia nao exercitados |
| BE-705 | **verified** | `E4 E12` | `DELETE /project_guarantee_types/<em uso>` -> 422 «tem 6 garantia(s) de projeto vinculado(s)»; ProjectGuaranteeType=8 antes e depois |
| BE-706 | migrated | `M2` | as rotas mortas do legado nao foram sondadas uma a uma |

### availability — backend (BE-120 … BE-149)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| BE-120 | **verified** | `E1 E8 E9 E12` | a grade de um dia: `company_id` de empresa de OUTRO projeto responde 422 «Empresa invalida para este projeto» — e o id INEXISTENTE responde exatamente a mesma coisa, entao nao ha oraculo |
| BE-121 | dropped | `-` | `dropped` no Phase 3; nada a verificar |
| BE-122 | **verified** | `E10 E12` | lancamento duplicado -> 422 «Ja existe lancamento para este padrao, nesta data e nesta empresa» e NADA foi destruido (AvailabilityEntry=4233 antes e depois); consolidacao nao e lancavel (`company_id` obrigatorio -> 400) |
| BE-123 | **verified** | `E1 E12` | `PUT`/`DELETE` de lancamento de outro projeto -> mesma resposta do id inexistente |
| BE-124 | **verified** | `E1 E12` | `PUT`/`DELETE` de lancamento de outro projeto -> mesma resposta do id inexistente |
| BE-125 | **verified** | `E8 E10 E12` | a consolidacao geral (company_id nulo) e uma linha propria, com rotulo «Consolidacao geral — soma bruta» na tela, e nao aceita lancamento |
| BE-126 | **verified** | `E8 E12` | no com filhos soma os filhos com sinal e respeita `is_cumulative`: 1.2 = 4.056.460,20 + 491.359,41 = 4.547.819,61, deixando de fora os 2.668.605,80 da «Carteira cedida», marcada «Nao soma» |
| BE-127 | migrated | `M1` | a correcao por dias uteis aparece na tela («base R$ 1.025.550,83» em 1.1.2 e em 2.3) e o golden test cobre a formula; o NUMERO contra producao depende da carga |
| BE-128 | **verified** | `E8 E12` | as duas semanticas de soma coexistem com ROTULO (DEC-26/DEC-27): a grade mostra `value` (2 Compromissos -R$ 7.177.788,24) e o cartao mostra `virtual_value` sob «SALDO ACUMULADO» (R$ 13.326.438,66). Conferido contra `sfg/app/models/availability_entry.rb:186-223`: a formula do ai9 e replica linha a linha, inclusive a dupla aplicacao de sinal do legado |
| BE-129 | **verified** | `E10 E11 E12` | a cascata roda dentro do job e e atomica: apos desativar e reativar, os 4233 lancamentos e os valores do no 2 voltaram identicos |
| BE-130 | **verified** | `E10 E12` | LER a grade nao cria registro (DC-30): 3 leituras em datas sem lancamento (2026-09-15/16) e a contagem ficou em 833 no projeto |
| BE-131 | migrated | `M2` | validacoes e derivacoes da entrada so parcialmente exercitadas (obrigatoriedade de `company_id` e o indice unico) |
| BE-132 | **verified** | `E3 E8 E9 E12` | catalogo global de padroes: leitura 200 nos 5 papeis (DEC-18.4, o formulario do projeto consome o padrao); tela com os 16 padroes em 3 niveis |
| BE-133 | migrated | `M2` | show/new/edit do padrao global nao exercitados |
| BE-134 | **verified** | `E3 E12` | `POST /availability_templates`: 201 para OG/Admin/Gerente, 403 ROLE_REQUIRED para Colaborador, 403 READONLY_RESTRICTED para readonly — a linha `R*` da matriz. Os 3 criados foram removidos (220 antes e depois) |
| BE-135 | **verified** | `E3 E12` | `PUT`: 200 para Gerente, 403 para Colaborador. O titulo alterado foi restaurado |
| BE-136 | migrated | `M4` | exclusao de padrao global e destrutiva no banco compartilhado |
| BE-137 | **verified** | `E10 E12` | `PUT /availability_templates/:id/position` reordenou de verdade: 1.1.2 virou 1.1.1 e o irmao desceu; a numeracao dos 16 nos foi recalculada e voltou ao original quando reordenei de volta |
| BE-138 | **verified** | `E10 E12` | `PUT /availability_templates/:id/position` reordenou de verdade: 1.1.2 virou 1.1.1 e o irmao desceu; a numeracao dos 16 nos foi recalculada e voltou ao original quando reordenei de volta |
| BE-139 | **verified** | `E10 E12` | obrigatoriedade HIERARQUICA no servidor: marcar 1.2.1 «Carteira propria» como obrigatoria, tendo o pai 1.2 nao-obrigatorio, responde 422 e o estado real NAO muda (`mandatory=false` depois da tentativa) |
| BE-140 | **verified** | `E1 E8 E9 E12` | arvore do projeto; id inexistente -> 404 |
| BE-141 | migrated | `M2` | new/edit do padrao do projeto nao exercitados |
| BE-142 | migrated | `M2` | criar/atualizar padrao do projeto com payload valido nao exercitados |
| BE-143 | migrated | `M2` | criar/atualizar padrao do projeto com payload valido nao exercitados |
| BE-144 | **verified** | `E10 E11 E12` | ativacao e desativacao: padrao OBRIGATORIO responde 422 «Este padrao e obrigatorio e nao pode ser desativado» (fecha D-04/D-33, que no legado vivia num metodo que nenhum caminho chamava); Colaborador 202 (a matriz da CRUD de projeto a ele), readonly 403 |
| BE-145 | **verified** | `E10 E11 E12` | ativacao e desativacao: padrao OBRIGATORIO responde 422 «Este padrao e obrigatorio e nao pode ser desativado» (fecha D-04/D-33, que no legado vivia num metodo que nenhum caminho chamava); Colaborador 202 (a matriz da CRUD de projeto a ele), readonly 403 |
| BE-146 | migrated | `M4` | remocao de padrao do projeto e destrutiva |
| BE-147 | **verified** | `E11 E12` | o bloqueio em cascata funciona nos dois sentidos: 6 nos com `locked_message` «Este padrao foi desativado e fica bloqueado ate a atualizacao dos lancamentos terminar», e o `ensure` do job liberou todos |
| BE-148 | migrated | `M1` | `get_values_hash` replicado e conferido contra o legado por leitura; o numero contra producao depende da carga |
| BE-149 | **verified** | `E1 E12` | sem dupla serializacao: o corpo do `GET /api/v1/availability` e OBJETO, nao string JSON dentro de JSON |

### companies-carriers — frontend (FE-050 … FE-079)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| FE-050 | **verified** | `E8 E9 E12` | menu por papel funcionando na tela: Colaborador em `/carriers`, `/segments` e `/projects` cai em `/dashboard`; Admin ve as 3 |
| FE-051 | **verified** | `E8 E9 E14 E12` | lista de Empresas em light, dark e 390x844; carregando, vazio (com o termo citado) e falha («Nao foi possivel carregar») todos renderizados |
| FE-052 | **verified** | `E8 E14 E12` | `useDebouncedSearch` existe, e compartilhado (8 telas o consomem) e FUNCIONA na tela: digitar «zzz-nada-existe-zzz» refaz a consulta e muda o estado. Sai de `pending` |
| FE-053 | **verified** | `E5 E8 E12` | `components/ui/Pagination.tsx` na tela (primeiro/anterior/POR PAGINA/1 de 1/proximo/ultimo) e o servidor recebe o limite de verdade: `per_page=2` devolve 2 com `X-Total-Count: 5`. 11 testes em `Pagination.test.tsx`. Sai de `pending` |
| FE-054 | **verified** | `E8 E12` | so os filtros que existem estao na tela: nao ha `kind` nem `state` fantasmas (DC-05) |
| FE-055 | **verified** | `E8 E12` | a linha comunica o bloqueio: cadeado com `aria-label` de uso no lugar da lixeira quando ha vinculo — o criterio do botao e o mesmo do servidor (422) |
| FE-056 | migrated | `M2` | o drawer de criar/editar Empresa nao foi aberto |
| FE-057 | migrated | `M2` | o dialogo de exclusao a partir da lista nao foi confirmado na tela (o 422 do servidor esta provado) |
| FE-058 | **verified** | `E8 E9 E12` | detalhe de Empresa com data formatada («26/08/2026 as 09:54»), resumo de portadores/limites e a marca derivada do projeto |
| FE-059 | **verified** | `E8 E12` | a aba «Controles de Risco» NAO foi portada (DC-06) — nao ha aba vazia na tela |
| FE-060 | **verified** | `E5 E6 E8 E9 E12` | lista de Portadores com as 6 colunas e paginacao — que o legado nao tinha |
| FE-061 | **verified** | `E6 E8 E12` | `components/ui/DataTable.tsx` existe, e compartilhado e ordena de verdade: o cabecalho EMPRESA mostra a seta de ordenacao e as chaves que davam 500 no legado respondem 200. 26 testes entre `DataTable`, `dataTableArraste` e `dataTableTransbordo`. Sai de `pending` |
| FE-062 | **verified** | `E14 E8 E12` | o vazio CITA o termo: «Nenhum resultado para «zzz-nada-existe-zzz»» com «Limpar busca», em Empresas, Portadores e Fornecedores |
| FE-063 | **verified** | `E8 E12` | linha de portador com fallback e navegacao para o detalhe |
| FE-064 | migrated | `M2` | formulario de portador e o derivado «% contas subordinadas» nao exercitados |
| FE-065 | migrated | `M2` | formulario de portador e o derivado «% contas subordinadas» nao exercitados |
| FE-066 | **verified** | `E8 E12` | `MoneyInput.tsx` e `NumericInput.tsx` (que exporta `PercentInput`) existem, sao compartilhados e tem 18 testes verdes; os valores em pt-BR aparecem corretos na tela (R$ 2.269.754,50). Sai de `pending` |
| FE-067 | migrated | `M2` | upload de logo do Portador nao exercitado |
| FE-068 | **verified** | `E8 E9 E12` | detalhe de Portador ALCANCAVEL (D-22): 3 abas — Identificacao, Estrutura de cotas, Relacoes |
| FE-069 | **verified** | `E8 E9 E12` | lista de Fornecedores com documento mascarado, chave de integracao e contagem de renegociacoes |
| FE-070 | **verified** | `E8 E12` | linha de fornecedor com iniciais no lugar do logo e SEM acao inerte (DC-07) |
| FE-071 | migrated | `M2` | alternancia CPF/CNPJ, mascara, autopreenchimento e upload de logo sao interacoes de formulario que nao exercitei |
| FE-072 | migrated | `M2` | alternancia CPF/CNPJ, mascara, autopreenchimento e upload de logo sao interacoes de formulario que nao exercitei |
| FE-073 | migrated | `M2` | alternancia CPF/CNPJ, mascara, autopreenchimento e upload de logo sao interacoes de formulario que nao exercitei |
| FE-074 | migrated | `M2` | alternancia CPF/CNPJ, mascara, autopreenchimento e upload de logo sao interacoes de formulario que nao exercitei |
| FE-075 | **verified** | `E8 E9 E12` | lista de Grupos de Portadores renderizada. **Com o numero errado na coluna PORTADORES** — ver defeito P4-01 |
| FE-076 | migrated | `M2` | drawer de grupo nao aberto |
| FE-077 | **verified** | `E8 E9 E12` | Segmentos: lista, contagem de projetos coerente (3+7+2 = 12) e criacao habilitada aos papeis certos |
| FE-078 | **verified** | `E8 E9 E12` | Subsegmentos com texto proprio (nao o placeholder herdado de Segmento) e contagem 1 por projeto, somando 12 |
| FE-079 | **verified** | `E8 E14 E12` | `components/ui/States.tsx` e `AsyncSection.tsx` existem, sao compartilhados e os QUATRO estados foram vistos renderizando: carregando, vazio, erro («Nao foi possivel carregar» + «Tentar de novo») e cheio, em light e dark. 11 testes em `CatalogScreen.test.tsx`. Sai de `pending` |

### projects — frontend (FE-080 … FE-119)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| FE-080 | **verified** | `E8 E9 E12` | lista Projetos em light/dark/390; Gerente ve 6, Admin ve 12 (DEC-99) |
| FE-081 | migrated | `M2` | busca incremental de projetos nao exercitada na tela |
| FE-082 | **verified** | `E8 E12` | widget de projeto com chave de integracao, estado, marca e contagem de membros |
| FE-083 | migrated | `M2` | alerta de atualizacao em andamento e remocao pela lista nao exercitados (dependem de job com worker) |
| FE-084 | migrated | `M2` | alerta de atualizacao em andamento e remocao pela lista nao exercitados (dependem de job com worker) |
| FE-085 | migrated | `M2` | o formulario de projeto (campos, seletor de responsavel, logo, datepicker, salvamento e erros) nao foi aberto — criar projeto e destrutivo no banco compartilhado |
| FE-086 | migrated | `M2` | o formulario de projeto (campos, seletor de responsavel, logo, datepicker, salvamento e erros) nao foi aberto — criar projeto e destrutivo no banco compartilhado |
| FE-087 | migrated | `M2` | o formulario de projeto (campos, seletor de responsavel, logo, datepicker, salvamento e erros) nao foi aberto — criar projeto e destrutivo no banco compartilhado |
| FE-088 | migrated | `M2` | o formulario de projeto (campos, seletor de responsavel, logo, datepicker, salvamento e erros) nao foi aberto — criar projeto e destrutivo no banco compartilhado |
| FE-089 | migrated | `M2` | o formulario de projeto (campos, seletor de responsavel, logo, datepicker, salvamento e erros) nao foi aberto — criar projeto e destrutivo no banco compartilhado |
| FE-090 | migrated | `M2` | o formulario de projeto (campos, seletor de responsavel, logo, datepicker, salvamento e erros) nao foi aberto — criar projeto e destrutivo no banco compartilhado |
| FE-091 | **verified** | `E8 E9 E12` | detalhe do projeto com as 4 abas e o cartao de dados completo |
| FE-092 | migrated | `M2` | o switch «Gerido pela Safegold» nao foi acionado na tela |
| FE-093 | **verified** | `E13 E8 E12` | o switch «BI contratado» tem endpoint proprio que ALTERNA e PERSISTE, e a alteracao entra na trilha com autor |
| FE-094 | migrated | `M2` | «Acoes rapidas» nao exercitadas |
| FE-095 | **verified** | `E2 E8 E12` | aba Membros: os 4 membros do projeto vem com `is_project_owner` marcado no dono — o rotulo implicito do legado virou campo explicito |
| FE-096 | migrated | `M2` | adicionar/remover membro PELA TELA nao exercitado; as regras estao provadas no servidor (BE-099) |
| FE-097 | migrated | `M2` | adicionar/remover membro PELA TELA nao exercitado; as regras estao provadas no servidor (BE-099) |
| FE-098 | **verified** | `E8 E12` | cartoes «Portadores» e «Observacao - Disponibilidade» renderizados com o rich text do projeto |
| FE-099 | **verified** | `E8 E12` | cartoes «Portadores» e «Observacao - Disponibilidade» renderizados com o rich text do projeto |
| FE-100 | **verified** | `E8 E9 E12` | tela «Portadores do projeto» com Conectar/Desconectar e os 5 conectados marcados |
| FE-101 | **verified** | `E8 E9 E12` | tela «Portadores do projeto» com Conectar/Desconectar e os 5 conectados marcados |
| FE-102 | migrated | `M2` | «Indicadores especificos» e do bloco `indicators` |
| FE-103 | migrated | `M2` | «Indicadores especificos» e do bloco `indicators` |
| FE-104 | migrated | `M2` | «Indicadores especificos» e do bloco `indicators` |
| FE-105 | **verified** | `E1 E8 E12` | o projeto corrente e resolvido NO SERVIDOR e revalidado a cada request; trocar de usuario troca o escopo (Gerente ve 6 projetos, Colaborador 4) sem cache mentiroso |
| FE-106 | **verified** | `E1 E8 E12` | o projeto corrente e resolvido NO SERVIDOR e revalidado a cada request; trocar de usuario troca o escopo (Gerente ve 6 projetos, Colaborador 4) sem cache mentiroso |
| FE-107 | **verified** | `E8 E9 E12` | tela «Disponibilidades» do projeto: arvore de 3 niveis, coluna N, natureza, estado e marcadores |
| FE-108 | **verified** | `E8 E12` | estados do widget visiveis: Global x Especifico, Ativo, Obrigatorio, Corrigido, Nao soma |
| FE-109 | migrated | `M2` | drawer de padrao e a dependencia «Faz parte de» x niveis nao exercitados |
| FE-110 | migrated | `M2` | drawer de padrao e a dependencia «Faz parte de» x niveis nao exercitados |
| FE-111 | **verified** | `E10 E11 E12` | ativar/desativar pela lista chega ao servidor: 202 + trava, job libera, e o obrigatorio e recusado com 422 |
| FE-112 | migrated | `M4` | remover padrao e destrutivo |
| FE-113 | **verified** | `E8 E9 E12` | «Garantias do Projeto» com portador, grupo, tipo e valor em pt-BR |
| FE-114 | **verified** | `E8 E9 E12` | «Garantias do Projeto» com portador, grupo, tipo e valor em pt-BR |
| FE-115 | migrated | `M2` | formulario de garantia nao aberto |
| FE-116 | **verified** | `E8 E9 E12` | «Tipos de garantia» com a marca «provisorio» (DEC-86), ORDEM e EM USO |
| FE-117 | **verified** | `E8 E9 E12` | «Tipos de garantia» com a marca «provisorio» (DEC-86), ORDEM e EM USO |
| FE-118 | migrated | `M2` | aba «Projetos» no detalhe do usuario e do bloco auth-users |
| FE-119 | **verified** | `E8 E12` | gating por papel provado nos dois sentidos: Colaborador redirecionado de 3 telas, Admin entra nas 3 |

### availability — frontend (FE-120 … FE-149)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| FE-120 | **verified** | `E8 E9 E12` | Painel de Disponibilidade: duas colunas, seletor de visao com «Consolidacao geral» e calendario pt-BR marcando com ponto os dias que tem lancamento (4, 11, 18, 25, 26 de agosto) |
| FE-121 | **verified** | `E8 E9 E12` | Painel de Disponibilidade: duas colunas, seletor de visao com «Consolidacao geral» e calendario pt-BR marcando com ponto os dias que tem lancamento (4, 11, 18, 25, 26 de agosto) |
| FE-122 | **verified** | `E8 E9 E12` | Painel de Disponibilidade: duas colunas, seletor de visao com «Consolidacao geral» e calendario pt-BR marcando com ponto os dias que tem lancamento (4, 11, 18, 25, 26 de agosto) |
| FE-123 | **verified** | `E9 E12` | variante 390x844 renderizada, com o seletor de data em cartao proprio |
| FE-124 | **verified** | `E8 E9 E12` | «Lancamentos com valor: 60» — contador de valor diferente de zero |
| FE-125 | **verified** | `E8 E9 E12` | um cartao por padrao base sob o rotulo SALDO ACUMULADO, com o sinal NO NUMERO (a grade mostra -R$ 7.177.788,24 em vermelho) em vez do modulo + cor do legado |
| FE-126 | **verified** | `E8 E12` | bloco «Observacao» com o rich text do projeto; some quando vazio |
| FE-127 | **verified** | `E8 E9 E12` | grade hierarquica recursiva de 3 niveis com titulo posicional (1, 1.1, 1.1.1) e valor |
| FE-128 | migrated | `M2` | estados da grade, campo monetario inline, salvamento por blur, lixeira e input bloqueado sao interacoes de edicao que nao exercitei na tela |
| FE-129 | migrated | `M2` | estados da grade, campo monetario inline, salvamento por blur, lixeira e input bloqueado sao interacoes de edicao que nao exercitei na tela |
| FE-130 | migrated | `M2` | estados da grade, campo monetario inline, salvamento por blur, lixeira e input bloqueado sao interacoes de edicao que nao exercitei na tela |
| FE-131 | migrated | `M2` | estados da grade, campo monetario inline, salvamento por blur, lixeira e input bloqueado sao interacoes de edicao que nao exercitei na tela |
| FE-132 | migrated | `M2` | estados da grade, campo monetario inline, salvamento por blur, lixeira e input bloqueado sao interacoes de edicao que nao exercitei na tela |
| FE-133 | **verified** | `E8 E12` | os marcadores estao na tela e legiveis: «Nao soma» em 1.2.2 e «base R$ ...» (valor corrigido) em 1.1.2 e 2.3 — no legado eram um `*` e um `@` |
| FE-134 | **verified** | `E8 E12` | os marcadores estao na tela e legiveis: «Nao soma» em 1.2.2 e «base R$ ...» (valor corrigido) em 1.1.2 e 2.3 — no legado eram um `*` e um `@` |
| FE-135 | **verified** | `E8 E9 E12` | «Tipos de disponibilidade» (catalogo global) com N, natureza, PRAZO e marcadores |
| FE-136 | migrated | `M2` | busca com debounce e estados da lista de templates globais nao exercitados nesta tela especifica |
| FE-137 | migrated | `M2` | busca com debounce e estados da lista de templates globais nao exercitados nesta tela especifica |
| FE-138 | **verified** | `E8 E12` | linha com indentacao por nivel e a numeracao hierarquica correta |
| FE-139 | migrated | `M2` | helper e card de detalhe do template nao abertos |
| FE-140 | migrated | `M2` | helper e card de detalhe do template nao abertos |
| FE-141 | **verified** | `E3 E12` | o controle do botao «Cadastrar» tem correspondente no SERVIDOR: Colaborador 403, readonly 403 |
| FE-142 | **verified** | `E8 E9 E12` | arvore do projeto renderizada, com «Mostrar desativados» ligado por padrao — que e o que o spec pede («ativos e inativos», linhas 416 e 437-440) |
| FE-143 | **verified** | `E8 E9 E12` | arvore do projeto renderizada, com «Mostrar desativados» ligado por padrao — que e o que o spec pede («ativos e inativos», linhas 416 e 437-440) |
| FE-144 | **verified** | `E10 E11 E12` | o toggle e o menu de contexto chegam ao servidor (202 + trava + job) |
| FE-145 | **verified** | `E10 E11 E12` | o toggle e o menu de contexto chegam ao servidor (202 + trava + job) |
| FE-146 | **verified** | `E8 E9 E12` | estados visuais presentes: Global, Especifico, Ativo, Obrigatorio, Corrigido |
| FE-147 | migrated | `M2` | helper, auto-preenchimento de niveis e botao de atualizar nao exercitados |
| FE-148 | migrated | `M2` | helper, auto-preenchimento de niveis e botao de atualizar nao exercitados |
| FE-149 | migrated | `M2` | helper, auto-preenchimento de niveis e botao de atualizar nao exercitados |

### dados (DB-050 … DB-135)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| DB-050 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-051 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-052 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-053 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-054 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-055 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-056 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-057 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-058 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-059 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-060 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-061 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-062 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-063 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-064 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-065 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-066 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-067 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-068 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-069 | **verified** | `E4 E12` | JA ERA `verified`, RE-CONFERIDO: o banco recusa apagar portador com `risk_controls` — a mensagem do 422 conta 14 limites de risco, ou seja a FK esta la e BLOQUEIA, nao cascateia |
| DB-070 | blocked | `-` | `blocked` no Phase 3, dono fora deste bloco (S6/S9). Re-conferido em 26/08: continuam dependendo das tabelas de recebiveis e renegociacoes |
| DB-071 | blocked | `-` | `blocked` no Phase 3, dono fora deste bloco (S6/S9). Re-conferido em 26/08: continuam dependendo das tabelas de recebiveis e renegociacoes |
| DB-072 | migrated | `M6` | schema conferido pelas migrations e pelos specs; o que se comporta ja esta provado nos BE correspondentes. `verified` de tabela exige a CARGA rodada e a reconciliacao (DEC-102) |
| DB-080 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-081 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-082 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-083 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-084 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-085 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-086 | **verified** | `E2 E12` | `memberships` com unico `(user_id, project_id)` provado por uso: recriar a participacao removida devolveu 201 e a contagem voltou a 30; e a linha de membership e A VERDADE do escopo — removida a participacao, o projeto sumiu da lista do usuario na mesma requisicao |
| DB-087 | **verified** | `E2 E12` | `users.current_project_id` e resolvido no servidor: ao remover a participacao, a coluna do usuario foi LIMPA (virou nil) — nao ficou apontando para projeto de onde ele saiu |
| DB-088 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-089 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-090 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-091 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-092 | migrated | `M6` | idem — schema por migration + spec; a paridade de dado depende da carga |
| DB-120 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-121 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-122 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-123 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-124 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-125 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-126 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-127 | **verified** | `E8 E10 E12` | `availability_entries.virtual_value` esta gravado e e o que alimenta o cartao SALDO ACUMULADO; conferi o valor GRAVADO contra o RECALCULADO nos 3 nos base e bateu nos 3 |
| DB-128 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-129 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-130 | migrated | `M1` | `has_safegold_management` denormalizado no lancamento: sem a carga nao ha com o que comparar |
| DB-131 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-132 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-133 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-134 | migrated | `M6` | schema/STI conferido por migration e spec |
| DB-135 | migrated | `M6` | schema/STI conferido por migration e spec |

### operação (OPS-050 … OPS-129)

| ID | Estado final | Prova | Como verifiquei / por que não |
| -- | ------------ | ----- | --------------------------- |
| OPS-050 | migrated | `M3` | ReceitaWS: a chave em `Credential` e a validacao estao no lugar; a consulta real devolveu 503 (sem rede/credencial nesta maquina) com a mensagem certa |
| OPS-051 | migrated | `M2` | upload de logo nao exercitado |
| OPS-052 | migrated | `M1` | importadores: so a carga prova |
| OPS-053 | migrated | `M1` | importadores: so a carga prova |
| OPS-054 | migrated | `M2` | seed de referencia nao reexecutado (o de demonstracao esta no ar e foi a base de tudo que verifiquei) |
| OPS-055 | migrated | `M4` | rake de correcao de dados nao rodado no banco compartilhado |
| OPS-056 | **verified** | `E12` | a busca por ILIKE com bind: `zzz-nada-existe-zzz` e os termos com aspas nao quebram a consulta; 271 exemplos de rspec verdes em banco proprio |
| OPS-057 | **verified** | `E12` | as 27 UFs como constante: a cidade do portador vem formatada «Sao Paulo, SP» na tela e no detalhe |
| OPS-058 | migrated | `DEFEITO` | REPROVADO junto com BE-074: o `counter_cache` existe, mas o `delete_all` de `db/seeds/demo/reset.rb:152` o dessincroniza. Ver **P4-01** |
| OPS-080 | migrated | `M4` | `LinkDefaultMembersJob` so roda criando projeto |
| OPS-081 | migrated | `M5` | semear/propagar templates globais exige worker Sidekiq de pe — medido: `Sidekiq::ProcessSet` = 0 nesta maquina |
| OPS-082 | **verified** | `E11 E12` | `ActivateProjectTemplateJob` executado: reativou os 6 nos, recalculou e devolveu `travados=0` |
| OPS-083 | **verified** | `E11 E12` | `DeactivateProjectTemplateJob` executado: desativou os 6, reconsolidou os totais e liberou a trava no `ensure` |
| OPS-084 | migrated | `M4` | job de REMOCAO e destrutivo; nao executado no banco compartilhado |
| OPS-085 | migrated | `M4` | espelho usuario -> todos os projetos: mexeria em participacao alheia |
| OPS-086 | **verified** | `E13 E12` | a trilha e o `paper_trail` e ela FUNCIONA: a alteracao do projeto gerou a versao 27906 com `item_type: Project`, `event: update` e autor nomeado; o no-op nao gerou versao (nao polui a trilha) |
| OPS-087 | migrated | `M5` | progresso ao vivo por Action Cable exige o job rodando por Sidekiq — rodei por `perform_now`, que nao passa pelo canal |
| OPS-088 | migrated | `M2` | variantes do logo do projeto nao exercitadas |
| OPS-120 | migrated | `M5` | semear/propagar templates globais exige worker Sidekiq de pe — medido: `Sidekiq::ProcessSet` = 0 nesta maquina |
| OPS-121 | migrated | `M5` | semear/propagar templates globais exige worker Sidekiq de pe — medido: `Sidekiq::ProcessSet` = 0 nesta maquina |
| OPS-122 | **verified** | `E11 E12` | `ActivateProjectTemplateJob` executado: reativou os 6 nos, recalculou e devolveu `travados=0` |
| OPS-123 | **verified** | `E11 E12` | `DeactivateProjectTemplateJob` executado: desativou os 6, reconsolidou os totais e liberou a trava no `ensure` |
| OPS-124 | migrated | `M4` | job de REMOCAO e destrutivo; nao executado no banco compartilhado |
| OPS-125 | migrated | `M6` | `grep` por `ProgressJob`/`Delayed::Job` devolve zero; nao ha o que executar |
| OPS-126 | dropped | `-` | `dropped` no Phase 3 |
| OPS-127 | migrated | `M5` | progresso ao vivo por Action Cable exige o job rodando por Sidekiq — rodei por `perform_now`, que nao passa pelo canal |
| OPS-128 | migrated | `M5` | politica de retencao/retry so se observa com worker de pe |
| OPS-129 | migrated | `M4` | rake de conserto nao rodado |
