# Design: S15 — gráficos e dashboard sobre peças que já existem

> Feature **nova** (DEC-21), não paridade. Contexto do achado que a origina:
> `.migration-ai9/migration-map.md`, "Achados do mapeamento que mudam o escopo", item 1, e
> `.migration-ai9/map/risk-indicators.md` §0.3. Dado da demonstração:
> `.migration-ai9/demo-seed-design.md` §8 e §11.

## Context

Três medições definem o desenho:

1. **Não há gráfico a migrar.** `Doughnut` é global em `index.js.erb:31,37` e nenhuma view o
   instancia. Logo, não existe comportamento de origem a replicar — o desenho é livre, e a
   única disciplina que sobra é **não inventar número**.
2. **A peça de gráfico já está na base e não tem consumidor.**
   `frontend/src/components/charts/RechartsLine.tsx` e `RechartsBar.tsx` recebem
   `{ labels: string[], values: number[] }`; `RechartsPie.tsx` recebe
   `{ items: {label, value}[] }`; `charts/theme.ts` lê `--primary`, `--accent`,
   `--muted-foreground` e `--border` do tema em runtime, com fallback para SSR. `KpiCard`
   (`components/kpi/KpiCard.tsx`) aceita `title`, `value`, `change`, `changeType`, `icon`,
   `footer` e faz count-up. **Recharts já está no `package.json`.**
3. **A tela inicial é um placeholder que documenta a própria dívida.**
   `DashboardPage.tsx` explica no comentário que consumia
   `GET /api/v1/analytics/dashboard` (AI9-010, removido no Bloco 2 do trim) e que o painel do
   Safegold nasceria depois. É esta fatia.

## Goals / Non-Goals

**Goals**
- Tornar legível o dado que já existe: 24 meses de série e quatro números de saúde da
  carteira.
- Reusar `charts/` e `KpiCard` **sem alterá-los** — eles servem os outros sistemas da base.
- Que **todo número exibido tenha exatamente uma origem**, a mesma da tela de detalhe.

**Non-Goals**
- Não construir camada de analytics, nem tabela de métricas, nem cache de agregado.
- Não calcular série derivada (variação, acumulado, média) — a nota de escopo de `indicators`
  continua valendo para isso.
- Não introduzir biblioteca de gráfico nova, nem alterar `charts/theme.ts` (Princípio 6b).
- Não fazer polling.

## Decisions

### G1. O número vem do serviço de domínio. Sempre

Contrato **C2** aplicado a uma superfície de leitura: a prévia da tela e a gravação chamam o
mesmo serviço, e agora **o dashboard também**. O endpoint de resumo é um **compositor**:
chama `Risk::Calculator`, o agregador de recebíveis e o contador de renegociação, e monta um
payload. Ele **não tem SQL próprio de agregação financeira**.

Se um agregado necessário não existir, a tarefa correspondente **o cria no serviço de
domínio, com teste golden**, e o dashboard passa a consumi-lo. O que não pode acontecer é
`SUM(valor_bruto)` aparecendo dentro do endpoint do dashboard: nesse momento o sistema passa
a ter dois números para a mesma coisa, que é o **D-09**.

### G2. Escopo por projeto no endpoint, e escopo por permissão no payload

Contrato **C1**: `current_project!` no endpoint, **nunca** `default_scope`. E a lição do
**D-110** (a trilha do legado listava o sistema inteiro para qualquer sessão autenticada)
vale igual aqui: um dashboard é, por definição, um agregado — **um agregado sem escopo é um
vazamento silencioso**, porque o número vaza sem mostrar a linha.

Regras:
- Projeto inexistente e projeto sem membership respondem **o mesmo status** (distinguir 403
  de 404 vira oráculo de existência de id).
- `user_is_readonly` **vê** o dashboard; ele é leitura pura.
- Cada cartão respeita a matriz DEC-18 da sua capability: quem não pode ver renegociação não
  recebe o cartão de renegociações — **o cartão some, não vem zerado**. Zero e "não
  autorizado" são estados diferentes, e num sistema financeiro confundi-los é grave (é o
  mesmo raciocínio do **D-117**/FE-431: nulo e zero não podem ser a mesma coisa na tela).

### G3. `NEW-001` mora nas telas de indicadores, não numa tela nova

- **Série mensal** (`RechartsLine`): eixo X = meses do período filtrado; eixo Y = valor do
  indicador selecionado. Alimentado por BE-716/BE-324, **os mesmos** dados da grade — o
  gráfico é uma segunda representação da tabela que está na mesma tela, e trocar de mês na
  grade muda o gráfico.
- **Volume por portador** (`RechartsBar`): agregado por `Carrier` no período e no projeto
  corrente, vindo de BE-249/BE-251.

Ambos herdam o filtro de período da tela; **não** ganham filtro próprio. Um gráfico com
filtro próprio ao lado de uma tabela com outro filtro produz duas verdades na mesma tela.

