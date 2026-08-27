# Perguntas ao usuário — rodada 1 (documento único)

> **DEC-23** pediu uma rodada completa de perguntas antes/durante o Phase 3. Duas metades foram
> compiladas em paralelo — uma a partir dos 5 mapas de bloco (`Q-01..Q-98`), outra a partir dos
> 20 `openspec/changes/*/proposal.md` (`F-01..F-51`). **Este arquivo é a fusão das duas**, e é o
> único que precisa ser respondido. Os dois de origem ficam no repositório só para auditoria.
>
> Cada entrada se sustenta sozinha: você **não precisa** ter lido mapa, proposal ou inventário.
> Todo contexto foi conferido abrindo o arquivo do legado (`/home/vinao/workspace/sfg`) ou da
> base ai9 — onde o material interno divergiu da fonte, **vale a fonte**, e a correção está na
> seção "Achados que não são pergunta".

---

## 1. Como responder

Escreva uma linha por pergunta: **`P-007: b`**, ou **`P-007: default`**, ou
**`P-007: b, mas só para lançamentos novos`**. Não precisa de mais nada.

**Não responder é escolher o default.** Toda entrada tem o campo **Default vigente** escrito
— se você pular a pergunta, é aquilo que vai ser construído. Em 4 entradas (P-002, P-020,
P-021, P-097) **não existe default**: elas param a fatia até você responder.

---

## 2. Placar

| | Antes da fusão | Depois da fusão |
| - | -------------- | --------------- |
| Perguntas dos mapas de bloco | 98 (`Q-01..Q-98`) | — |
| Perguntas do empacotamento | 51 (`F-01..F-51`) | — |
| **Total** | **149 entradas em 2 arquivos** | **117 perguntas em 1 arquivo** |

Como se chega de 149 a 117: **35 fusões** (a mesma decisão perguntada com dois números),
**1 desdobramento** (uma entrada que embutia duas decisões independentes) e
**2 recuperações** (perguntas que a metade das fatias descartou como "duplicata" e que **não
tinham par** do lado do mapa — ver seção 4).

### Por impacto, e é nesta ordem que elas estão

| Impacto | Antes | Depois | Faixa | O que significa |
| ------- | ----- | ------ | ----- | --------------- |
| `muda número na tela` | 16 + 11 | **18** | P-001 … P-018 | A resposta muda um valor que o cliente lê. Nenhuma dá para responder no automático |
| `muda comportamento observável` | 41 + 21 | **48** | P-019 … P-066 | Muda o que a tela faz, quem entra, ou o que fica gravado |
| `muda escopo` | 29 + 16 | **37** | P-067 … P-103 | Decide se algo é construído ou descartado |
| `só interno` | 12 + 3 | **14** | P-104 … P-117 | Retenção, esquema, nomes. O default resolve; a resposta melhora |

Sete entradas trocaram de faixa na fusão porque as duas metades as classificaram diferente.
O critério usado para desempatar: **o que muda se a resposta for diferente do default.** A
lista está na seção 4.

---

## 3. Comece por aqui

Com o prazo de **sexta, 28/08** e escopo completo aprovado (DEC-22), é esta seção que decide
o dia. São duas listas curtas.

### 3.1 As que travam código HOJE — alguém não consegue começar sem elas

| P | O que está parado | Onde |
| - | ----------------- | ---- |
| **P-097** | **O seed de demonstração não tem dono.** S18 criou `lib/tasks/demo.rake` **vazio**, S14 e S15 o consomem, **ninguém o preenche**. Sem ele as 20 fatias entregam telas vazias na sexta | `s18/tasks.md:108-111`, `s14/proposal.md:122`, `s15/tasks.md:88` |
| P-001 … P-004 | A **seção 5 inteira** de S11 — o motor de números das disponibilidades | `s11/tasks.md:31-33`, tarefas 5.3–5.7 e 6.5.8–6.5.10 |
| P-020, P-021, P-022, P-067 | **20 tarefas** de S12 — o ciclo de aceite de contrato inteiro | `s12/tasks.md:10, 34, 110-145, 230-245, 305-315` |
| P-015, P-016, P-032 | "Bloco 0 — nada de código antes" de S7 | `s7/tasks.md:21-25` |
| P-009, P-026, P-070, P-077 | Bloco 0 de S8; 9 IDs de `resource_kinds` atrás de um portão | `s8/tasks.md:22-28, 104, 146` |
| P-018, P-078 | Bloco 0 de S5; a tarefa 6.1 (`RiskEntry`) e o rótulo "Legado" de `FE-243` | `s5/tasks.md:20-23, 93, 117` |
| P-036, P-038, P-082, P-096 | Bloco 0 de S10 | `s10/tasks.md:26-31` |
| P-116 | Bloco 0 de S5, item 0.3: **escolher o padrão de paginação** e valer para os 14 endpoints de lista. "Não pode ficar meio a meio" | `s5/tasks.md:20` (0.3) |
| P-019 | S4 tarefa 1.19: *"não implementar as tabelas filhas antes da resposta"* | `s4/tasks.md:86-89` |
| P-091 | Portão de S13: 12 IDs e as tarefas 6.5–6.9 esperam **uma contagem** | `s13/tasks.md:26-30` |
| P-045 | S13 tarefa **1.1**, a primeira da fatia: `OPS-477` só existe se S12 responder | `s13/tasks.md:22-25` |
| P-099 | S13 tarefa 1.5 pergunta "S2 já entregou `Tracking`?" — e S2 não é o dono | `s13/tasks.md:37-39` |
| P-100 | Se S9 começar antes de S13, a base ganha um **terceiro** caminho de upload | `s13/proposal.md:178-183` |
| P-005 | S6 tarefa 5.5 — o backfill dos borderôs históricos | `s6/tasks.md:424-428` |
| P-102 | `LoginCarousel.tsx` é a **primeira tela** da demo e está com espaço reservado no lugar da arte | `frontend/src/components/LoginCarousel.tsx:11-16` |

### 3.2 As que mudam um número que o cliente JÁ vê

Todas as 18 primeiras (P-001 a P-018). O default delas é quase sempre "replicar o que está
lá" — o que significa que **o silêncio também é uma resposta**, e ela carrega o erro atual
para dentro do produto novo. Se você só tiver tempo para uma coisa hoje, é esta faixa.

Dentro dela, as três que mais valem a resposta por escrito:

- **P-009** — a fórmula que fatura. `receipt.rb:63` é a **única** fórmula de faturamento do
  sistema, e o legado não tem um único teste que a cubra.
- **P-005** — o valor de operação de risco dos borderôs históricos está errado **no banco**,
  não só no código. Decidir "copiar" é gravar número errado de propósito num banco novo.
- **P-015** — o subtipo decide em qual bucket de limite a operação entra, e hoje ele é
  escolhido pela **ordem de inserção de linhas** num cadastro.

---

## 4. Achados que não são pergunta

Trinta pontos em que o nosso próprio material (mapa de bloco ou proposal) afirmava uma coisa
e o código diz outra. **Não precisam de resposta** — são correções ao material, já aplicadas
dentro das entradas abaixo. Estão aqui porque cinco delas mudam a leitura de várias perguntas.

### 4.1 Os cinco que você precisa ver antes de responder qualquer coisa

**A-1 · Não existe gate de autorização em contratos. Hoje qualquer usuário autenticado
publica uma nova versão dos Termos de Uso.**
Os dois mapas afirmavam que `BE-335` "exige papel administrativo para publicar". Conferido
na fonte: `/home/vinao/workspace/sfg/app/controllers/pub/contracts_controller.rb` tem **101
linhas e zero ocorrências** de `before_action`, `may?`, `admin?`, `og?` ou `authorize`. O
único filtro é o herdado `lock_if_there_is_no_user` (`pub_application_controller.rb:12`), que
só exige estar logado. A action `create` (`:56-67`) instancia `Contract.new(contract_params)`,
carimba `creator = current_user` e salva. As rotas não têm constraint
(`config/routes.rb:30-31`). Isso reclassifica **P-022**: deixa de ser "confirmar um gate" e
vira **"criar o gate que nunca existiu"**. Some-se a isso o mass assignment de `id` e
`version` no mesmo `permit`.

**A-2 · `login_attempts` é passivo de LGPD adotado, não herdado.**
O mapa dizia que "o legado guardava IP e user-agent das tentativas de login, sem política".
Não guardava: no legado inteiro há **3 ocorrências** de `login_attempt`, e as três são o
método `invalid_login_attempt` em `engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:42,61,80`.
Não existe tabela. O único rastro é o contador `failed_attempts` do Devise
(`engines/auth19/db/migrate/20160409121830_create_users.rb:16`), sem IP e sem user-agent.
Quem tem a tabela é a **base ai9**: `backend/db/schema.rb:451-460` cria `login_attempts` com
`identifier`, `method`, `ip_address` (`inet`, `null: false`), `user_agent`, `success`,
`error_reason` e `user_id`, com 9 índices — e **nenhum job de expurgo**. Ou seja: o Safegold
**adota** esse passivo ao nascer sobre a base. Ver **P-104**.

**A-3 · Duas tabelas com dois donos: `charges` e `receipts`.**
`openspec/changes/s11-disponibilidades-cobrancas/proposal.md:200-208` diz, na seção
"Fronteiras", que a feature de cobranças e recibos **não é de S11** e lista os IDs como sendo
de S6 (`DB-162`…`DB-165`, `BE-187`…`BE-189`, `FE-179`…`FE-186`). Oitenta linhas depois,
`:283-290` reivindica `DB-583` (`charges`) e `DB-584` (`receipts`) para S11, "porque S11 é
dona das cobranças (DEC-15.1)". **São as mesmas duas tabelas com dois IDs de inventário
diferentes**, e o mesmo documento se contradiz. A conferência consolidada não pegou porque
ela compara **IDs**, não **tabelas** — o que significa que pode haver outras. Virou pergunta
em **P-098** porque alguém precisa dizer quem é dono antes das duas migrations existirem.

**A-4 · Colisão no de-para de `hierarchy_level` — é o contrato C3, o item de maior risco.**
`.migration-ai9/migration-map.md` manda OG→1, Admin→2, Gerente→3, Colaborador→4. Mas a base
já semeia, em `backend/app/models/user_type.rb:37-41`:
`OG`=1, `client`=2, `free`=4, `visitor`=5. Logo **Admin colide com `client`** e
**Colaborador colide com `free`**. E o DS0-4 decidiu "acrescentar sem remover" (porque
`UserType` é peça compartilhada e `visitor` é usado por `restrict_visitor_access!`), o que
torna a colisão **inevitável**. Dois papéis no mesmo nível fazem
`higher_than` (`where('hierarchy_level < ?', level)`) devolver conjuntos que ninguém espera —
num contrato onde inverter o sinal significa "dar poder de OG a um Colaborador". Ver **P-061**,
que por isso foi promovida de `só interno` para `muda comportamento observável`.

**A-5 · Três defeitos do legado que ninguém catalogou** — candidatos a `legacy-defects.md`:
- `TrackingsController#show` está quebrada em **três frentes**: `@tracking` nunca é carregado
  (`fetch_tracking`, `app/controllers/api/v1/trackings_controller.rb:54-56`, tem corpo **vazio**
  e nem é registrado como `before_action`), `Tracking` **não declara** associação `geolocation`
  (`app/models/tracking.rb`), e nada é salvo nem recalculado.
- `Indicator.prepare_ordering` (`app/models/indicator.rb:68-69`) devolve `"integration_key"`
  — coluna que **não existe** em `indicators` (a coluna é `key`). É um `prepare_ordering`
  copiado do `Segment` (`:53-61`).
- `Contract#description` (`app/models/contract.rb:28`) aplica `URI.unescape` sobre um
  `ActionText::RichText` — método **removido no Ruby 3**.

### 4.2 As outras 25 divergências entre o material e a fonte

| # | Afeta | O que o material dizia | O que a fonte diz |
| - | ----- | ---------------------- | ----------------- |
| A-6 | P-001 | O decaimento vem do `update` seguido de `save` no controller (`availability_entries_controller.rb:42,44`) | O segundo `save` não recalcula. O decaimento vem do **formulário preencher o campo com `e.value`, o valor já corrigido** (`.../availability_entries/list/_widget.html.erb:56` e `:131`), enquanto `availability_entry.rb:20` re-carimba `original_value` com o que chegar |
| A-7 | P-002/P-003 | As duas regras de soma estão em `project_availability_template.rb` / `global_availability_template.rb` | Estão em `project.rb:406` (soma bruta da consolidação geral) e `availability_entry.rb:188`/`:191`. Nenhum dos dois models de template soma valor. **Agravante:** `values[:total]` é calculado e **nunca renderizado** — o painel só usa `by_entry[].total` (= `virtual_value`) |
| A-8 | P-005 | O `after_commit` dispara duas vezes e o segundo disparo atualiza tipo/subtipo | Confirmado, **e o segundo disparo nunca corrige `operation_value`** (`receivable_entry.rb:168` só toca tipo e subtipo). O valor sem tarifas fica congelado para sempre |
| A-9 | P-009 | A fórmula de faturamento está em `remuneration.rb` | Está em `receipt.rb:63`. `remuneration.rb` só guarda o percentual |
| A-10 | P-014 | "Pagar só a mora pode quitar a parcela" | **Não acontece.** A mora entra idêntica nos dois lados e **se cancela** (`renegotiation_installment.rb:62-67`); `is_paid` só vira 1 com o principal coberto. O efeito real é outro: a mora **nunca é efetivamente cobrada** na parcela e **infla o "R$ Pago"** no agregado (`renegotiation.rb:105`) |
| A-11 | P-015 | Os subtipos de operação de risco "estão comentados no legado" | **Estão vivos e são infraestrutura central** (`risk_operation.rb:10,29-32,148-154`, `risk_control.rb:20,22,129,144`, select em `.../receivables/new/_body.html.erb:95`). Comentada há **uma** linha: `console_controller.rb:172`. O que falta é CRUD, menu e campo no formulário de risco |
| A-12 | P-019 | "Nenhum consumidor foi encontrado" (dito com dúvida) | **Confirmado por varredura exaustiva:** as 6 colunas denormalizadas são **write-only**. Nenhum `where`, scope ou `if` de regra as lê. As únicas leituras são o interruptor no projeto e uma cópia em `risk_control.rb:184` |
| A-13 | P-024 | "~40 textos de ajuda" (recebíveis) e "26 tooltips" (risco + estruturadas) | **91 chaves**, em 3 arquivos: 65 em `receivables_help_inputs.yml`, 13 + 13 nos outros. 100% com o mesmo placeholder |
| A-14 | P-041 | `resource_kinds` e `resource_sources` têm "o mesmo rótulo de menu e o mesmo título de aba" | **Título de aba idêntico byte a byte** (`console_controller.rb:348-349` e `:358-359`), mas **só `resource_sources` tem item de menu**; `resource_kinds` não tem nenhum. Os títulos das páginas diferem por **uma letra** ("Tipos de Recurso" × "Tipos de Recursos") |
| A-15 | P-044 | "O ETL **Django** forçava `user_id = 1` nos borderôs de **2016-2021**" | **Não é Django** — é um módulo Ruby dentro do próprio Rails (`app/models/legacy.rb`, `establish_connection :sfg_legacy`, tabela `fbordero`); não há uma linha de Python no repositório. E **não é 2016-2021**: o importador não filtra data (`legacy.rb:96` faz `klazz.all.each`) e o dump versionado tem registros também em 2022 |
| A-16 | P-055 | Pedir "Concluído" grava "Fechado" (um typo num lado só) | **A inversão é dupla:** o `update` grava Fechado quando se pede Concluído (`messages_controller.rb:118-119`) **e** a action `close` grava **Concluído** (`:156-159`). Os dois estados estão trocados entre si |
| A-17 | P-058, P-109 | "os outros dois logos" / logos de projeto e empresa | Os anexos são **projeto** (`project.rb:48`, `avatar`) e **fornecedor** (`provider.rb:12`, `logo`). **`Company` não tem anexo nenhum** |
| A-18 | P-059 | `default_position` usado em `availability_templates_controller.rb:22` | Confirmado, **e há um segundo problema na mesma action**: `:21` monta o `where!` com fragmento SQL malformado (`"title #{Dev.ilike} "`, sem o placeholder). A busca por texto tem dois defeitos independentes |
| A-19 | P-069 | `is_title` e `is_liquidation` "não têm consumidor visível" | Só `is_title` é órfão. **`is_liquidation` tem consumidor**: `movement_kind.rb:14` o soma com `is_advalorem`/`is_desagio`/`is_iof` para validar exclusividade mútua (`:13-18`) |
| A-20 | P-078 | O item de menu da posição diária de risco "está comentado" | **Não há item de menu nenhum** para `risk_entries` em `application_helper.rb`. O que está comentado é a **aba** (`.../risk/_body.html.erb:30`, `_body.js.erb:32`) e o handler do botão "Cadastrar posição" (`_body.js.erb:34-40,127-134`) |
| A-21 | P-081 | Os 4 flags de `structured_operation_types` estão "sem consumidor" | **`is_default` e `has_pre_faturamento` têm consumidor no lado estruturado** (`structured_operation_type.rb:11`, `.../structured_operation_types/list/_widget.html.erb:23`, `.../structured_operations/list/_widget.html.erb:16,22`). Órfãos mesmo são só `allow_manual_operations` e `allow_receivable_entries` |
| A-22 | P-087 | `generic_rating` "pode ser resquício; não achei consumidor claro" | **Só existe o CSS** (`app/frontend/css/pub/recyclable/generic_rating.scss`). Zero ocorrências de `app_rating_widget`/`generic_rating` em qualquer `.erb`, `.rb` ou `.js`. Sem model, controller, rota ou partial |
| A-23 | P-090 | Item de menu `reports` marcado `inactive` em `application_helper.rb` | Está na **view** (`.../base/menu/_container.html.erb:24`), não no helper — **e o item nem existe**: nenhum item da lista tem `identifier: "reports"`, então a condição nunca é verdadeira. Código morto guardando um identificador fantasma |
| A-24 | P-091 | O portão de `geolocations` decide "**9** IDs" | São **12**, e a lista autoritativa está em `s13/tasks.md:26-30`: `DB-592`, `DB-431`, `DB-480`, `OPS-481`, `OPS-482`, `FE-483`, `BE-435`…`BE-440`. A lista escrita no mapa contradiz o próprio título dele (enumera 14 itens sob o rótulo "9"), incluindo `OPS-621` e `OPS-483`, que **não** estão no portão da fatia e precisam ser conferidos à parte |
| A-25 | P-107 | Chaves de terceiro vêm de ENV/credentials | Parcialmente. O token da ReceitaWS vem de ENV **mas o valor real está versionado** (`config/application.arch.yml:12`); a chave do **Google Maps está hardcoded e duplicada** em `app/definitions/SFG/metadata.rb:8-9` (a segunda dentro da URL que vai para o HTML); e o `secret_key_base` está em texto puro em `config/development_credentials.yml:1` |
| A-26 | P-108 | `app_symbol.png` e `app_text.png` "não existem no repositório" e por isso o seed de tema estoura (afirmado por **dois** documentos: o mapa e `s17`/`s16`) | **Os dois existem**: `app/frontend/images/brand/app_symbol.png` (1,1 KB) e `app_text.png` (1,3 KB), e a factory de tema os usa (`db/factories/app_theme_factory.rb:22-24`) — se não existissem, o seed quebraria. O defeito real é outro: as variantes `_WHITE` e `_MONO` apontam **todas para o mesmo arquivo** (`SFG/theme.rb:47-57`) |
| A-27 | P-110 | (implícito) o legado tem trilha de auditoria a preservar | O legado **não tem `paper_trail`**. A trilha é caseira (`app/models/tracking.rb` + `lib/tracking_facade.rb`) e cobre **só** jobs de template de disponibilidade e criação de projeto. Não cobre CRUD, lançamentos, valores, permissões nem login — **não há trilha financeira a preservar** |
| A-28 | P-111 | "Três colunas de `renegotiations` renomeadas em 29/04/2022" | São **três renomeações em três tabelas**, e só **uma** é em `renegotiations` (`total_value → installments_main_value`). As outras são `renegotiation_installments.value → main_value` e `renegotiation_payments.value → installment_paid_value_with_interest_cm` |
| A-29 | P-114 | O `user_id` do lançamento de indicador é "quem alterou por último" | Confirmado, **e o autor não é exibido em nenhuma tela** — as únicas ocorrências de `user` nas views de lançamentos são dois `hidden_field`. O dado é sobrescrito e ninguém sequer o vê |
| A-30 | P-089, P-099 | Duas fatias decidiram coisas diferentes para o mesmo item, e um documento se contradiz sobre o dono de `Tracking` | GA: `s2/design.md:103` decide **não injetar**, `s13/proposal.md` (Q-09) decide **portar desligado** — ver P-089. `Tracking`: `s13/proposal.md:165` e `s13/design.md:220` dizem **S2**, `s13/proposal.md:289` diz **S19**, `s19/proposal.md:57-59` reivindica como seu, e S2 não menciona o assunto — ver P-099 |

### 4.3 As duas "duplicatas" que não tinham par — e foram recuperadas

A metade das fatias descartou 19 entradas como "duplicata pura do mapa, deixo lá". Conferi
uma a uma contra o de-para do mapa. **Dezessete têm par.** Duas não tinham:

- **`C-07` — o padrão de paginação (Kaminari).** Não existe nenhuma pergunta equivalente do
  lado do mapa (`grep -i kaminari` no documento dos mapas = 0). E não está decidida: **DEC-09**
  fechou que *"a paginação passa a funcionar de verdade"*, que é outra coisa. A escolha do
  padrão continua aberta e está escrita como tarefa de bloco 0 em `s5/tasks.md:20` (item 0.3),
  valendo para 14 endpoints de lista. Recuperada como **P-116**.
- **`Q-02` de S17 — dark mode entra?** (`s17/proposal.md:141`). Também sem par no mapa. Não
  tem DEC numerado, mas `decisions.md:602` já manda o `theming-brand-engineer` entregar a marca
  "em light **e** dark", o que na prática fixa a resposta. Recuperada como **P-117**, para você
  confirmar com uma letra em vez de deixar implícito.

As outras 17 têm par confirmado: `Q-01`→P-059, `Q-03`→P-057, `Q-04`→P-058, `Q-05`→P-109,
`Q-06`→P-110, `Q-B6`…`Q-B20`→P-006/P-007/P-008/P-068/P-029/P-025/P-027/P-069/P-009/P-030/P-031/P-070/P-071/P-044/P-024,
`Q-B21`…`Q-B32`→P-025/P-011/P-010/P-012/P-013/P-014/P-072/P-042/P-073/P-074/P-111/P-019,
`Q-B33`/`Q-B34`/`Q-B35`→P-075/P-043/P-076, e a família `Q-R*` toda. Três delas (`Q-R1`,
`Q-R20`, `Q-R23`) não aparecem como pergunta porque o mapa as removeu por já estarem
decididas (DEC-21.1, DEC-01, DEC-09) — não é perda.

### 4.4 As sete que mudaram de faixa de impacto

| P | Faixa no mapa | Faixa nas fatias | Onde ficou, e por quê |
| - | ------------- | ---------------- | --------------------- |
| P-019 | comportamento | número na tela | **comportamento** — a varredura provou que **nenhuma tela lê** as 6 colunas (A-12); nenhum número muda |
| P-036 | comportamento | número na tela | **comportamento** — o `update_all` reescreve `title`/`key`/`value_type`, não valor |
| P-061 | (não existia) | só interno | **comportamento** — colidir `hierarchy_level` muda **quem pode o quê** (A-4); é o C3 |
| P-077 | escopo | número na tela | **escopo** — o default replica e não muda número; a alternativa é construir um subsistema de baixa que não existe |
| P-082 | escopo | comportamento | **escopo** — decide se a feature de exclusão é construída |
| P-092 | escopo | comportamento | **escopo** — decide se a família de geolocalização é construída |
| P-096 | só interno | escopo | **escopo** — a opção (c) remove o campo, e (b) pode quebrar um consumidor externo em silêncio |

---

## 5. As oito consultas ao dump que resolvem 27 IDs de uma vez

Você tem o dump desde 25/08 (DEC-15.3). **Estas oito perguntas não precisam de opinião —
precisam de um número.** Rodar o bloco abaixo de uma vez responde P-018, P-026, P-049, P-053,
P-059, P-070, P-078 e P-091 (e, por tabela, esvazia P-041).

```sql
-- 1) P-059 — a coluna default_position existe mesmo em produção?
--    Nenhuma migration a cria; três views e o controller a usam.
--    Se NÃO existir, a busca de padrões globais está quebrada há anos.
--    Se existir, é a 2ª prova de schema fora do versionamento e o DEC-04 precisa ser revisitado.
\d availability_templates

-- 2) P-070 — resource_kinds tem uso? Decide 9 IDs
--    (BE-307, BE-720..BE-724, FE-307, DB-286, DB-289, DB-294)
SELECT count(*) AS resource_kind_em_uso
  FROM receivable_entries
 WHERE resource_kind_id IS NOT NULL;

-- 3) P-091 — geolocations tem linhas? Decide 12 IDs
--    (DB-592, DB-431, DB-480, OPS-481, OPS-482, FE-483, BE-435..BE-440)
SELECT count(*) AS geolocations FROM geolocations;

-- 4) P-078 — a posição diária de risco tem dado? Decide a fatia R8 inteira
--    (BE-269, DB-231, FE-234). Zero = a fatia some com evidência.
SELECT count(*) AS risk_entries FROM risk_entries;

-- 5) P-018 — sobrou limite no formato pré-2022 (sem tipo)?
--    Linha sem tipo SOME de todos os agregados do ai9. Decide DB-240, OPS-236
--    e o rótulo "Legado" de FE-243, mais o descarte das 8 colunas limite_*/taxa_*.
SELECT count(*) AS risk_controls_sem_tipo
  FROM risk_controls
 WHERE risk_operation_type_id IS NULL;

-- 6) P-049 — alguém entra hoje digitando USERNAME em vez de e-mail?
--    Possível BLOQUEADOR DE CUTOVER: no ai9 a identificação é e-mail ou telefone.
SELECT count(*) AS so_tem_username
  FROM users
 WHERE username IS NOT NULL
   AND username <> ''
   AND (email IS NULL OR email = '' OR email NOT LIKE '%@%');

-- 7) P-053 — quem foi rebaixado a Gerente pela precedência invertida do importador de 2021?
--    Esta é a LISTA para revisão humana, não uma contagem.
SELECT id, username, email
  FROM users
 WHERE is_staff = true AND is_superuser = true
 ORDER BY id;

-- 8) P-026 — existe remuneração com taxa fora de 0-100?
--    A taxa multiplica TODO o faturamento e não tem validação nenhuma.
SELECT count(*) AS fora_da_faixa,
       min(value) AS menor,
       max(value) AS maior
  FROM remunerations
 WHERE value < 0 OR value > 100;
```

