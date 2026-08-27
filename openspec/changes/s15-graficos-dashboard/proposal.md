# Proposal: S15 — Gráficos nos indicadores (`NEW-001`) e dashboard resumo (`NEW-002`)

> Fatia **S15** da ordem de execução de `.migration-ai9/migration-map.md`, seção
> **"Adições de escopo aprovadas (DEC-21)"**.
> Depende de **S10** (indicadores) e de **S5..S8/S10** (limites, recebíveis, operações de
> risco, estruturadas e séries mensais).

## ⚠️ Esta fatia é FEATURE NOVA, não paridade

**Nada do que está aqui existe no legado.** No `parity-ledger.md`, `NEW-001` e `NEW-002`
entram como **`new`** — nunca como item de paridade.

**O QA do Phase 4 NÃO deve procurar estas telas no legado**, porque elas não estão lá. Sem
este aviso escrito, uma auditoria futura lê "gráfico de indicador" e "dashboard" como itens
migrados que ninguém consegue localizar na origem — e conclui, errado, que houve perda ou
invenção não autorizada.

**A prova de que não há paridade a preservar** foi medida no Phase 2 e é de uma linha:
`Doughnut` é importado e exposto como global em
`../sfg/app/frontend/vendor/js/index.js.erb:31,37` e **nenhuma view o instancia** — grep
recursivo em `app/views/`, `app/frontend/js/`, `*.erb`, `*.js` e `*.scss`: **zero
ocorrências fora do próprio `vendor/`**. Nenhuma tela do Safegold renderiza gráfico algum.

Isso **revoga a premissa do DEC-10** ("usar as libs de gráfico do ai9"), que supunha haver um
gráfico a migrar. Não havia. O DEC-10 continua valendo onde tem alcance real (`vendor/dialog`
→ `ui/dialog.tsx`, formatação monetária → `Intl`/`date-fns`).

Também é **exceção explícita à nota de escopo do `openspec/specs/indicators/spec.md`**, que
diz que "gráfico de indicador NÃO existe no legado e fica fora do escopo" (DEC-09). Continua
verdade que não existe no legado; o que mudou é a **decisão do usuário** (DEC-21) de que
passa a existir no ai9. A nota de escopo não é contrariada por engano — é superada por
decisão posterior, e este parágrafo é o registro disso.

## Why

Duas razões, e nenhuma delas é "ficaria bonito":

1. **A grade mensal de indicadores é o caso de uso natural de um gráfico.** 24 meses × N
   indicadores numa tabela é exatamente o dado que ninguém lê em números. O
   `demo-seed-design.md` §11 já conta com isso no roteiro da demonstração: *"Indicadores — 24
   meses de gráfico com a inflexão do mês 9 e a sazonalidade"*.
2. **A tela inicial do console hoje é um placeholder honesto.**
   `frontend/src/app/pages/DashboardPage.tsx` diz no próprio comentário que perdeu a fonte de
   dados quando o AI9-010 saiu no trim, e que *"o painel do Safegold nasce dos dados do
   legado no Phase 2"*. É a **primeira tela depois do login**: entrar num sistema de crédito
   e ver um card vazio é a pior primeira impressão possível de um produto que, atrás dela,
   está completo.

E o custo é baixo **porque a peça já existe**: `frontend/src/components/charts/`
(`RechartsLine`, `RechartsBar`, `RechartsPie` + `theme.ts` lendo as variáveis CSS de tema) e
`components/kpi/KpiCard.tsx` sobreviveram ao trim e não têm consumidor. Recharts está em
`package.json`. Não se instala nada.

**Por que no fim da fila:** dependem dos serviços de cálculo. Dashboard bonito sobre número
errado é pior que dashboard nenhum — o usuário confia no número, e é justamente o número que
está errado.

## What Changes

### `NEW-001` — Gráficos nos indicadores

Dois gráficos, ambos dentro das telas de indicadores que S10 entrega, **sem nenhuma tela
nova**:

- **Série mensal** (linha): o valor de **um** indicador ao longo dos meses do período
  filtrado, sobre `RechartsLine`. Fonte: as consultas de lançamento por período que **S10** já
  expõe (os dois IDs de grade mensal são de S10 — ver Fronteiras).
- **Volume por portador** (barra): distribuição do volume operado por `Carrier` no período e
  no projeto corrente, sobre `RechartsBar`. Fonte: os agregados que o bloco de risco já
  calcula (`Risk::AggregateService`, de **S5** — ver Fronteiras) — **não** um cálculo novo
  no cliente.

### `NEW-002` — Dashboard resumo na tela inicial

Substitui o placeholder de `DashboardPage.tsx` por quatro números e um gráfico, **todos
escopados ao projeto corrente e ao que o solicitante pode ver**:

