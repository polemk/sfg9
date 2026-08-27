# Brazilian Software — Landing horizontal com NavKit

> **Branch:** `brazilian-software` (criada de `8a943821`, HEAD ainda na main)
> **Status:** Aguardando aval de Vossa Excelência Ministro da Tecnologia pra começar execução. Main está ocupada por outro agente (plano `atomic-dancing-kazoo.md`). Execução só começa depois que ele terminar.
> **Modo do orquestrador:** Planning / Foco Frontend
> **Idioma:** pt-br (código, comentários, logs, commits)

---

## Contexto

Vossa Excelência lançou a marca **Brazilian Software** (meet de 02/03/2026) com posicionamento enterprise, banco-friendly e LGPD-first — "software feito no Brasil, pra empresa que paga em real". A marca convive com Fábrica Polêmica mas tem identidade própria: cores da bandeira brasileira, logo `BR/SW` stacked, mascote capivara, tipografia humanista.

A landing **não** vai usar o layout vertical `campfire/*` atual. Vai usar o **NavKit** — sistema de navegação 2D em grid `(x,y)` já existente em `frontend/src/NavKit/` e demonstrado em `frontend/src/app/pages/NavKitHome.tsx`. Referência conceitual: homepage do **GOAT.com** (hero + drops + categorias) adaptada pra vender SaaS, e o "joy" interno da Polemk.

### Assets confirmados em `frontend/public/brsw/`

- `brsw_icon_black.svg` / `brsw_icon_white.svg` — só o quadrado BR/SW
- `brsw_horizontal_black.svg` / `brsw_horizontal_white.svg` — wordmark horizontal
- `brsw_vertical_black.svg` / `brsw_vertical_white.svg` — wordmark vertical
- `brsw_alt_black.svg` / `brsw_alt_white.svg` — variante alternativa (capivara?)

> ⚠️ Arquivo `brsw_icon_black (1).svg` tem espaço e sufixo `(1)` no nome — deve ser renomeado pra `brsw_icon_black.svg` antes de qualquer import.

### Paleta Brasil

| Token | Hex | Uso |
|:---|:---|:---|
| `--brsw-navy` | `#002776` | Background primário, texto headline |
| `--brsw-yellow` | `#FEDF00` | CTA principal, hover, destaque |
| `--brsw-green` | `#009C3B` | Badges, success states, accent |
| `--brsw-cyan` | `#1CABE2` | Links, info, secondary accent |
| `--brsw-white` | `#FFFFFF` | Texto sobre navy |
| `--brsw-ink` | `#0A0A0A` | Texto sobre claro |

### Grid NavKit — 6 telas aprovadas

| Pos | Path | Tela | Conteúdo |
|:---|:---|:---|:---|
| (0,0) | `/brsw` | **Hero** | Wordmark + tagline + CTA "entrar" com captura de e-mail |
| (1,0) | `/brsw/produtos` | **Produtos** | 3 cards: `site.com.ia`, `api.royale`, `claudify` |
| (2,0) | `/brsw/manifesto` | **Manifesto** | "Regra e fundamento, zero papagaio" — scroll interno |
| (3,0) | `/brsw/cases` | **Cases** | Grid tipo GOAT drops, thumbnails de projetos (stubs) |
| (4,0) | `/brsw/contrato` | **Contrato** | CTA final → jogar o cara pro dashboard ai9 |
| (0,1) | `/brsw/sobre` | **Sobre** | 10 stubs de membros + CNPJ + LGPD + footer |

---

## Plano de Implementação (template obrigatório do GEMINI.md)