**O que cada resultado destrava, em uma linha:**

| Consulta | Se der zero | Se der maior que zero |
| -------- | ----------- | --------------------- |
| 1 `default_position` | A busca de padrões globais nasce ordenada pela hierarquia; fecha o DEC-04 | Há schema fora do versionamento — o DEC-04 é revisitado com o dump em mãos |
| 2 `resource_kinds` | 9 IDs viram `dropped` **com evidência**, S8 encolhe, e **P-041 desaparece junto** | Os 9 IDs entram e P-041 (os nomes indistinguíveis) precisa de resposta |
| 3 `geolocations` | 12 IDs viram `dropped`, as tarefas 6.5–6.9 de S13 somem, e **P-092 vira código morto antes de nascer** | A família de geolocalização é construída |
| 4 `risk_entries` | A fatia R8 é descartada com evidência (P-078 vira "(c)") | Tabela e model são portados, sem tela (o default) |
| 5 `risk_controls` sem tipo | As 8 colunas `limite_*`/`taxa_*` podem ser descartadas e o rótulo "Legado" vira `dropped` | Uma rake de conversão entra no ETL, idempotente e sem apagar `risk_entries` |
| 6 `username` sem e-mail | P-049 fecha em "(a) seguir" | **Vira bloqueador de cutover** — precisa de plano antes da virada |
| 7 `is_staff AND is_superuser` | Ninguém foi rebaixado; P-053 fecha | A lista vai para revisão humana antes do cutover (nunca promoção automática) |
| 8 remuneração fora da faixa | Validar 0–100 fica **grátis** (P-026 vira "(b)") | Validar recusaria dado existente — aí a resposta é (c), com confirmação acima do limiar |


---

# `muda número na tela` — P-001 a P-018

> A resposta muda um valor que o cliente lê hoje. Nenhuma dá para responder no automático.

### P-001 — Correção por dias úteis: o valor decai a cada salvamento repetido

- **Origem:** `Q-01` + `F-02` (fundidas)
- **Fatia:** S11 (disponibilidades). O ETL de S14 depende da resposta para reconstituir `original_value`.
- **Trava:** trava `BE-127`, `BE-123` e `DB-125`, e as tarefas 5.3 e 6.5.8 de S11 (`s11/tasks.md:218, 326`). Sem resposta, o motor de disponibilidades não pode ser escrito.
- **Impacto:** `muda número na tela`
- **Contexto:** No legado, o lançamento de disponibilidade com padrão "ajustado" é corrigido por `value = original_value × (dias úteis até a data ÷ dias úteis do mês)` (`app/models/availability_entry.rb:193`), e um `before_validation` regrava `original_value = value` sempre que `value` chega alterado (`:20`). O formulário da grade preenche o campo com **`e.value` — o valor já corrigido** (`.../availability_entries/list/_widget.html.erb:56` e `:131`), então **salvar a mesma célula de novo aplica o multiplicador sobre um número que já foi multiplicado**. É o defeito **D-02**: dois usuários salvando a mesma linha produzem valores diferentes, e parte da base pode ter sofrido a correção mais de uma vez. O desenho do ai9 (`s11/design.md:118-134`) guarda o valor digitado em `original_value` e nunca o sobrescreve.
- **Opções:** (a) corrigir — a correção passa a ser aplicada **uma vez só**, sempre sobre `original_value`, e o ETL reconstitui `original_value` onde der, reportando o resto; (b) replicar o decaimento exatamente como está, com teste golden, e nunca mais tocar; (c) corrigir a fórmula **e** rodar um backfill que desfaz as reaplicações históricas (números antigos mudam).
- **Default vigente:** (a) — **DEC-01** (sinal) e **DEC-02** (float) não cobrem este caso: não é convenção nem precisão, é o mesmo dado valendo coisas diferentes conforme quantas vezes alguém apertou "salvar".
- **Recomendação:** (a) para os lançamentos novos, e (c) **só se** o relatório do dry-run mostrar volume relevante — desfazer decaimento histórico é caro e pode não valer o ganho. Replicar um número que depende do número de salvamentos não é preservar comportamento, é preservar a impossibilidade de conferir a conta.

### P-002 — Consolidação geral: passa a respeitar cumulatividade e sinal?

- **Origem:** `Q-02` (primeira metade) + `F-03`
- **Fatia:** S11
- **Trava:** trava `BE-125`, `BE-126`, `BE-148`, `DB-126`, `DB-130` e as tarefas 5.4, 5.5 e 5.7 de S11 — o serviço de consolidação não pode ser escrito com duas semânticas.
- **Impacto:** `muda número na tela`
- **Contexto:** Quando o usuário escolhe uma empresa, um nó com filhos soma **aplicando** cumulatividade e sinal: filho não cumulativo entra como zero e débito entra com `-1` (`app/models/availability_entry.rb:191`). Quando ele escolhe **"Consolidação geral"** (o item em branco do select, `.../availability/_body.html.erb:24`), a linha consolidada é a "mirror" e soma **bruto**: `self.value = self.mirrored_entries.sum(:value)` (`:188`), ignorando `is_cumulative` e `is_debit`. É o **D-08**: duas regras de soma na mesma tela, e uma das duas está errada.
- **Opções:** (a) a consolidação geral passa a respeitar `is_cumulative`/`is_debit`, ficando igual aos nós; (b) os nós passam a somar bruto, ficando iguais à consolidação; (c) replicar as duas semânticas como estão, com golden test, e rotulá-las na tela.
- **Default vigente:** **nenhum.** As duas metades divergiram (o mapa propôs (a); o empacotamento remeteu a você). O desenho só fixou que **passa a existir uma definição só**, seja ela qual for.
- **Recomendação:** (a). Débito que soma como crédito é o tipo de erro que o cliente descobre sozinho na primeira conferência.

### P-003 — "Total" quer dizer duas coisas na mesma tela

- **Origem:** `Q-02` (segunda metade, **desdobrada**) + `F-04`
- **Fatia:** S11
- **Trava:** trava `BE-148` e as tarefas 5.7 e 6.5.10 de S11.
- **Impacto:** `muda número na tela`
- **Contexto:** É uma decisão **independente** de P-002 — aquela decide *como somar*, esta decide *o que somar*. No mesmo painel, o total geral vem de `base_entries.pluck(:value).sum` (`app/models/project.rb:406`) e cada card de padrão base vem de `be.virtual_value`, que é **saldo acumulado com sinal** (`:415`). O usuário lê a palavra "Total" em dois lugares e recebe duas métricas diferentes. É o **DC-34**. Achado adjacente: `values[:total]` é calculado e **nunca renderizado** — o painel só usa `by_entry[].total`.
- **Opções:** (a) "Total" é sempre `value` (soma bruta) nos dois lugares; (b) "Total" é sempre `virtual_value` (saldo acumulado) nos dois lugares; (c) manter as duas métricas e **renomear** uma delas na interface — por exemplo "Total bruto" × "Saldo acumulado".
- **Default vigente:** (c).
- **Recomendação:** (c) se as duas métricas forem legítimas — renomear é barato e não muda número nenhum, e impede que alguém compare dois números que nunca foram comparáveis. (a) se só uma for legítima.

### P-004 — Dias úteis passam a considerar feriados?

- **Origem:** `Q-03` + `F-05` (fundidas)
- **Fatia:** S11
- **Trava:** tarefas 5.3 e 6.5.8 de S11. Fora isso, nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** O contador de dias úteis do legado descarta apenas sábado e domingo: `reject { |d| d.cwday == 7 || d.cwday == 6 }` (`app/decorators/models/date_decorator.rb:3` e `:7`). Não existe calendário de feriados em lugar nenhum do repositório. É o **D-03**: em todo mês com feriado, o multiplicador de correção de P-001 está alto, e sempre esteve.
- **Opções:** (a) manter seg–sex sem feriados; (b) ligar feriados **nacionais** (gem/tabela versionada), valendo só para lançamentos novos; (c) ligar o calendário **bancário** (Anbima), que é o que o mercado de crédito usa; (d) ligar feriados e reprocessar o histórico.
- **Default vigente:** (a) — ligar feriados muda o resultado financeiro de **todo** o histórico e ainda obriga a escolher o calendário, que é decisão de negócio.
- **Recomendação:** (a) nesta entrega. É a única das quatro perguntas de S11 que dá para adiar sem deixar duas semânticas no código: o calendário é aditivo, entra depois sem refazer nada, e aí com a escolha feita conscientemente.

### P-005 — Borderô: recalcular ou copiar o valor das operações de risco históricas?

- **Origem:** `Q-04` + `F-01` (fundidas)
- **Fatia:** S6 (motor de cálculo), executada em S14 (ETL)
- **Trava:** trava a tarefa 5.5 de S6 (`s6/tasks.md:424-428`), a carga de `risk_operations` no ETL e o desenho de `BE-183`. O ai9 já nasce certo; o que falta decidir é o histórico.
- **Impacto:** `muda número na tela`
- **Contexto:** No cadastro de borderô o controller salva duas vezes: `receivables_controller.rb:77` (grava o recebível) e `:89` (grava de novo depois de criar as tarifas, com o comentário *"atualizar os calculos internos com os valores das taxas \o/"*). O `after_commit` de `receivable_entry.rb:124-175` dispara nas duas — e na primeira ainda não existe nenhuma `ReceivableTax`, então a `RiskOperation` nasce com `operation_value: self.valor_liquido` (`:161`) calculado **sem as tarifas**. O segundo disparo **não conserta**: ele cai no ramo de `:168`, que só atualiza tipo e subtipo. O valor errado fica congelado para sempre. O próprio autor deixou o comentário `# aqui está o caso de bugar o save do recebível` em `:123`. É o **D-11**, e é dado sujo em produção, não só bug de código.
- **Opções:** (a) recalcular o valor de operação dos borderôs históricos no ETL, com relatório de quantos mudaram e de quanto; (b) copiar o valor legado como está (bate com o que o cliente vê hoje, continua errado); (c) copiar e marcar as linhas divergentes com um selo visível, deixando a correção para depois da venda.
- **Default vigente:** (a) — o ai9 já nasce com a operação criada depois das tarifas, e manter dois regimes de verdade no mesmo painel de exposição seria pior que a correção.
- **Recomendação:** (a), **com o relatório entregue antes de qualquer carga definitiva**. É o único item desta lista em que replicar o defeito significa gravar número errado de propósito num banco novo. Se o delta agregado for material, (c) vira o caminho conservador — mas isso só se sabe com o número na mão.

### P-006 — `calc_valor_liq_correto`: desconto linear é a regra pretendida?

- **Origem:** `Q-05`
- **Fatia:** S6
- **Trava:** nada — só muda o resultado (e o rótulo "OK"/"Diferença" que o operador lê).
- **Impacto:** `muda número na tela`
- **Contexto:** A fórmula converte o custo efetivo acordado em taxa diária equivalente e desconta **linearmente**: `power_tx = ((cst_efetivo_acordado/100 + 1) ** 0.0333…) - 1`, depois `vp = (vlr_bruto_final - tx * (prz_med_pond_emp + float_acordado)).round(2)` (`app/models/receivable_entry.rb:107-112`). Não é desconto composto (`VF/(1+i)^n`). Esse número alimenta direto o carimbo que o operador vê: `dif_calc_vlr_liq` em `:114` e `status = dif < 0 ? "Diferença" : "OK"` em `:115`. A mesma fórmula está duplicada no JS da tela (`.../receivables/new/_body.js.erb:462-467`) — é o **D-14** e a origem do **D-09**.
- **Opções:** (a) replicar exatamente, com teste golden (nada muda); (b) trocar para desconto composto — o valor presente e a classificação OK/Diferença mudam em todo o histórico; (c) replicar e exibir os dois lado a lado por um período, para o negócio comparar.
- **Default vigente:** (a), por **DEC-02** — o resultado é replicado, incluindo os casts e os pontos de arredondamento.
- **Recomendação:** (a). Se a aproximação linear for um erro, trocá-la é uma linha depois — mas trocar junto com a migração torna impossível saber se um número novo veio do ai9 ou da fórmula nova.

### P-007 — CET do banco: a guarda olha o prazo da **empresa**

- **Origem:** `Q-06`
- **Fatia:** S6
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** `app/models/receivable_entry.rb:74` zera o custo efetivo do banco quando o prazo médio ponderado da **empresa** é zero: `self.custo_efetivo_pz_med_banco_sem_iof = self.prz_med_pond_emp == 0 ? 0 : tx_banco_iof` — mas a base do cálculo (`power_bco_iof`, `:72`) usa `prz_med_pond_bco + float_acordado`. Quatro linhas abaixo, `:78` faz a guarda **certa**, com `prz_med_pond_bco == 0`. A assimetria não tem explicação no código e tem cara de copy/paste.
- **Opções:** (a) replicar exatamente; (b) corrigir a guarda para `prz_med_pond_bco == 0`, alinhando com `:78`.
- **Default vigente:** (a) — trocar muda o valor exibido em qualquer borderô com prazo de empresa zero e prazo de banco diferente de zero.
- **Recomendação:** (a) na entrega, **com a divergência registrada no `improvements-log.md`** e um golden que documenta o comportamento. É um caso raro e vale corrigir depois, com o cliente ciente.

### P-008 — CET: 2 casas num campo, 4 no outro, com a mesma base

- **Origem:** `Q-07`
- **Fatia:** S6
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** `custo_efetivo_pz_med_emp` fecha com `.round(4)` (`app/models/receivable_entry.rb:90-92`) e `custo_efetivo_com_float_total` fecha com `.round(2)` (`:99`), sendo a expressão **algebricamente a mesma**. Os dois aparecem no mesmo bloco do formulário.
- **Opções:** (a) replicar os dois arredondamentos como estão; (b) padronizar em 4 casas nos dois; (c) padronizar em 2.
- **Default vigente:** (a), por **DEC-02** e porque o arredondamento faz parte da cadeia que produz o número que a tela mostra.
- **Recomendação:** (a). Padronizar é cosmética que muda dinheiro; se incomodar, é ajuste de uma linha com o cliente avisado.

### P-009 — A remuneração é percentual flat sobre o capital, sem prazo?

- **Origem:** `Q-08` + `F-09` (fundidas; levantada também nos blocos de recebíveis e de risco)
- **Fatia:** S8 (remuneração e recibos)
- **Trava:** trava `BE-305`, `BE-188` e o bloco 0 de S8 (`s8/tasks.md:26`) — é a **única fórmula de faturamento do sistema**.
- **Impacto:** `muda número na tela`
- **Contexto:** `app/models/receipt.rb:63` — `self.value = self.operation_value * (self.fee.to_f / 100.0)`, com `fee` vindo de `remuneration.value` (`:61`). Não entram `agreed_rate`, nem `issue_date`/`due_date`, nem `balance`: a tabela de recibos guarda `fee`, `operation_value`, `value`, `date` e o rótulo da operação (`db/migrate/20220802225011_create_receipts.rb:3-17`), e a `date` é só uma cópia do `issue_date` da operação (`receipt.rb:46`). O legado **não tem nenhum teste** (D-114), então essa fórmula nunca foi verificada por nada. É o **D-72**. O modelo guardar `issue_date` e `due_date` **sugere** um pro-rata que a fórmula não faz.
- **Opções:** (a) replicar o flat exatamente, com golden (o valor faturado não muda); (b) implementar pro-rata por prazo, usando `issue_date`/`due_date` que já estão guardados — muda a receita reconhecida; (c) replicar agora e abrir um tipo de remuneração "pro-rata" como opção de cadastro depois.
- **Default vigente:** (a) — é dinheiro cobrado do cliente, e mudar fórmula de cobrança sem confirmação do negócio é a pior classe de erro possível.
- **Recomendação:** (a), **e esta é a resposta que mais vale ter por escrito**: é a linha que fatura. Se a intenção sempre foi pro-rata, o legado vem cobrando errado há anos, e isso é assunto comercial, não de migração.

### P-010 — "A vencer" na renegociação inclui as parcelas já vencidas

- **Origem:** `Q-09`
- **Fatia:** S9
- **Trava:** nada — só muda o número da coluna.
- **Impacto:** `muda número na tela`
- **Contexto:** `app/models/renegotiation.rb:110` — `self.due_installments = self.installments_count - self.paid_installments`. Uma linha acima, `:109` calcula `overdue_installments` com `DATE(due_date) < hoje AND is_paid = 0`. Como "a vencer" é só "tudo que não foi pago", **as vencidas estão contadas dentro dela**. E `due_installments` não é só rótulo: é usado como **expoente do valor presente** em `:180`.
- **Opções:** (a) manter a semântica atual e **renomear** a coluna para "Em aberto"; (b) mudar a conta para `installments_count - paid_installments - overdue_installments` (o número na tela muda, e o VP de `:180` muda junto); (c) manter a conta e acrescentar uma coluna "Vencidas" ao lado, sem mexer no cálculo.
- **Default vigente:** (a) — mexer em `due_installments` mexe no valor presente, e valor presente é DEC-02.
- **Recomendação:** (a). Renomear resolve a confusão sem tocar em dinheiro; (c) como complemento se o negócio quiser ver os dois.

### P-011 — Renegociação: dois números diferentes para "o que falta pagar"

- **Origem:** `Q-10`
- **Fatia:** S9
- **Trava:** trava `BE-205` — o serviço de agregação precisa de uma definição só.
- **Impacto:** `muda número na tela`
- **Contexto:** `renegotiation.rb:102` calcula `pending_main_value = main_value - paid_value_with_interest_cm`, **sem piso** — pagar a mais deixa o número negativo. `renegotiation.rb:107` calcula `remaining_value = installments.pluck(:pending_value).sum`, e `pending_value` tem piso em zero (`renegotiation_installment.rb:66` e `:24`). Os dois medem "o que falta" e podem discordar na mesma tela; só `remaining_value` decide o status da renegociação (`:122`).
- **Opções:** (a) `remaining_value` (soma das parcelas, com piso) é o número oficial e `pending_main_value` vira interno; (b) `pending_main_value` é o oficial, e o crédito por pagamento a maior passa a aparecer como saldo negativo; (c) manter os dois, com rótulos que expliquem a diferença.
- **Default vigente:** (a) — é o que já governa o status hoje, então é o que o sistema de fato considera verdade.
- **Recomendação:** (a). E o pagamento a maior merece tratamento explícito (crédito), não um número negativo escondido num campo secundário.

### P-012 — Correção monetária e carência: a tela promete, o cálculo ignora

- **Origem:** `Q-11`
- **Fatia:** S9
- **Trava:** trava `BE-208` e `FE-199` — decide se dois campos existem ou não.
- **Impacto:** `muda número na tela`
- **Contexto:** `interest_rate_correction` e `grace_period` são criados na migration (`db/migrate/20210324173930_create_renegotiations.rb:17,19`), aparecem no formulário e **não são lidos por nenhum cálculo** no repositório inteiro — só por comentários (`renegotiation.rb:247,248,275,277`) e por mensagens de erro traduzidas. O valor corrigido é sempre cópia crua: `renegotiation.rb:93` — `self.correct_value = self.total_debt`. É o **D-47**.
- **Opções:** (a) implementar de verdade — os valores corrigidos passam a divergir do que o cliente vê hoje em toda renegociação com esses campos preenchidos; (b) remover os dois campos da tela e registrar como funcionalidade nunca entregue; (c) manter os campos visíveis e somente leitura, marcados como "não aplicado", até o negócio definir a fórmula.
- **Default vigente:** (b) — DEC-09 manda portar o que **existe**, e o que existe é a coluna, não o cálculo.
- **Recomendação:** (b). Campo que promete correção monetária e não corrige nada num sistema de crédito é pior que campo ausente.

### P-013 — "Valor Parcela" é sobrescrito pelo valor presente

- **Origem:** `Q-12`
- **Fatia:** S9
- **Trava:** nada — mas é a coluna mais lida da tela de renegociação.
- **Impacto:** `muda número na tela`
- **Contexto:** `renegotiation.rb:125` calcula `current_installment_value` pelo valor nominal da parcela do mês; **na linha seguinte**, `:126` chama `calculate_current_value`, que dentro de si faz `self.current_installment_value = vp.round(2)` (`:182`) — reatribuindo a mesma coluna com o **valor presente**. Resultado: sempre que há juros > 0 e saldo em aberto, a coluna "Valor Parcela" mostra outra coisa. É o **D-46**.
- **Opções:** (a) replicar o efeito exatamente, com golden; (b) separar em dois campos — "Valor da parcela" (nominal) e "Valor presente" — e mostrar os dois; (c) manter só o nominal na coluna e expor o VP no detalhe.
- **Default vigente:** (a) — mudar altera o número que o cliente lê hoje, e não há reconciliação feita.
- **Recomendação:** (b) **depois** de (a): replicar na entrega e propor os dois campos no `improvements-log`. É reatribuição acidental, não regra de negócio — mas provar isso exige o cliente confirmar.

### P-014 — Mora na parcela: entra dos dois lados da conta e infla o "R$ Pago"

- **Origem:** `Q-13`
- **Fatia:** S9
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** A mora entra no devido (`renegotiation_installment.rb:62-63`: `installment_total_value = main_value_with_interest_cm + late_payment_value`) **e** no pago (`:64`, via `renegotiation_payment.rb:13`, onde `total_paid_value` já a embute). Como entra idêntica dos dois lados, ela **se cancela**: `pending_value = main_cm − pago_cm` (`:65-67`), e `is_paid` só vira 1 quando o principal com juros é coberto (`:67`). O efeito real: **a mora nunca é efetivamente cobrada** na parcela, e no nível da renegociação ela é contada como pagamento (`renegotiation.rb:105`), **inflando o "R$ Pago"** exibido.
- **Opções:** (a) replicar exatamente (mora neutra na parcela, inflando o pago no agregado); (b) tirar a mora do lado pago da parcela, para que ela passe a ser efetivamente devida — muda o saldo de toda renegociação com atraso; (c) replicar na parcela e corrigir só o agregado `paid_value`, para o "R$ Pago" parar de contar mora como amortização.
- **Default vigente:** (a) — é dinheiro e não houve reconciliação.
- **Recomendação:** (c). É a correção de menor risco: não mexe em quitação de parcela nenhuma e conserta o único número que hoje é claramente enganoso.

### P-015 — Subtipo da operação de risco: o formulário não pergunta e o código escolhe "o primeiro"

- **Origem:** `Q-14` + `F-06` (fundidas)
- **Fatia:** S7, com efeito direto em S5 (limites) e S6 (borderô)
- **Trava:** trava `BE-262`, `BE-244`, `BE-245` e o bloco 0 de S7 (`s7/tasks.md:23`) — nada de código de operação de risco antes.
- **Impacto:** `muda número na tela`
- **Contexto:** Quando o subtipo não vem no formulário, `app/models/risk_operation.rb:32` faz `operation_subtype_id = operation_type.subtypes.where(...).pluck(:id).first` — **sem `order`**, ou seja, pela ordem de inserção no banco. E o formulário de operação de risco **não tem campo de subtipo** (zero ocorrências de `subtype` em `.../risk_operations/new/_body.html.erb`), então esse caminho é o padrão em toda criação manual. O subtipo decide o bucket de limite: `is_pre = 0` entra em "liquidável" (`risk_control.rb:129-130`) e `is_pre = 1` entra em "pré-faturamento" (`:144-145`) — e é o bucket que aparece somado na tela de risco. Como `risk_operation_type.rb:23` cria o subtipo "pré" antes do de "antecipação" (`:31`), **o `.first` tende a cair no pré**. **Conflito interno registrado:** o mapa manda replicar o legado; a spec `BE-262` manda **recusar com 422** pedindo escolha explícita.
- **Opções:** (a) recusar com 422 e obrigar a escolha explícita (a spec); (b) replicar o `.first`, com `order` explícito por id para pelo menos ser determinístico (o mapa); (c) tornar o subtipo padrão uma **configuração do tipo** (`is_default` já existe nessa família), e o formulário só o mostra quando há mais de um; (d) recusar nas gravações novas e replicar na carga histórica.
- **Default vigente:** conflitante — o mapa fixou (b), a spec fixou (a). **Precisa da sua palavra.**
- **Recomendação:** (c) para o comportamento, com (d) na prática — a carga histórica não tem a quem perguntar. (c) é a única opção em que o número deixa de depender da ordem de inserção de linhas num cadastro, sem obrigar o operador a responder uma pergunta que ele hoje não responde.

### P-016 — "Encerrar" uma operação de risco deve tirá-la da exposição?