### G4. `NEW-002` é uma composição de quatro leituras e um gráfico

`GET /api/v1/dashboard/summary?date=…` devolve os quatro números, cada um com **valor,
rótulo e o destino de navegação**. O frontend não decide para onde o cartão leva — isso
mantém dashboard e menu coerentes quando uma rota muda.

Estados que precisam existir desde o primeiro commit, porque são os que aparecem numa demo
antes de o seed rodar:
- **Sem dado** → "sem lançamentos no período", **não** `R$ 0,00` (D-117).
- **Erro** → estado de erro com opção de tentar de novo. A tela de risco do legado **não
  tinha estado de erro** (FE-239) e é justamente o defeito que não se repete.
- **Carregando** → esqueleto, sem deslocamento de layout quando o número chega.

### G5. Nenhum polling, e realtime só se houver motivo

Princípio 10. A atualização normal é o refetch do React Query ao navegar/focar. Se algum
número precisar ser vivo numa demo, o caminho é **Action Cable** (a infra já está montada, e
`useCable`/`useChannel` existem) — nunca `setInterval`. O legado, aliás, quase não fazia
polling: **uma** instanciação de `PollingManager`, já desligada.

### G6. Tema: os gráficos já são theme-aware, e é isso que os torna baratos

`charts/theme.ts` lê as variáveis CSS em runtime, então o mesmo componente serve light e dark
sem código condicional. A consequência prática é de ordem: **a tematização Safegold roda
antes** (é transversal e sai cedo, por decisão do `migration-map`), e os gráficos nascem com
a cor certa. Se rodar depois, eles aparecem com a paleta do produto anterior numa demo
comercial.

Uma restrição de acessibilidade que vale a pena escrever: **cor não pode ser o único
portador de informação** no gráfico de barras por portador — rótulo e tooltip carregam o
nome. É o mesmo motivo pelo qual FE-435 troca a cor aleatória do legado por cor derivada da
identidade da entidade, estável entre renderizações.

### G7. O filtro de datas: **um ponto no tempo e um intervalo, nunca duas datas** (bloco 7)

O painel mistura duas naturezas de tempo na mesma tela, e um filtro que ignore a
diferença produz número errado ou rótulo mentiroso:

| Bloco | Natureza | Selo |
| ----- | -------- | ---- |
| Exposição · Limites no teto · Renegociações em atraso · Consumo de limite · Prestes a estourar · Exposição por portador | **ponto no tempo** | "em 26/08/2026" |
| Total operado · Total operado por mês | **período** | "09/2025 a 08/2026" |

**A decisão: há exatamente UM ponto no tempo na página.** O controle de data
(`?date=`) define a posição; o período **não é uma segunda data**, é uma
**janela** (`?months=`) ancorada nessa mesma posição — "os N meses que terminam
no mês de `date`". É o que o `Dashboard::SummaryService` já faz
(`window_for(date, months)`), então o contrato não muda: muda quem escolhe.

Por que isso importa e não é detalhe de interface: **dois seletores de data na
mesma tela deixam o usuário comparar números apurados em dias diferentes sem
perceber.** Com uma posição e uma janela isso é impossível por construção — mexer
na janela não move a data de apuração de nenhum cartão, e mexer na data move
tudo junto. Os selos continuam dizendo a verdade sobre o que cada número mede,
que é a regra que o bloco 7 não permite quebrar.

O filtro é **de página** (o G3 já proíbe filtro dentro do gráfico), vive na
**URL** (para o link do painel filtrado ser compartilhável e o botão voltar
funcionar) e a troca **invalida a consulta** — não liga temporizador
(Princípio 10).

## Risks / Trade-offs

| Risco | Mitigação |
| ----- | --------- |
| **O dashboard virar uma segunda implementação das fórmulas** — dois números para a mesma coisa (D-09) | G1: o endpoint compõe serviços, não agrega. Nenhum `SUM` financeiro dentro dele. Revisão explícita na tarefa de teste |
| **Agregado sem escopo vazando dado entre projetos** (a lição do D-110) | G2: `current_project!` no endpoint + teste que prova que dois projetos devolvem números diferentes para o mesmo usuário |
| **Cartão zerado por falta de permissão** parecendo "não há operações" | O cartão **some**; zero e não-autorizado nunca se confundem |
| **QA do Phase 4 procurando estas telas no legado** | Escrito no `proposal.md`, no ledger como `new`, e repetido aqui |
| **Gráfico bonito sobre número errado** | A fatia é a **última** de propósito; os testes golden de C2 já travaram as fórmulas antes |
| **Alterar `charts/` ou `KpiCard` para caber** — eles servem outros sistemas da base | Reuso sem modificação. Se um componente não couber, o wrapper novo vive em `features/`, e a limitação vira linha em `upstream-flags.md` |
