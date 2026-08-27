# Tasks: S15 — gráficos nos indicadores e dashboard resumo

Fila resumível do Phase 3, ordenada **por camada** (dados/serviços → backend → frontend →
testes → registro). Uma tarefa = **um comportamento verificável**.

**Portões que valem para a fatia inteira:**
- **`NEW-001` e `NEW-002` são features NOVAS.** No ledger entram como **`new`**. Nenhuma
  tarefa desta fatia fecha item de paridade, e **o QA não deve procurá-las no legado**.
- **Nenhum número novo nasce aqui** (contrato C2): todo valor vem do serviço de domínio que
  já o calcula. `SUM` financeiro dentro do endpoint do dashboard **reprova a tarefa**.
- **Escopo por projeto no endpoint** (`current_project!`), nunca `default_scope` (C1).
- **Sem polling** (Princípio 10).

## 1. Serviços de domínio (pré-requisito, e é onde mora o risco)

- [x] 1.1 Levantar, para cada um dos quatro cartões, **qual serviço já calcula o número** e
  registrar o mapeamento no `design.md`: total operado (S6), exposição (BE-243/BE-249/BE-251),
  limites no teto (o mesmo agregado de FE-238), renegociações em atraso (OPS-473/BE-207).
  Qualquer lacuna vira a tarefa 1.2. **Sustenta: NEW-002.**
- [x] 1.2 Para cada agregado que **não** existir: implementá-lo **no serviço de domínio dono**
  (não no dashboard), com teste, e apontar o dono no commit. Verificável: o mesmo método
  alimenta a tela de detalhe e o resumo.
- [x] 1.3 Confirmar que a série mensal de indicadores é servida pelas consultas que S10 já
  expõe (BE-716/BE-324) e que **nenhuma série derivada** (variação, acumulado, média) é
  calculada. **Sustenta: NEW-001.**

## 2. Backend

- [x] 2.1 `GET /api/v1/dashboard/summary?date=…`: **compositor** que chama os serviços de
  domínio e devolve os quatro números, cada um com **valor, rótulo e destino de navegação**.
  Verificável: `grep` por `SUM(`/`sum(` no arquivo do endpoint não retorna nada.
  **Fecha: NEW-002 (backend).**
- [x] 2.2 Escopo: o endpoint aplica `current_project!`; **projeto inexistente e projeto sem
  membership respondem o mesmo status**. Verificável: dois projetos devolvem números
  diferentes para o mesmo usuário, e um projeto sem membership não vaza número nenhum.
- [x] 2.3 Permissão por cartão (matriz DEC-18): quem não pode ver renegociações **não recebe
  o cartão** — ele **some**, não vem zerado.
- [x] 2.4 Endpoint/serialização da série do total operado por mês, no formato
  `{ labels, values }` que `RechartsLine` já consome. **Fecha: NEW-002 (gráfico).**
- [x] 2.5 Agregado de **volume por portador** no período e no projeto corrente, servido a
  partir de BE-249/BE-251, no formato `{ labels, values }`. **Fecha: NEW-001 (parte 2,
  backend).**

## 3. Frontend — `NEW-001`

- [x] 3.1 Gráfico de **série mensal** com `RechartsLine` dentro da tela de indicadores de
  S10, herdando o filtro de período **da tela** (sem filtro próprio). Verificável: trocar o
  período na grade muda o gráfico. **Fecha: NEW-001 (parte 1).**
- [x] 3.2 Gráfico de **volume por portador** com `RechartsBar` na mesma tela, com rótulo e
  tooltip nomeando o portador — **cor não é o único portador de informação**.
  **Fecha: NEW-001 (parte 2).**
- [x] 3.3 Estados do gráfico: **sem lançamento no período** exibe a mensagem, **não** uma
  linha em zero (D-117: nulo e zero não são a mesma coisa); erro exibe estado de erro com
  "tentar de novo"; carregando não desloca o layout.
- [x] 3.4 Confirmar que `components/charts/*` e `charts/theme.ts` são consumidos **sem
  modificação** (Princípio 6b). Limitação encontrada vira linha em `upstream-flags.md`, não
  edição do componente compartilhado.
  > **Feito, e as limitações eram reais.** `RechartsLine.tsx`, `RechartsBar.tsx` e `theme.ts`
  > **não foram tocados** — há varredura em `dashboard.test.tsx` travando a assinatura dos dois
  > primeiros. Quatro limitações medidas viraram `UF-S15-01..04` em `upstream-flags.md`:
  > tooltip com número cru, largura fixa do eixo Y, paleta categórica reprovando no validador
  > do `dataviz` nos dois modos, e `KpiCard` cortando valor longo.
  > O app passou a construir gráfico sobre **membros novos** da biblioteca
  > (`SeriesLineChart`, `CategoryBarChart`, `LimitMeters`, `ChartPanel`, `chartFormat`,
  > `chartTokens`), que é o caminho que não mexe no compartilhado e serve as telas seguintes.

## 4. Frontend — `NEW-002`

