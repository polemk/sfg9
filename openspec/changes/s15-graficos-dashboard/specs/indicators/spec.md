## ADDED Requirements

### Requirement: NEW-001 — Gráficos de indicador (FEATURE NOVA, não paridade)
O ai9 **MUST** oferecer, dentro das telas de indicadores, dois gráficos sobre os
componentes Recharts que já existem na base
(`frontend/src/components/charts/RechartsLine.tsx` e `RechartsBar.tsx`, com
`charts/theme.ts` lendo as variáveis CSS do tema): **série mensal** do indicador selecionado
no período filtrado, e **volume por portador** no período e no projeto corrente.

> **Esta é uma feature nova (DEC-21), não paridade.** Ela **NÃO existe no legado** e **NÃO
> deve ser procurada lá** pelo QA do Phase 4. Prova medida no Phase 2: `Doughnut` é exposto
> como global em `../sfg/app/frontend/vendor/js/index.js.erb:31,37` e **nenhuma view o
> instancia** (grep em `app/views/`, `app/frontend/js/`, `*.erb`, `*.js`, `*.scss`: zero
> ocorrências fora de `vendor/`). No `parity-ledger.md` entra como **`new`**.
> Isto **supera**, por decisão posterior do usuário, a nota de escopo do DEC-09 registrada no
> Purpose desta capability ("gráfico de indicador NÃO existe no legado e fica fora do
> escopo") — a nota continua correta quanto ao legado; o que mudou foi a decisão.

Os dados **MUST** vir dos endpoints que a capability já expõe (BE-716, BE-324) e dos
agregados de risco já calculados (BE-249, BE-251). O ai9 **MUST NOT** calcular série derivada
(variação mês a mês, ano a ano, percentual, acumulado ou média) — isso permanece fora de
escopo — e **MUST NOT** agregar valor financeiro no cliente.

Os gráficos **MUST** herdar o filtro de período da tela em que vivem e **MUST NOT** ter
filtro próprio; **MUST** distinguir "sem lançamento no período" de valor zero; e **MUST NOT**
usar cor como único portador de informação.

#### Scenario: série mensal de um indicador
- **GIVEN** um indicador com lançamentos em 24 meses
- **WHEN** o usuário abre a grade de lançamentos do projeto
- **THEN** o gráfico de linha mostra os valores lançados mês a mês no período filtrado

#### Scenario: o gráfico segue o filtro da tela
- **GIVEN** o gráfico e a grade na mesma tela
- **WHEN** o usuário troca o período na grade
- **THEN** o gráfico passa a mostrar o novo período, sem um segundo filtro que produza duas verdades na mesma tela

#### Scenario: período sem lançamento
- **GIVEN** um indicador sem nenhum lançamento no período filtrado
- **WHEN** o gráfico é renderizado
- **THEN** ele exibe o estado "sem lançamentos no período", e não uma série de zeros

#### Scenario: volume por portador é legível sem depender da cor
- **GIVEN** o gráfico de barras de volume por portador
- **WHEN** ele é renderizado
- **THEN** cada barra é identificada por rótulo e tooltip com o nome do portador, além da cor

#### Scenario: tema claro e escuro
- **GIVEN** o console em tema claro e em tema escuro
- **WHEN** os gráficos são renderizados
- **THEN** eles usam as variáveis CSS do tema vigente, sem código condicional por tema