- **Origem:** `Q-15` + `F-16` (fundidas)
- **Fatia:** S7
- **Trava:** trava `BE-268`, `BE-277`, o bloco 0 de S7 (`s7/tasks.md:24`) e as tarefas 2.6 e 3.5. Toca o núcleo protegido pelo DEC-01.
- **Impacto:** `muda número na tela`
- **Contexto:** Hoje `is_ended` não faz quase nada. Aparece em 6 lugares e nenhum é uma trava: a janela de exposição filtra **só** por data (`risk_control.rb:76-79`, `due_date >= d AND issue_date <= d`), então **operação encerrada continua somando** em `limite_utilizado_on` (`:115-124`), `limite_liquidavel_on` (`:126-140`) e `limite_pre_on` (`:141-156`). Lançar movimento numa operação encerrada é aceito (`risk_movement.rb:20-28` só valida a data) e prorrogar também (`risk_operation_extension.rb:8-16` empurra a `due_date` sem olhar nada). O único uso real de `is_ended` é bucketizar "vencidos" × "a vencer" (`risk_control.rb:94` e `:106`). É o **D-94**: renovar não encerra a original, então as duas consomem limite ao mesmo tempo.
- **Opções:** (a) não mexer — `is_ended` continua sendo rótulo (a spec, por DEC-01); (b) bloquear movimento e prorrogação em operação encerrada, **sem** mexer na janela de exposição (os números do painel não mudam); (c) bloquear só a prorrogação, que é a que gera a contagem dupla do D-94; (d) (b) + retirar as encerradas de `operations_on` — a exposição de **todo o histórico** muda.
- **Default vigente:** conflitante — o mapa fixou (b) (o D-94 autoriza dar estado real ao encerramento), a spec fixou (a) (DEC-01 manda replicar). **Precisa da sua palavra.**
- **Recomendação:** (b). E fica **explicitamente fora de qualquer default**: retirar a operação encerrada de `operations_on` (opção d) muda a exposição do histórico inteiro e precisa de reconciliação com o cliente antes, não junto com a migração.

### P-017 — Transferência a partir da antecipação não gera contrapartida

- **Origem:** `Q-16`
- **Fatia:** S7
- **Trava:** nada — mas afeta o saldo dos dois lados da transferência.
- **Impacto:** `muda número na tela`
- **Contexto:** O `after_create` de `app/models/risk_movement.rb:45-65` só cria o movimento espelho quando a origem é pré-faturamento: `if self.movement_type_id == RiskMovementType.transferencia_enviada_id && self.risk_operation.is_pre?` (`:46`). Partindo da operação de antecipação (`is_pre = 0`), o "enviado" é gravado e **nenhum "recebido" nasce do outro lado** — o valor sai de uma operação e não entra em nenhuma.
- **Opções:** (a) replicar a assimetria exatamente; (b) espelhar nos dois sentidos; (c) recusar (422) a transferência a partir da antecipação, deixando explícito que o sentido não é suportado.
- **Default vigente:** (a) — espelhar cria movimento que hoje não existe, e movimento muda saldo, que muda exposição.
- **Recomendação:** (c) para lançamentos **novos** e (a) para o histórico. Aceitar em silêncio um lançamento que perde metade da contrapartida é o pior dos três.

### P-018 — Sobrou limite de risco no formato pré-2022, sem tipo?

- **Origem:** `F-07` (T-D1)
- **Fatia:** S5 (executa em S14)
- **Trava:** trava `DB-240`, `OPS-236`, o rótulo "Legado" de `FE-243` e o bloco 0 de S5 (`s5/tasks.md:20`, item 0.1) — mais a decisão de descartar ou não as 8 colunas `limite_*`/`taxa_*`.
- **Impacto:** `muda número na tela`
- **Contexto:** `RiskControl` **mudou de forma em 2022** (`db/migrate/20220611152145_change_risk_control_fields`): deixou de ser 4 modalidades em colunas fixas e passou a ser uma linha por (empresa, portador, tipo). Se sobrou linha sem `risk_operation_type_id`, **ela some de todos os agregados** do ai9 — o limite simplesmente deixa de existir na tela. Isto não é opinião, é uma consulta: **ver a consulta 5 da seção 5**.
- **Opções:** (a) rodar a contagem no dump agora e decidir com o número; (b) assumir zero e descartar as 8 colunas; (c) assumir maior que zero e escrever a rake de conversão sem saber se ela terá o que converter.
- **Default vigente:** (a) — as colunas nascem preservadas e o descarte fica adiado para o ETL.
- **Recomendação:** (a). São cinco segundos de consulta e fecham 2 IDs, um rótulo de tela e o destino de 8 colunas.

---

# `muda comportamento observável` — P-019 a P-066

> A resposta muda o que a tela faz, quem entra, ou o que fica gravado.

### P-019 — `has_safegold_management`: carimbo histórico ou derivado do projeto?

