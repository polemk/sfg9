# Migration map — Safegold -> ai9 (consolidado)

> **Phase 2 fechado em 25/08/2026.** Este arquivo e o indice e o contrato de ordem. As
> **1433 linhas item-a-item** vivem nos 5 mapas de bloco em `.migration-ai9/map/`; nao sao
> duplicadas aqui.

## Cobertura — verificada por script, nao por relatorio

```
Inventario: 1439 IDs
  auth-admin.md                    341      projects-cadastros.md            290
  receivables-renegotiations.md    246      risk-indicators.md               281
  data-infra.md                    275
Mapeados (unicos): 1433
FALTANDO: 6  -> FE-640..645 (site publico, `dropped` por decisao do usuario no Phase 0)
SOBRANDO: 0        EM DOIS BLOCOS: 0
```

Mesma disciplina do Phase 1: cinco agentes reportaram "cobertura conferida" e cada um
estava certo **dentro da sua fatia** — a conferencia que vale e no consolidado. Desta vez
nao houve orfao de fronteira **no mapeamento**, o que e resultado do contrato §0.6 ter sido
definido cedo.

**Mas houve no empacotamento em fatias, e a conferencia consolidada o encontrou.** Os 17
openspec changes iniciais deixaram **175 IDs sem dono nenhum** e **27 com dois donos**. A
causa e conhecida e esta registrada: o bloco `data-infra` reivindicou 100 dos seus 275 IDs,
presumindo que as fatias irmas pegariam o resto — **nenhuma pegou** (161 dos 175 vinham de
`data-infra.md`). Os 27 com dois donos eram, quase todos, fatias apontando uma para a outra
por fora de uma secao de fronteira.

Fechado com **tres fatias novas** (S17, S18, S19), **169 IDs adotados** por fatia existente
ou nova, e **um dono unico** para cada um dos 27 em disputa, escrito na secao "Fronteiras"
das duas pontas. Sobram **6 sem dono** — `FE-640..645`, o site publico, `dropped` por decisao
do usuario no Phase 0. **Um ID sem fatia nao vira tarefa, nao vira codigo e nao e procurado
no Phase 4.**

## Placar por estrategia

| Bloco | reuse | adapt | build | build? | drop |
| ----- | ----- | ----- | ----- | ------ | ---- |
| auth-admin | 59 | 154 | 47 | 2 | 82 |
| projects-cadastros | 5 | 26 | 259 | — | — |
| receivables-renegotiations | 25 | 33 | 188 | — | — |
| risk-indicators | 5 | 12 | 220 | 23 | 21 |
| data-infra | 29 | 49 | 164 | 16 | 28 |
| **Total** | **123** | **274** | **878** | **41** | **131** |

**A leitura correta destes numeros:** `build` alto **nao** e falha de reuso — e o
diagnostico. A base pos-trim nao tem dominio financeiro, e forcar `adapt` entregaria uma
abstracao que nao foi feita para o problema. O reuso real esta **dentro** de cada `build`:
a coluna "Equivalente ai9" esta preenchida nas 878 linhas, apontando a infra herdada
(auth, ActiveStorage, Action Cable, paginacao, design system, React Query).

O contraste entre `auth-admin` (**62% reuse+adapt**) e `projects` (**89% build**) e
exatamente o que o catalogo previu.

---

## Os quatro contratos transversais (valem para todos os blocos)

Nasceram durante o mapeamento, quando um bloco mediu algo que mudava o desenho dos outros.
**Estao aqui porque um sistema com duas semanticas para a mesma coisa e pior que um sistema
com a semantica errada.**

### C1 — Escopo por projeto: **no endpoint, nunca `default_scope`**
Definido em `map/projects-cadastros.md` §0.6. A base ai9 e **declaradamente single-tenant**
— nao ha `tenant_id`/`account_id`/`organization_id` em model nenhum. O mecanismo nasce aqui:
`memberships` + `users.current_project_id` + `current_project!` + concern `ProjectScoped`.

`default_scope` foi recusado porque vaza para `unscoped`, quebra `joins` em silencio,
contamina jobs e seeds que **legitimamente** cruzam projetos, e torna o escopo **invisivel
na leitura**. O legado errou exatamente ai: sempre que chegava um id por parametro, o filtro
de projeto era descartado — a familia **D-01 / D-16 / D-29 / D-76 / D-100**.