| Etapa | Ação Técnica | Skill (Caminho em .agent/skills/) | Justificativa (Stack Focus) |
| :--- | :--- | :--- | :--- |
| **0** | **Checkout da branch** via worktree separado (`git worktree add ../ai9-brsw brazilian-software`) pra isolar do outro agente que segue na main. | `skill-orchestrator`, `using-git-worktrees` | Protege a WIP do colega na main e permite dev paralelo sem `git switch`. |
| **1** | **Design brief no template Stitch** — escrever prompt formal (`[Screen] for [User] / Key Features / Visual Style / Platform`) pra cada uma das 6 telas. Salvar em `frontend/src/app/pages/BrazilianSoftware/DESIGN_BRIEF.md` pra Vossa Excelência poder levar pro Stitch externo e refinar visualmente. | `stitch-ui-design` | `stitch-ui-design/SKILL.md` define o template exato e proíbe prompts vagos. Serve como espec visual viva da implementação. |
| **2** | **Design tokens Brasil** — criar `frontend/src/app/pages/BrazilianSoftware/brsw-theme.css` com as 6 CSS vars da paleta + escala tipográfica + tokens de sombra + raio. Scope via `[data-brsw="true"]` pra não vazar pro resto do app. | `tailwind-design-system`, `frontend-design` | Isolamento de tema: `campfire` usa paleta própria, `brsw` é navy/amarelo/verde/cyan. Sem conflito. |
| **3** | **Componente `<BrswLogo variant="icon\|horizontal\|vertical\|alt" tone="black\|white" />`** que consome os SVGs de `public/brsw/`. Renomear `brsw_icon_black (1).svg` → `brsw_icon_black.svg`. | `react-components`, `frontend-dev-guidelines` | Logo único centralizado evita hard-coded de path espalhado. Renomear é crítico porque path com espaço quebra SSR e analytics. |
| **4** | **Rota `/brsw` e filhas no React Router** — editar `frontend/src/app/App.tsx` adicionando bloco `<Route path="/brsw/*" element={<BrazilianSoftwarePage />} />`. **Ponto de conflito previsto com o outro agente** — ele toca `/admin/logger`, mas os dois blocos convivem. | `frontend-dev-guidelines`, `nextjs-react-expert` | Basta UM entry-point no React Router; o NavKit cuida da sincronia de URL internamente (deep-linking via `path` no `NavKitScreen`). |
| **5** | **`BrazilianSoftwarePage.tsx`** — envolve tudo em `NavKitProvider` + adiciona atributo `data-brsw="true"` no root pra escopar CSS vars. Esqueleto das 6 `NavKitScreen` com `x/y/path` corretos conforme grid acima. | `navkit` (rule), `react-components` | `navkit.md` exige `path` em cada tela pra URL sync e permite `hideBotBar`/`hideArrows`/`disableScroll` onde fizer sentido. |
| **6** | **Tela `BrswHero` (0,0)** — wordmark (`BrswLogo variant="vertical"`), tagline "software feito no Brasil, pra empresa que paga em real", CTA captura de e-mail com fallback pro `leadsApi` existente. Seta sequencial animada à direita (padrão do `NavKitHome.tsx` linha 66-78) chamando `move('RIGHT')`. | `stitch-ui-design`, `frontend-design` | Espelha o padrão visual já validado de `NavKitHome.tsx` — reuso de animação `arrow-seq`. |
| **7** | **Tela `BrswProdutos` (1,0)** — 3 cards horizontais com borda dashed (padrão `NavKitHome`): `site.com.ia`, `api.royale`, `claudify`. Cada card tem ícone lucide, 1 linha de copy, preço de exemplo, CTA "conversar". | `react-components`, `shadcn-ui` | Padrão card repetível, evita criar design novo — reusa dashed-border do NavKitHome. |
| **8** | **Tela `BrswManifesto` (2,0)** — texto longo em 3-4 colunas com scroll interno. **DEVE ter `data-navkit-scrollable="true"`** no container scroll pra SmartArrow detectar. Conteúdo extraído do meet (regra e fundamento, zero papagaio, banco-friendly). | `navkit` (rule) | Instrução específica da `navkit.md` linha 109: sem esse atributo, as setas não reconhecem scroll e o user trava. |
| **9** | **Tela `BrswCases` (3,0)** — grid 3×2 tipo "drops" do GOAT. 6 stubs com placeholder (cor sólida + nome do projeto). Hover eleva o card. Preparado pra receber thumbnails reais depois. | `frontend-design`, `web-design-guidelines` | Mock-ready: a estrutura é a mesma, só o `src` da imagem muda depois. Zero refator quando chegar material real. |
| **10** | **Tela `BrswContrato` (4,0)** — CTA final full-bleed navy com amarelo, botão "entrar no dashboard" que redireciona pra `/login?from=brsw`. Mini-FAQ de 3 perguntas (CNPJ? LGPD? Prazo?). | `frontend-design`, `form-cro` | Converge em 1 ação: jogar o cara pra dentro do app (estratégia do meet minuto 03:29). |
| **11** | **Tela `BrswSobre` (0,1)** — stubs de 10 membros (nome, cargo, foto placeholder). Vossa Excelência como "Ministro da Tecnologia / Sócio Administrador". CNPJ stub, selo LGPD, footer com links. | `react-components` | Posição vertical `(0,1)` — user desce da hero ao invés de ir pra direita. Mantém navegação intuitiva. |
| **12** | **Tipagem + lint + build** — `npx tsc --noEmit`, `npm run lint`, `npm run build` na pasta `frontend/`. Zero erros. | `typescript-pro`, `lint-and-validate` | Regra de higiene do GEMINI.md — não entrega quebrando build. |
| **13** | **Testes Vitest** — smoke test pra `BrazilianSoftwarePage` (renderiza sem crashar) + teste pra cada tela (`BrswHero`, `BrswProdutos`, etc). Pular Rails porque a feature **não toca backend**. | `vitest`, `react-best-practices` | Sem Rails ⇒ sem spec ruby. Mas Vitest protege contra regressão de componente. |
| **14** | **Checklist final** — rodar `python .agent/scripts/checklist.py .` conforme instrução do `skill-orchestrator` (seção "Regra de Higiene"). | `skill-orchestrator`, `verification-before-completion` | Fecha o ciclo de higiene obrigatória do orquestrador. |
| **15** | **Commit + push da branch `brazilian-software`** (sem merge na main ainda). Mensagem em pt-br explicando o porquê. Aguardar Vossa Excelência autorizar o merge pra resolver os conflitos com a WIP do niche/logger. | `commit`, `git-pushing` | Merge fica pro momento certo — quando o outro agente terminar na main. |