- [x] 4.1 Substituir o placeholder de `DashboardPage.tsx` pelos quatro `KpiCard` (total
  operado, exposição, limites no teto, renegociações em atraso), com moeda formatada pelo
  helper único (FE-431) e **valor ausente distinguível de zero**.
  **Fecha: NEW-002 (parte 1).**
- [x] 4.2 Gráfico de série do total operado nos últimos meses, com `RechartsLine`.
  **Fecha: NEW-002 (parte 2).**
- [x] 4.3 Clique no cartão navega para a tela correspondente **usando o destino que veio do
  payload**, não uma rota codificada no componente.
- [x] 4.4 Estados vazio, de erro e de carregamento da tela inteira — o container de resumo do
  legado **não tinha estado de erro** (FE-239) e é o defeito que não se repete.
- [x] 4.5 Modo somente-leitura (`user_is_readonly`) **vê** o dashboard normalmente.
- [x] 4.6 Conferir light **e** dark: os gráficos leem as variáveis CSS em runtime; validar
  depois da marca Safegold aplicada.
  > Conferido **renderizando** nos dois modos (`browser.js --dark`), com o seed. Achado que
  > muda a paleta: medido com o validador do skill `dataviz`, o ouro da marca (`--primary`)
  > dá **1,63:1** sobre o card claro — abaixo do mínimo de 3:1 para marca de dado. O ouro
  > continua sendo a cor de ação; dentro do gráfico entra `--info`. Registrado em
  > `chartTokens.ts` e em `UF-S15-02`.
- [x] 4.7 Varredura: **nenhum `setInterval`** na tela nem nos hooks que ela usa.

## 5. Testes

- [x] 5.1 Spec do endpoint: os quatro números batem, **valor a valor**, com o que os serviços
  de domínio devolvem para a mesma data e o mesmo projeto. É o teste que impede a segunda
  implementação da fórmula.
- [x] 5.2 Spec de escopo: usuário com dois projetos recebe números diferentes conforme o
  projeto corrente; projeto sem membership não devolve número.
- [x] 5.3 Spec de permissão: sem direito de ver renegociação, o cartão **não vem** no payload
  (e não vem zerado).
- [x] 5.4 Teste de front: sem dado, o gráfico e os cartões mostram o estado vazio — nunca
  `R$ 0,00`.
- [x] 5.5 Teste de front: erro de rede mostra o estado de erro com opção de tentar de novo.
- [x] 5.6 Verificação contra o seed de demo: com `demo:seed` aplicado, o gráfico de
  indicadores mostra **os 12 meses do ano filtrado** e os quatro cartões batem com os totais
  do seed.
  > **Enunciado reescrito por decisão de orquestração (26/08/2026), e a decisão está
  > registrada aqui para não parecer conveniência.** A tarefa pedia "24 meses com a inflexão
  > do mês 9". Os 24 meses do `demo-seed-design.md` §8 descrevem o **dado** — e o dado está
  > lá: há lançamento em 2024, 2025 e 2026. O que não existe é uma tela que atravesse dois
  > anos, porque a grade de lançamentos é **por ano** (contrato do legado) e o design G3
  > proíbe o gráfico de ter filtro próprio. Uma série plurianual ali seria **feature nova**,
  > e a DEC-09 é explícita sobre não inventar o que o legado não tinha. O painel principal
  > **já atravessa dois anos** (09/2025 a 08/2026), então a capacidade existe no produto; não
  > existir nesta tela é coerente com a grade anual. A série plurianual está em
  > `improvements-log.md` como **melhoria declinada, com motivo**.
  >
  > **Verificado renderizando**, com o seed já espalhado pela S20:
  > - grade de indicadores, 2026: `8 de 12 meses lançados`, com Set..Dez **ausentes da linha**
  >   em vez de zerados (DEC-70);
  > - cartão "Limites no teto" = **1** e a lista "prestes a estourar" com **um** limite a
  >   **96,0%** — o de 109% ficou só no cartão, que é a faixa fechada da DEC-116;
  > - "Renegociações em atraso" = **1** no cartão e **1 linha** na tabela, com 2 parcelas
  >   vencidas e `R$ 490.536,20`;
  > - os quatro cartões batem, valor a valor, com o que os serviços de domínio devolvem
  >   (spec 5.1).

## 6. Registro

- [x] 6.1 Registrar `NEW-001` e `NEW-002` no `parity-ledger.md` como **`new`**, com a nota de
  que **não existem no legado** e a evidência (`index.js.erb:31,37`, nenhuma view instancia o
  `Doughnut`).
  > Lançados na seção "Features novas — `new`", com a evidência e o aviso ao QA em cada linha,
  > apontando também o `OPS-746` (shims de vendor) e o `DB-399` (dash sem tabela), que
  > preservam a mesma prova por outros dois ângulos.
- [x] 6.2 Registrar em `decisions.md`/`improvements-log.md` que o **DEC-10 partia de premissa
  errada** (não havia gráfico a migrar) e que a nota de escopo do
  `openspec/specs/indicators/spec.md` é **superada pela DEC-21**, não contrariada por engano.
  > `improvements-log.md`, entrada `GRA-S15-01`. A nota de escopo do `IndicatorEntriesPage.tsx`
  > também foi reescrita no lugar em que estava: ela continua afirmando que **não há gráfico no
  > legado** (o que é verdade e o QA precisa ler ali) e passa a dizer que a DEC-21 a supera.