**Duas condicoes que o bloco de auth acrescentou, e que ficam valendo:** o valor armazenado
em `current_project_id` e **revalidado a cada request** (senao membership revogada continua
valendo); e projeto inexistente e projeto sem membership respondem **o mesmo status**
(distinguir 403 de 404 vira oraculo de existencia de id).

### C2 — Calculo financeiro: **um servico, chamado pela tela E pela gravacao**
`ReceivableCalculator`, `Risk::Calculator` e `Structured::RemunerationCalculator`. A previa
em tempo real da tela chama **o mesmo servico** que grava — unica forma de garantir que
previa e gravacao nunca divirjam (**D-09**), e o que torna o **DEC-02** auditavel.

**Golden test por formula**, alimentado com valores extraidos do legado — que **nao tem
nenhum teste** (**D-114**). E o que transforma "replicar o float" de intencao em contrato
verificavel.

### C3 — Hierarquia de papel: **a escala e INVERTIDA entre os dois sistemas**
Legado: **maior = mais poder** (OG 1111 > Admin 998 > Gerente 888 > Colaborador 799).
ai9: **menor = mais poder** (`user_type.rb:38-41`, OG = 1). E os scopes seguem a convencao
do ai9: `higher_than` e `where('hierarchy_level < ?', level)` (`:20`).

Adotada a convencao do **ai9** (Principio 6b: `UserType` e peca da base). A conversao no ETL
e **tabela de-para explicita, nunca formula** — formula sobrevive a valor inesperado e
produz nivel plausivel e errado.

**Por que e o item de maior risco da migracao:** as decisoes **DEC-18.2** e **DEC-18.3**
(Admin so age sobre hierarquia inferior) dependem inteiramente do **sinal** dessa
comparacao. Inverter o sinal **da poder de OG a um Colaborador** — e passa em qualquer teste
que verifique so que "a trava existe", porque a trava existe: esta apontando para o lado
errado. **Todo teste de hierarquia verifica os DOIS lados**: "Admin NAO edita ability de OG"
**e** "Admin EDITA ability de Colaborador".

### C4 — Propriedade de `Membership`: nasce em `projects`
Dois blocos a reivindicaram (`auth-admin` S4 e `projects` §0.6). Vale o desenho de
`projects`, que e o normativo e o mais completo; `auth-admin` aponta para ele. **O risco
aqui nunca foi construir duas vezes — era os dois blocos apontarem um para o outro.**

---

## Ordem de execucao das fatias

Ordenada por **dependencia tecnica** (DEC-17.1 revogou a ordem "por valor de demo"). S0 e
pre-requisito de tudo.

| # | Fatia | Bloco | Depende de |
| - | ----- | ----- | ---------- |
| **S0** | **Fundacao**: `Project`, `Membership`, `current_project!`, `ProjectScoped`, papeis + hierarquia (C3), `user_is_readonly`, primitivos que faltam no design system | projects + auth | — |
| S1 | Autenticacao e conta: entrada por convite, magic link/codigo (e-mail **e** WhatsApp), perfil, bloqueio de conta | auth | S0 |
| S2 | Console e navegacao: shell, menu por papel, 404, estados vazio/erro | auth + data | S0 |
| S3 | Cadastros globais: portadores, grupos de portadores, segmentos, subsegmentos, tipos de garantia + o arcabouço de seed de referência | projects | S0 |
| S4 | Projeto e empresas: CRUD, membros, garantias, indicadores especificos | projects | S0, S3 |
| S5 | Limites de risco (`RiskControl` — **uma linha por empresa x portador x tipo**) | risk | S4 |
| S6 | Recebiveis / borderô, com o motor de calculo (C2) | receivables | S5 |
| S7 | Operacoes de risco: movimentos, extensoes, renovacao | risk | S5, S6 |
| S8 | Operacoes estruturadas e remuneracao | risk | S7 |
| S9 | Renegociacoes: parcelas, pagamentos, anexos | renegotiations | S4 |
| S10 | Indicadores e series mensais | risk | S4 |
| S11 | Disponibilidades e cobrancas (**vivas**, DEC-15.1) | projects | S4 |
| S12 | Contratos, ajuda, FAQ | receivables + data | S1 |
| S13 | Jobs agendados e integracoes | data | S6, S7 |
| S14 | ETL: introspeccao, dry-run, reconciliacao, runbook | data | todas |
| **S17** | **Temas**: tema como dado (CRUD, precedencia, tokens em runtime, dark mode), marca em fonte unica | data | S2, S13, tematizacao |
| **S18** | **Plataforma**: configuracao, segredos, boot fail-fast, TLS, i18n, CSP, pipeline de assets, bases de endpoint | data | **nenhuma** |
| **S19** | **Trilha de auditoria** (`Tracking`) **e transversais** de dominio e UI (helpers, validadores, ordenacao) | data | S0, S18 |