---

## Arquivos a criar/editar

### Novos (dentro da branch `brazilian-software`, fora da main)

```
frontend/src/app/pages/BrazilianSoftware/
├── BrazilianSoftwarePage.tsx       # wrapper com NavKitProvider + data-brsw
├── brsw-theme.css                  # design tokens Brasil scoped
├── DESIGN_BRIEF.md                 # prompts Stitch formatados (etapa 1)
├── components/
│   ├── BrswLogo.tsx                # componente logo multi-variante
│   └── BrswCard.tsx                # card dashed-border reutilizável
└── screens/
    ├── BrswHero.tsx                # (0,0)
    ├── BrswProdutos.tsx            # (1,0)
    ├── BrswManifesto.tsx           # (2,0) com data-navkit-scrollable
    ├── BrswCases.tsx               # (3,0)
    ├── BrswContrato.tsx            # (4,0)
    └── BrswSobre.tsx               # (0,1)
```

### Editados (ponto de conflito previsto)

- `frontend/src/app/App.tsx` — +1 `<Route path="/brsw/*" ...>`. Convive com o `/admin/logger` do outro agente.

### Renomeados

- `frontend/public/brsw/brsw_icon_black (1).svg` → `frontend/public/brsw/brsw_icon_black.svg`

---

## Decisões arquiteturais declaradas

1. **Não mexer em `campfire/*`** — é o tema atual da Fábrica Polêmica, continua vivo em paralelo. Brazilian Software é namespace **isolado** em `BrazilianSoftware/`.
2. **CSS vars escopados via `[data-brsw="true"]`** — não usar `:root` pra não vazar paleta brasileira pro resto do app.
3. **NavKit, não campfire** — a navegação horizontal é o coração da proposta. Campfire é vertical, não serve aqui.
4. **Deep-linking obrigatório** — cada `NavKitScreen` tem `path` próprio, então `/brsw/cases` é URL compartilhável, indexável e SEO-friendly.
5. **Stubs do time (10 pessoas)** — Vossa Excelência envia material depois. Contrato de interface do componente `<BrswTimeMember>` fica pronto pra receber props reais sem refator.
6. **Sem backend novo** — feature é 100% estática + reuso do `leadsApi` existente pra captura de e-mail. Zero migration, zero spec Rails.
7. **Renomear `brsw_icon_black (1).svg`** — path com espaço é landmine. Fazer antes de qualquer import.
8. **Worktree em vez de checkout** — evita tocar no working tree da main enquanto o colega opera.

---

## Critérios de aceite

1. Branch `brazilian-software` existe, aponta pra `8a943821`, não contém a WIP de niche/logger da main.
2. `/brsw` carrega a tela Hero; navegar pelas setas/URL atinge Produtos → Manifesto → Cases → Contrato, e Sobre desce.
3. Todas as 6 telas têm `path` NavKit próprio e deep-link funciona (reload em `/brsw/cases` carrega direto).
4. Design tokens brasileiros estão scopados — outras páginas do ai9 não são afetadas visualmente.
5. Logo renderizado via `<BrswLogo>` em todas as 4 variantes (icon/horizontal/vertical/alt) e 2 tons (black/white).
6. Tela Manifesto tem scroll interno funcional e as setas do NavKit reconhecem (via `data-navkit-scrollable`).
7. 10 stubs de equipe renderizam na tela Sobre.
8. `npx tsc --noEmit` e `npm run build` passam. `npx vitest run` passa.
9. Branch comitada e pushada — **sem merge na main**, aguardando sinal verde.
10. `DESIGN_BRIEF.md` existe e serve como documentação viva pra Vossa Excelência refinar no Stitch externo.

---

## O que NÃO vou fazer (escopo bloqueado)

- ❌ Backend Rails — nenhuma migration, controller, service ou spec ruby
- ❌ Mexer em `frontend/src/components/campfire/*`
- ❌ Mexer em `frontend/src/app/pages/admin/*`
- ❌ Tocar em `AnalyticsProvider.tsx`, `Sidebar.tsx`, `Topbar.tsx`, `endpoints.ts` (território do outro agente)
- ❌ Merge na main sem autorização
- ❌ Implementar antes do sinal verde

---

## Próximo passo

Aguardando Vossa Excelência dar o **sinal verde pra execução**. No momento em que o outro agente finalizar a main (ou Vossa Excelência autorizar dev paralelo via worktree), eu começo pela **Etapa 0** e sigo na ordem.