- **Origem:** `Q-17` + `F-10` (fundidas; também levantada no bloco de renegociações)
- **Fatia:** S4 (projeto e empresas); atinge S6, S9, S11 e S5
- **Trava:** trava `BE-093`, `DB-051`, `DB-090`, `DB-130` e `DB-197` — decide o desenho de **6 tabelas**. S4 tarefa 1.19 diz literalmente *"não implementar as tabelas filhas antes da resposta"* (`s4/tasks.md:86-89`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** O projeto tem a marca "gestão Safegold", e ela é **copiada** para 6 tabelas na criação de cada registro: `company.rb:13`, `availability_entry.rb:17`, `receivable_entry.rb:40`, `renegotiation.rb:24`, `risk_control.rb:15` e `risk_entry.rb:32`. Quando a marca do projeto muda, o único lugar atualizado em massa é `companies` (`project.rb:298-303`) — as outras cinco ficam com o carimbo velho para sempre. É o **D-30**. **Varredura exaustiva:** não existe **nenhum** leitor — nenhum `where(has_safegold_management: …)`, nenhum scope, nenhum `if` de regra em `app/`, `engines/`, `lib/` ou `config/`. As únicas leituras são a exibição do próprio interruptor no projeto e uma cópia interna em `risk_control.rb:184`. Ou seja: hoje a marca **não muda nada dentro do sistema** — o risco é só um consumidor externo (BI, planilha, relatório do cliente) lendo o banco.
- **Opções:** (a) derivar do projeto em tempo de consulta e **remover a coluna das 6 filhas** — a inconsistência acaba, e um registro de 2019 passa a refletir a marca **atual**; (b) manter o carimbo como está (foto do momento), inclusive a inconsistência; (c) derivar, **mas manter a coluna antiga preenchida e congelada** como `legacy_*` para conferência; (d) manter o carimbo **e** passar a ressincronizar as 6 tabelas quando a marca muda.
- **Default vigente:** (a) — nenhum consumidor interno existe, e derivar simplifica 6 tabelas de uma vez.
- **Recomendação:** (c). O custo é uma migration, e é o único caminho que não perde a foto caso apareça um consumidor externo. Se você confirmar que nenhum relatório externo lê essas colunas, (a) é mais limpo.

### P-020 — Aceite de contrato volta a ser explícito?

- **Origem:** `Q-18` + `F-12` (fundidas)
- **Fatia:** S12, com dependência de S1 (convite)
- **Trava:** **bloqueia S12** — o SC-2 inteiro, 20 tarefas marcadas como bloqueadas (`s12/tasks.md:110-145`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** Em produção o aceite explícito está morto por **quatro** motivos independentes, todos conferidos: (1) o bloqueio de acesso por contrato pendente está inteiramente comentado (`app/controllers/pub_application_controller.rb:55-63`); (2) os dois botões "ACEITAR" estão comentados nas views (`.../contracts/header/_body.html.erb:44` e `.../_toolbar_body.html.erb:22`), embora os handlers JS e a rota `PUT` continuem vivos e inalcançáveis — **hoje não existe nenhuma forma de aceitar um contrato pela interface**; (3) o cálculo de pendência **levanta exceção** porque a associação está errada (`app/decorators/models/user_decorator.rb:40` declara `source: :contract_deal`, e `ContractDeal` só tem `:contract` e `:user`), então quem abria `/contract/:type` recebia 500; (4) os checkboxes de cadastro e de "Minha Conta" vêm **pré-marcados** e não são lidos por controller nenhum. O aceite real é implícito: um `after_create` no usuário grava os dois (`user_decorator.rb:2` e `:234-240`). É o **D-64**, e a consequência é jurídica — **o sistema registra hoje um aceite que o usuário nunca deu conscientemente**.
- **Opções:** (a) reativar o ciclo completo — aceite explícito **com** bloqueio de acesso enquanto houver contrato pendente (é o comportamento que o código pretendia); (b) reativar só a **ação** de aceitar, sem bloqueio — banner persistente até aceitar; (c) manter tudo desligado e portar apenas a página de leitura.
- **Default vigente:** **nenhum.** As tarefas estão travadas de propósito. Nenhum default seguro existe aqui.
- **Recomendação:** (b) para a demo e (a) antes do cutover, com o jurídico definindo o prazo de tolerância. Ligar o bloqueio numa demo comercial arrisca travar o cliente na primeira tela. Com **DEC-18.7** (cadastro público desligado, entrada só por convite), o consentimento passa naturalmente para o fluxo de convite (`BE-340`, `FE-337`).

### P-021 — O que fazer com os aceites implícitos que já estão gravados?

- **Origem:** `Q-19` + `F-13` (fundidas)
- **Fatia:** S12, executada em S14 (ETL)
- **Trava:** trava o conversor de `contract_deals` do ETL e o seed de contratos (`s12/tasks.md:46`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** Além do `after_create` que grava aceite sem interação (P-020), o seed do legado **fabricou aceite retroativo para toda a base**: `db/seeds.rb:141-148` e `:150-157` pegam todos os usuários sem aceite e criam um `ContractDeal` para cada um. A base de aceites existente **não distingue "aceitou" de "foi carimbado"** — migrar esses registros é migrar uma prova jurídica que não existe.
- **Opções:** (a) migrar como estão, sem marca; (b) migrar marcados como `implicit_legacy`, preservando a data mas registrando que não houve ato do usuário — quem já está na base não é incomodado; (c) migrar marcados como implícitos **e** exigir novo aceite na próxima entrada, preservando o registro antigo como histórico; (d) descartar e exigir novo aceite de todo mundo no primeiro login.
- **Default vigente:** **nenhum, e não deve haver.** É decisão jurídica: qualquer escolha nossa aqui é opinião sobre validade de consentimento.
- **Recomendação:** (c), sujeito ao jurídico. É a única que não descarta registro nem finge que o registro vale, e é aditiva em relação a (d) se o jurídico pedir reaceite geral.

### P-022 — Quem pode publicar uma versão de contrato? (hoje: qualquer autenticado)

- **Origem:** `Q-20` + `F-15` (fundidas; levantada em dois mapas)
- **Fatia:** S12
- **Trava:** trava `BE-335`, a tarefa 2.6 de S12 (`s12/tasks.md:80-86`) e a matriz de autorização, que é **contrato aprovado** (DEC-18).
- **Impacto:** `muda comportamento observável`
- **Contexto:** **Ver o achado A-1.** A matriz aprovada dá `contracts` como **`R` para os quatro papéis** (`authorization-matrix.md:197`), derivada dos links do rodapé da sidebar e do aceite — ela descreve **ler e aceitar os Termos**. A administração (criar versão, publicar) nunca entrou na matriz porque **não tem item de menu**. E o gate que os dois mapas afirmavam existir **não existe**: `contracts_controller.rb` tem 101 linhas e zero ocorrências de `before_action`/`may?`/`admin?`/`og?`/`authorize`; as rotas não têm constraint (`config/routes.rb:30-31`); o `create` (`:56-67`) só carimba `creator = current_user` e salva. Some-se o mass assignment de `id` e `version` no mesmo `permit`. **Hoje qualquer usuário autenticado que acerte a URL publica uma nova versão dos Termos de Uso.** A pergunta não é "confirmar um gate", é **"criar o gate que nunca existiu"**.
- **Opções:** (a) novo recurso `contract_versions` = **CRUD para OG + Admin**, `-` para Gerente e Colaborador; `contracts` (ler/aceitar) fica exatamente como aprovado — o total passa de 45 para 46 recursos; (b) publicação só para **OG** (é documento jurídico do fornecedor); (c) manter a matriz literal — todos leem, ninguém publica pela aplicação, e versão nova entra por seed; (d) deixar como está no legado (qualquer autenticado).
- **Default vigente:** (a), proposta e **aguardando confirmação**. A matriz não foi alterada por iniciativa própria.
- **Recomendação:** (a). Publicar Termos vincula **todos** os usuários — não é operação de gestor, mas também não precisa ser exclusiva do fornecedor, e (b) obriga o cliente a chamar a Livetat para trocar uma vírgula. Uma armadilha para não repetir: `user_is_readonly` pode tirar C/U/D de `contract_versions`, mas **não pode** bloquear o aceite dos Termos pelo próprio usuário — senão o readonly nunca aceita e fica trancado fora do sistema.

### P-023 — `receipts` herda o gate de `charges` ou merece linha própria na matriz?

- **Origem:** `Q-21`
- **Fatia:** S11 (cobranças e recibos)
- **Trava:** trava o `authorize!` das rotas de recibo.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A matriz aprovada tem `charges` como **CRUD para os quatro papéis, com escopo por projeto** (`authorization-matrix.md:139`), e **não tem linha para `receipts`**. Recibo é sub-recurso de cobrança (o candidato a recibo sai de `Charge#receipt_candidates`, `app/models/charge.rb:34-46`), então a herança é a leitura natural — mas ela não está escrita em lugar nenhum, e "por inferência" é como se perde um gate.
- **Opções:** (a) `receipts` herda explicitamente o gate de `charges` (CRUD/4 papéis, escopo por projeto), escrito na matriz como linha derivada; (b) linha própria mais restrita (por exemplo, emitir recibo só OG/Admin/Gerente); (c) deixar implícito.
- **Default vigente:** (a) — é o comportamento do legado e não tira acesso de ninguém.
- **Recomendação:** (a), com a linha escrita. O custo de escrever é zero e o custo de não escrever é alguém decidir diferente no Phase 3.

### P-024 — Os 91 textos de ajuda dos formulários são todos o mesmo placeholder

- **Origem:** `Q-22` (levantada em três mapas)
- **Fatia:** S6, S7, S8 (o mecanismo em S12)
- **Trava:** não trava código — o mecanismo é portado de qualquer forma. Trava só o conteúdo.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Três YAML alimentam os tooltips dos formulários financeiros: `db/seed_assets/receivables_help_inputs.yml` (**65 chaves**), `risk_operations_help_inputs.yml` (13) e `structured_operations_help_inputs.yml` (13). **As 91 chaves têm exatamente o mesmo texto:** *"Só um teste de informações do campo pra descrever para que serve cada campo"*. São lidos em runtime pela própria view (`.../receivables/new/_body.html.erb:14`, `.../risk_operations/new/_body.html.erb:15`, `.../structured_operations/new/_body.html.erb:15`) e exibidos via tippy.
- **Opções:** (a) portar o mecanismo e **sair sem tooltip** onde não houver texto (o campo não mostra o ícone); (b) portar o mecanismo com o placeholder, como no legado; (c) você (ou quem conhece o produto) escreve os 91 textos — é conteúdo de negócio sobre campos financeiros, e eu não invento.
- **Default vigente:** (a) — mostrar "Só um teste…" numa demo comercial é pior que não mostrar nada.
- **Recomendação:** (a) na entrega, com (c) priorizado só para os campos do borderô que envolvem CET e float — que são os que o operador realmente erra.

### P-025 — Introduzir as validações de faixa que o legado não tem?

- **Origem:** `Q-23` (levantada em três mapas)
- **Fatia:** S6, S7, S8, S9
- **Trava:** trava `BE-181`, `FE-177`, `BE-199`, `BE-267` e `BE-293`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Em quatro lugares o legado aceita dado que não deveria existir. **Recebível:** `date` tem só `presence` (`receivable_entry.rb:13`) — 1900 e 2100 passam, e o campo é texto livre no HTML (`.../receivables/new/_body.html.erb:129`); `valor_bruto` tem só `presence` (`:18`), embora as linhas vizinhas `:19-20` usem `numericality: {greater_than: 0}` para os prazos. **Renegociação:** `original_value`, `total_debt` e `operation_interest_rate` têm só `presence` (`renegotiation.rb:17,18,20`) — zero, dívida negativa e taxa negativa entram. **Risco e estruturadas:** nenhuma validação de `due_date >= issue_date` nem de `operation_value > 0` (`risk_operation.rb:54-62`, `structured_operation.rb:13-20`).
- **Opções:** (a) replicar as ausências — nada é recusado que hoje entra; (b) validar tudo em registros **novos** e deixar o histórico em paz; (c) validar tudo e reportar no dry-run quantos registros históricos violam cada regra, para o cliente decidir o que fazer com eles.
- **Default vigente:** (a) — para não recusar dado que hoje o sistema aceita.
- **Recomendação:** (c). É a única que responde à pergunta que você vai fazer de qualquer jeito: "quantos registros estão assim hoje?". Se a resposta for zero, (b) vira grátis.

### P-026 — A taxa de remuneração pode ficar fora de 0–100?

- **Origem:** `Q-24` + `F-18` (fundidas)
- **Fatia:** S8
- **Trava:** trava `BE-301`, `FE-305` e as tarefas 4.2 e 11.6 de S8.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A taxa que multiplica **todo** o faturamento não tem validação nenhuma: `app/models/remuneration.rb:9` tem só `presence: true`, o campo do formulário não tem `min`/`max`/`pattern` (`.../remunerations/helper/_body.html.erb:30`), e a coluna é **float** (`db/migrate/20220629123512_create_remunerations.rb:6`). No recibo, o `fee` copiado também é float, com um comentário que promete a faixa e não a impõe: `db/migrate/20220802225011_create_receipts.rb:11` — `t.float :fee # taxa em % 0-100`. Na prática, **250% passa pela UI** e a API aceita mais casas ainda. **Consulta 8 da seção 5** diz quantos registros existentes já estão fora da faixa.
- **Opções:** (a) replicar a ausência; (b) validar `0 <= value <= 100` e recusar o que estiver fora; (c) aceitar, mas exigir **confirmação explícita** na tela acima de um limiar (por exemplo 100%).
- **Default vigente:** (a) — validar passa a recusar registro que hoje o sistema aceita, e pode haver registro legítimo fora da faixa.
- **Recomendação:** (c) se a consulta 8 devolver algo; (b) se devolver zero, porque aí validar é grátis. Um typo nessa taxa fatura dez vezes a mais e nada avisa.

### P-027 — `is_active` dos catálogos passa a filtrar de verdade?

- **Origem:** `Q-25` (levantada em dois mapas)
- **Fatia:** S6 (carteiras, tipos de recebível) e S8 (fontes de recurso)
- **Trava:** trava `BE-185`, `FE-157`, `BE-308` e `DB-287`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Três catálogos gravam e exibem um interruptor "Ativado/Desativado" que **não filtra nada**. Carteiras: gravado em `wallets_controller.rb:124`, exibido em `.../wallets/helper/_body.html.erb:26`, e os selects usam `Wallet.all`. Tipos de recebível: idem (`receivable_kinds_controller.rb:125`; `ReceivableKind.order(title: :asc).all`). Fontes de recurso: o select é `ResourceSource.all.order(title: :asc)` e o model **nem tem scope `active`** — pior, o valor padrão do select é `ResourceSource.first.id`, que também ignora o interruptor. É o **D-19**.
- **Opções:** (a) passar a filtrar: desativado some dos selects, mas continua visível em registros antigos; (b) manter como está (o interruptor continua decorativo); (c) filtrar apenas nos formulários de **criação**, mantendo o item disponível na edição de registros que já o usam.
- **Default vigente:** (a) — um interruptor que não desliga nada é pior que interruptor nenhum.
- **Recomendação:** (c). É (a) sem o efeito colateral que P-028 descreve, que é exatamente o que acontece quando se filtra sem pensar na edição.

### P-028 — Editar uma remuneração cujo tipo foi desativado mostra o tipo errado

- **Origem:** `Q-26`
- **Fatia:** S8
- **Trava:** trava `FE-304`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O formulário de remuneração monta os selects com `RiskOperationType.active` e `StructuredOperationType.active` (`.../remunerations/helper/_body.html.erb:20-21`). Na edição o select fica `disabled`, mas as opções continuam vindo do `.active` — então, se o tipo tiver sido desativado, o `selected` não casa com nada e **a tela mostra o primeiro tipo ativo, não o tipo real da remuneração**. O usuário vê um dado errado sem nenhum aviso.
- **Opções:** (a) na edição, incluir o tipo atual na lista mesmo desativado, marcado como "(desativado)"; (b) recusar a edição de remuneração cujo tipo foi desativado; (c) replicar o comportamento atual.
- **Default vigente:** (a) — é o menor conserto possível e elimina um dado exibido errado.
- **Recomendação:** (a), e vale como regra geral do ai9 para todo select de catálogo com `is_active`, não só aqui.

### P-029 — `nominal_tax` diverge das checagens calculadas: erro, alerta ou nada?

- **Origem:** `Q-27`
- **Fatia:** S6
- **Trava:** trava `BE-180`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O usuário informa a taxa nominal no formulário (`.../receivables/new/_body.html.erb:389`) e o sistema calcula duas checagens ao lado (`receivable_entry.rb:117-118`), exibidas somente leitura (`:397,407`). **As três nunca são comparadas** — as validações do model terminam em `:36` e não há nenhuma. O único consumo de `nominal_tax` é ser copiada como `agreed_rate` da `RiskOperation` (`:163`), o que significa que uma taxa digitada errada **viaja direto para a exposição de risco**.
- **Opções:** (a) informativo, como hoje; (b) alerta na tela quando a diferença passar de um limiar (a definir por você), sem bloquear; (c) erro de validação, bloqueando o salvamento.
- **Default vigente:** (a) — replicar.
- **Recomendação:** (b), com o limiar vindo de você. É o campo digitado à mão que alimenta o número calculado; um alerta é barato e pega o dedo trocado.

### P-030 — Tarifa do mesmo tipo repetida no mesmo borderô

- **Origem:** `Q-28`
- **Fatia:** S6
- **Trava:** trava `FE-175`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Não há `validates_uniqueness_of` em `app/models/receivable_tax.rb`, o servidor faz um loop cego sobre as tarifas recebidas (`receivables_controller.rb:80-86` e `:105-115`) e o formulário deixa acrescentar quantas linhas quiser do mesmo tipo (`.../receivables/new/_body.js.erb:506-535`). As duas linhas somam no mesmo bucket (`receivable_entry.rb:42-45`), então o resultado é aritmeticamente coerente — mas o operador não tem como perceber que digitou o IOF duas vezes.
- **Opções:** (a) permitir, como hoje; (b) bloquear duplicata do mesmo tipo; (c) permitir com aviso na tela ("IOF já lançado nesta operação").
- **Default vigente:** (a) — pode haver caso legítimo de duas linhas do mesmo tipo com descrições diferentes.
- **Recomendação:** (c). Bloquear pode recusar um lançamento válido; avisar não recusa nada e resolve o caso real, que é o duplo clique.

### P-031 — Excluir tarifa já gravada tem efeito imediato, mesmo se o usuário cancelar

- **Origem:** `Q-29`
- **Fatia:** S6
- **Trava:** trava `FE-176`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O botão de remover tarifa persistida (`.../receivables/new/_body.html.erb:484`) dispara um `DELETE` direto assim que o usuário confirma o modal (`.../new/_body.js.erb:663-681`, linha 674), **fora de qualquer submit do borderô**. O servidor apaga (`receivable_taxes_controller.rb:15-24`) e **não recalcula o borderô pai** — os agregados `tarifas_*` só se corrigem no próximo save do recebível. Cancelar a edição não desfaz a exclusão, e entre a exclusão e o próximo save o borderô fica com totais desatualizados.
- **Opções:** (a) manter o efeito imediato, mas **recalcular o borderô na hora**; (b) postergar a exclusão até o salvamento do borderô (o formulário passa a ter estado pendente); (c) replicar exatamente, inclusive os totais desatualizados.
- **Default vigente:** (b) — é o que o usuário espera de um botão dentro de um formulário com "Salvar".
- **Recomendação:** (b), com (a) como piso inegociável caso você prefira manter o imediato. Um total que fica errado até alguém salvar de novo não pode sobreviver à migração.

### P-032 — Datas de operação: a tela trava, a API aceita

- **Origem:** `Q-30` + `F-17` (fundidas)
- **Fatia:** S7 e S8 (a mesma decisão nos dois módulos irmãos)
- **Trava:** trava `FE-260`, `FE-297`, o bloco 0 das duas fatias (`s7/tasks.md:25`, `s8/tasks.md:27`) e as tarefas 8.11 de S7 e 10.4 de S8.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Na edição de uma operação existente, os campos de data aparecem como `readonly` e, pior, **nem são os campos reais** — a view renderiza `issue_date_fake` e `due_date_fake` (`.../risk_operations/new/_body.html.erb:146,153` e `.../structured_operations/new/_body.html.erb:117,124`). Mas o `permit` do controller aceita `issue_date` e `due_date` no update (`risk_operations_controller.rb:227,230` e `structured_operations_controller.rb:164,168`). Quem usa a tela não edita; quem chama a API edita. Em risco isso **fura o `RiskOperationExtension`**, que é o caminho oficial de prorrogação e o único que deixa rastro.
- **Opções:** (a) alinhar pelo servidor — as datas passam a ser imutáveis no update, e prorrogação só pela extensão; (b) alinhar pela API — o campo vira editável na tela também; (c) liberar a edição com trilha de auditoria obrigatória.
- **Default vigente:** (a) — a UI expressa a intenção, e a API estar aberta é o furo, não a regra. Manter duas semânticas para a mesma pergunta em módulos irmãos é pior que qualquer uma das duas.
- **Recomendação:** (a), **mas confirme com quem opera**: se alguém corrige data errada por API hoje, (c) é o que preserva o trabalho dessa pessoa. Uma data de vencimento que muda sem gerar extensão é exatamente o histórico que ninguém consegue reconstituir depois.

### P-033 — Trocar a empresa de uma operação estruturada move a operação de projeto em silêncio

- **Origem:** `Q-31`
- **Fatia:** S8
- **Trava:** trava `BE-291`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/structured_operation.rb:36` faz `self.project_id = self.company.project_id` num `before_validation` **sem `on:`**, ou seja, também no update. `company_id` é editável no formulário (`.../structured_operations/new/_body.html.erb:53`) e permitido no controller (`:161`). Trocar a empresa move a operação para outro projeto **sem aviso e sem log** — e pode invalidar remuneração e recibo já emitidos. O mesmo padrão existe em `risk_operation.rb:28`.
- **Opções:** (a) proibir a troca de empresa depois da criação (é o que `projects` já decidiu para empresa→projeto, DC-04); (b) permitir com confirmação explícita e evento na trilha de auditoria; (c) replicar o comportamento atual.
- **Default vigente:** (a) — mover uma operação de projeto arrasta escopo, cobrança e recibo.
- **Recomendação:** (a). Se o caso de uso existir de verdade, ele merece um fluxo próprio com revalidação, não um select de formulário.

### P-034 — Operação encerrada continua candidata a cobrança

- **Origem:** `Q-32`
- **Fatia:** S8
- **Trava:** trava `BE-306`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/remuneration.rb:26` monta os candidatos a recibo filtrando **só** por projeto, tipo de operação e `receipt_id: nil` — sem olhar `is_ended` nem `due_date`. Os scopes `available_for_receipt` (`risk_operation.rb:2`, `structured_operation.rb:10`) também são só `receipt_id: nil`. Isso alimenta `Charge#receipt_candidates` (`charge.rb:34-46`) e a tela de cobrança (`charges_controller.rb:24`). Uma operação marcada como encerrada continua aparecendo para faturar.
- **Opções:** (a) manter como está; (b) excluir operações encerradas da lista de candidatos; (c) mantê-las na lista, marcadas como "encerrada", e o operador decide.
- **Default vigente:** (a) — pode haver cobrança legítima de operação já encerrada.
- **Recomendação:** (c). É a resposta que não perde faturamento nem esconde informação — e depende de **P-016**, porque é a mesma pergunta sobre o que "encerrar" significa.

### P-035 — A busca de operações estruturadas ignora número de contrato e empresa

- **Origem:** `Q-33`
- **Fatia:** S8 (e S7, pelo mesmo motivo)
- **Trava:** trava `BE-281`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `structured_operations_controller.rb:30` busca por `carriers.title` e `structured_operations.title`, e nada mais — apesar de o `joins(:company)` já estar ali (`:22`) e de portador **e empresa** aparecerem lado a lado na tabela (`.../structured_operations/_body.html.erb:63`). O `contract_number` nem é buscável, embora seja chave de ordenação (`structured_operation.rb:82-83`). Empresa só se filtra por dropdown (`:27`). O mesmo acontece em risco (`risk_operations_controller.rb:30`).
- **Opções:** (a) replicar a busca como está; (b) ampliar para incluir `contract_number` e `companies.title` nas duas telas.
- **Default vigente:** (a) — ampliar é mudança visível que ninguém pediu.
- **Recomendação:** (b). Uma busca que não acha pelo que está escrito na coluna ao lado é lida como bug pelo usuário, não como escopo — e numa demo isso aparece.

### P-036 — Renomear o indicador reescreve o histórico dos lançamentos

- **Origem:** `Q-34` + `F-11` (fundidas)
- **Fatia:** S10
- **Trava:** trava `BE-322`, `DB-310`, o bloco 0 de S10 (`s10/tasks.md:29`) e a tarefa 2.4.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Cada `IndicatorEntry` guarda cópia de `title`, `key` e `value_type` do indicador (`indicator_entry.rb:23-27`). E um `after_save` no indicador faz `self.entries.update_all({title:, key:, value_type:})` (`app/models/indicator.rb:48-50`) — **sem callbacks, sem validação, atingindo todos os lançamentos de todos os projetos**. Renomear o indicador em 2026 faz o lançamento de 2023 dizer que sempre se chamou assim. Existe até um `Indicator.fix_titles` (`:88-92`) que dispara isso em massa. É o **D-70**, a mesma família do D-30 (P-019).
- **Opções:** (a) replicar o resultado (o histórico continua sendo reescrito), tirando pelo menos o `update_all` de dentro do request; (b) **foto do momento** — o lançamento guarda o nome que o indicador tinha na época, e renomear não reescreve nada; (c) derivar sempre do indicador atual (a cópia desaparece e o lançamento nunca mente sobre o presente).
- **Default vigente:** conflitante — o mapa fixou (b) ("se a coluna existe e é copiada, a intenção era congelar"), o empacotamento fixou (a) ("é o comportamento observado hoje"). **Precisa da sua palavra.**
- **Recomendação:** (c). É a única que não obriga a decidir "qual dos dois nomes é o certo" — e o nome de um indicador é rótulo, não dado histórico. Se o negócio quiser o histórico, (b); mas então o `update_all` tem que morrer.

### P-037 — Na grade de indicadores, "não lançado" e "lançado como zero" são o mesmo `0`

- **Origem:** `Q-35`
- **Fatia:** S10
- **Trava:** trava `FE-326`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A grade instancia um `IndicatorEntry.new` quando não há lançamento (`.../indicator_entries/list/_widget.html.erb:14`) e renderiza `value: entry.value.blank? ? 0 : entry.value` nas quatro variantes (`:27,:32,:52,:57`). Como a coluna tem default `0.0`, ausência e zero saem idênticos — e nem a cor distingue (positivo verde, negativo vermelho, zero e vazio ambos neutros). Existe um `beauty_value` que devolveria `"N/A"` para entrada sem id (`indicator_entry.rb:29-33`) e **a grade não o usa**. **Verificado:** a grade **não tem nenhuma linha ou coluna de total**, então distinguir os dois **não muda nenhuma soma** — muda só a célula.
- **Opções:** (a) distinguir: célula vazia (ou `—`) para não lançado, `0` para zero lançado; (b) manter os dois como `0`; (c) distinguir e ainda destacar visualmente as células não lançadas do mês corrente.
- **Default vigente:** (a) — é a mesma disciplina do D-117 (`format_money` renderiza nulo como R$ 0,00): num sistema financeiro, campo nulo e campo zerado não podem ser indistinguíveis.
- **Recomendação:** (a), e o custo é usar um método que o legado já escreveu e esqueceu de chamar. **Responda junto com P-082**: só faz sentido apagar um lançamento se "não lançado" for visualmente diferente de "zero".

### P-038 — O título do indicador continua em CAIXA ALTA sem acento?

- **Origem:** `Q-36` + `F-19` (fundidas)
- **Fatia:** S10
- **Trava:** trava `BE-321`, o bloco 0 de S10 (`s10/tasks.md:28`) e a tarefa 2.2.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/indicator.rb:39` faz `self.title = I18n.transliterate(self.title).upcase` num `before_validation` **sem `on:`** — em todo save, e duplicado em `:43` no callback de criação. A `key` deriva do mesmo (`:44`). **Ponto do ETL que não tem volta:** os acentos originais **já se perderam no dado legado**, então o dado migrado chega em caixa alta de qualquer forma; "re-humanizar" seria adivinhação. A diferença aparece só no que for digitado depois. **Conflito interno:** o mapa manda replicar; a spec de `BE-321` diz que o título aparece **como digitado**, com a comparação de unicidade ignorando acento e caixa.
- **Opções:** (a) preservar o que foi digitado, normalizando só para comparação (a spec); (b) continuar forçando caixa alta sem acento, e a tela fica homogênea (o mapa); (c) (a) mais uma passagem manual de "re-humanização" dos títulos existentes, feita por gente; (d) parar de transformar o dado e resolver a aparência só na camada de apresentação.
- **Default vigente:** conflitante — o mapa fixou (b), a spec fixou (a). **Precisa da sua palavra.**
- **Recomendação:** (a) + (c) se forem poucos indicadores. A tela mista (uns em caixa alta, outros não) é feia e vai ser notada na demo; e (d) guarda o dado como está e resolve a aparência na camada certa, sem inventar acento nenhum.

### P-039 — Reconectar um indicador recupera o histórico: é o desejado?

- **Origem:** `Q-37`
- **Fatia:** S10
- **Trava:** trava `BE-710`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/project_indicator_connection.rb` (9 linhas) não tem `dependent:` nem callback nenhum, e desconectar só destrói a linha de conexão (`project_indicator_connections_controller.rb:87-91`). Os lançamentos sobrevivem porque estão presos ao **indicador**, não à conexão (`indicator.rb:4`, `has_many :entries, dependent: :delete_all`). Reconectar recria a conexão (`:80-86`) e a grade reencontra tudo intacto.
- **Opções:** (a) replicar (desconectar esconde, reconectar traz de volta); (b) desconectar passa a apagar os lançamentos daquele projeto; (c) desconectar arquiva os lançamentos explicitamente, com aviso na tela do que vai acontecer.
- **Default vigente:** (a) — é conservador e não perde dado.
- **Recomendação:** (a) com o aviso de (c) na tela. O comportamento está certo; o que falta é a tela dizer que os lançamentos ficam guardados.

### P-040 — Dois itens de menu chamados "Indicadores"

- **Origem:** `Q-38`
- **Fatia:** S2 (menu) e S10
- **Trava:** trava `FE-324`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/helpers/application_helper.rb:113` põe "Indicadores" no grupo **Gestão** (são os **lançamentos**) e `:142` põe "Indicadores" no grupo **Cadastro** (é o **catálogo**). Rótulo idêntico, telas diferentes. Há ainda um terceiro, esse distinguível: "Indicadores específicos" no grupo Projeto (`:131`). Os títulos de aba do navegador também colidem em parte (`console_controller.rb:353`).
- **Opções:** (a) "Indicadores" (catálogo) e **"Lançamentos de indicadores"** (gestão); (b) "Cadastro de indicadores" e "Indicadores"; (c) replicar os dois rótulos iguais.
- **Default vigente:** (a).
- **Recomendação:** (a). Custo zero, e resolve um item em que o cliente clica errado na primeira tentativa da demo.

### P-041 — `resource_kinds` e `resource_sources` são indistinguíveis

- **Origem:** `Q-39`
- **Fatia:** S8
- **Trava:** depende de **P-070** — se `resource_kinds` for descartado, esta pergunta desaparece.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O **título de aba é idêntico byte a byte** — `"Safegold - Tipos de Recursos"` para os dois (`console_controller.rb:348-349` e `:358-359`) — mas **rótulo de menu só existe para `resource_sources`** (`application_helper.rb:153`); `resource_kinds` **não tem item de menu nenhum** e só é alcançável digitando a URL. Os títulos das próprias páginas diferem por **uma letra**: "Tipos de Recurso" (`.../resource_kinds/_body.html.erb:3`) contra "Tipos de Recursos" (`.../resource_sources/_body.html.erb:3`).
- **Opções:** (a) se os dois sobreviverem, renomear — por exemplo "Naturezas de recurso" (`resource_kinds`) e "Fontes de recurso" (`resource_sources`); (b) manter os nomes atuais; (c) fundir os dois cadastros num só.
- **Default vigente:** (a) — mas só se aplica se P-070 mantiver `resource_kinds`.
- **Recomendação:** (a), com os nomes vindos de você: qual é a diferença de negócio entre os dois é a informação que falta, e o código não a tem.

### P-042 — Renegociação: `provider_name` no detalhe, `title` na lista

- **Origem:** `Q-40`
- **Fatia:** S9
- **Trava:** trava `FE-196`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A lista de renegociações identifica cada linha por `r.title` em negrito (`.../renegotiations/list/_widget.html.erb:6`), com `provider_name` só como subtítulo (`:8`). Mas o detalhe grava o **`provider_name`** no histórico do navegador (`.../renegotiations/detail/_body.js.erb:87-91`), então o título da aba e o "voltar" mostram outra coisa. O cabeçalho do detalhe exibe os dois (`.../detail/_body.html.erb:10` e `:11`).
- **Opções:** (a) `title` prevalece em tudo (lista, aba, cabeçalho); (b) `provider_name` prevalece; (c) título composto ("`title` — `provider_name`").
- **Default vigente:** (a) — é o que a lista usa, e a lista é por onde o usuário entra.
- **Recomendação:** (c) na aba do navegador e (a) na tela. Quem tem várias renegociações abertas em abas precisa distinguir pelo fornecedor.

### P-043 — URLs públicas de contrato com espaço e com erro de acento

- **Origem:** `Q-41`
- **Fatia:** S12
- **Trava:** trava `BE-331` e `FE-335`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O tipo do contrato viaja **cru na URL**, em português, com espaço e com o typo consolidado: `@@KIND__PRIVACY_POLICY = "Politicas de Privacidade"` (sem acento em "Políticas", `app/models/contract.rb:14`), e a rota recebe a string como parâmetro (`config/routes.rb:48`). No HTML aparece escapado — `/contract/Termos%20de%20Uso` e `/contract/Politicas%20de%20Privacidade` (`.../sign_up/_sign_up.html.erb:61`) — e interpolado com espaço literal no menu do console (`.../base/menu/_container.html.erb:37,40`) e em "Minha Conta" (`:119,122`). Essas URLs existem em links externos.
- **Opções:** (a) adotar slug (`/contratos/termos-de-uso`, `/contratos/politica-de-privacidade`) com **redirect 301** das strings antigas, inclusive a com o typo; (b) preservar a string literal, typo incluído; (c) slug sem redirect.
- **Default vigente:** (a).
- **Recomendação:** (a). O redirect é barato e é o que impede que um link em contrato assinado ou em e-mail antigo pare de funcionar.

### P-044 — O ETL do legado atribuiu todos os borderôs antigos ao usuário 1 e à empresa 1

- **Origem:** `Q-42`
- **Fatia:** S14
- **Trava:** trava `OPS-150`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O importador força a autoria: `app/models/legacy/receivable_entry.rb:65` — `user_id: 1, # forçado mestre dos magos` — e `:67` — `company_id: 1 # forçado por questão de portabilidade`. Todo borderô importado aparece como criado pela mesma pessoa e pertencente à mesma empresa (~62 mil registros). **Duas correções ao material** (ver A-15): não é um ETL Django, é um módulo Ruby dentro do próprio Rails; e a janela não é 2016-2021, porque o importador não filtra data.
- **Opções:** (a) manter a atribuição como está; (b) reatribuir a partir do dado original do legado, se ele existir no dump; (c) manter e marcar explicitamente como "importado" — **sem autor e sem empresa atribuída**, em vez de atribuir a pessoa errada.
- **Default vigente:** (a) — o número não muda e a demo roda com seed próprio.
- **Recomendação:** (c). Atribuir a autoria de 62 mil borderôs a uma pessoa que não os criou é dado errado que ninguém consegue distinguir de dado certo depois.

### P-045 — Contratos: o texto vem do arquivo versionado ou da linha que está no banco?

- **Origem:** `Q-43` + `F-45` (fundidas)
- **Fatia:** S12, semeada por S14; consumida por S13
- **Trava:** trava o seed de contratos, o que o usuário lê no dia 1, e a **tarefa 1.1 de S13**, que é a **primeira da fatia** (`s13/tasks.md:22-25`): `OPS-477` (leitor de arquivo com limite de tamanho) só existe se a resposta for "de arquivo".
- **Impacto:** `muda comportamento observável`
- **Contexto:** O legado carrega o texto dos contratos de arquivos versionados — `db/seeds.rb:113-116` referencia `privacy.html` e `tou.html` em `db/seed_assets/contracts/` — mas o texto que vale em produção é o que está gravado em `action_text_rich_texts` (`app/models/contract.rb:11`, `has_rich_text :description`), editável pelo console. Os dois podem ter divergido a qualquer momento nos últimos anos, e não há como saber qual foi aceito (ver P-067). Existe ainda um terceiro arquivo órfão, `db/seed_assets/contracts/user.html` (20 bytes), que **nenhum seed carrega**.
- **Opções:** (a) semear a partir do arquivo versionado **apenas se não houver contrato no banco**, preservando o que já existe → S12 escreve o leitor e `OPS-477` existe; (b) semear com conteúdo **inline** no seed → `OPS-477` vira `dropped` por "sem consumidor"; (c) importar o texto do banco e ignorar os arquivos; (d) o documento órfão é **registrado e não carregado**, e o conteúdo real dos contratos vem de você.
- **Default vigente:** (a) do lado do mapa, (d) do lado de S13. **Divergem, mas são compatíveis:** (a) descreve a origem do texto, (d) descreve o que fazer com o arquivo órfão.
- **Recomendação:** (a) para preservar o que está no ar, com (d) para o `user.html`. Termos de Uso de um produto que vai ser vendido não deve nascer de um HTML órfão de 2021 que ninguém revisou. E vale conferir o diff entre arquivo e banco no dry-run: se divergirem muito, é sinal de que alguém editou pelo console e o repositório ficou para trás.

### P-046 — Qual é a cor primária da marca?

- **Origem:** `Q-44`
- **Fatia:** transversal (a tematização roda antes de qualquer tela) e S17
- **Trava:** trava a paleta do produto inteiro. **Não pode ser inferida do código.**
- **Impacto:** `muda comportamento observável`
- **Contexto:** Há **quatro** valores vivos ao mesmo tempo, em camadas diferentes, e um quinto de fallback. `#2D2D2A` está em `app/definitions/SFG/theme.rb:32` (`COLOR__PRIMARY`) e — verificado — **nunca é lido por nada**. `#050517` está em `app/frontend/css/pub/colors.scss:1` (`$primary`) e é o que **de fato compila** para `.primary-color` (`:103-108`). `#373435` é o que a factory grava no banco (`db/factories/app_theme_factory.rb:17`). `#504746` está em `engines/ux_kit19/lib/livetat/ux_kit19/configuration.rb:14`. E quando `primary_color` é nulo, `app/models/app_theme.rb:200-201` cai em `#444444`. Como o motor de temas não pintava nada (todo o CSS do template está dentro de um comentário), **nem o valor do banco chegava à tela**.
- **Opções:** (a) `#2D2D2A` (o valor canônico declarado, e o que `brand-and-metadata.md` já registra); (b) `#050517` (o que o usuário de fato vê hoje, porque é o que compila); (c) você fornece o hex oficial da marca.
- **Default vigente:** (a), com confirmação **visual contra o app rodando**.
- **Recomendação:** (c) se existir manual de marca; senão (b), porque é a cor que o cliente reconhece como "o sistema dele". `#2D2D2A` e `#050517` são visualmente muito diferentes — isto não é detalhe, e o DEC-22 marcou como item a resolver antes da demo.

### P-047 — O login por Facebook continua existindo?

- **Origem:** `Q-45`
- **Fatia:** S1
- **Trava:** nada — só muda quem consegue entrar.
- **Impacto:** `muda comportamento observável`
- **Contexto:** No legado está morto por duas pontas: `app/definitions/SFG/metadata.rb:4-5` tem `FACEBOOK_APP_ID = 0` e `FACEBOOK_APP_SECRET = 0`, e **não existe nenhum botão de Facebook em nenhuma view** — o formulário de login (`.../sign_in/_sign_in.html.erb:12-43`) tem só login/senha. Os handlers JS ficaram órfãos, ligados a um seletor que nunca casa (`:22,30`), e o provider Devise segue declarado (`engines/auth_omni19/app/decorators/user_decorator.rb:2`). É o **D-41**. No ai9, o login social **funciona** e vem com Google junto.
- **Opções:** (a) manter ligado no ai9 (custo zero, já existe) e anunciar na tela; (b) manter ligado e **não** anunciar até você confirmar; (c) desligar os dois provedores sociais.
- **Default vigente:** (b).
- **Recomendação:** (b), e provavelmente (c) para o Facebook: com **DEC-14** (entrada por código de e-mail ou WhatsApp) e **DEC-18.7** (só por convite), um provedor social a mais é uma superfície de identidade a mais para pouco ganho.

### P-048 — ETL: o que acontece com `is_active` e com `legacy_password`?

- **Origem:** `Q-46`
- **Fatia:** S14
- **Trava:** trava a carga de usuários — define quem consegue entrar no dia 1.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O importador do legado copia a senha antiga para uma coluna `legacy_password` e ainda inventa uma senha determinística a partir do primeiro nome + `#6230` (`app/models/legacy/u.rb:28` e `:30`). O `is_active` vem do sistema Django antigo e nunca ficou claro se `0` significa "conta desligada" ou "nunca ativada". O ai9 não tem senha nenhuma (DEC-14: entrada por código), e o bloco de auth já decidiu que o bloqueio de conta vira `users.blocked_at` (DC-07).
- **Opções:** (a) `is_active = 0` nasce com `blocked_at` preenchido e o usuário sai numa **lista de exceções** para revisão humana antes do cutover (mesmo tratamento do papel vazio, DEC-18 #8); `legacy_password` **não é migrado**; (b) `is_active = 0` nasce ativo (assumindo "nunca ativado") — todos entram; (c) `is_active = 0` não é migrado de forma alguma.
- **Default vigente:** (a) — bloquear e revisar é reversível; liberar por engano não é.
- **Recomendação:** (a). E `legacy_password` não deve nem chegar ao banco novo: é hash de um sistema que não existe mais, num produto sem senha.

### P-049 — Alguém entra hoje digitando **username** em vez de e-mail?

- **Origem:** `Q-47`
- **Fatia:** S14 (dry-run) e S1
- **Trava:** é um possível **bloqueador de cutover**, não de código.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O legado autentica por uma chave genérica: `engines/auth19/config/initializers/devise.rb:14` define `authentication_keys = [:login]`, e a resolução aceita os dois — `engines/auth19/app/models/livetat/auth/user.rb:108`: `where(["lower(username) = :value OR lower(email) = :value", …])`. O próprio campo anuncia: `placeholder="user ou e-mail"` (`.../sign_in/_sign_in.html.erb:22`). Há inclusive um caminho JSON alternativo por `user_name`. No ai9, a identificação é por **e-mail ou telefone** — quem só sabe o próprio `username` perde o acesso no dia 1. **Consulta 6 da seção 5** resolve.
- **Opções:** (a) assumir que ninguém usa e seguir; (b) o dry-run **conta** quantos usuários têm `username` e não têm e-mail válido, e o número decide; (c) portar `username` como identificador alternativo no ai9.
- **Default vigente:** (b) — se houver algum, isto vira bloqueador de cutover.
- **Recomendação:** (b). É uma consulta no dump e responde de vez; (c) só se o número for grande, porque acrescenta uma terceira chave de identidade a uma base compartilhada.

### P-050 — "Verificação: {nível}" — o telefone verificado volta a existir?

- **Origem:** `Q-48` (funde duas perguntas do mesmo mapa)
- **Fatia:** S1
- **Trava:** trava o desenho do indicador de confiabilidade do perfil.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O nível é calculado numa escada de quatro degraus (`engines/auth19/app/models/livetat/auth/user_info.rb:53-74`) e o degrau mais alto — "Máxima" — depende **só** de `is_phone_checked` (`:59`). Só que **não existe fluxo de verificação de telefone no legado**: a única forma de a flag virar 1 é mass-assignment pelo formulário (`app/decorators/controllers/registrations_decorator.rb:104`), e, uma vez ligada, ela **trava o campo de telefone para sempre** (`.../my_account/parts/phone/_container.js.erb:14-16`, `prop('readonly')`). O degrau máximo é inalcançável e o campo fica preso sem saída. **Verificado, e por isso não pergunto separado:** o nível **não decide nenhuma regra de negócio** — a única leitura fora da exibição é `user_decorator.rb:272`, que expõe `nice_info` num JSON. No ai9 o telefone **é verificado de verdade**, porque é canal de login (DEC-14).
- **Opções:** (a) marcar como verificado quando a pessoa entrar por código de WhatsApp/SMS naquele número, e o campo deixa de travar sem saída; (b) remover o indicador de confiabilidade inteiro (ele não decide nada); (c) replicar como está.
- **Default vigente:** (a).
- **Recomendação:** (a). O ai9 torna verdadeiro um indicador que no legado era decorativo, e o custo é zero porque a verificação já acontece no login.

### P-051 — Onde ficam os arquivos em produção?

- **Origem:** `Q-49` + `F-41` (fundidas; levantada em dois mapas)
- **Fatia:** S18 e S13, com efeito em S9 (anexos de renegociação) e S17
- **Trava:** não trava a demo. **Trava o cutover**, e o runbook de S14.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base ai9 só tem serviço de disco local: `backend/config/storage.yml` declara apenas `local` e `test`, e `backend/config/environments/production.rb:10` faz `config.active_storage.service = :local`. Ou seja, **produção grava anexo no disco do container**. Sem volume persistente garantido pelo deploy, **anexo desaparece entre deploys** — avatar, logo e, principalmente, os documentos de renegociação, que são documento financeiro (`s9/design.md:179-183`). No legado tudo vive em `public/system/:attachment/:id/…` no disco da máquina, via kt-paperclip (11 anexos, 44 colunas).
- **Opções:** (a) escolher provedor agora (S3, GCS, R2…) e configurar; (b) `Disk` com **volume persistente garantido** pelo deploy, com o requisito de infraestrutura documentado; (c) `Disk` para a demo, e a decisão de provedor vira item **obrigatório** do runbook de cutover.
- **Default vigente:** (c).
- **Recomendação:** (c) para sexta, com (a) ou (b) **escrito no runbook com data**. Documento financeiro privado em disco de container é o tipo de decisão que só aparece quando o arquivo já sumiu — normalmente no primeiro redeploy depois da venda.

### P-052 — Com DEC-14 (sem senha), o que dizem os e-mails "Perdeu a senha?" e "Nova senha configurada"?

- **Origem:** `Q-50`
- **Fatia:** S1
- **Trava:** trava `BE-481` e `BE-482`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** São dois e-mails cujo assunto e corpo falam de uma coisa que o produto **não tem mais**: o ai9 não tem senha em lugar nenhum (verificado — nenhuma coluna `encrypted_password`, `devise :omniauthable` e nada mais). Mas os gatilhos continuam fazendo sentido: "pedi um novo acesso" e "minha credencial mudou".
- **Opções:** (a) preservar os gatilhos e **reescrever os textos** ("Seu código de acesso" / "Seu acesso foi alterado"), registrando no `improvements-log`; (b) não portar os dois e-mails; (c) portar os textos como estão.
- **Default vigente:** (a).
- **Recomendação:** (a). Um e-mail que fala de senha num produto sem senha é o tipo de detalhe que o cliente nota numa demo.

### P-053 — A precedência de papel do importador estava invertida — reprocessamos?

- **Origem:** `Q-51` + `F-21` (fundidas)
- **Fatia:** S14
- **Trava:** trava `BE-453` e o de-para de papéis no ETL.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/legacy/u.rb:33` decide o papel com um ternário aninhado: `o.role_type = i.is_staff ? ::U.MANAGER : i.is_superuser ? ::U.ADMIN : ::U.COLAB`. A marca de **equipe** é avaliada primeiro, então quem era `is_staff = true` **e** `is_superuser = true` foi importado como **Gerente**, nunca como Admin. Isso definiu papéis de usuários que **ainda estão ativos desde 2021** — e é justamente o papel que a matriz do DEC-18 vai passar a **aplicar de verdade**. **Consulta 7 da seção 5** produz a lista.
- **Opções:** (a) não reprocessar; o dry-run **lista** os usuários nessa condição para revisão humana antes do cutover (mesma disciplina do DEC-19); (b) reprocessar automaticamente, promovendo quem tinha `is_superuser`; (c) reprocessar e pedir a cada um desses usuários que confirme o papel.
- **Default vigente:** (a).
- **Recomendação:** (a). A lista custa uma consulta; a promoção automática é escalação de privilégio por script, ainda que bem-intencionada, e não é reversível sem susto.

### P-054 — O mapeamento de gênero está certo? (hoje, quem não preencheu é tratado como homem)

- **Origem:** `Q-52`
- **Fatia:** S14 e S1
- **Trava:** trava `FE-432` e a migração de `user_infos.gender`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/helpers/application_helper.rb:15-20` monta a concordância assim: `1` devolve `"a"` (feminino), `2` devolve `""` (neutro) e **qualquer outro valor, incluindo `nil` e `0`, devolve `"o"`** (masculino). A coluna é `integer` sem default e sem validação de domínio (`engines/auth19/db/migrate/20171020133117_create_livetat_user_infos.rb:7`).
- **Opções:** (a) migrar os valores como estão e usar formulação **neutra** quando desconhecido — nunca masculino por padrão; (b) replicar o fallback masculino; (c) migrar como estão e perguntar o gênero no primeiro acesso.
- **Default vigente:** (a).
- **Recomendação:** (a). O dado migra intacto e o texto para de afirmar uma coisa que ninguém informou.

### P-055 — Na tela de mensagens, pedir "Concluído" grava "Fechado" (e vice-versa)

- **Origem:** `Q-53`
- **Fatia:** S2
- **Trava:** trava `BE-527`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Os dois estados existem e são distintos (`engines/feedback19/app/models/livetat/feedback19/state.rb:11-12`). No `update`, escolher "Concluído" no select grava **"Fechado"**: `messages_controller.rb:118-119` — `if message_params[:state_id].to_i == State.done.id then @message.state_id = State.closed.id`. **A inversão é dupla:** a action chamada `close` (`:156-159`, rota `PUT /messages/:id/close`) grava **"Concluído"**. Os dois estados estão trocados **entre si**, não é um typo num lado só.
- **Opções:** (a) corrigir os dois — "Concluído" grava Concluído, "Fechar" grava Fechado; (b) replicar a inversão; (c) fundir os dois estados num só (a distinção nunca foi usada de forma coerente).
- **Default vigente:** (a), com linha no `improvements-log.md` porque é comportamento observável.
- **Recomendação:** (a). Com a inversão nos dois sentidos, "alguém se acostumou com o comportamento atual" deixa de ser plausível: não há comportamento coerente com que se acostumar.

### P-056 — O envio anônimo de mensagem de feedback é usado?

- **Origem:** `Q-54`
- **Fatia:** S2
- **Trava:** trava `BE-531` e a allowlist pública de rotas.
- **Impacto:** `muda comportamento observável`
- **Contexto:** No legado o `POST` de mensagem é **público de propósito**: `engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:6` isenta explicitamente o `create` da autenticação por token, e a action não referencia `current_user` (`:85-105`). O único filtro restante, `lock_if_its_not_a_valid_client_app`, faz **bypass total** quando o formato é HTML ou JS (`engines/auth_ux19/.../application_controller.rb:21-27`) — e o console usa `format: :js`, então na prática não bloqueia nada. Vale lembrar que o próprio `api/root.rb:14-17` da base ai9 registra que um bypass por header já vazou a base inteira até 01/08/2026.
- **Opções:** (a) só autenticado; (b) público, mas **por rota na allowlist**, com throttle do Rack::Attack e captcha; (c) público sem throttle (como hoje).
- **Default vigente:** (a) — e, se o anônimo for necessário, (b).
- **Recomendação:** (a). Com o cadastro público desligado (DEC-18.7), não sobra visitante legítimo para usar o canal anônimo.

### P-057 — O autopreenchimento por CNPJ (ReceitaWS) volta a funcionar?

- **Origem:** `Q-55`
- **Fatia:** S4 (empresas e fornecedores)
- **Trava:** nada — é um botão.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O backend está **vivo e configurado**: gem no `Gemfile.linux:39`, `config/initializers/receitaws.rb:5` (token), `:10` (cache de 365 dias), `:14` (timeout de 10 s), serviço em `app/helpers/cnpj_api.rb:3` e endpoint em `app/controllers/pub/providers_controller.rb:121-133`. A UI está **duplamente morta**: o botão está comentado (`.../providers/helper/_body.html.erb:54-56`) e a URL do JS tem ERB escapado (`.../helper/_body.js.erb:155` usa `<%%=`, então o literal chega ao navegador). É o **D-27**, e a integração é **paga**. **Nota de segurança que sai junto:** o token real está versionado no repositório (`config/application.arch.yml:12`) e precisa ser rotacionado de qualquer forma (ver P-107).
- **Opções:** (a) ligar (o endpoint existe, o custo é reconectar o botão); (b) não portar; (c) ligar com limite de chamadas por usuário/dia, por causa do custo por consulta.
- **Default vigente:** (a).
- **Recomendação:** (c). É a mesma feature, com a única precaução que o legado não tinha — e o custo por consulta é seu, não nosso.

### P-058 — O logo do Portador volta a existir?

- **Origem:** `Q-56`
- **Fatia:** S3 (cadastros globais)
- **Trava:** nada.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Está morto por metade: o bloco HTML do upload está comentado no formulário (`.../carriers/helper/_body.html.erb:13-23`, com o `file_field` na linha 21) e a exibição está comentada na lista (`.../carriers/list/_widget.html.erb:3-12`) — mas o handler JS está vivo, ligado a um input que não existe (`.../helper/_body.js.erb:12-13`), o `permit` aceita `logo` (`carriers_controller.rb:140`) e o model tem o anexo completo, com validações (`app/models/carrier.rb:16,32-33,79-80`). É o **DC-10**. Os outros anexos de logo do legado são **projeto** (`project.rb:48`, `avatar`) e **fornecedor** (`provider.rb:12`, `logo`) — **`Company` não tem anexo nenhum**.
- **Opções:** (a) ligar, reusando a mesma pilha ActiveStorage dos outros dois; (b) não portar; (c) ligar e acrescentar também logo de empresa (feature nova).
- **Default vigente:** (a).
- **Recomendação:** (a). É um campo, a coluna já existe, e o dry-run precisa contar quantos portadores têm arquivo antes de migrar binários.

### P-059 — A coluna `default_position` existe no banco de produção?

- **Origem:** `Q-57`
- **Fatia:** S11 (padrões de disponibilidade)
- **Trava:** nada para começar. É uma consulta no dump — **consulta 1 da seção 5**.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/controllers/pub/availability_templates_controller.rb:22` ordena a busca por `default_position`, e a coluna aparece também em três views. **Nenhuma migration a cria** — as migrations criam `position` e `parent_position` (`db/migrate/20210420180734_create_availability_templates.rb:22,24`). Se a coluna **não** existe, a busca de padrões globais está quebrada em produção há anos e ninguém reclamou; se **existe**, é a segunda prova de schema fora do versionamento (junto com `contracts.description`, D-108) e o **DEC-04** precisa ser revisitado com o dump em mãos. **Achado adjacente na mesma action:** a linha `:21` monta o `where!` com um fragmento SQL malformado (`"title #{Dev.ilike} "`, sem o placeholder) — a busca por texto tem um segundo problema, independente da coluna.
- **Opções:** (a) assumir que não existe; a busca nasce ordenada pela hierarquia e registra-se para o dry-run confirmar; (b) rodar `\d availability_templates` no dump agora e decidir com o fato; (c) criar a coluna no ai9 de qualquer forma.
- **Default vigente:** (a).
- **Recomendação:** (b). A consulta leva um minuto e também fecha o DEC-04, que hoje carrega o risco como "aceito e documentado".

### P-060 — As 4 rotas públicas de auto-cadastro da base ai9: tirar da allowlist ou gatear pela flag?

- **Origem:** `F-22`
- **Fatia:** S1 (a rota) e S19 (a flag `FE-444`)
- **Trava:** nada hoje — S1 tarefa 2.1 já manda tirar. O que falta é a **decisão de tocar a base compartilhada**.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Conferido em `backend/app/controllers/api/root.rb:36,38,45,46` — `pre_register`, `complete_registration`, `visitor_signup` e `visitor_signup_with_link` estão na **allowlist pública**. Ou seja: o **D-39** (auto-cadastro público), que o DEC-18.7 desligou do lado do legado, **volta sozinho** por essa porta, que nunca veio do legado. S1 tarefa 2.1 manda retirar as 4 e a 2.2 manda desmontar os endpoints em `api/auth/v1/registration.rb`; S19 constrói a flag `public_create_user?` nascendo `false`. **A tensão:** `api/root.rb` e `registration.rb` são da **base compartilhada** (Princípio 6b — não refatorar a base), e outros produtos ai9 podem usar essas rotas.
- **Opções:** (a) **remover** as 4 rotas da allowlist e desmontar os endpoints, como S1 escreveu — resolve de vez, mas altera a base para todo mundo; (b) manter as rotas e gateá-las pela flag `public_create_user?` de S19, que nasce `false` — a base fica intacta e o Safegold fica fechado; (c) (a) no Safegold e uma flag de upstream para a base decidir depois.
- **Default vigente:** (a), escrito nas tarefas de S1 — **mas a decisão de mexer na base não foi tomada por ninguém.**
- **Recomendação:** (b). A flag vai ser construída de qualquer jeito, e é a única opção que não deixa o Safegold dependendo de uma remoção que outro produto pode reverter na semana seguinte.

### P-061 — Os papéis do Safegold colidem com os `hierarchy_level` que a base já semeia (contrato C3)

- **Origem:** `F-50` (DS0-4)
- **Fatia:** S0
- **Trava:** trava o seed de `user_types` (`OPS-541`, `DB-730`) e, por tabela, o de-para de papéis do ETL.
- **Impacto:** `muda comportamento observável` — **reclassificada** (o empacotamento a tinha como `só interno`; ela decide quem pode o quê)
- **Contexto:** **Ver o achado A-4.** A decisão declarada (DS0-4) é **acrescentar** os 4 papéis do Safegold sem remover os da base, porque `UserType` é peça compartilhada (Princípio 6b) e `visitor` é usado por `restrict_visitor_access!`. Mas a base já semeia, em `backend/app/models/user_type.rb:37-41`: `OG`=1, `client`=2, `free`=4, `visitor`=5. O de-para escrito no `migration-map.md` é OG→1, Admin→2, Gerente→3, Colaborador→4 — logo **Admin colide com `client`** e **Colaborador colide com `free`**. Dois papéis no mesmo nível fazem `higher_than` (`where('hierarchy_level < ?', level)`) devolver conjuntos que ninguém esperava. É o contrato **C3**, o item de maior risco da migração.
- **Opções:** (a) usar níveis que não colidem, com espaçamento (por exemplo Admin=10, Gerente=20, Colaborador=30); (b) reaproveitar `client` como Admin e `free` como Colaborador — não acrescenta papel, mas muda a semântica de peça compartilhada; (c) manter os níveis colidentes e fazer a comparação considerar nível **e** nome.
- **Default vigente:** (a) implícito — o desenho diz "acrescentar", mas não fixa os números, e o de-para escrito usa 1/2/3/4.
- **Recomendação:** (a), com espaçamento. Colisão de nível num contrato onde inverter o sinal significa "dar poder de OG a um Colaborador" não é lugar para economizar números.

### P-062 — A trilha de auditoria global é visível a que papéis?

- **Origem:** `F-23`
- **Fatia:** S19
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A trilha global é um **índice de tudo que aconteceu no sistema**: quem viu o quê, quem alterou o quê, quando. O histórico **do próprio objeto** (o "quem mexeu nesta renegociação") é outra coisa, e não está em questão aqui.
- **Opções:** (a) trilha global só para OG/Admin; histórico do objeto para quem vê o objeto; (b) trilha global para todos os papéis; (c) trilha global para OG/Admin/Gerente.
- **Default vigente:** (a), declarado pelo agente por conta própria.
- **Recomendação:** (a). É o único caso desta lista em que o default mais restritivo também é o mais barato de afrouxar depois.

### P-063 — A trilha guarda o payload completo do objeto?

- **Origem:** `F-24`
- **Fatia:** S19
- **Trava:** nada no código, mas a forma da tabela `trackings` depende disso.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Trilha que copia o registro inteiro vira o maior objeto do banco em três meses, e num sistema financeiro isso significa **duplicar dado pessoal e financeiro sem política de retenção**. S13 já registrou que o expurgo é requisito novo.
- **Opções:** (a) payload enxuto (evento, entidade, autor, campos alterados); (b) payload completo (a foto inteira do registro); (c) payload enxuto por padrão e completo só para um conjunto **nomeado** de entidades críticas.
- **Default vigente:** (a).
- **Recomendação:** (a). Se aparecer necessidade de foto completa, (c) é aditivo e não quebra nada do que for construído agora.

### P-064 — O CSP nasce em `report-only` ou bloqueando?

- **Origem:** `F-26`
- **Fatia:** S18
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base ai9 **nunca teve CSP**. Ligar bloqueante numa base que nunca teve **quebra tela em silêncio** — recurso bloqueado não dá erro visível, só some.
- **Opções:** (a) `report-only` primeiro, com **prazo escrito** para virar bloqueio; (b) bloqueante desde o início; (c) `report-only` sem prazo.
- **Default vigente:** (a), declarado pelo agente.
- **Recomendação:** (a). Numa demo comercial, tela quebrada em silêncio é o pior modo de falha possível — e (c) é como CSP nunca vira bloqueio em lugar nenhum.

### P-065 — `WhatsappPage.tsx` existe e não está roteada. Ganha rota?

- **Origem:** `F-28` (DS2-2)
- **Fatia:** S2 (dependência de S1)
- **Trava:** nada hoje — mas o login por WhatsApp (DEC-14) **cai** quando a sessão da instância expirar, e ninguém terá como parear.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `frontend/src/app/pages/WhatsappPage.tsx` existe na base e **não tem rota**. É a tela de pareamento por QR de que `EvolutionConnection.send_message` depende via `PolemkInstance.first`. Sem ela, um canal de login do produto tem prazo de validade e nenhuma forma de renovação pelo cliente. Decisão declarada pelo agente: **ganha rota**, gateada por papel administrativo (`s2/design.md:101`).
- **Opções:** (a) rota gateada por OG/Admin; (b) sem rota — o pareamento é feito por console/rake pela equipe da Livetat; (c) rota gateada só por OG.
- **Default vigente:** (a).
- **Recomendação:** (a).

### P-066 — O seletor de idioma fica visível numa interface que não traduz nada?

- **Origem:** `F-30` (DS2-5)
- **Fatia:** S2
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base **tem** o runtime de i18n (`i18next`, `react-i18next`, bundles) e **não traduz nada**: zero componentes chamam `useTranslation`, o bundle `pt-br` tem 255 chaves de marketing de **outro produto**, e o `LanguageSwitcher` não troca idioma. DEC-09 fixou pt-BR. A decisão declarada é **não ligar** (`s2/design.md:104`).
- **Opções:** (a) não ligar, e registrar como flag de upstream; (b) não ligar **e remover** o `LanguageSwitcher` da interface, para ninguém clicar num botão que não faz nada; (c) ligar o i18n.
- **Default vigente:** (a).
- **Recomendação:** (b). Um seletor de idioma visível que não troca idioma é exatamente o tipo de coisa que um técnico do cliente clica na demo.

---

# `muda escopo` — P-067 a P-103

> A resposta decide se algo é construído ou descartado.

### P-067 — Qual é a prova mínima exigida de um aceite?

- **Origem:** `Q-58` + `F-14` (fundidas)
- **Fatia:** S12
- **Trava:** trava `DB-331`, `OPS-333`, a migration `create_contract_deals` (`s12/tasks.md:34`) e é pré-requisito de `BE-342`/`BE-343` (tolerância e bloqueio).
- **Impacto:** `muda escopo`
- **Contexto:** `contract_deals` guarda hoje **`user_id`, `contract_id`, `created_at` e `updated_at`** e nada mais (`db/migrate/20180405164055_create_contract_deals.rb:3-8`). Sem IP, sem user-agent, sem versão congelada e sem impressão do texto — e como o texto vive em `action_text_rich_texts` e pode ser editado no próprio registro, **não há garantia técnica de qual conteúdo foi aceito**. É o **D-65**. O desenho de S12 propõe guardar usuário, versão, data/hora, IP, user-agent e **hash do texto aceito**, com índice único `(user_id, contract_id)` e um exportador de prova (`s12/design.md:88-92, 104`) — o que é **requisito novo, não paridade**.
- **Opções:** (a) manter o mínimo atual (usuário + contrato + data); (b) o conjunto completo proposto: IP, user-agent, **hash imutável do texto** e exportador de prova; (c) (b) **menos o IP**, que é dado pessoal com custo de LGPD e retenção; (d) (b) + versionamento imutável do documento (nova versão = nova linha, edição proibida).
- **Default vigente:** (b) — é a recomendação técnica, mas o mínimo probatório é definição **jurídica**, não de engenharia.
- **Recomendação:** (d). O hash prova o texto, mas sem versão imutável ele não prova **qual versão estava publicada** — e é justamente isso que se pergunta num litígio. IP e user-agent são baratos de guardar e caros de recuperar depois.

### P-068 — Existe estado de baixa, liquidação ou vencimento do recebível?

- **Origem:** `Q-59`
- **Fatia:** S6
- **Trava:** trava `BE-178`.
- **Impacto:** `muda escopo`
- **Contexto:** O recebível tem **um** campo de estado e ele só assume dois valores: `"OK"` e `"Diferença"` (`app/models/entry.rb:10-12`), atribuídos em `receivable_entry.rb:115` a partir da diferença de valor presente. Não há `enum`, `aasm` nem máquina de estados; não há coluna de baixa, de liquidação nem de vencimento; e a tela só exibe esse carimbo, somente leitura. É o **D-19**. Ou a ausência é real (o borderô é registro de operação, não de cobrança) ou falta uma funcionalidade inteira.
- **Opções:** (a) replicar — o borderô continua sem ciclo de vida; (b) construir o ciclo (baixa, liquidação, vencimento) — é feature nova, contra DEC-09; (c) replicar e registrar como lacuna conhecida no ledger, para o pós-venda.
- **Default vigente:** (a)/(c) — DEC-09 manda portar o que existe.
- **Recomendação:** (c). Se o cliente controla baixa em planilha hoje, esse é o item de maior valor do pós-venda — e vale saber agora, não depois.

### P-069 — `is_title` e `is_liquidation` em `movement_kinds`: campos vivos ou resíduo?

- **Origem:** `Q-60`
- **Fatia:** S6
- **Trava:** trava `BE-186`.
- **Impacto:** `muda escopo`
- **Contexto:** Os dois **não** são igualmente órfãos. `is_title` aparece apenas no CRUD (`movement_kinds_controller.rb:126`, `.../movement_kinds/helper/_body.html.erb:48`), no importador (`app/models/legacy/movement_kind.rb:16`), no seed (`db/seeds.rb:206-222`) e na migration — nenhuma regra o lê. Já `is_liquidation` **tem consumidor**: `app/models/movement_kind.rb:14` faz `txks = [is_advalorem, is_desagio, is_iof, is_liquidation].sum` e valida a **exclusividade mútua** entre os quatro (`:13-18`). Ele não entra em cálculo de tarifa, mas é regra de negócio ativa. Nota relacionada: `receivable_taxes` **não** tem `is_liquidation`, embora `movement_kinds` tenha (D-B13).
- **Opções:** (a) portar os dois como estão (`is_liquidation` com a validação, `is_title` como coluna sem consumidor); (b) portar `is_liquidation` e **descartar `is_title`** com evidência no ledger; (c) descartar os dois.
- **Default vigente:** (a) — DEC-09 e o mesmo raciocínio do DC-16: pode haver consumidor externo.
- **Recomendação:** (b). `is_liquidation` fica porque é regra viva; `is_title` sai com evidência, e voltar é aditivo.

### P-070 — `resource_kinds`: portar ou descartar? Uma contagem decide 9 IDs

- **Origem:** `Q-61` + `F-34` (fundidas; levantada em dois mapas)
- **Fatia:** S6 e S8 — são **9 IDs** (`BE-307`, `BE-720`…`BE-724`, `FE-307`, `DB-286`, `DB-289`, `DB-294`)
- **Trava:** trava o escopo de S8 e o bloco 0 (`s8/tasks.md:26, 104, 146, 168-169`). **Consulta 2 da seção 5** resolve.
- **Impacto:** `muda escopo`
- **Contexto:** A entidade tem CRUD completo (controller, views, rotas) e é **inalcançável pelo menu**: `application_helper.rb:153` só tem `resource_sources`; `resource_kinds` só abre digitando a URL. A coluna `receivable_entries.resource_kind_id` existe (`db/migrate/20210315183541_create_receivable_entries.rb:11`) e está no `permit` (`receivables_controller.rb:191`), mas **não há campo no formulário** e `receivable_entry.rb` **não declara `belongs_to :resource_kind`** — o único lado da associação é o inverso, em `resource_kind.rb:2`. Os dois flags da entidade (`is_conta_corrente`, `is_unique`) não têm nenhum leitor de regra. E ela **não participou da importação**: `app/models/legacy.rb:2-15` lista `ResourceSource` e não `ResourceKind`.
- **Opções:** (a) rodar a contagem no dump — zero significa `dropped` **com evidência**, e S8 encolhe 9 IDs; (b) portar tudo por precaução; (c) descartar sem consultar.
- **Default vigente:** (a) — a tabela e o seed nascem de qualquer forma (preservar dado é barato, perdê-lo é irreversível), com a **superfície** bloqueada até a contagem.
- **Recomendação:** (a). Se vier zero, a tarefa 13.4 já está escrita: remover a tabela numa tarefa explícita, **nunca por omissão**. É a mesma consulta que resolve P-041: se `resource_kinds` cai, aquela pergunta desaparece junto.

### P-071 — `receivable_entries.observacoes`: campo visível, fundido ou descartado?

- **Origem:** `Q-62`
- **Fatia:** S6
- **Trava:** trava `DB-155`.
- **Impacto:** `muda escopo`
- **Contexto:** A coluna existe (`db/migrate/20210315183541_create_receivable_entries.rb:43`) e está no `permit` (`receivables_controller.rb:223`), mas **não há input no formulário** e nenhuma view a lê. Tem até tooltip órfão no YAML de ajuda (`receivables_help_inputs.yml:35`). O **único escritor real** é o importador: `app/models/legacy/receivable_entry.rb:56` grava `observacoes: i.bor_obs` — ou seja, **há texto de negócio gravado ali que ninguém nunca viu na tela**.
- **Opções:** (a) tornar o campo visível (ele já tem conteúdo vindo do sistema antigo); (b) fundir com `description`; (c) descartar.
- **Default vigente:** (a) — há dado real dentro.
- **Recomendação:** (a). Um campo de observação importado do sistema anterior e invisível há anos é justamente o tipo de coisa que o cliente pergunta "cadê?" na primeira semana.

### P-072 — Renomear anexo de renegociação entra no escopo?

- **Origem:** `Q-63`
- **Fatia:** S9
- **Trava:** trava `BE-228`.
- **Impacto:** `muda escopo`
- **Contexto:** A funcionalidade foi pretendida e **nunca entregue**. `app/controllers/pub/renegotiation_attachments_controller.rb:51` chama `@renegotiation_attachment.update_attributes(renegotiation_params)` — com **dois** erros na mesma linha: `renegotiation_params` não existe neste controller (só `renegotiation_attachment_params`, `:104`), e `update_attributes` foi removido no Rails 6.1. O `respond_to` da action está inteiramente comentado (`:54-59`). Nunca funcionou para ninguém.
- **Opções:** (a) não portar (DEC-09: não existe); (b) implementar — é uma tela de renomear, custo baixo; (c) não portar agora e registrar no ledger como intenção não concluída.
- **Default vigente:** (c).
- **Recomendação:** (c). Nome de anexo importa em documento de renegociação, mas a decisão é sua: o legado nunca ofereceu isso a ninguém.

### P-073 — A aba PAGAMENTOS da renegociação entra no escopo?

- **Origem:** `Q-64`
- **Fatia:** S9
- **Trava:** trava `FE-229`.
- **Impacto:** `muda escopo`
- **Contexto:** A aba está comentada na view (`.../renegotiations/detail/_body.html.erb:22`) e a lista de abas só declara "GERAL" e "PREVISÕES" (`:15`) — é o **D-53**, a causa de o painel não fechar. O botão "Excluir todas as parcelas" também está comentado (`.../tabs/_tab_renegotiation_installment.html.erb:11-15`). Mas o **backend dos dois continua vivo e órfão**: `renegotiations_controller.rb:76` e `:125` (`show_remove_all_option`), `renegotiation.rb:61-70` (`batch_destroy_installments!`) e o JS que mostra/esconde um botão que não existe.
- **Opções:** (a) portar a aba PAGAMENTOS (o backend está pronto) e **não** portar o botão de excluir em massa; (b) portar os dois; (c) não portar nenhum dos dois.
- **Default vigente:** (a) — a aba fecha um buraco visível no painel; excluir todas as parcelas de uma renegociação sem transação é operação destrutiva que ninguém pediu.
- **Recomendação:** (a). Se o excluir em massa for necessário, ele volta como ação explícita com confirmação e trilha — não como botão comentado que alguém descomenta.

### P-074 — Pagamento de renegociação sem forma de pagamento nem conciliação

- **Origem:** `Q-65`
- **Fatia:** S9
- **Trava:** trava `DB-192`.
- **Impacto:** `muda escopo`
- **Contexto:** A tabela guarda apenas `renegotiation_id`, `renegotiation_installment_id`, valor, data, `days_late`, `payment_number`, `late_payment_value` e `total_paid_value` (`db/migrate/20210324174615_create_renegotiation_payments.rb:3-11` + duas alterações de 2021/2022). **Nenhuma coluna de método, banco, documento ou conciliação.** O model confirma (`app/models/renegotiation_payment.rb:1-28`).
- **Opções:** (a) replicar (ausência intencional — o registro é de valor recebido, e a conciliação vive no banco); (b) acrescentar forma de pagamento como campo livre; (c) acrescentar forma + referência de conciliação bancária (feature nova).
- **Default vigente:** (a), por DEC-09.
- **Recomendação:** (a) nesta entrega. Conciliação bancária é subsistema, não campo — se for necessária, merece escopo próprio.

### P-075 — O percentual de aceite por contrato volta?

- **Origem:** `Q-66`
- **Fatia:** S12
- **Trava:** trava `BE-344`.
- **Impacto:** `muda escopo`
- **Contexto:** Está comentado nos **dois** únicos lugares em que aparecia: na lista (`.../contracts/list/_widget.html.erb:18`, *"Aceito por X dos usuários"*) e no detalhe (`.../contracts/detail/_body.html.erb:66`). O método que o calcula, `Contract#accept_users` (`app/models/contract.rb:23-25`), ficou sem nenhum chamador ativo. **Não há comentário explicando por que foi desligado** — pode ter sido performance (a conta é um `count` sobre `contract_deals`) ou pode ter sido por estar errada.
- **Opções:** (a) reativar, com a contagem feita em consulta e não em Ruby; (b) não portar; (c) reativar só no detalhe, não na lista (onde o custo por linha se multiplica).
- **Default vigente:** (b) — está comentado em produção e não se sabe por quê.
- **Recomendação:** (c). É a informação que dá sentido a ter um ciclo de aceite (P-020), e no detalhe o custo é uma consulta por página.

### P-076 — Tipos de contrato configuráveis pela UI?

- **Origem:** `Q-67`
- **Fatia:** S12
- **Trava:** trava `BE-339` e `OPS-332`.
- **Impacto:** `muda escopo`
- **Contexto:** Hoje os tipos são **literais em código**: `app/models/contract.rb:13-14` define as duas constantes e `:18-21` fecha a lista em `self.contract_kinds`. Não há CRUD de tipos; o formulário só oferece esse array. E existe um terceiro documento planejado e nunca ativado: `db/seed_assets/contracts/user.html` (20 bytes), que **nenhum seed carrega** — o que sugere um "contrato de adesão" que ficou pelo caminho (ver P-045).
- **Opções:** (a) manter os dois tipos fixos em código; (b) tornar os tipos configuráveis por cadastro; (c) manter fixos e acrescentar o terceiro tipo ("Contrato de adesão") se você confirmar que ele é necessário.
- **Default vigente:** (a).
- **Recomendação:** (a). Tipo de contrato muda uma vez por década; cadastro configurável para isso é complexidade que se paga todo dia por um ganho que quase nunca chega.

### P-077 — O `balance` da operação estruturada deveria evoluir?

- **Origem:** `Q-68` + `F-08` (fundidas)
- **Fatia:** S8
- **Trava:** **bloqueia** o desenho do bloco E1, o bloco 0 de S8 (`s8/tasks.md:24`) e a tarefa 5.3. É a diferença entre portar uma tela e construir um subsistema.
- **Impacto:** `muda escopo`
- **Contexto:** `app/models/structured_operation.rb:38` faz `self.balance = self.original_balance` num `before_validation` **sem `on:`** — ou seja, **editar só a observação zera o saldo de volta ao inicial**. A linha `:37` ainda força `original_balance` a ser negativo. E **nada no legado inteiro dá baixa nele**: não existe `StructuredMovement` — nem model, nem migration, nem tabela. `balance` só é escrito nessa linha e aceito no `permit` (`structured_operations_controller.rb:167`); todo o resto é ordenação e exibição. É o **D-73**, e é a maior ambiguidade financeira do bloco: ou falta uma feature inteira (baixa/liquidação de operação estruturada), ou a coluna é decorativa.
- **Opções:** (a) replicar o reset exatamente, cobrir com golden, e documentar a coluna como decorativa; (b) construir movimentação de operação estruturada, espelhando o que existe em risco (`RiskMovement`) — subsistema novo, contra DEC-09; (c) remover a coluna da tela, já que ela nunca reflete nada além do valor inicial.
- **Default vigente:** (a) — inventar mecanismo de baixa num saldo que o cliente vê seria criar número novo sem regra de negócio.
- **Recomendação:** (a) na entrega. **Mas esta é a pergunta que mais vale a pena você responder do bloco de estruturadas:** se alguém dá baixa nessas operações fora do sistema, o produto tem um buraco que nenhuma migração conserta — e a resposta muda o roadmap, não esta entrega.

### P-078 — A posição diária de risco (`RiskEntry`) volta a ter tela?

- **Origem:** `Q-69` + `F-36` (fundidas; T-D2)
- **Fatia:** S5/S7 — a fatia R8 fica bloqueada sem resposta
- **Trava:** trava `BE-269`, `DB-231`, `FE-234`, o bloco R8 e as tarefas 1.7 e 6.1 de S5 (`s5/tasks.md:23, 40, 93`).
- **Impacto:** `muda escopo`
- **Contexto:** A tabela e as regras estão vivas e há dado em produção, mas **não existe nenhuma view** — não há `app/views/pub/risk_entries` nem `.../parts/risk_entries`, e o controller aponta para templates inexistentes (`risk_entries_controller.rb:6,29,39,47,56`), com as rotas ainda no ar (`config/routes.rb:163-164`). **Não há item de menu nenhum**; o que está comentado é a **aba** (`.../risk/_body.html.erb:30`) e o handler do botão "Cadastrar posição". O problema de fundo: os **15 campos são hardcode dos 4 tipos originais** (Auto Liquidável, Fomento, Comissária, Intercompany — `db/migrate/20210510211736_create_risk_entries.rb:7-15` e duas alterações de 2022) e **não acompanham o `RiskOperationType` dinâmico** que existe desde 2022. Portar a tela como está entrega algo que **não funciona com os tipos atuais**. **Consulta 4 da seção 5** diz se há dado.
- **Opções:** (a) portar tabela e model (o dado sobrevive) e deixar a fatia R8 **sem endpoint e sem tela**; (b) remodelar por tipo dinâmico e entregar a tela — é feature nova, contra DEC-09; (c) descartar tudo com evidência.
- **Default vigente:** (a).
- **Recomendação:** (a), com a consulta rodada: se `risk_entries` estiver vazia, isto vira (c) e a fatia some com evidência. (b) é remodelagem, não migração; (c) sem a consulta perde dado que não volta.

### P-079 — Alerta de estouro de limite em tempo real entra?

- **Origem:** `Q-70`
- **Fatia:** S5
- **Trava:** nada — é escopo novo.
- **Impacto:** `muda escopo`
- **Contexto:** Confirmado na fonte: **o legado não faz polling em nenhuma tela deste bloco** e não renderiza gráfico nenhum (`vendor/doughnut` é pendurado no `global` em `app/frontend/vendor/js/index.js.erb:31,37` e **zero views o instanciam**; `grep "new Chart"` também é vazio). Logo, um alerta de estouro é **feature nova** (DEC-09), não paridade. Menciono porque é o candidato mais natural que o produto tem: o painel de risco existe, os limites existem, o cálculo de utilização existe.
- **Opções:** (a) não entra; (b) entra como **aviso na própria tela** quando a utilização passa do teto (custo baixo, o número já é calculado); (c) entra com notificação ativa (e-mail/WhatsApp) — subsistema novo.
- **Default vigente:** (a) — coerente com **DEC-21.1**, que explicitamente deixou "utilização de limite" para depois da venda.
- **Recomendação:** (a). O `NEW-002` (dashboard) já mostra "limites próximos do teto", então a demo cobre a ideia sem abrir uma frente nova.

### P-080 — `is_on_variable` ("Considerar no variável") — o que era isso?

- **Origem:** `Q-71`
- **Fatia:** S8 (e S7)
- **Trava:** trava `BE-295`.
- **Impacto:** `muda escopo`
- **Contexto:** É persistido, exibido no formulário e **nenhum cálculo do legado o lê**. Ocorrências completas: `permit` (`risk_operations_controller.rb:232`, `structured_operations_controller.rb:170`), formulário (`.../risk_operations/new/_body.html.erb:217,219` e `.../structured_operations/new/_body.html.erb:179,181`), cópia na renovação (`risk_operation.rb:131`) e as duas migrations. **Zero leituras** em cálculo, filtro, escopo ou relatório. O nome sugere uma remuneração variável que não existe no sistema.
- **Opções:** (a) portar como marca comercial (grava e exibe, como hoje); (b) descartar com evidência; (c) descobrir com o negócio o que era e implementar.
- **Default vigente:** (a) — mesmo raciocínio do `has_bi` (DC-16): pode haver consumidor externo, e manter custa uma coluna.
- **Recomendação:** (a) até você responder (c). Se a remuneração variável era feita em planilha, o campo é a pista de que alguém queria trazê-la para dentro.

### P-081 — Os 4 flags de `structured_operation_types` migram?

- **Origem:** `Q-72`
- **Fatia:** S8
- **Trava:** trava `BE-297` e `DB-283`.
- **Impacto:** `muda escopo`
- **Contexto:** Os quatro são aceitos pelo `permit` (`structured_operation_types_controller.rb:132-135`) e ausentes do formulário (que só tem título, chave e `is_active`). Mas **dois têm consumidor** no lado estruturado: `is_default` em `structured_operation_type.rb:11` (`before_destroy`), no controller (`:99`) e na listagem (`.../structured_operation_types/list/_widget.html.erb:23`); e `has_pre_faturamento` em `.../structured_operations/list/_widget.html.erb:16,22`, onde **esconde as datas da listagem**. Realmente órfãos no lado estruturado são só `allow_manual_operations` e `allow_receivable_entries` — que, no lado de **risco**, são scopes centrais (`risk_operation_type.rb:2-3`).
- **Opções:** (a) migrar os quatro; (b) migrar `is_default` e `has_pre_faturamento` e descartar os outros dois **do tipo estruturado**, mantendo-os no tipo de risco; (c) migrar os quatro e **expor** os relevantes no formulário, que hoje não os mostra.
- **Default vigente:** (a).
- **Recomendação:** (c) pelo menos para `has_pre_faturamento`: hoje ele nunca pode virar `1` pela UI, mas se virar por outro caminho a listagem de estruturadas **passa a esconder as datas** — um comportamento que ninguém consegue explicar depois.

### P-082 — Excluir lançamento de indicador é feature viva?

- **Origem:** `Q-73` + `F-20` (fundidas; T-D12)
- **Fatia:** S10
- **Trava:** trava `BE-328`, o bloco 0 de S10 (`s10/tasks.md:30`) e a tarefa 5.5.
- **Impacto:** `muda escopo`
- **Contexto:** A rota existe (`config/routes.rb:84`) e a action também (`indicator_entries_controller.rb:75-85`), mas **nenhuma tela a chama**: zero ocorrências de excluir/remover/`data-method: :delete` em toda a pasta de views de lançamentos. O controller nem tem o template do formulário que renderiza em `:34` e `:42`; e o ramo de erro referencia um template inexistente — dá 500 dentro de um 200. Na prática, "zerar" é digitar `0` no campo inline e submeter — o registro continua existindo.
- **Opções:** (a) não portar a exclusão (só zerar, como hoje); (b) construir, com confirmação e autorização, e a célula voltando ao estado "não lançado"; (c) `dropped` com evidência de que nenhuma tela a chama; (d) construir só o endpoint, sem botão na tela.
- **Default vigente:** conflitante — o mapa fixou (a) (nada a portar), o empacotamento fixou (b) (a rota existe e DEC-09 manda portar o que existe). **Precisa da sua palavra.**
- **Recomendação:** (b), **mas responda junto com P-037**. As duas são a mesma moeda: sem distinguir "não lançado" de "lançado como zero", excluir e zerar produzem exatamente a mesma tela, e a feature não tem sentido nenhum.

### P-083 — O indicador precisa de tipos além de "Dinheiro"?

- **Origem:** `Q-74`
- **Fatia:** S10
- **Trava:** trava `BE-715`.
- **Impacto:** `muda escopo`
- **Contexto:** Só existe um tipo, e o próprio código diz por quê: `app/models/indicator.rb:24-35` define `VALUE_TYPE__MONEY = "Dinheiro"` como **único** valor de `self.value_types`, com o comentário *"prevendo expansão futura para tipos diferentes de indicadores, no momento usamos apenas o tipo dinheiro, sendo forçado"*. Não há campo no formulário nem no `permit`; é forçado na criação (`:45`) e usado só para formatação (`indicator_entry.rb:35-37`).
- **Opções:** (a) só "Dinheiro", como hoje; (b) acrescentar percentual e quantidade (a estrutura já foi desenhada para isso); (c) acrescentar sob demanda depois.
- **Default vigente:** (a), por DEC-09.
- **Recomendação:** (a) com (c) planejado. Se o cliente acompanha inadimplência em % ou volume em unidades, hoje ele grava isso como "dinheiro" — e vale perguntar **antes** de a demo mostrar um R$ na frente de um percentual.

### P-084 — Existe consumidor externo dos headers `X-LAA-Agent` / `X-LAA-Token`?

- **Origem:** `Q-75`
- **Fatia:** S1
- **Trava:** trava a decisão de descartar o contrato de token da engine (`BE-004`).
- **Impacto:** `muda escopo`
- **Contexto:** O par de headers é definido em `engines/auth19/lib/livetat/auth/configuration.rb:15-16` e validado por inteiro em `engines/auth_ux19/.../application_controller.rb:16-17,23-25` (via `Auth::ClientApplication.find_through_token`). Mas os dois controllers de API do próprio app leem **só o token**, sem o agent (`app/controllers/api_application_controller.rb:7` e `api_private_application_controller.rb:7`). **Só você sabe quem chama essa API de fora** — descartar um contrato vivo quebra um consumidor que não está neste repositório.
- **Opções:** (a) descartar o contrato de token de usuário (o JWT o substitui) e **manter** `ClientApplication` funcionando por `Authorization: Bearer`; (b) manter os dois headers durante um período de transição, com prazo definido; (c) descartar tudo.
- **Default vigente:** (a).
- **Recomendação:** (a), mas a resposta é sua: se houver app móvel ou integração externa, precisamos do prazo de transição **antes** do cutover, não depois.

### P-085 — A área de temas existe no ai9 como CRUD, ou a marca vira configuração?

- **Origem:** `Q-76` (levantada em dois mapas, **com defaults divergentes**)
- **Fatia:** S17 — a fatia inteira depende desta resposta
- **Trava:** trava **S17 inteira**; pode economizar a fatia.
- **Impacto:** `muda escopo`
- **Contexto:** O motor de temas do legado **não pinta nada**: o CSS do template está integralmente dentro de um comentário — `app/frontend/css/pub/templates/app_theme_template.css`, 167 linhas, abre `/*` na linha 1 e fecha `*/` na 167, **sem uma única regra fora dele** (**D-55**). E o parser continua rodando em cima disso: `app_theme.rb:207-231` lê o arquivo, substitui as variáveis de cor e grava em `cached_css`, que as views injetam num `<style>` — sempre um comentário CSS inteiro. Além disso, a área **não tem item de menu** (zero ocorrências de "themes" em `application_helper.rb` e no menu) e o `else` do `fetch_resource` redireciona para `dash` (`console_controller.rb:402-405`) — **D-63**. Na prática, o tema só controlava logos e o branding de 3 e-mails.
- **Opções:** (a) implementar a área completa (CRUD de tema, precedência, tokens em runtime), como o inventário pede; (b) **não** portar a tela: marca e paleta viram tokens do app, light/dark fica no `ThemeToggle` que já existe no ai9, e S17 encolhe para "marca em fonte única"; (c) meio-termo: tema como **configuração única** editável (uma tela, um tema), sem CRUD nem precedência.
- **Default vigente:** **divergente entre os dois mapas** — um propõe (b), o outro propõe (a). **Precisa da sua palavra.**
- **Recomendação:** (c). Multi-tema num sistema de um cliente só é complexidade sem uso; mas o cliente vai querer trocar o logo sem abrir um chamado.

### P-086 — `UserTheme` (tema por usuário): requisito abandonado ou feature a ressuscitar?

- **Origem:** `Q-77` + `F-27` (fundidas; Q-19 de S17)
- **Fatia:** S17
- **Trava:** trava `BE-379` e metade de `BE-380`.
- **Impacto:** `muda escopo`
- **Contexto:** O tipo existe de verdade: `app/models/user_theme.rb:2` declara `has_many :users` e a coluna está criada (`db/migrate/20200206191948_add_app_theme_column_to_livetat_auth_user.rb:3`). Mas o `select` do formulário oferece **apenas** `GlobalTheme` (`.../themes/form/_body.html.erb:36` e `.../themes/helper/_body.html.erb:16`) — `UserTheme` **nunca aparece em nenhuma opção** e é inalcançável pela UI. Só `GlobalTheme` é referenciado em runtime. No ai9, mantê-lo significa implementar uma precedência de três níveis (usuário → global → fábrica) em que o nível de usuário **nunca é escrito por nada**.
- **Opções:** (a) portar o **tipo** (a coluna e o STI, porque pode haver dado) e **não** expor a criação de `UserTheme` na UI — igual ao legado; (b) descartar o tipo inteiro, e a precedência passa a ter dois níveis; (c) implementar tema por usuário de verdade, com tela.
- **Default vigente:** (a).
- **Recomendação:** (b), **se** P-085 for respondida com (b) ou (c). Portar um STI para um subtipo que nunca teve UI é carregar complexidade de graça; e no ai9 a preferência por usuário já existe como light/dark, que é o controle que o usuário corporativo espera.

### P-087 — `generic_rating` (avaliação por estrelas) é usado em alguma tela?

- **Origem:** `Q-78`
- **Fatia:** S19 / S2
- **Trava:** trava `BE-013` do inventário de componentes.
- **Impacto:** `muda escopo`
- **Contexto:** Só existe o **CSS** — `app/frontend/css/pub/recyclable/generic_rating.scss` (classe `.app_rating_widget`), importado em `recyclable.scss:7`. **Zero ocorrências** de `app_rating_widget` ou `generic_rating` em qualquer `.erb`, `.rb` ou `.js` do repositório. Não há model, controller, rota nem partial. É CSS morto, provável resquício de outro produto da Livetat.
- **Opções:** (a) descartar com evidência no ledger; (b) portar o componente para a biblioteca do ai9 mesmo sem consumidor.
- **Default vigente:** (a).
- **Recomendação:** (a). Com a evidência acima não há nem o que discutir — e se aparecer uso, é um componente pequeno de recuperar.

### P-088 — A citação aninhada em respostas de mensagem (`quoted_note_id`) é usada?

- **Origem:** `Q-79`
- **Fatia:** S2
- **Trava:** trava o desenho da tabela de notas do feedback.
- **Impacto:** `muda escopo`
- **Contexto:** O backend está completo e vivo: `engines/feedback19/app/models/livetat/feedback19/note.rb:6` (`belongs_to :quoted`), a lógica que deriva `top_parent_quote_id` (`:17-23`), o `permit` (`notes_controller.rb:90`) e a coluna (`db/migrate/20170516185759_create_livetat_feedback_notes.rb:9`). Mas a UI **nunca a preenche**: zero ocorrências de `quoted` em qualquer view ou JS do engine ou do app. Nenhum campo, hidden input ou parâmetro AJAX a envia.
- **Opções:** (a) não portar a citação aninhada (uma coluna e uma associação a menos numa tabela nova); (b) portar o esquema sem UI; (c) portar com UI (feature nova).
- **Default vigente:** (a).
- **Recomendação:** (a). Acrescentar depois é aditivo e não quebra nada — e uma thread de mensagens interna raramente precisa de citação aninhada.

### P-089 — Mantemos Google Analytics no console? (duas fatias decidiram coisas diferentes)

- **Origem:** `Q-80` + `F-29` (fundidas; levantada em dois mapas)
- **Fatia:** S18, S2 e S13
- **Trava:** trava `OPS` de analytics e o CSP — e, hoje, **duas fatias vão implementar coisas diferentes**.
- **Impacto:** `muda escopo`
- **Contexto:** Hoje o snippet é injetado **na primeira linha de cada entrypoint, sem nenhum consentimento**: `.../console/_index.js.erb:1`, `.../start/_index.js.erb:1`, `.../users/sessions/_new.js.erb:1` e `.../contracts/_index.js.erb:2` (este sem nem o guard de deduplicação). E está **quebrado**: o ID é GA4 (`GOOGLE_ANA_APP_ID = "G-7E78XXZX5X"`, `app/definitions/SFG/metadata.rb:7`) mas o snippet é Universal Analytics — carrega `analytics.js` e chama `ga('create', …)` (`app/views/livetat/analytics/_google.js.erb:1-8`). Um ID `G-` não funciona com `ga()`: **na prática não coleta nada hoje**. **O conflito interno:** `s2/design.md:103` (DS2-4) decide **não injetar**; `s13/proposal.md` (Q-09) decide **portar desligado, com o snippet correto pronto**. "Não existe" versus "existe e está desligado" são coisas diferentes.
- **Opções:** (a) não injetar, e o snippet **não entra no repositório**; se for preciso medir, usar a camada de analytics do próprio ai9; (b) portar desligado por configuração, com o snippet GA4 correto pronto para ligar; (c) portar ligado e corrigido.
- **Default vigente:** **os dois ao mesmo tempo** — é o conflito. Nenhuma paridade real se perde ao remover, porque nada é coletado hoje.
- **Recomendação:** (a). Sistema interno corporativo com dado financeiro mandando telemetria de uso para terceiro é decisão do **cliente**, não nossa; e snippet de terceiro desligado num sistema de crédito é uma linha que alguém liga por engano. O custo de ligar depois é um script.

### P-090 — O item de menu `reports` entra?

- **Origem:** `Q-81`
- **Fatia:** S2
- **Trava:** trava `NAV`.
- **Impacto:** `muda escopo`
- **Contexto:** O material descrevia `reports` como um item de menu marcado `inactive`. Conferido: (1) não está no helper — está na **view** do menu, `app/views/pub/console/base/menu/_container.html.erb:24`, como `<%= 'inactive' if i[:identifier] == "reports" %>`; (2) **o item nem existe** — a lista é montada em `application_helper.rb:103-171` e nenhum item tem `identifier: "reports"`, então a condição nunca é verdadeira; (3) não há rota, controller nem `when "reports"` no `fetch_resource`. É código morto guardando um identificador fantasma. O item mais próximo, `{ identifier: "results", title: "Resultados" }`, está **comentado** em `application_helper.rb:118`.
- **Opções:** (a) não portar nada (nem o item, nem o mecanismo `inactive`); (b) portar o mecanismo de item inativo, sem item marcado; (c) descobrir o que era "Relatórios"/"Resultados" e escopar.
- **Default vigente:** (a).
- **Recomendação:** (a), e vale a pergunta lateral: havia uma tela de **Resultados** planejada e comentada. Se o cliente sente falta de relatórios, isso é escopo de pós-venda, não paridade.

### P-091 — A tabela `geolocations` tem linhas? Um `SELECT count(*)` decide 12 IDs

- **Origem:** `Q-82` + `F-35` (fundidas)
- **Fatia:** S13 (e S19, por P-092)
- **Trava:** trava as tarefas 6.5–6.9 de S13 e **12 IDs**: `DB-592`, `DB-431`, `DB-480`, `OPS-481`, `OPS-482`, `FE-483`, `BE-435`…`BE-440` (`s13/tasks.md:26-30`). **Consulta 3 da seção 5.**
- **Impacto:** `muda escopo`
- **Contexto:** O model existe e é grande (`app/models/geolocation.rb`, com cálculo de distância via Geocoder em `:164-171`), mas **nenhum model declara `has_one`/`has_many :geolocation`** — zero resultados no repositório inteiro. E `geolocatable` só aparece dentro do próprio `geolocation.rb` (`:6,7,9,175`) e na migration (`db/migrate/20160302002809_create_geolocations.rb:4`). A associação polimórfica **não tem lado inverso nenhum**. É o maior portão de escopo por consulta única da migração. **Correção ao material (A-24):** o mapa dizia "9 IDs" mas enumerava 14; a lista autoritativa é a da fatia, com 12. Os dois extras que o mapa cita (`OPS-621`, `OPS-483`) precisam ser conferidos à parte.
- **Opções:** (a) rodar a contagem no dump agora e decidir com o número; (b) assumir que tem e construir; (c) assumir que não tem e descartar.
- **Default vigente:** (b) — "assumo que sim e implemento; se vier 0, os 12 IDs viram `dropped`".
- **Recomendação:** (a). É a consulta de melhor relação custo-benefício da lista inteira: cinco segundos decidem se 12 IDs viram código ou evidência.

### P-092 — Trilha de auditoria com geolocalização (`BE-433`): implementar a intenção ou descartar?

- **Origem:** `Q-83` + `F-25` (fundidas)
- **Fatia:** S19 — depende de **P-091**
- **Trava:** trava `BE-433`.
- **Impacto:** `muda escopo`
- **Contexto:** Existe uma assinatura que aceita coordenadas para recalcular distância — `app/controllers/api/v1/trackings_controller.rb:39-45` lê `params[:lat]` e `params[:lng]` (`:40`) e atribui em `@tracking.geolocation.ref_lat`/`ref_lng` (`:42-43`). Só que a action está **quebrada em três frentes** (ver A-5): `@tracking` nunca é carregado (o `fetch_tracking` de `:54-56` está **vazio** e nem é registrado como `before_action`), `Tracking` **não declara** associação `geolocation`, e nada é salvo nem recalculado. O recálculo real vive em `geolocation.rb:164-171`, fora do alcance desse controller. É uma feature **nunca entregue** — só a assinatura existe. E se P-091 vier zero, o cálculo nunca dispara e vira código morto no dia 1.
- **Opções:** (a) portar o cálculo **condicional** (só quando `lat`/`lng` vierem), sem geocoding; (b) não portar até P-091 responder; (c) descartar o caminho morto e registrar no ledger com a evidência.
- **Default vigente:** (a).
- **Recomendação:** (b) — amarrar a P-091 evita nascer com uma função que nunca executa; se a contagem der zero, vira (c). Vale registrar junto o achado colateral: `GET /api/v1/trackings` parte de `Tracking.all` **sem escopo nenhum** (D-110), e isso **tem** veredito `corrigir`.

### P-093 — O aviso de "atualização em andamento" vale para quais entidades?

- **Origem:** `Q-84` + `F-48` (fundidas)
- **Fatia:** S13
- **Trava:** trava `FE-482`, `OPS-463` (`s13/tasks.md:33-35`) e o número de canais Action Cable.
- **Impacto:** `muda escopo`
- **Contexto:** Só `Project` implementa `has_ongoing_job?` (`app/models/project.rb:145`), e `data-ongoing` é emitido **num único lugar** (`.../projects/list/_widget.html.erb:1`). Mas **7 outros widgets leem `data("ongoing")`** e recebem sempre `undefined`: garantias de projeto, recebíveis, operações estruturadas, renegociações, operações de risco, padrões de disponibilidade e empresas (todos na linha 10 do respectivo `list/_widget.js.erb`). É bloco morto — parece intenção não concluída.
- **Opções:** (a) implementar só para as entidades que de fato **têm** job (hoje: `Project` e `AvailabilityTemplate`), e os 7 widgets viram `dropped` com evidência; (b) implementar para as 8; (c) não portar o mecanismo.
- **Default vigente:** (a).
- **Recomendação:** (a). É medição, não opinião — a tarefa 1.3 de S13 já está escrita para listar quem tem job. Um indicador de "processando" numa tela que nunca processa nada é ruído, e a infra de Action Cable custa por canal.

### P-094 — Tipos de garantia: você quer, e qual é o conteúdo?

- **Origem:** `Q-85`
- **Fatia:** S3
- **Trava:** trava `DB-558` e o seed de referência.
- **Impacto:** `muda escopo`
- **Contexto:** A tabela existe (`db/migrate/20220627125208_create_project_guarantee_types.rb`) e **nenhum seed a popula** — zero ocorrências de "guarantee" em `db/seeds.rb`, nenhuma referência em `db/factories/`. Mas a UI e o backend dependem dela: CRUD completo (`project_guarantee_types_controller.rb`), o select do formulário de garantias é alimentado por `ProjectGuaranteeType.all` (`project_guarantees_controller.rb:52`) e há item de menu (`application_helper.rb:157`). Resultado no legado: **o select de tipo de garantia sobe vazio** até alguém cadastrar à mão pelo console. **Não há nada a migrar — o conteúdo é novo e é seu.**
- **Opções:** (a) portar só o mecanismo e semear **tipos plausíveis** no seed de demo, marcados como provisórios; (b) portar o mecanismo e subir vazio, como o legado; (c) você fornece a lista de tipos de garantia reais.
- **Default vigente:** (a).
- **Recomendação:** (c) se você tiver a lista — numa demo, um select de garantias vazio na tela de projeto é exatamente onde o cliente vai clicar. (a) é o plano B.

### P-095 — Teremos acesso ao disco do servidor legado?

- **Origem:** `Q-86` + `F-40` (fundidas)
- **Fatia:** S14 (e S9)
- **Trava:** trava a migração de **arquivos** (não a de registros), a tarefa 5.3 de S9 (`s9/tasks.md:419-422`) e o passo de arquivos do runbook.
- **Impacto:** `muda escopo`
- **Contexto:** São **11 anexos** (44 colunas de paperclip) vivendo em `public/system/:attachment/:id/…` **no disco da máquina do legado** — avatar de usuário, imagem de `Picture`, anexo de renegociação, logo de fornecedor e de portador, avatar de projeto e os 4 arquivos de tema. O path é configurado inline em cada model, não num initializer. Sem acesso a esse disco, **os arquivos não migram** — só os registros, que passam a apontar para nada. É dependência **externa**, como o dump, não decisão de desenho.
- **Opções:** (a) construir o ETL de arquivos com o caminho parametrizado e testar contra o seed de demo; o passo real fica no runbook de cutover, marcado como bloqueado por dependência externa; (b) obter uma cópia do diretório `public/system/` (rsync/tar) antes do cutover; (c) migrar só os registros e marcar cada anexo como "arquivo não recuperado", com relatório; (d) aceitar a perda dos binários históricos.
- **Default vigente:** (a) parametrizado.
- **Recomendação:** (b) marcado como **pré-requisito de cutover**, com (c) como rede de segurança. Anexo de renegociação é documento financeiro — perder o binário e manter o registro é pior que não migrar, e um anexo quebrado em silêncio é pior que a ausência declarada.

### P-096 — A "Chave de Integração" do indicador tem consumidor fora do repositório?

- **Origem:** `Q-95` + `F-44` (fundidas; T-D13)
- **Fatia:** S10
- **Trava:** trava `OPS-312`, a tarefa 3.4 de S10 e a decisão de tornar `indicator.key` única (`s10/tasks.md:31, 64`).
- **Impacto:** `muda escopo` — **reclassificada** (o mapa a tinha como `só interno`; a opção (c) remove o campo e a (b) pode quebrar um consumidor externo em silêncio)
- **Contexto:** Dentro do repositório, **nada lê `indicator.key`** para integrar coisa nenhuma — nem API, nem job, nem export. As ocorrências são todas de encanamento: geração a partir do título (`indicator.rb:44`), denormalização (`:49` e `indicator_entry.rb:25`), o próprio campo no formulário, `permit` e mensagem de erro. A chave **não é única hoje**. E a ordenação por chave está inclusive **quebrada**: `indicator.rb:68-69` devolve `"integration_key"`, coluna que **não existe** em `indicators` (a coluna é `key`) — ver A-5. O campo se chama "Chave de Integração" e não integra nada aqui dentro; mas o nome anuncia consumidor externo, e se houver BI ou planilha lendo, mudar formato ou impor unicidade quebra do lado de fora, **em silêncio**.
- **Opções:** (a) **não mexer** — a chave continua obrigatória, derivada do título, sem unicidade e sem mudança de formato; (b) tornar única e imutável após a criação, corrigindo as duplicatas (mesma disciplina do DC-17 e DC-22); (c) remover o campo.
- **Default vigente:** (a).
- **Recomendação:** É uma pergunta de 30 segundos para quem conhece a operação. **(b) se houver consumidor externo; (c) se não houver.** O que não faz sentido é manter um campo chamado "Chave de Integração" que ninguém garante ser estável nem única.

### P-097 — URGENTE: o seed de demonstração não tem dono. Ninguém o constrói

- **Origem:** `F-33`
- **Fatia:** nenhuma — **é o problema**
- **Trava:** trava a demonstração de **sexta (28/08)**. Sem ele, as 20 fatias entregam telas vazias.
- **Impacto:** `muda escopo`
- **Contexto:** Conferido nos três lados. **S18** cria os alvos vazios: `s18/tasks.md:108-111` — *"criar os alvos `lib/tasks/sfg_etl.rake` e `lib/tasks/demo.rake` **vazios e nomeados**, que S14 e o seed de demo preenchem"*. **S14** o exclui explicitamente: `s14/proposal.md:122` — *"O seed de demonstração (`db/seeds/demo/` + `rake demo:seed`) — é a fatia S-16 do mapa de bloco… S14 o **consome**"*. **S15** também o consome (`s15/tasks.md:88`). O desenho está pronto e é bom: `.migration-ai9/demo-seed-design.md`, 262 linhas, com a cadeia aritmética `Project → Company → (Carrier, limite, taxa) → borderôs → movimentos → saldo`. **Não aparece em nenhum script de cobertura porque não tem ID de inventário** — os scripts contam os 1439 IDs, e o seed não é um deles. Com DEC-22 (escopo completo) e a demo na sexta, é o item mais urgente desta lista inteira.
- **Opções:** (a) criar uma fatia **S20 — seed de demonstração**, com proposal/design/tasks, e rodá-la em paralelo desde já; (b) atribuir o seed a S18 (que já criou o `demo.rake` vazio); (c) atribuir a S14 (que hoje o exclui e o consome); (d) cada fatia semeia o seu próprio domínio dentro de `db/seeds/demo/`.
- **Default vigente:** **nenhum — é exatamente o problema.** Sem dono, o `demo.rake` chega sexta-feira vazio.
- **Recomendação:** (a). O seed cruza todos os domínios e tem uma exigência que nenhuma fatia isolada consegue cumprir: **a cadeia tem de fechar aritmeticamente entre domínios**. (d) é o caminho para cinco seeds que não conversam.

### P-098 — `charges` e `receipts` têm dois donos: S6 e S11

- **Origem:** `F-43`
- **Fatia:** S6 e S11
- **Trava:** duas migrations para as mesmas duas tabelas, se as duas fatias rodarem em paralelo — e com DEC-22 elas rodam.
- **Impacto:** `muda escopo`
- **Contexto:** **Ver o achado A-3.** `s11/proposal.md:200-208` diz, na seção "Fronteiras", que a feature de cobranças e recibos **não é de S11**: *"os IDs (BE-187, BE-188, BE-189, DB-162…DB-165, FE-179..FE-186) pertencem ao bloco `receivables-renegotiations`… o que desta fatia toca 'Cobranças' é **exclusivamente** o item de menu nascer habilitado"*. E S6 confirma, com todos esses IDs na sua lista. Mas a seção "IDs adotados no fechamento do Phase 2" do mesmo `s11/proposal.md:283-290` reivindica `DB-583` (`charges`) e `DB-584` (`receipts`) com a justificativa *"S11 é dona das cobranças (DEC-15.1: vivas)"*. São as **mesmas duas tabelas com dois IDs de inventário diferentes**, e a conferência consolidada não pegou porque ela compara IDs, não tabelas.
- **Opções:** (a) **S6 é dona das duas tabelas**; S11 fica só com o item de menu habilitado, e `DB-583`/`DB-584` são registrados como "mesma tabela, fechado por S6"; (b) S11 é dona das tabelas e S6 do comportamento; (c) as duas migrations existem, uma cria e a outra altera.
- **Default vigente:** contraditório dentro do mesmo documento — é o achado.
- **Recomendação:** (a). É o que a própria seção "Fronteiras" de S11 já diz; o que falta é a seção "IDs adotados" concordar com ela. E vale rodar a conferência **por tabela**, não só por ID, para descobrir se há outros casos.

### P-099 — Quem é o dono de `Tracking`/`trackings` (`BE-430`, `DB-591`): S2, S13 ou S19?

- **Origem:** `F-38`
- **Fatia:** S2, S13 e S19
- **Trava:** trava a tarefa 1.5 de S13 (*"verificar se S2 já entregou `Tracking`"*) e a tarefa 3.9, que cria "o mínimo" se ninguém tiver criado.
- **Impacto:** `muda escopo`
- **Contexto:** **Três documentos discordam, e um se contradiz sozinho.** `s13/proposal.md:165-167` diz que `Tracking` é *"de `misc-domain`, fatia de navegação/transversais (**S2**)"*; `s13/design.md:220` repete ("são de **S2**, decisão **D-P**"); `s13/proposal.md:289` diz que *"`OPS-126` e o model `Tracking` são de **S19**"*. E `s19/proposal.md:57-59` reivindica `DB-591` e `BE-430` como seus — o que **é o certo**: o `migration-map.md` criou a S19 justamente para isso, e ela roda logo depois de S0. S2 **não menciona `Tracking` em lugar nenhum**.
- **Opções:** (a) **S19 é dona**, e S13 apenas consome (a fatia existe e roda antes de S13); (b) S13 cria o mínimo e S19 constrói a leitura em cima; (c) S2 é dona, como dois dos três documentos dizem.
- **Default vigente:** ambíguo — a tarefa 3.9 de S13 é um "se ninguém fez, eu faço", que é exatamente o padrão que produz dois donos.
- **Recomendação:** (a), e corrigir as três referências a S2 dentro de S13. **S13 não deve ter tarefa de criar `Tracking`** — só de consumir. Note que isto interage com P-110: `AuditEvent`, `Tracking` e `permission_audit_logs` seriam **três** trilhas.

### P-100 — Ordem: o motor de anexos (S13) está declarado depois de S9, que tem 4 anexos

- **Origem:** `F-37`
- **Fatia:** S13 e S9
- **Trava:** se S9 começar antes de S13, ela improvisa um segundo caminho de arquivo **hoje**.
- **Impacto:** `muda escopo`
- **Contexto:** O próprio S13 registra a ambiguidade em `s13/proposal.md:178-183`: *"**NÃO depende de S6/S7:** o sub-bloco B (anexos) só precisa de S1 + das entidades donas… Se S9 (renegociações, com 4 anexos) rodar antes de S13, o motor de anexos **tem de ser antecipado** — senão S9 improvisa um segundo caminho e a base fica com três."* Mas a ordem do `migration-map.md` põe S13 depois de S6/S7, e S9 depende só de S4. **Com a paralelização máxima do DEC-22, S9 pode estar rodando agora.**
- **Opções:** (a) **antecipar o sub-bloco B de S13** (motor de anexos) para logo depois de S1, antes de S9; (b) S9 espera S13; (c) S9 usa ActiveStorage diretamente e S13 depois unifica.
- **Default vigente:** **nenhum** — está registrado como "ambiguidade de ordem no relatório", que é onde as coisas somem.
- **Recomendação:** (a). "Depois unificamos" (c) é como uma base ganha três caminhos de upload; e (b) atrasa uma fatia inteira por causa de quatro campos de arquivo.

### P-101 — `BE-445` (`Entry`, a classe base abstrata): fica em S6 ou vai para S19?

- **Origem:** `F-39`
- **Fatia:** S6 (alternativa: S19)
- **Trava:** nada agora — S6 roda antes de S11 de qualquer forma.
- **Impacto:** `muda escopo`
- **Contexto:** `Entry` é a classe base de `ReceivableEntry` (S6) e `AvailabilityEntry` (S11) — transversal por natureza, o que a tornava candidata à fatia de transversais. Ficou em S6 pelo contrato **C4** (quem constrói é dono): `ReceivableEntry` nasce lá, antes de S11 (`s6/proposal.md:261`, `s19/proposal.md:131`). O que ela carrega junto: **"Diferença" e "OK" deixam de ser strings em pt-BR gravadas na coluna e comparadas por igualdade de texto, e viram `enum`**.
- **Opções:** (a) fica em S6, como está; (b) vai para S19, junto dos demais transversais de domínio; (c) fica em S6, mas a conversão dos enums-string é tarefa de S14 (já é — `s14/tasks.md:70`).
- **Default vigente:** (a), por C4.
- **Recomendação:** (a). O risco real não é onde a classe mora — é S11 herdar de uma classe que ainda não existe. Como S6 roda antes de S11 na ordem de dependência, (a) resolve.

### P-102 — A arte do carousel de login: reusar do legado, gerar, ou você fornece?

- **Origem:** `F-42`
- **Fatia:** tematização (aparece antes de S1)
- **Trava:** nada tecnicamente — mas é a **primeira tela** que o cliente vê na sexta.
- **Impacto:** `muda escopo`
- **Contexto:** Conferido em `frontend/src/components/LoginCarousel.tsx:11-16`. Os 5 slides padrão do ai9 (imagens geradas por IA + copy sobre "Inteligência Artificial Nativa", "Conectividade Global") foram substituídos por 5 slides novos em pt-BR sobre o domínio real — risco, recebível/borderô, limite por portador, renegociação e indicadores. Mas **os slides estão sem fotografia**: a sessão de migração não tinha gerador de imagem, e reusar arte do legado não foi autorizado. O fundo hoje é a marca tokenizada (grafite + ouro Safegold) com a marca d'água do símbolo — sóbrio e correto nos dois modos, mas é espaço reservado. Registrado como `THEME-07` em `improvements-log.md:19`.
- **Opções:** (a) você fornece 5 imagens (ou uma) da marca; (b) gerar arte por IA numa sessão com a ferramenta disponível; (c) reusar a arte do legado, se houver e se for autorizado; (d) manter o fundo tokenizado — é uma escolha estética defensável, não um buraco.
- **Default vigente:** (d), por ausência de ferramenta.
- **Recomendação:** (d) para sexta, e (a) depois. Fundo de marca sóbrio numa tela de login de sistema financeiro lê como decisão de design; foto genérica de banco de imagens lê como template.

### P-103 — Convivem dois editores rich text na base (Slate e TipTap)

- **Origem:** `F-47` (flag F-14 de S12)
- **Fatia:** S12
- **Trava:** nada — o desenho já escolheu.
- **Impacto:** `muda escopo`
- **Contexto:** `frontend/src/components/RichTextEditor.tsx` usa **Slate** e está em uso; **TipTap** está declarado no `package.json` **sem consumidor**. S12 decidiu usar **um só** — o que já está em uso — e registrar o outro como flag de upstream (`s12/design.md:23-25`).
- **Opções:** (a) usar Slate e registrar TipTap como flag de upstream; (b) usar Slate e **remover** TipTap do `package.json`; (c) migrar para TipTap.
- **Default vigente:** (a).
- **Recomendação:** (b) se nenhum outro produto da base usar TipTap — mas isso é decisão de plataforma, não do Safegold, e o Princípio 6b diz para não mexer. Então (a), com a flag escrita.

---

# `só interno` — P-104 a P-117

> Retenção, esquema, nomes. O default resolve; a sua resposta melhora.

### P-104 — Por quanto tempo guardamos IP e user-agent das tentativas de login?

- **Origem:** `Q-87`
- **Fatia:** S1
- **Trava:** nada — só muda a política de retenção.
- **Impacto:** `só interno`
- **Contexto:** **Ver o achado A-2 — a origem do problema é o contrário do que o material dizia.** O legado **não tem** essa tabela: as 3 ocorrências de `login_attempt` no repositório inteiro são o método `invalid_login_attempt` em `engines/auth_ux19/.../sessions_controller.rb:42,61,80`. O único rastro de login é o contador `failed_attempts` do Devise, sem IP e sem user-agent. Quem tem a tabela é a **base ai9**: `backend/db/schema.rb:451-460` cria `login_attempts` com `identifier`, `method`, `ip_address` (`inet`, `null: false`), `user_agent`, `success`, `error_reason` e `user_id`, com 9 índices — e **nenhum job de expurgo**. Não é passivo herdado, é passivo **adotado**.
- **Opções:** (a) 90 dias, com job de expurgo (`sidekiq-cron` já está no Gemfile e o bloco de cron está vazio); (b) 180 dias; (c) retenção indefinida, como está hoje na base.
- **Default vigente:** (a) — suficiente para investigar incidente, curto o bastante para não virar passivo de LGPD.
- **Recomendação:** (a). E vale registrar como **flag de upstream**: a tabela é da base compartilhada, então a política ideal é decidida uma vez para todos os sistemas.

### P-105 — Guardamos o corpo de todo e-mail enviado?

- **Origem:** `Q-88` + `F-31` (fundidas; DS1-3)
- **Fatia:** S1 e S13
- **Trava:** a forma da tabela `email_logs` (`DB-514`, e `DB-481` em S13).
- **Impacto:** `só interno`
- **Contexto:** No legado, `livetat_mailer_contacts` guarda `sender`, `target`, `target_name`, `subject`, `message` e `type` (`engines/mailer19/db/migrate/20160409121840_...:3-12`), e a coluna `message` foi **promovida de `string` para `text` justamente para caber o corpo** (duas migrations de 19/05/2017). Cada envio grava o corpo antes de enfileirar (`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:5-13`, e igualmente `:27,47,67,85`, mais 4 pontos em `engines/feedback19/app/decorators/grind_mailer_decorator.rb`) — **inclusive e-mails de credenciais** (`app/decorators/models/mailer_decorator.rb:4`). **Não há expurgo**: zero ocorrências de purge/cleanup/`destroy_all` em `lib/`, `app/jobs` ou no engine. Retenção infinita, e o único leitor é uma listagem paginada. No ai9, os 3 e-mails vivos do produto são de identidade (convite, código de acesso, boas-vindas) — e **o código de acesso é a credencial**.
- **Opções:** (a) **metadados sem corpo** (remetente, destinatário, assunto, status, timestamp), com expurgo de 180 dias; (b) corpo incluído, com expurgo curto (30 dias); (c) replicar (corpo, para sempre).
- **Default vigente:** (a).
- **Recomendação:** (a). Guardar o corpo de um e-mail que contém código de login é guardar a credencial em texto puro por outro nome — e é o passivo mais barato de eliminar desta lista.

### P-106 — Quem assina DKIM no ai9: a aplicação ou o provedor de envio?

- **Origem:** `Q-89` + `F-32` (fundidas; DS1-4)
- **Fatia:** S18 e S1
- **Trava:** nada no código — é infraestrutura. Mas `OPS-501` fica em aberto, e é **obrigatório antes do cutover**.
- **Impacto:** `só interno`
- **Contexto:** No legado a aplicação assina, e **a chave privada está versionada no repositório**: `lib/dkim_private_key.pem` (1,7 KB, rastreada pelo git), carregada em `config/application.rb:112`, com domínio `safegold.com.br` (`:110`) e seletor `dk` (`:111`). É o **D-85**. A chave precisa ser **rotacionada de qualquer forma** — está exposta a quem tiver o repositório, e o histórico do git não esquece.
- **Opções:** (a) assinatura no provedor de envio, chave fora do repositório; (b) assinatura na aplicação, com a chave em ENV/credentials e rotacionada; (c) não assinar nesta entrega.
- **Default vigente:** (a).
- **Recomendação:** (a). E, independentemente da escolha, **rotacionar a chave atual antes da demo** é item de runbook, não de decisão: ela já vazou por definição.

### P-107 — Chaves de terceiro vivem em ENV/credentials ou no model `Credential`?

- **Origem:** `Q-90`
- **Fatia:** S18
- **Trava:** trava `CFG-01`.
- **Impacto:** `só interno`
- **Contexto:** O catálogo da base sugeria o model `Credential`, mas `backend/app/models/credential.rb:7` restringe `provider` a provedores de IA — e a chave do Google Maps precisa chegar ao **navegador** de qualquer forma. No legado a situação é pior do que o material registrava (A-25): o token da ReceitaWS vem de ENV (`config/initializers/receitaws.rb:5`) **mas o valor real está versionado** em `config/application.arch.yml:12`; a chave do **Google Maps está hardcoded e duplicada** em `app/definitions/SFG/metadata.rb:8` e `:9` (a segunda dentro da própria URL, que vai para o HTML); e o `secret_key_base` está em texto puro em `config/development_credentials.yml:1`.
- **Opções:** (a) ENV/credentials, com `VITE_GOOGLE_API_KEY` para o front; **não** estender o `Credential`; (b) estender o `Credential` para aceitar provedores não-IA (mexe num model compartilhado, Princípio 6b); (c) misto.
- **Default vigente:** (a).
- **Recomendação:** (a), com uma regra inegociável: **nenhum segredo do legado entra no repositório novo**, e os três acima (ReceitaWS, Maps, `secret_key_base`) precisam ser **rotacionados no cutover**.

### P-108 — O logo da marca precisa de versões branca e monocromática de verdade?

- **Origem:** `Q-91` + `F-46` (fundidas; Q-14 de S17/S16)
- **Fatia:** S17 e S16
- **Trava:** os 4 anexos de tema de S17 e os ícones do manifest de S16.
- **Impacto:** `só interno`
- **Contexto:** **A premissa do material estava errada, em dois documentos (A-26).** O mapa e as fatias S16/S17 afirmavam que `app_symbol.png` e `app_text.png` "não existem no repositório". **Os dois existem**: `app/frontend/images/brand/app_symbol.png` (1,1 KB) e `app_text.png` (1,3 KB), junto de `app_logo_full.png` e várias variantes de tamanho — e a factory de tema os usa (`db/factories/app_theme_factory.rb:22-24`), o que só funciona porque estão lá. **O defeito real é outro:** em `app/definitions/SFG/theme.rb:47-57`, as variantes `_WHITE` e `_MONO` apontam **todas para o mesmo arquivo** da versão normal. Não existe logo branco nem monocromático de verdade — e S16 depende de um símbolo limpo para o `apple-touch-icon` e para o ícone `maskable` 512×512 (sem o qual o Android recorta o logo dentro de um círculo branco).
- **Opções:** (a) derivar as versões branca e monocromática (e o maskable) a partir dos arquivos existentes, registrando que são derivadas; (b) você fornece os originais do manual de marca; (c) usar o mesmo arquivo nas três variantes, como o legado.
- **Default vigente:** (a).
- **Recomendação:** (b) se existirem em algum lugar (site, apresentação, papelaria); senão (a). Um logo colorido sobre fundo escuro é a coisa que mais rápido faz uma demo parecer improvisada.

### P-109 — Logos: model `Medium` ou `has_one_attached` direto nos models?

- **Origem:** `Q-92`
- **Fatia:** S3 e S4
- **Trava:** trava `DB-056`, `DB-062`, `DB-089`, `FE-074` e `FE-087`.
- **Impacto:** `só interno`
- **Contexto:** No legado tudo é kt-paperclip em disco local. No ai9 há duas rotas: usar o model `Medium` (que a base já tem) ou `has_one_attached` direto nos models novos. O problema do `Medium` é que a tabela `media` **não tem dono nem escopo** — um logo criado por lá aparece na galeria `/media` para **qualquer autenticado**, e filtrar a galeria significaria mexer em `MediumService`, que é da base compartilhada (Princípio 6b). Nas duas opções, **Paperclip não é portado**. Os anexos em questão são **projeto** (`project.rb:48`, `avatar`), **portador** (`carrier.rb:16`) e **fornecedor** (`provider.rb:12`) — **`Company` não tem anexo nenhum**.
- **Opções:** (a) `has_one_attached` direto em `Project#logo`, `Carrier#logo` e `Provider#logo`, reusando a mesma pilha ActiveStorage + `image_processing` que o `Medium` usa; (b) usar `Medium`, aceitando que os logos apareçam na galeria; (c) usar `Medium` e autorizar tocar no `MediumService` para filtrar por escopo.
- **Default vigente:** (a).
- **Recomendação:** (a).

### P-110 — Uma trilha de auditoria só, e qual: `AuditEvent`, `paper_trail` ou `permission_audit_logs`?

- **Origem:** `Q-93` + `F-49` (fundidas; DS0-1)
- **Fatia:** S0 (consumida por S4, S9, S11, S12, S19)
- **Trava:** trava o desenho da trilha de auditoria. **Não trava tarefa nenhuma hoje — e é exatamente esse o risco.**
- **Impacto:** `só interno`
- **Contexto:** Há três candidatos e dois documentos internos que divergiam. `paper_trail` está declarada no `backend/Gemfile:47` da base ai9 e **não é usada por nenhum sistema** (mesma família de `aasm`, `Gemfile:45`, e `pg_search`, `Gemfile:87`) — ativá-la é decisão de **plataforma**, não de uma migração. `permission_audit_logs` **já existe na base**, tem o formato certo (`actor_type`/`actor_id`/`reason`/`metadata`) e **zero produtores**. `AuditEvent` é a trilha genérica que o desenho de S0 escolheu criar (`s0/design.md:89-91`), usando o formato de `permission_audit_logs` como molde. **Contexto do legado que ajuda a decidir:** o legado **não tem `paper_trail`**; a trilha dele é caseira (`app/models/tracking.rb` + `lib/tracking_facade.rb`) e cobre **só** jobs de template de disponibilidade e criação de projeto — não cobre CRUD, lançamentos, valores, permissões nem login. **Não há trilha financeira a preservar**: o que houver no ai9 é novo. **Por que é caro depois:** concessão de permissão, troca de papel, impersonation, renegociação, risco e recebíveis vão todos gravar nessa tabela. Trocar de tabela depois é migrar dado de auditoria, que é o dado que não se pode reescrever.
- **Opções:** (a) `AuditEvent` genérica — uma trilha para todos os domínios, e `paper_trail`/`permission_audit_logs` viram linhas em `upstream-flags.md`; (b) `permission_audit_logs` para atos administrativos e `AuditEvent` para domínio — duas trilhas, cada uma com semântica própria; (c) dar produtor a `permission_audit_logs` e **não** criar `AuditEvent`; (d) ativar `paper_trail` na base.
- **Default vigente:** (a).
- **Recomendação:** (a), **e é agora ou nunca** — a partir da primeira gravação, mudar vira migração de trilha. Duas trilhas para o mesmo tipo de ato é exatamente o que os contratos transversais existem para evitar, e ativar uma gem na base compartilhada afeta todos os sistemas. **Confira na mesma resposta o P-099:** `Tracking` seria uma **terceira** trilha, e vale decidir se ela e `AuditEvent` deveriam ser a mesma coisa.

### P-111 — As colunas renomeadas em 2022 têm leitores externos?

- **Origem:** `Q-94`
- **Fatia:** S9 e S14
- **Trava:** nada — é informação que você tem e o repositório não.
- **Impacto:** `só interno`
- **Contexto:** São **três renomeações, em três tabelas diferentes**, todas em 29/04/2022 — e só **uma** é em `renegotiations`: `rename_column :renegotiations, :total_value, :installments_main_value` (`db/migrate/20220429122226_...:4`), **com mudança real de semântica** (era "R$ Total da dívida", virou "soma do principal das parcelas" — o comentário legado em `renegotiation.rb:273` confirma). As outras duas: `renegotiation_installments.value → main_value` (`20220429122346_...:3`) e `renegotiation_payments.value → installment_paid_value_with_interest_cm` (`20220429122419_...:3`).
- **Opções:** (a) adotar os nomes novos e pronto; (b) adotar os nomes novos e manter uma *view* de compatibilidade com os antigos; (c) manter os nomes antigos.
- **Default vigente:** (a).
- **Recomendação:** (a), a menos que você saiba de relatório ou integração externa lendo `total_value`. A mudança de **semântica** de `total_value` é a que mais importa: um relatório antigo que some essa coluna passou a somar outra coisa desde 2022.

### P-112 — `is_active` está no `permit` do indicador mas não no formulário

- **Origem:** `Q-96`
- **Fatia:** S10
- **Trava:** trava `BE-316`.
- **Impacto:** `só interno`
- **Contexto:** `app/controllers/pub/indicators_controller.rb:144` permite `:is_active`, mas o formulário só tem título, chave e descrição (`.../indicators/helper/_body.html.erb`). Existe ainda uma action paralela `activated` (`:86-98`) que grava direto de `params[:is_active]`, **fora do `permit`** — ou seja, há **dois caminhos de escrita e nenhum deles é o formulário**.
- **Opções:** (a) manter os dois caminhos; (b) só a action explícita de ativar/desativar, tirando `is_active` do `permit` do update; (c) expor o campo no formulário.
- **Default vigente:** (a) — pode haver cliente externo postando.
- **Recomendação:** (b). Um campo com dois caminhos de escrita, sendo um deles fora do `permit`, é a receita de "ninguém sabe quem desativou".

### P-113 — `month`/`year` do lançamento: inteiros soltos ou uma coluna `date`?

- **Origem:** `Q-97`
- **Fatia:** S10
- **Trava:** trava `BE-329` e `DB-311`.
- **Impacto:** `só interno`
- **Contexto:** `db/migrate/20211027140815_create_indicator_entries.rb:9-10` cria `t.integer :month` e `t.integer :year` — sem `null: false`, sem default, sem CHECK e sem índice. No model há só `presence` (`indicator_entry.rb:10-11`) e a unicidade composta (`:6`). **Nada impede `month = 47`**, e o único guarda-corpo é indireto e tardio: `Date.new(self.year, self.month)` em `:57` **estoura em runtime** na hora de exibir.
- **Opções:** (a) manter inteiros, acrescentando `CHECK (month BETWEEN 1 AND 12)` e `NOT NULL`; (b) trocar por uma coluna `date` normalizada no primeiro dia do mês; (c) replicar como está.
- **Default vigente:** (a).
- **Recomendação:** (a). Preserva a forma que a grade já usa para montar as colunas do ano e fecha o buraco no banco, que é onde ele precisa ser fechado.

### P-114 — O `user_id` do lançamento é "quem lançou" ou "quem alterou por último"?

- **Origem:** `Q-98`
- **Fatia:** S10
- **Trava:** trava `BE-327`.
- **Impacto:** `só interno`
- **Contexto:** É o segundo, e por acidente: o formulário da grade é o mesmo para criar e atualizar, e reenvia `current_user.id` num `hidden_field` a cada submissão (`.../indicator_entries/list/_widget.html.erb:18` e `:44`). O `permit` aceita (`indicator_entries_controller.rb:107`) e o `update` aplica (`:61`), sem nenhum `on: [:create]` protegendo o campo. **Verificado, e isso muda o peso da pergunta:** o autor **não é exibido em lugar nenhum** — as únicas ocorrências de `user` em toda a pasta de views de lançamentos são esses dois `hidden_field`. Não há coluna "lançado por", tooltip nem tela de detalhe. O dado é sobrescrito e ninguém sequer o vê.
- **Opções:** (a) `created_by` imutável na criação + `updated_by` atualizado a cada alteração (dois campos, cada um dizendo a verdade); (b) manter um campo só, com a semântica de "quem alterou por último", agora **documentada**; (c) replicar sem mudar nada.
- **Default vigente:** (b).
- **Recomendação:** (a). São duas colunas e resolvem de vez uma pergunta ("quem lançou isto?") que num sistema financeiro sempre acaba sendo feita.

### P-115 — `polemk_webhooks`: renomear o campo exige coordenar front e backend

- **Origem:** `F-51`
- **Fatia:** S2 (a tela) e a base compartilhada
- **Trava:** nada — é a pergunta se vale a pena.
- **Impacto:** `só interno`
- **Contexto:** Conferido: `polemk_webhooks` **não é nome interno, é campo de contrato de API**. Aparece em `backend/app/controllers/api/entities/polemk_instances.rb:26` (`expose :polemk_webhooks`) e é consumido em `frontend/src/app/pages/WhatsappPage.tsx:117` e `:304-305`. Mais o model, o serviço, o seed, duas migrations e três specs. "polemk" é a marca de **outro produto da base** aparecendo dentro do Safegold.
- **Opções:** (a) não renomear — é nome de peça compartilhada (Princípio 6b), e o campo não aparece para o usuário final; (b) renomear tudo de uma vez (entity, front, model, serviço, seed, migrations, specs) numa mudança coordenada; (c) manter o campo e expor um **alias** no entity, para o front usar o nome novo sem quebrar a base.
- **Default vigente:** (a) implícito — nenhuma fatia tem tarefa de renomear.
- **Recomendação:** (a). O nome não vaza para nenhuma tela do Safegold; renomear contrato de API compartilhado por estética é o tipo de mudança que quebra outro produto na sexta-feira.

### P-116 — Qual é o padrão de paginação do backend? (Kaminari está no Gemfile sem uso)

- **Origem:** `C-07` — **recuperada** (a metade das fatias a descartou como "duplicata do mapa", e o mapa não a tem; ver 4.3)
- **Fatia:** S0, consumida por todas as fatias com lista
- **Trava:** **trava código hoje** — bloco 0 de S5, item 0.3 (`s5/tasks.md:20`): *"Escolher o padrão de paginação do backend (Kaminari × padrão manual de `users_service.rb:49`) e registrar. Vale para os 14 endpoints de lista do bloco. **Não pode ficar meio a meio.**"* O mesmo vale para os outros blocos.
- **Impacto:** `só interno`
- **Contexto:** `kaminari` está declarada no `backend/Gemfile:85` da base ai9 e **não tem uma única chamada em `backend/app`** (`s5/design.md:257`). O padrão que de fato existe hoje é manual, com `limit`/`offset` calculados à mão em `users_service.rb:49`. Se cada fatia escolher sozinha, metade dos endpoints vai devolver um envelope de paginação e a outra metade outro — e o front vai ter que lidar com dois contratos. **Isto é diferente de DEC-09/Q-04**, que decidiu que *a paginação passa a funcionar de verdade* (hoje `limit`/`offset` são descartados em quase todo `search`, D-20); aquilo é o comportamento, isto é a forma.
- **Opções:** (a) usar **Kaminari**, já que a gem está no Gemfile, e registrar como consumo de uma peça que a base já declarou; (b) padronizar o **manual** de `users_service.rb:49` e registrar Kaminari como flag de upstream ("gem declarada sem uso"); (c) deixar cada fatia escolher.
- **Default vigente:** **nenhum** — a tarefa está escrita como "escolher", e ninguém escolheu.
- **Recomendação:** (b) se o padrão manual já for o de fato usado pelos endpoints existentes da base (é o caso hoje), porque adotar Kaminari agora significaria reescrever os endpoints que já existem. (c) está fora de questão: é literalmente o cenário que a tarefa proíbe.

### P-117 — Dark mode entra?

- **Origem:** `Q-02` de S17 — **recuperada** (descartada como "duplicata do mapa", e o mapa não a tem; ver 4.3)
- **Fatia:** S17 e a tematização
- **Trava:** nada — o mecanismo já existe na base (`ThemeToggle`).
- **Impacto:** `só interno`
- **Contexto:** `s17/proposal.md:141` registra a pergunta com default "entra: o mecanismo já está na base; o custo é a paleta". E `decisions.md:602` já manda o `theming-brand-engineer` entregar "a marca Safegold em light **e** dark" como item **crítico para o resultado** da demo. Na prática a resposta já está dada em dois lugares — só nunca virou DEC numerado, e cada tela precisa ser conferida nos dois modos.
- **Opções:** (a) entra — a marca é tokenizada e conferida nos dois modos; (b) só light nesta entrega, e dark depois.
- **Default vigente:** (a).
- **Recomendação:** (a). Confirmar com uma letra é mais barato que deixar implícito, porque "conferir toda tela nos dois modos" é custo real de QA e precisa estar no plano da sexta.

---

## Já decididas — não estão neste documento

Cruzamento com `decisions.md` (DEC-01..DEC-23), das duas metades juntas. Ficam aqui para que
ninguém as reabra por engano, e como prova de que as 117 acima não repetem nada.

| Pergunta | Decisão que já a fechou |
| -------- | ----------------------- |
| Sinal da exposição ao risco (D-93, D-95, D-96) | **DEC-01** — replicar exatamente |
| Dinheiro em float (D-104, D-13) | **DEC-02** — replicar para bater número |
| Versão de produção (Ruby/Rails) | **DEC-03** — 2.6.1 / 6.0.3.2 |
| Dump do banco: `pg_dump --schema-only`? | **DEC-04** — seguir só com as migrations |
| Banco de produção: PostgreSQL ou MySQL | **DEC-05** — PostgreSQL |
| Timezone: UTC ou horário local | **DEC-06** — UTC, convertido por faixa de DST |
| Multi-tenancy: escopo por projeto, empresa ou nenhum | **DEC-07** — mantém a divisão do legado (C1) |
| Features novas (dashboard, série histórica, PDF, i18n) | **DEC-09** — fora; parcialmente emendada por DEC-21 |
| A paginação passa a funcionar de verdade? (Q-04/D-20) | **DEC-09** — sim (**mas a escolha do padrão continua aberta: P-116**) |
| `vendor/doughnut` / `vendor/dialog` | **DEC-10** — substituir pela lib do ai9 (parcialmente revogado: não havia gráfico a migrar) |
| `Legacy::execute` ainda roda? | **DEC-09/DEC-12** — assumido como não executado desde 2021 |
| Rota `/` aponta para o login | **DEC-13.3** |
| Login mantém o canal WhatsApp | **DEC-14** (revoga DEC-13.4) |
| Disponibilidades e cobranças estão vivas (Q-A3) | **DEC-15.1** — os 4 itens nascem habilitados |
| Quem administra `app_themes` (Q-A4) | **DEC-18** — OG/Admin |
| Os 4 limites `max_*` não são aplicados (Q-A7) | **DEC-18** |
| OG é papel do fornecedor (Q-A5) | **DEC-18.1** |
| Colaborador lê os catálogos globais | **DEC-18.4** |
| Quem gerencia membership (Q-A6) | **DEC-18.5** — criam/removem OG, Admin e Gerente; o dono do projeto não vira papel |
| `Membership.role` é rótulo descritivo (Q-A2) | **DEC-18.6** |
| Cadastro público desligado; entrada só por convite | **DEC-18.7** — mas ver **P-060**, que é sobre as rotas **da base ai9**, não do legado |
| Abilities editadas à mão em produção (Q-A1) | **DEC-19** — adiada para depois da venda |
| Histórico só em memória/Redis, sem tabela | **DEC-20** |
| Gráficos nos indicadores (`NEW-001`) | **DEC-21.1** — entra, em S15. E **não** no risco |
| Dashboard resumo na tela inicial (`NEW-002`) | **DEC-21.2** — entra, em S15 |
| PWA (`NEW-003`) | **DEC-21.3** — só o mínimo instalável (manifest + ícones), sem service worker, em S16 |
| TLS do SMTP: `openssl_verify_mode: 'none'` → `peer`? | **DEC-21.4** — *"esquece isso por enquanto"*. Fica como flag de upstream, com `OPS-484` e `OPS-626` **explicitamente não atendidos** |
| Escopo da demo: cortar fatias? | **DEC-22** — manter tudo, as 20 fatias |
| Detalhe de operação estruturada exibe Saldo negativo (Q-R20) | **DEC-01** — o negativo é o comportamento aprovado |
| Série histórica de indicador abandonada (Q-R23) | **DEC-09** + **DEC-21.1**, que entrega a série mensal por outra porta |

---

## De-para: origem → `P-xxx`

Prova de que a fusão não perdeu nada. **Toda origem `Q-01..Q-98` e `F-01..F-51` aparece
exatamente uma vez nesta tabela**, mais as 2 recuperadas.

### Metade dos mapas (`Q-01` … `Q-98`)

| Q | P | | Q | P | | Q | P | | Q | P |
| - | - | - | - | - | - | - | - | - | - | - |
| Q-01 | P-001 | | Q-26 | P-028 | | Q-51 | P-053 | | Q-76 | P-085 |
| Q-02 | P-002 **+** P-003 *(desdobrada)* | | Q-27 | P-029 | | Q-52 | P-054 | | Q-77 | P-086 |
| Q-03 | P-004 | | Q-28 | P-030 | | Q-53 | P-055 | | Q-78 | P-087 |
| Q-04 | P-005 | | Q-29 | P-031 | | Q-54 | P-056 | | Q-79 | P-088 |
| Q-05 | P-006 | | Q-30 | P-032 | | Q-55 | P-057 | | Q-80 | P-089 |
| Q-06 | P-007 | | Q-31 | P-033 | | Q-56 | P-058 | | Q-81 | P-090 |
| Q-07 | P-008 | | Q-32 | P-034 | | Q-57 | P-059 | | Q-82 | P-091 |
| Q-08 | P-009 | | Q-33 | P-035 | | Q-58 | P-067 | | Q-83 | P-092 |
| Q-09 | P-010 | | Q-34 | P-036 | | Q-59 | P-068 | | Q-84 | P-093 |
| Q-10 | P-011 | | Q-35 | P-037 | | Q-60 | P-069 | | Q-85 | P-094 |
| Q-11 | P-012 | | Q-36 | P-038 | | Q-61 | P-070 | | Q-86 | P-095 |
| Q-12 | P-013 | | Q-37 | P-039 | | Q-62 | P-071 | | Q-87 | P-104 |
| Q-13 | P-014 | | Q-38 | P-040 | | Q-63 | P-072 | | Q-88 | P-105 |
| Q-14 | P-015 | | Q-39 | P-041 | | Q-64 | P-073 | | Q-89 | P-106 |
| Q-15 | P-016 | | Q-40 | P-042 | | Q-65 | P-074 | | Q-90 | P-107 |
| Q-16 | P-017 | | Q-41 | P-043 | | Q-66 | P-075 | | Q-91 | P-108 |
| Q-17 | P-019 | | Q-42 | P-044 | | Q-67 | P-076 | | Q-92 | P-109 |
| Q-18 | P-020 | | Q-43 | P-045 | | Q-68 | P-077 | | Q-93 | P-110 |
| Q-19 | P-021 | | Q-44 | P-046 | | Q-69 | P-078 | | Q-94 | P-111 |
| Q-20 | P-022 | | Q-45 | P-047 | | Q-70 | P-079 | | Q-95 | P-096 |
| Q-21 | P-023 | | Q-46 | P-048 | | Q-71 | P-080 | | Q-96 | P-112 |
| Q-22 | P-024 | | Q-47 | P-049 | | Q-72 | P-081 | | Q-97 | P-113 |
| Q-23 | P-025 | | Q-48 | P-050 | | Q-73 | P-082 | | Q-98 | P-114 |
| Q-24 | P-026 | | Q-49 | P-051 | | Q-74 | P-083 | | | |
| Q-25 | P-027 | | Q-50 | P-052 | | Q-75 | P-084 | | | |

### Metade do empacotamento (`F-01` … `F-51`)

| F | P | Como entrou | | F | P | Como entrou |
| - | - | ----------- | - | - | - | ----------- |
| F-01 | P-005 | fundida com Q-04 | | F-27 | P-086 | fundida com Q-77 |
| F-02 | P-001 | fundida com Q-01 | | F-28 | P-065 | nova |
| F-03 | P-002 | fundida com Q-02 (1ª metade) | | F-29 | P-089 | fundida com Q-80 |
| F-04 | P-003 | fundida com Q-02 (2ª metade) | | F-30 | P-066 | nova |
| F-05 | P-004 | fundida com Q-03 | | F-31 | P-105 | fundida com Q-88 |
| F-06 | P-015 | fundida com Q-14 | | F-32 | P-106 | fundida com Q-89 |
| F-07 | P-018 | nova | | F-33 | P-097 | nova |
| F-08 | P-077 | fundida com Q-68 | | F-34 | P-070 | fundida com Q-61 |
| F-09 | P-009 | fundida com Q-08 | | F-35 | P-091 | fundida com Q-82 |
| F-10 | P-019 | fundida com Q-17 | | F-36 | P-078 | fundida com Q-69 |
| F-11 | P-036 | fundida com Q-34 | | F-37 | P-100 | nova |
| F-12 | P-020 | fundida com Q-18 | | F-38 | P-099 | nova |
| F-13 | P-021 | fundida com Q-19 | | F-39 | P-101 | nova |
| F-14 | P-067 | fundida com Q-58 | | F-40 | P-095 | fundida com Q-86 |
| F-15 | P-022 | fundida com Q-20 | | F-41 | P-051 | fundida com Q-49 |
| F-16 | P-016 | fundida com Q-15 | | F-42 | P-102 | nova |
| F-17 | P-032 | fundida com Q-30 | | F-43 | P-098 | nova |
| F-18 | P-026 | fundida com Q-24 | | F-44 | P-096 | fundida com Q-95 |
| F-19 | P-038 | fundida com Q-36 | | F-45 | P-045 | fundida com Q-43 |
| F-20 | P-082 | fundida com Q-73 | | F-46 | P-108 | fundida com Q-91 |
| F-21 | P-053 | fundida com Q-51 | | F-47 | P-103 | nova |
| F-22 | P-060 | nova | | F-48 | P-093 | fundida com Q-84 |
| F-23 | P-062 | nova | | F-49 | P-110 | fundida com Q-93 |
| F-24 | P-063 | nova | | F-50 | P-061 | nova |
| F-25 | P-092 | fundida com Q-83 | | F-51 | P-115 | nova |
| F-26 | P-064 | nova | | | | |

### Recuperadas (não estavam em nenhuma das duas metades como pergunta)

| Origem | P | Por quê |
| ------ | - | ------- |
| `C-07` (`s5/proposal.md:221`, `s5/design.md:257`, `s5/tasks.md:20`) | P-116 | Marcada como "duplicata do mapa" e **sem par no mapa**. Continua aberta e trava 14 endpoints |
| `Q-02` de S17 (`s17/proposal.md:141`) | P-117 | Marcada como "duplicata do mapa" e **sem par no mapa**. Sem DEC numerado, embora `decisions.md:602` já a assuma |

### Colisão de nomes `Q-B*` — desambiguada por assunto, não por número

O identificador `Q-B*` significa coisas diferentes em documentos diferentes. **Ao responder,
use o número `P-`, nunca o `Q-B`.**

| Identificador | Significado A | Significado B | Significado C |
| ------------- | ------------- | ------------- | ------------- |
| `Q-B1` | app móvel consumindo os headers `X-LAA-*` (`map/auth-admin.md:658`) → **P-084** | o aceite volta a ser explícito? (`map/receivables-renegotiations.md:89`) → **P-020** | — |
| `Q-B2` | login por Facebook (S1) → **P-047** | mínimo probatório do aceite (S12) → **P-067** | — |
| `Q-B5` | onde ficam os arquivos em produção (`map/auth-admin.md:662`) → **P-051** | recalcular o histórico do borderô (`map/receivables-renegotiations.md:490`) → **P-005** | tolerância de 30 dias (`s12/tasks.md:134`) → coberta por **P-020** |

---

## Validação da fusão

Rodada contra este arquivo. Reproduzível: o script confere numeração, ordem, campos e o
de-para contra as duas metades de origem.

```
1) ENTRADAS ENCONTRADAS ............ 117
2) NUMERACAO ...................... OK  P-001..P-117, sequencial, sem buraco e sem repetida
3) 7 CAMPOS + ORIGEM .............. OK  todas as 117 entradas tem os 8 campos
4) ORDEM POR IMPACTO .............. OK  monotonica
     muda número na tela=18 (P-001..P-018)
     muda comportamento observável=48 (P-019..P-066)
     muda escopo=37 (P-067..P-103)
     só interno=14 (P-104..P-117)
5) DE-PARA COMPLETO ............... OK  Q-01..Q-98 (98/98) e F-01..F-51 (51/51), cada uma exatamente 1x
6) ALVOS DO DE-PARA ............... OK  os 117 P-xxx citados existem como entrada
7) ORIGEM RASTREAVEL .............. OK  todas as 117 entradas citam Q-xx, F-xx ou a origem recuperada
8) PLACAR x CONTAGEM REAL ......... OK  117 = 18 + 48 + 37 + 14, igual ao declarado na secao 2

RESULTADO: TODAS AS 8 VERIFICACOES PASSARAM
```