| Cartão | Fonte (serviço que já existe) |
| ------ | ----------------------------- |
| **Total operado** no período | Agregados de recebíveis/borderô (S6) |
| **Exposição** atual | `Risk::Calculator` — limite utilizado numa data (serviços de **S5**) |
| **Limites no teto** | O mesmo agregado que pinta o semáforo de limite estourado na tela de risco (**S5**) |
| **Renegociações em atraso** | O contador `overdue_installments` (**S9**), que S13 transformou em **consulta** |

Mais um gráfico de série do total operado nos últimos meses (`RechartsLine`).

## A regra que segura a fatia inteira: nenhum número novo nasce aqui

**Todo valor exibido vem do mesmo serviço que já o calcula para a tela correspondente** —
é o contrato **C2** aplicado a uma superfície nova. Se um agregado ainda não existir, ele é
escrito **no serviço de domínio**, com teste, e o dashboard o consome; **nunca** somado no
frontend nem num SQL solto do endpoint do dashboard.

Sem essa regra, o dashboard vira uma segunda implementação das fórmulas financeiras, e o
sistema passa a ter dois números para a mesma coisa — que é exatamente o **D-09** que o C2
existe para impedir.

## Fronteiras — o que este change **não** cobre

- **Nenhum requirement de paridade.** S10, S5..S8 entregam as telas, os endpoints e os
  cálculos. S15 só **lê**.
- **Nenhuma métrica inventada.** Os quatro cartões do `NEW-002` foram nomeados na DEC-21;
  acrescentar um quinto é decisão do usuário, não do implementador.
- **Nenhuma série histórica calculada** (variação mês a mês, acumulado, média) — a nota de
  escopo de `indicators` continua valendo para isso. O gráfico plota **o que já está
  lançado**.
- **Sem exportação** (PNG/CSV/PDF) e **sem drill-down**. Clicar no cartão navega para a tela
  que já existe.
- **Sem polling** (Princípio 10). Atualização por navegação/refetch do React Query; se algum
  número precisar ser vivo, é Action Cable, nunca `setInterval`.

## Dependências

- **S10** — catálogo, conexões e grade mensal de lançamentos (`NEW-001`).
- **S5, S6, S7, S8** — os serviços de cálculo que alimentam os quatro cartões (`NEW-002`).
- **S0** — `current_project!` e o escopo por projeto (contrato **C1**).
- **Tematização** — os gráficos leem `--primary`, `--accent`, `--muted-foreground` e
  `--border` via `charts/theme.ts`. Com a marca Safegold aplicada, eles ficam certos de
  graça; sem ela, ficam com a paleta do produto errado.

## Capabilities

### New Capabilities

- `dashboard`: o resumo da tela inicial do console — quais números aparecem, de onde vêm,
  como são escopados e o que acontece quando não há dado. Não existe capability equivalente:
  o `dash` do legado **não referencia indicadores** e o dashboard do ai9 saiu no trim.

### Modified Capabilities

- `indicators`: **um** requirement novo (`NEW-001`), marcado como **feature nova**, que
  convive com a nota de escopo do DEC-09 em vez de contradizê-la em silêncio.

## Impact

- **Backend:** um endpoint de resumo (`GET /api/v1/dashboard/summary`, escopado por
  `current_project!`) que **compõe** serviços existentes, e o endpoint de série que S10 já
  expõe. Nenhuma tabela nova, nenhuma migration.
- **Frontend:** `src/app/pages/DashboardPage.tsx` (deixa de ser placeholder),
  `src/features/indicators/` (os dois gráficos), reuso de
  `components/charts/{RechartsLine,RechartsBar}` e `components/kpi/KpiCard`.
- **Não afetado:** nenhum serviço de cálculo é alterado. Se um agregado faltar, ele nasce no
  domínio — e isso é tarefa desta fatia apontando para o dono, não uma segunda fórmula aqui.
- **Paridade:** 2 IDs `new`. **Nenhum** item de paridade é fechado por esta fatia.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

Esta fatia é **feature nova** e **não é dona de nenhum ID de paridade**. Os IDs que ela cita
são serviços que outras fatias constroem, e que o dashboard **consome sem recalcular** — é o
contrato **C2** aplicado a uma superfície nova. O fechamento do Phase 2 encontrou oito deles
com dois donos, porque este proposal os citava fora de uma seção de fronteira:

- **`BE-716` e `BE-324` são de S10** — a grade mensal e as 4 consultas de lançamento por
  período. `NEW-001` lê exatamente estas.
- **`BE-243`, `BE-249`, `BE-251` e `FE-238` são de S5** — `Risk::Calculator`,
  `Risk::AggregateService` e o par de tokens do semáforo de limite estourado. `NEW-002` lê
  estes serviços; nenhum agregado novo nasce no cliente.
- **`BE-207` é de S9** — o contador de parcelas vencidas da renegociação.
- **`OPS-473` é de S13** — a transformação da varredura diária em consulta.

**Se um agregado ainda não existir**, ele é escrito **no serviço de domínio da fatia dona**,
com teste, e o dashboard o consome. Nunca somado aqui.