**Onde entram as tres fatias novas na ordem real:** **S18** roda **junto de S0** (nao depende
de nada e todas dependem dela — sem `.env.example`, banco `sfg9_dev` e boot fail-fast, cada
fatia improvisa a sua configuracao). **S19** roda logo depois de S0, porque S13 emite trilha
e S11 a consome. **S17** roda depois de S2 e do motor de anexos de S13, e e a fatia que
transforma a marca em dado — o `theming-brand-engineer` entrega a paleta, S17 entrega o
mecanismo que a serve.

**Transversal, roda ANTES de qualquer tela de feature:** o `theming-brand-engineer` — marca
Safegold em **light e dark**, conteudo padrao do ai9 substituido, primitivos padronizados.
Numa demo comercial, tela funcionalmente correta com identidade generica **nao demonstra o
produto do cliente**.

**Dependencias entre blocos, ja mapeadas:** SR-5/SR-6 (recebiveis) dependem de R5/R6
(risco) · E2 (remuneracao) depende de `receipts`/`charges` (projetos) · BE-052 (resumo de
limites) consome R3 (risco).

---

## Achados do mapeamento que mudam o escopo

Cinco coisas que so apareceram porque alguem foi conferir na fonte:

1. **O legado nao renderiza grafico nenhum.** `vendor/doughnut` e exposto como global em
   `index.js.erb:31,37` e **nenhuma view o instancia** (`grep` por `new Chart`/`doughnut`
   nas views: vazio). O **DEC-10** ("usar as libs de grafico do ai9") partia da premissa de
   que havia grafico a migrar. **Nao ha.** Grafico passa a ser **feature nova** — decisao do
   usuario, nao paridade.
2. **O legado quase nao faz polling.** `PollingManager` tem **uma** instanciacao, no monitor
   de usuario da navbar. O Principio 10 continua valendo para o que construirmos, mas
   "converter polling para Action Cable" e um item pequeno, nao um tema.
3. **`RiskControl` mudou de forma em 2022** (`20220611152145_change_risk_control_fields`):
   deixou de ser 4 modalidades em colunas fixas (`limite_*`/`taxa_*`) e passou a ser **uma
   linha por (empresa, portador, tipo)**, com um `limite` e uma `taxa` — e as modalidades
   viraram linhas de `RiskOperationType`, **cadastro aberto**. Eu havia descrito o schema
   pre-2022 no briefing; quem lesse literalmente perderia o motor de pre-faturamento.
4. **O cadastro publico renasce no ai9 por uma porta que nao veio do legado.**
   `pre_register`, `complete_registration` e `visitor_signup*` estao na allowlist publica
   (`api/root.rb:35-46`). Nao basta "nao portar" o cadastro do legado — o **D-39** volta
   sozinho se essas rotas ficarem.
5. **PWA foi decidido SIM no Phase 0 e nao esta em nenhuma fatia.** A base nao tem nada de
   PWA. Registrado para a decisao nao sumir — ver a lista de perguntas.

## Adicoes de escopo aprovadas (DEC-21) — **features novas, nao paridade**

| ID | O que | Fatia | Depende de |
| -- | ----- | ----- | ---------- |
| `NEW-001` | Graficos nos **indicadores** (serie mensal + volume por portador, Recharts) | S15 | S10 |
| `NEW-002` | **Dashboard resumo** na tela inicial (total operado, exposicao, limites no teto, renegociacoes em atraso) | S15 | S5..S8, S10 |
| `NEW-003` | **PWA minimo**: manifest + icones, instalavel. Sem service worker, sem offline | S16 | S2 |

Entram **no fim** de proposito: dependem dos servicos de calculo. Dashboard bonito sobre
numero errado e pior que dashboard nenhum.

No ledger entram como **`new`**, nunca como item de paridade — o QA do Phase 4 **nao deve
procura-los no legado**, porque nao estao la.

## Onde estao as perguntas ao usuario

Cada mapa tem a sua secao; **~76 no total**, todas com default declarado. As que travam
codigo ou mudam escopo foram levadas ao usuario em separado. As demais seguem pelo default
registrado, e o default esta escrito — nao e silencio.