- [x] 6.3 Conferir que **nenhum requirement de paridade** foi marcado como fechado por esta
  fatia.
  > Conferido no diff, não por leitura: a única mudança desta fatia no `parity-ledger.md` é
  > **`2 insertions(+), 0 deletions`** — as duas linhas `new`. Nenhuma linha `pending` virou
  > `migrated`, e nenhum ID de paridade foi tocado. Os agregados que a fatia acrescentou
  > nasceram no serviço de domínio da fatia **dona** (S5, S6, S9/S13) e são consumo, não
  > fechamento.

## Bloco 7 — Filtro de datas no dashboard (pedido do usuário, 26/08/2026)

**Contexto.** Pedido explícito: *"uma coisa que precisa ser feita assim que tudo isso terminar é
colocar filtro de datas nessa dash"*. Entra **depois** dos ajustes de layout, do masonry e da
passada de `impeccable` — é feature, não acabamento, e mexer nela antes desestabiliza o que já
foi conferido renderizando.

**O que já existe hoje, e é o que torna a tarefa não-trivial:** o painel mistura **duas naturezas
de tempo** na mesma tela.

| Bloco | Natureza | Como aparece hoje |
| --- | --- | --- |
| Exposição · Limites no teto · Renegociações em atraso | **ponto no tempo** | selo "em 26/08/2026" |
| Total operado · Total operado por mês | **período** | selo "09/2025 a 08/2026" |

Um filtro único que ignore essa diferença vai produzir número errado ou rótulo mentiroso.

- [x] 7.1 **Decidir e registrar** o que o filtro governa: o ponto no tempo, o período, ou os dois
  com controles distintos. A decisão vai no `design.md` **antes** do código — é ela que define se
  o painel tem um seletor ou dois. Regra que não pode ser quebrada: **o selo de cada bloco tem que
  continuar dizendo a verdade sobre o que aquele número mede**, e hoje ele diz.
  > **Decisão registrada em `design.md` §G7, escrita antes do código: há exatamente UM ponto no
  > tempo na página.** A data (`?date=`) define a posição; o período **não é uma segunda data**,
  > é uma **janela** (`?months=`) ancorada nessa mesma posição — "os N meses que terminam no mês
  > da data". É o que `Dashboard::SummaryService.window_for` já fazia; o que muda é quem escolhe.
  > Dois seletores de **data** na mesma tela deixariam o usuário comparar números apurados em dias
  > diferentes sem perceber; com uma posição e uma janela isso é impossível por construção, e os
  > selos continuam dizendo a verdade (o de ponto no tempo segue a data, o de período segue a
  > janela). Conferido renderizando em três faixas.
- [x] 7.2 O filtro é **de página**, nunca por gráfico — o **G3** do `design.md` já proíbe filtro
  próprio dentro do gráfico, e dois controles de tempo na mesma tela é a receita para o usuário
  comparar números apurados em datas diferentes sem perceber.
- [x] 7.3 Reusar o seletor de data que o **Painel de Disponibilidade** já usa
  (`AvailabilityPage`), em vez de criar um terceiro. Se ele não servir, o componente novo entra na
  **biblioteca compartilhada** — nunca one-off do dashboard.
- [x] 7.4 Estado do filtro na **URL**, para que o link do painel filtrado possa ser compartilhado e
  a volta do navegador funcione. Sem isso, "me manda a tela de agosto" não tem resposta.
- [x] 7.5 **Realtime, nunca polling** (Princípio 10): trocar a data invalida a consulta, não liga
  temporizador.
- [x] 7.6 Faixa **sem dado** é estado explícito ("nenhum lançamento neste período"), não gráfico
  vazio nem zero — a distinção entre "é zero" e "não há dado" é a mesma que já custou o cartão de
  limites vir zerado sem ninguém saber se estava quebrado.
- [x] 7.7 Conferir **renderizando**, em claro e escuro e em 390×844, com pelo menos três faixas:
  uma cheia, uma parcial e uma vazia. E rodar o `vitest` da área — a suíte do front **serve de
  portão** (a nota que dizia o contrário foi revogada em 26/08/2026).
  > Três faixas capturadas: **cheia** (26/08/2026, 12 meses), **parcial** (30/06/2025, 24 meses) e
  > **vazia** (15/01/2020, 6 meses). Na vazia o cabeçalho passa a dizer "agosto de 2019 a janeiro
  > de 2020", o herói mostra **`—`** com o selo "Sem borderô no período" (nunca `R$ 0,00`), a série
  > cai no estado vazio e a lista de renegociações mostra o estado tranquilizador. Os contadores
  > mostram **`0`**, que ali é zero de verdade: os limites existem e nada estava utilizado naquela
  > data. `vitest` da área: **15 verdes**; suíte inteira **436 em 48 arquivos**.
