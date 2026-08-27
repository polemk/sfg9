# Features removidas da base ai9 (Phase 1b — trim para o Safegold)

Registro auditável e reversível do strip. Uma seção por feature: o que foi **apagado**,
o que foi **editado** para não deixar referência solta, e o que foi **deixado de
propósito** (compartilhado com uma feature mantida ou com um bloco ainda não executado).

Referências: `openspec/changes/trim-ai9-safegold/{design,tasks}.md`,
`.migration-ai9/ai9-feature-selection.md`, `.migration-ai9/decisions.md` (DEC-13).

---

## Bloco 1 — Folhas visuais + landing (24/08/2026)

**Escopo:** AI9-021, 022, 023, 024, 025, 026, 027, 028, 029, 031, 032 (11 features).

**Verificação:**

| Verificação | Baseline (antes) | Depois |
| ----------- | ---------------- | ------ |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **305 erros** (282 em `src/components/3d/`, 23 em `src/components/3d/chat/`) | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | — | **limpo, 0 findings** |
| `node node_modules/vitest/vitest.mjs run` | não executável neste shell | não executável — `@rollup/rollup-win32-x64-msvc` ausente (os `node_modules` foram instalados no Linux; o binário nativo do rollup não bate com o Node do Windows). **Limitação de ambiente, anterior ao trim.** |

Total: **167 arquivos apagados**, **13 arquivos editados**. Nenhuma migration envolvida —
o bloco é 100% front, mais 3 docs e 1 endpoint público no backend.

---

### AI9-022 — Cenas 3D / WebGL (tarefa 1.1)

**Apagado**
- `frontend/src/components/3d/` (11 cenas: `FinalPurpleRoom`, `FinalScenario`, `FloatingShape`,
  `GallerySection`, `HeroScene`, `HiddenRoom`, `PortalWall`, `ScrollTextOverlay`,
  `StellarSpace`, `TransitionSpace`, `Wormhole`)
- `frontend/src/components/3d/chat/HolographicChat.tsx` (+ 2 swapfiles de vim versionados por engano)
- `frontend/src/stores/useHolographicChatStore.ts` — consumido só por `3d/HeroScene` e `3d/chat/HolographicChat`

**Editado** — nada: o único consumidor externo era `DesignDemoPage` (AI9-028, removida na mesma leva).

**Deixado de propósito**
- `frontend/package.json` continua declarando `three`, `@types/three`, `@react-three/fiber`,
  `@react-three/drei`. **Nenhum arquivo em `src/` importa mais essas libs.** Não removi porque
  `pnpm` não existe neste shell e mexer no `package.json` sem regravar o `pnpm-lock.yaml`
  deixaria o lockfile dessincronizado (quebraria um `--frozen-lockfile` no CI).
  **Follow-up:** remover as 4 dependências + `pnpm install` num ambiente com pnpm.

> Esta remoção é a que zera o baseline: os 305 erros de type-check eram todos
> `JSX.IntrinsicElements` de `three.js` sem tipos registrados, dentro deste diretório.

---

### AI9-023 — UI de terminal / typewriter (tarefa 1.2)

**Apagado**
- `frontend/src/components/terminal/TerminalWindow.tsx`
- `frontend/src/components/terminal/TypewriterText.tsx`
- `frontend/src/stores/useTerminalStore.ts`

**Editado**
- `frontend/src/app/App.tsx` — import de `TerminalWindow` e o `<TerminalWindow />` global
- `frontend/src/components/leads/LeadChatView.tsx` — import **morto** de `TypewriterText`
  (import relativo `../terminal/TypewriterText`, sem uso no JSX). Só o import saiu; o
  arquivo é AI9-006 e sai inteiro no Bloco 6.

---

### AI9-024 — Easter egg sazonal (tarefa 1.3)

**Apagado**
- `frontend/src/components/seasonal/{EasterEggHunt,EasterEggModal,EasterOverlay,EasterProgressPanel}.tsx`
- `frontend/src/styles/easter-theme.css`

**Editado**
- `frontend/src/app/App.tsx` — imports, `<EasterOverlay />`, `<SiteOnly><EasterEggHunt /></SiteOnly>`
  e o helper `SiteOnly` (que existia só para o egg hunt), mais os imports `ReactNode` e
  `useLocation` que ficaram órfãos com ele

**Deixado de propósito**
- `frontend/src/components/LanguageSwitcher.tsx` tem um `EasterEggCanvas` interno — é um
  easter egg **do seletor de idioma**, homônimo mas sem relação com a caça aos ovos sazonal.
  Não é AI9-024.

---

### AI9-031 — Audio visualizer / componentes áudio-reativos (tarefa 1.4)

**Apagado**
- `frontend/src/app/experiments/audio-visualizer/page.tsx` (e o diretório `app/experiments/`)
- `frontend/src/components/chat/AudioVisualizerPlayer.tsx`
- `frontend/src/components/ui/{AudioReactiveButton,AudioReactiveText}.tsx`
- `frontend/src/components/experiments/NeonOscilloscope.tsx` (e o diretório)
- `frontend/src/hooks/useAudioAnalyzer.ts`

**Editado**
- `frontend/src/app/App.tsx` — lazy import e rota `/audio-visualizer`

**Deixado de propósito**
- **`frontend/src/store/audioPlayerStore.ts` FICA.** Não é do AI9-031: é consumido pelo
  chatbot mantido (`hooks/useChatFlow.ts` dispara `activatePlayer` na ação de nó
  `play_audio`) e pelo `components/ParticlesBackground.tsx`, que é global e renderizado
  em toda a app. Remover quebraria o AI9-007 (mantido, DEC-13.2).
- O resto de `components/chat/` ficou intacto — pertence ao chatbot AI9-007, que é mantido.

---

### AI9-028 — Design demo / playground de tokens (tarefa 1.5)

**Apagado**
- `frontend/src/app/pages/DesignDemoPage.tsx`

**Editado**
- `frontend/src/app/App.tsx` — lazy import e rota `/design-demo`

A página não tinha item de `Sidebar` (era rota pública não linkada).

---

### AI9-029 — Guia de rastreamento (tarefa 1.6)

**Apagado**
- `frontend/src/app/pages/TrackingGuidePage.tsx`
- `backend/docs/TRACKING_GUIDE.md`
- `backend/docs/UTM_STANDARDS.md`
- `backend/docs/GTM_SETUP.md`

**Editado**
- `frontend/src/app/App.tsx` — lazy import e rota `/guia-rastreamento`

Sem item de `Sidebar` (rota pública não linkada).

**Deixado de propósito**
- `backend/docs/{GA4_SETUP,META_CAPI_SETUP}.md` — são docs do AI9-010 (analytics próprio),
  que sai no **Bloco 2**, não do guia de UTM/GTM.
- `README_TRACKING.md` na raiz — não está no escopo declarado do AI9-029; revisar no Bloco 2
  junto com o analytics.

---

### AI9-027 — Preview de site / "Vem com site" (tarefa 1.7)

**Apagado**
- `frontend/src/app/pages/SitePreviewPage.tsx`
- `frontend/src/app/pages/BuildPage.tsx`

**Editado**
- `frontend/src/app/App.tsx` — lazy imports e as rotas `/preview-site` **e** `/build`
- `frontend/src/components/Sidebar.tsx` — item `{ path: '/preview-site', label: 'Vem com site' }`,
  o guard `hasSite`, o `isClientOrVisitor` que ficou sem uso e o ícone `Globe` do import
- `frontend/src/hooks/useNavItems.ts` — o mesmo item (`label: 'Site'`), `hasSite` e `isClientOrVisitor`

**Deixado de propósito — divergência do plano**
- **`frontend/src/components/preview/*` FICA.** A `tasks.md` lista esse diretório como
  AI9-027, mas o código diz outra coisa: `PreviewBadge`, `PreviewInfoCard` e `PreviewCta`
  implementam o **modo de preview de plano** (`usePlanPreviewStore`), que é AI9-002
  (feature-gating, **Bloco 4**) — nada a ver com "preview de site". São importados por
  10 páginas, entre elas `DashboardPage` (AI9-033, **mantida**) e `MediaPage` (AI9-016,
  **mantida**). Apagar aqui quebraria features mantidas. Sai no Bloco 4, com o AI9-002.

---

### AI9-026 — NavKit (tarefa 1.8)

**Apagado**
- `frontend/src/NavKit/` (index, 5 componentes, context + routes + types, 5 hooks)
- `frontend/src/app/NavKitDemo.tsx`
- `frontend/src/app/pages/NavKitHome.tsx`, `frontend/src/app/pages/NavKitOverview.tsx`
- `frontend/src/app/pages/NavKitLanding/` (5 telas + 3 componentes)
- `frontend/src/app/styles/NavKitHome.css`

**Editado**
- `frontend/src/app/App.tsx` — lazy import e rota `/navkit/*`

**Deixado de propósito**
- `frontend/src/lib/analytics/AnalyticsProvider.tsx:109` (`path.startsWith('/navkit')`) e
  `frontend/src/lib/analytics/useHeatmapTracker.ts:14` (`[data-navkit-scrollable="true"]`)
  são **strings**, não imports — pertencem ao AI9-010/AI9-012, que saem no **Bloco 2**.
  Não quebram nada agora (viram condições que nunca casam). Ver "Referências residuais"
  no fim deste documento.
- `frontend/src/store/__tests__/planPreviewStore.test.ts:47` tem uma *fixture* com
  `title: 'NavKit'` — é um dado de teste do AI9-002, não uma referência ao kit.

---

### AI9-025 — Página "Brazilian Software" (tarefa 1.9)

**Apagado**
- `frontend/src/app/pages/BrazilianSoftware/` inteiro: `BrazilianSoftwarePage.tsx`,
  `brsw-theme.css`, `DESIGN_BRIEF.md`, 7 componentes `Brsw*`, 6 telas, 2 sketches SVG,
  `__tests__/BrswLogo.test.tsx`
- `backend/app/controllers/api/v1/public/brazilian_posts.rb` (proxy cacheado do blog da brsw)

**Editado**
- `backend/app/controllers/api/v1/base.rb` — `mount Api::V1::Public::BrazilianPosts`
- `backend/app/controllers/api/root.rb` — a entrada `%r{^/api/v1/public/brazilian_posts(/.*)?$}`
  da allowlist de rotas públicas

A página não tinha rota registrada no `App.tsx` (era servida por um path secreto no
próprio componente). O único consumidor do endpoint era `campfire/sections/ArtigosBrazilian.tsx`,
apagado com o AI9-021.

**Deixado de propósito**
- `frontend/index.html:73` (`"url": "https://brsw.org/"` no JSON-LD) — é metadado de marca
  da app, tratado em `.migration-ai9/brand-and-metadata.md`, não código do AI9-025.

---

### AI9-032 — Servidor MCP do n8n (tarefa 1.10)

**Apagado**
- `tools/n8n-mcp-server/` inteiro (61 arquivos: `src/`, `build/`, `patches/`, `package.json`,
  `package-lock.json`, os zips e o `tsconfig.json`)

**Editado** — nada. Nenhum código da app referenciava a ferramenta.
`tools/graphify` permanece.

---

### AI9-021 — Landing pública "campfire" (tarefa 1.11)

**Apagado**
- `frontend/src/components/campfire/` — 14 componentes (`BrandTicker`, `FooterCrowd`,
  `HeaderCard`, `HeroCampfire`, `InstagramVideo`, `LetterCard`, `ManifestoFinal`,
  `MediaShowcase`, `NicheSelector`, `PublicFooter`, `SectionHeader`, `SloganCanvas`,
  `TimelineCanvas`, `Topbar`), 10 `sections/` e `__tests__/hero.test.tsx`
- `frontend/src/app/pages/HomePage.tsx` e `frontend/src/app/pages/__tests__/HomePage.plans.test.tsx`
- `frontend/src/styles/tokens-campfire.css`
- `frontend/src/wireframes/HomeCampfire.tsx` (e o diretório `wireframes/`)

**Editado**
- `frontend/src/app/App.tsx` — lazy import de `HomePage`, rota `/n/:niche`, e **a rota `/`
  passou a apontar para `LoginPage` (DEC-13.3)**. A raiz não fica quebrada em nenhum
  momento: `/` e `/login` renderizam a mesma tela.
- `frontend/src/main.tsx` — import de `./styles/tokens-campfire.css`
- `frontend/src/styles/globals.css` — bloco `.btn-campfire` (+ `:hover`, `:active`, `span`,
  `.dark`), sem nenhum consumidor restante
- `frontend/src/app/pages/CouponRedirectPage.tsx` (AI9-003, Bloco 4) — renderizava
  `<HomePage />` como fundo enquanto validava o cupom. Trocado por um placeholder
  "Validando cupom..."; o `useEffect` de validação e o redirect para `/` seguem intactos.
- `frontend/src/app/pages/posts/{PostListPage,PostByCategoryPage,PostPage,PostByTagPage}.tsx`
  (AI9-004, Bloco 3) — importavam `Topbar` e `PublicFooter` do campfire. Imports e JSX
  removidos; as páginas continuam compilando e renderizando o conteúdo, só sem o chrome
  da landing. Saem inteiras no Bloco 3.

**Por que `Topbar`/`PublicFooter` não foram preservados para o Bloco 3**
Manter os dois obrigaria a manter também `useTerminalStore` (AI9-023),
`AudioVisualizerPlayer` (AI9-031) e `NicheSelector` (AI9-021) — ou seja, esvaziaria três
outras tarefas deste bloco. Preferi remover e ajustar os 4 consumidores, que são páginas
já marcadas para remoção.

**Deixado de propósito**
- **`frontend/src/app/pages/dictionaries.ts` FICA.** É o dicionário de nichos (`/n/:niche`),
  mas `CouponRedirectPage` ainda o usa para distinguir um código de cupom de um slug de
  nicho (`if (code in dictionaries)`). Sai no Bloco 4, junto com a rota catch-all `/:code`.
- **`frontend/src/components/layouts/PublicSplitLayout.tsx` FICA.** É o layout que hospeda
  o widget de chat (AI9-007, **mantido**). Ficou sem consumidor depois que `HomePage` e
  `TrackingGuidePage` saíram, mas é infra do chatbot — cabe ao Bloco 8 decidir.
- `frontend/src/components/chat/ChatOverlay.tsx` e `frontend/src/stores/useFinaleStore.ts`
  **ficam**: já eram código morto **antes** do trim (o único import estava comentado em
  `3d/HeroScene.tsx`). São de `components/chat/` (AI9-007, mantido) e o princípio 6b diz
  que não refatoramos a base ai9 — apagar aqui seria limpeza fora de escopo.

---

## Referências residuais conhecidas (varredura do repo inteiro)

> **Lista viva.** Cada bloco tira o que limpou e acrescenta o que deixou.
> Última atualização: **Bloco 2 (analytics)**. As duas pendências que o Bloco 1 deixou
> para cá — `'/navkit'` e `'/design-demo'` no `AnalyticsProvider` e o seletor
> `[data-navkit-scrollable]` no `useHeatmapTracker` — **foram resolvidas**: os dois
> arquivos foram apagados inteiros (AI9-010 e AI9-012).

Varredura feita **depois** do strip, sobre `frontend/ backend/ config/ scripts/ bin/`,
procurando os 19 termos das 11 features. Resultado: **nenhuma referência load-bearing** —
nada importa, carrega ou aponta para arquivo apagado. O que sobrou é **string inerte** ou
**linha de seed**, tudo pertencente a features que saem nos Blocos 2, 3 e 4. Registrado
aqui para que esses blocos não precisem redescobrir.

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `frontend/src/store/__tests__/planPreviewStore.test.ts:47` | fixture `{ title: 'NavKit' }` | Dado de teste do AI9-002, não referência ao kit | Bloco 4 |
| `backend/db/seeds/niche_plans.rb` (linhas 61, 64, 83, 102, 121, 141, 144, 149, 157) | features de plano `campfire:` e `navkit:` + os `feature_list` que as citam | **Linhas de seed do catálogo de planos (AI9-002)** — criam linhas de `plan_feature` com nome comercial "NavKit"/"Campfire". Não carregam nenhum código removido | Bloco 4 |
| `backend/db/seeds/plans_and_features.rb:211-220` | feature `'NavKit Spatial UX'` + copy HTML de marketing | idem — catálogo de planos AI9-002 | Bloco 4 |
| `backend/db/seeds/brsw_showrooms.rb:111,135,171` | `description:` de showroom citando "NavKit" | Copy de vitrine; o arquivo é seed do AI9-015 | Bloco 3 |
| `backend/script/update_feature_descriptions.rb:95-102` | copy HTML de `"NavKit Spatial UX"` | Script one-off que reescreve descrições de `plan_feature` (AI9-002) | Bloco 4 |
| `frontend/dist/assets/*` | bundle compilado antigo com CSS/JS das features removidas | Saída de build **não versionada** (só `dist/index.html` é tracked); não é fonte. Some no próximo build | — (rebuild) |
| `frontend/index.html:73` | `"url": "https://brsw.org/"` no JSON-LD | Metadado de marca da app, tratado em `brand-and-metadata.md` | — |
| `frontend/src/lib/analytics/__tests__/identidade.test.ts:8` | comentário citando o `AnalyticsProvider` | Comentário histórico num arquivo **mantido** (a âncora `identidade.ts` serve o chatbot AI9-007). Não é import nem chamada | — (comentário) |
| `frontend/src/app/pages/DashboardPage.tsx` | chama `analyticsApi.dashboard/reportCsv/reportPdf`, cujo endpoint saiu no Bloco 2 | **Dívida consciente do Bloco 2** — a página é AI9-033 (mantida) mas seu conteúdo é vendas/leads/cupons, que morrem nos Blocos 4/6. Refatorá-la agora seria refatorar a base ai9 (princípio 6b). Type-check e specs seguem verdes; a degradação é de runtime | Blocos 4/6 + Phase 2 |
| `backend/app/models/canal.rb:7` e `backend/db/seeds/goat_canais.rb:10` | comentários citando `tracked_events`/`viewers` | Comentário, não código. Os dois arquivos são AI9-006 | Bloco 6 |
| `backend/db/schema.rb:202` | `comment:` de `canais.mapeamento` citando `viewers.first_utm_source` | Comentário de coluna gerado pela migration do `Canal` (AI9-006) | Bloco 6 |
| `backend/db/seeds/data_agent_flow.json:88` | texto de demonstração do chatbot descrevendo o `AnalyticsProvider` e o `trackEvent` | Conteúdo de seed do fluxo de demo (AI9-007, mantido); é prosa dentro de um JSON, não código | Bloco 8 (revisão dos seeds do chat) |
| `backend/app/services/analytics_service.rb` + `spec/services/analytics_service{,_coverage}_spec.rb` + `app/jobs/dashboard_kpis_broadcast_job.rb` | dashboard de vendas/assinaturas (não é `tracked_events`) | Ver "O que NÃO saiu, de propósito" no Bloco 2. Depende de `Purchase`/`Subscription`/`Lead` | Blocos 4/6 |
| `backend/app/models/purchase.rb` | o model inteiro | Ver a decisão registrada no Bloco 2: 2 dos 9 consumidores são do **AI9-030, mantido** | Bloco 4 (decisão) |
| `.git/hooks/{post-checkout,post-commit}` | hooks do graphify com CRLF — shebang inválido, o hook não roda | **Defeito pré-existente**, fora do escopo do trim. Quebra `git checkout` e `git worktree add` | — (fora do trim) |
| `backend/.ruby-version` (3.4.9) x `backend/Gemfile` (3.2.3) | versões de Ruby em conflito | **Pré-existente.** O `bundle` recusa rodar no 3.4.9; só o wrapper do 3.2.3 funciona | — (fora do trim) |
| `tools/graphify/steps/05_label.py:49,54,59` e `tools/graphify/semantic-layer.json:272,811` | dicas de rotulagem citando `PainelTV.tsx`, `AnalyticsPage.tsx`, `dateRangeStore.ts`, `HubForwardEventsJob`, `AnalyticsProvider` | **Ferramenta, não a app.** São heurísticas de nomeação de comunidade do graphify; nomes que não casam com nenhum nó simplesmente não rotulam nada. Editá-las mexeria na qualidade do grafo, o que é escopo de outra ferramenta, não do trim | — (manutenção do graphify) |

**Por que não editei os seeds agora.** A regra 5 do `design.md` manda tirar seed junto com
a feature — e é o que os Blocos 3/4 vão fazer, apagando `niche_plans.rb`,
`plans_and_features.rb` e `brsw_showrooms*.rb` **inteiros** junto com AI9-002/AI9-015.
Remover cirurgicamente só as entradas `campfire`/`navkit` agora significaria desmontar os
arrays `feature_list` de 3 planos num arquivo que é deletado por completo daqui a dois
blocos — refactor grande para salvar uma remoção, exatamente o que o princípio 6b proíbe.
Nenhuma dessas linhas referencia código apagado: são `find_or_create_feature("<nome>")`,
puro dado. O `rails db:seed` continua funcionando igual.

---

## Notas do bloco

1. **Nenhuma migration foi tocada** e o `schema.rb` não mudou — o bloco não tem tabela
   exclusiva. Coerente com a regra 4 do `design.md`.
2. **Nenhuma rota órfã.** Rotas removidas: `/`(realocada), `/n/:niche`, `/guia-rastreamento`,
   `/build`, `/preview-site`, `/audio-visualizer`, `/navkit/*`, `/design-demo`.
   Rotas de nav removidas: `/preview-site` (`Sidebar` e `useNavItems`).
   Restam menções **inertes** a `/design-demo` e `/navkit` no analytics e nos seeds de
   plano — inventariadas em "Referências residuais conhecidas", todas endereçadas nos
   Blocos 2/3/4.
3. **Ledger:** `.migration-ai9/parity-ledger.md` — as 11 linhas `AI9-021..029, 031, 032`
   viraram `to-remove` → `removed`.
4. **Reversão:** o bloco é um commit único; `git revert` desse commit restaura as 11
   features e volta o type-check para os 305 erros do baseline.

---

## Bloco 2 — Analytics (24/08/2026)

**Escopo:** AI9-011, AI9-012, AI9-013 (folhas) → **AI9-010** (o hub `TrackedEvent`).

**Verificação:** ver "Verificação do Bloco 2" no fim desta seção.

> **Nota de método.** As tarefas 2.1–2.3 removem folhas cujos únicos consumidores são
> arquivos do próprio AI9-010, apagados na tarefa 2.4 **do mesmo bloco**. Não editei esses
> consumidores para "compilar no meio do caminho": seria trabalho jogado fora num arquivo
> que morre na tarefa seguinte (princípio 6b). O portão de type-check do bloco é a tarefa
> 2.5, e é lá que ele é medido.

---

### AI9-011 — Painel TV (tarefa 2.1)

**Apagado**
- `frontend/src/features/metrics/PainelTV.tsx` — a parede de métricas em tela cheia
- `frontend/src/features/metrics/MosaicoParede.tsx` — o algoritmo `distribuir` que empacota as 24 peças
- `frontend/src/features/metrics/LiveFeed.tsx`
- `frontend/src/features/metrics/ScoreRing.tsx`
- `frontend/src/features/metrics/__tests__/MosaicoParede.test.ts`
- `frontend/src/features/metrics/__tests__/PainelTV.smoke.test.tsx`

**Editado**
- `frontend/src/features/metrics/index.ts` — os 7 re-exports (`ScoreRing`, `ScoreRingProps`,
  `ScoreTone`, `LiveFeed`, `PainelTV`, `PainelTVProps`, `MosaicoParede`/`distribuir`, `Peca`)

**Único consumidor externo:** `frontend/src/app/pages/admin/AnalyticsPageMobile.tsx`
(aba "TV", o `ScoreRing` de profundidade de rolagem e dois `LiveFeed`). O arquivo é
AI9-010 e foi apagado inteiro na tarefa 2.4 — por isso não foi editado aqui.

**Deixado de propósito** — nada. `JornadaChart`, `Rosca`, `OrigemPicker`, `OrigensTable`
e `LimiteDeErro`, que o `PainelTV` importava, pertencem ao AI9-010 e saíram na tarefa 2.4.

---

### AI9-012 — Logger de eventos ao vivo + Heatmap de cliques (tarefa 2.2)

**Apagado**
- `frontend/src/app/pages/admin/EventLoggerPage.tsx`
- `frontend/src/app/pages/admin/HeatmapPage.tsx`
- `frontend/src/hooks/useEventStream.ts` — hook do `EventLoggerChannel`; **único consumidor
  era o `EventLoggerPage`** (verificado por grep no `src/` inteiro)
- `frontend/src/lib/analytics/useHeatmapTracker.ts` — o tracker de cliques que alimentava o mapa
- `backend/app/services/analytics/get_heatmap_data.rb`
- `backend/app/channels/event_logger_channel.rb` — o único publicador era
  `Analytics::TrackEvent` (AI9-010, apagado na tarefa 2.4) e o único assinante era o hook acima

**Editado**
- `frontend/src/app/App.tsx` — os 2 `lazy(import(...))` e as rotas `admin/logger` e `admin/heatmap`
- `frontend/src/components/Sidebar.tsx` — a chave `logger` do `MENU_KEY_MAP` e o item
  `/admin/logger` da lista `isOG`
- `frontend/src/hooks/useNavItems.ts` — as chaves `logger` e `heatmap` do `MENU_KEY_MAP`
  e os 2 itens `/admin/logger` e `/admin/heatmap`

**Deixado de propósito**
- O endpoint `GET /api/v1/analytics/heatmap` em `backend/app/controllers/api/v1/analytics.rb`
  e o método `analyticsApi.heatmap` em `frontend/src/lib/api/endpoints.ts`: os dois arquivos
  são AI9-010 e foram tratados inteiros na tarefa 2.4.

**Rastreamento de heatmap ≠ nav.** O `useHeatmapTracker` era chamado pelo `AnalyticsProvider`
(AI9-010). Com o Provider fora (2.4), não sobra ponto de chamada.

---

### AI9-013 — Espelhamento no hub "brsw" (tarefa 2.3)

**Apagado**
- `backend/app/jobs/hub_push_job.rb` — push de lead, um a um, em tempo real
- `backend/app/jobs/hub_metricas_job.rb` — resumo diário agregado (cron 07:00 UTC)
- `backend/app/jobs/hub_forward_events_job.rb` — encaminhamento de `tracked_events`
- `backend/lib/tasks/hub_backfill.rake` — rake de backfill, exclusivo da ponte
- `backend/spec/models/lead_hub_push_spec.rb` — o spec existia **só** para a ponte
  (6 exemplos, todos sobre `HubPushJob`)

**Editado**
- `backend/config/initializers/sidekiq.rb` — a entrada de cron `hub_metricas` (a última do
  hash; a vírgula do item anterior saiu junto para o Ruby continuar válido — `ruby -c` OK)
- `backend/.env.example` — o bloco inteiro "Ponte com o hub (brsw)": `HUB_URL`,
  `HUB_SOURCE_TOKEN` e `HUB_INSTALACAO`
- `backend/app/models/lead.rb` (AI9-006, sai no Bloco 6) — **tinha de sair agora**: os
  callbacks `after_create_commit :push_to_hub_on_create` / `after_update_commit
  :push_to_hub_on_update` e os métodos `hub_relevant_update?`, `push_to_hub_on_create`,
  `push_to_hub_on_update` e `push_to_hub` referenciavam `HubPushJob`, que deixou de existir.
  Deixar isso para o Bloco 6 significaria um `NameError` em **todo save de lead**.
  `ruby -c` OK; nenhum outro método do model foi tocado.

**Deixado de propósito**
- `backend/app/services/analytics/track_event.rb:81` chamava `HubForwardEventsJob` — o
  arquivo inteiro é AI9-010 e foi apagado na tarefa 2.4, então não precisou de edição parcial.

**Verificação do toolchain:** `ruby`/`bundle` **não estão no PATH do Git Bash** (Windows);
vivem dentro do WSL (`rvm`, ruby 3.4.9). Os checks de Ruby deste bloco foram rodados via
`wsl.exe -d ubuntu-22.04`.

---

### AI9-010 — Analytics próprio (o hub `TrackedEvent`) (tarefa 2.4)

O maior nó do bloco: tracking de eventos, funil de conversão, dashboard de KPIs,
resultados por origem, viewers e conversão de servidor (GA4 Measurement Protocol +
Meta CAPI).

**Apagado — frontend**
- `frontend/src/app/pages/admin/{AnalyticsPage,AnalyticsPageDesktop,AnalyticsPageMobile,ConversionFunnelSection}.tsx`
- `frontend/src/features/metrics/` — 21 arquivos (`FilterPill`, `FunnelBars`, `JornadaChart`,
  `KpiCard`, `LatestLeadsList`, `LeadPathTrail`, `LimiteDeErro`, `MobileTabBar`,
  `ModosDaJornada`, `OrigemPicker`, `OrigensTable`, `Rosca`, `SectionCard`, `SourceBars`,
  `Sparkline`, `ViewerCard`, `ViewersPanel`, `index.ts`, `paleta.ts`, `types.ts`,
  `useCollapsedOnScroll.ts`, `utils.ts`) — **exceto `invalidateAnalytics.ts`, ver abaixo**
- `frontend/src/lib/analytics/AnalyticsProvider.tsx`
- `frontend/src/components/GlobalDateRangeSelector.tsx` e `frontend/src/store/dateRangeStore.ts`
  (consumidos só pelas três telas de analytics)
- `frontend/src/components/charts/{BarChart,LineChart,PieChart,Sparkline}.tsx` — **zero
  consumidores** (o único `import` de `charts/Sparkline` já estava comentado em `DashboardPage`)
- `frontend/src/components/kpi/PerformanceIndicators.tsx` — zero consumidores

**Apagado — backend**
- `backend/app/controllers/api/v1/analytics.rb` (7 endpoints) e
  `backend/app/controllers/api/entities/{tracked_event.rb,analytics/dashboard.rb}`
- `backend/app/services/analytics/` inteiro — `conversion_funnel`, `get_dashboard_data`,
  `get_filter_options`, `list_events`, `list_viewers`, `resultados_por_origem`,
  `server_conversion`, `track_event`, `viewer_tracker`, `ga4/send_event`,
  `providers/meta_capi`
- `backend/app/models/{tracked_event,viewer}.rb`
- `backend/app/jobs/viewer_track_job.rb`, `backend/app/jobs/analytics/{distribute_event_job,send_to_ga4_job}.rb`
- `backend/app/jobs/link_events_to_lead_job.rb` — catalogado como AI9-006, mas é 100%
  plumbing de `tracked_events`; sem a tabela não sobra o que costurar
- specs: `spec/requests/api/v1/analytics_spec.rb`, `spec/models/tracked_event_spec.rb`,
  `spec/factories/tracked_events.rb`, `spec/services/analytics/` (4 arquivos)

**Apagado — dados (migrations + schema)**
- 7 migrations exclusivas: `create_tracked_events`, `add_source_to_tracked_events`,
  `add_indices_to_tracked_events`, `add_lead_id_to_tracked_events`,
  `add_niche_to_tracked_events`, `create_viewers`, `add_viewer_to_tracked_events`
- `db/schema.rb`: as tabelas `tracked_events` e `viewers` e as duas
  `add_foreign_key "tracked_events", ...`
- `db/migrate/20260808020000_goat_alcanca_o_modelo_de_pessoa.rb` foi **editada, não apagada**:
  tratava `viewers`, `tracked_events` **e `leads`** na mesma passada. Ficou só a parte de
  `leads` (visitor_id + colunas de anúncio), que continua viva até o Bloco 6.

**Editado**
- `frontend/src/app/App.tsx` — lazy import de `AnalyticsPage` e rota `admin/metrics`
- `frontend/src/main.tsx` — o `<AnalyticsProvider>` que embrulhava o app inteiro
- `frontend/src/components/{Sidebar,Topbar}.tsx` e `frontend/src/hooks/useNavItems.ts` —
  as entradas `/admin/metrics` (inclusive a do bloco de visitante no `Topbar`) e os
  imports de ícone que ficaram órfãos (`BarChart2`, `Activity`, `Globe`)
- `frontend/src/components/chat/MobileChatBar.tsx` — as duas linhas de `ROUTE_HINTS`
  para `/admin/metrics` e `/admin/analytics`
- `frontend/src/lib/api/endpoints.ts` — de `analyticsApi` saíram `batchEvents`,
  `listEvents`, `getFilterOptions`, `viewers`, `reset` e `heatmap`; saiu também
  `origensApi.resultados` e a interface `OrigemResult`
- `frontend/src/app/pages/CheckoutPage.tsx` (AI9-002, Bloco 4) — o `useAnalytics()` e as
  5 chamadas de `trackEvent` (`checkout_started`, `payment_initiated`, `payment_success`
  via `trackSuccess`, `payment_failed`)
- `backend/app/controllers/api/v1/base.rb` — o `namespace :analytics`
- `backend/app/controllers/api/root.rb` — a rota `/api/v1/analytics/events` da allowlist pública
- `backend/app/controllers/api/v1/origens.rb` (AI9-006, Bloco 6) — o endpoint
  `GET /origens/resultados`, que chamava `Analytics::ResultadosPorOrigem`
- `backend/app/models/lead.rb` (AI9-006, Bloco 6) — 4 callbacks e 8 métodos privados que
  dependiam de `Viewer`/`TrackedEvent`: `atribuir_origem_da_sessao`, `link_tracked_events`,
  `fechar_viewer*`, `conversao_servidor*`, `virou_identificado?`, `tem_identidade?`
- `backend/app/models/purchase.rb` (**FICA** — ver a decisão abaixo) — o
  `registrar_payment_success` (gravava em `tracked_events`) e a chamada
  `Analytics::ServerConversion.compra_fechada`
- `backend/app/services/ai/tools/tool_executor.rb` (**AI9-007, MANTIDO**) — o
  `registrar_evento_de_funil` e a chamada de `checkout_started`
- `backend/spec/requests/chat_lead_no_primeiro_input_spec.rb` (AI9-007) — os 2 exemplos que
  criavam `Viewer` para testar atribuição/fechamento; o resto do arquivo (chat não vira lead) fica
- `backend/config/sidekiq.yml` e `backend/app/models/canal.rb` — comentários que citavam
  classes apagadas

---

## Decisão: `Purchase` **FICA** (revoga a linha 83 do `design.md`)

O `design.md` dizia "`Purchase` é compartilhado entre AI9-001 e o funil de AI9-010: sai com
o bloco 2". **A evidência no código diz o contrário** — o design.md considerou dois dos nove
consumidores. Levantamento completo:

| Consumidor | Feature | Sai quando |
| ---------- | ------- | ---------- |
| `app/services/auth/checkout_session_service.rb` (23 usos) | **AI9-030 — login. MANTIDO** | nunca |
| `app/controllers/api/entities/user.rb` (`purchased_plan_ids`, 3 usos) | **AI9-030 / entidade de usuário. MANTIDO** | nunca |
| `app/models/user.rb` — `has_many :purchases` | infra de usuário | nunca |
| `app/channels/application_cable/connection.rb` — `Purchase.by_any_id` na autorização do socket | infra de Action Cable | nunca |
| `app/services/permissions_sync_service.rb` (7 usos, `grant_for_purchase`/`revoke_for_purchase`) | AI9-002 — e o `design.md` já manda revisá-lo no Bloco 4 | Bloco 4 |
| `api/v1/checkout.rb`, `api/auth/v1/checkout.rb`, `plans_service`, `subscription_management_service` | AI9-002 | Bloco 4 |
| `asaas_*_webhook_service`, `payments/create_charge`, `sales_service`, `payments_channel` | AI9-001 | Bloco 4 |
| `models/coupon.rb`, `api/v1/partner/dashboard.rb` | AI9-003 | Bloco 4 |
| `analytics/{conversion_funnel,server_conversion,get_dashboard_data,ga4/send_event,providers/meta_capi}` | AI9-010 | **este bloco** |

**Conclusão:** o funil do AI9-010 é **um** dos nove consumidores, e dois deles
(`checkout_session_service` e `Api::Entities::User`) pertencem ao **AI9-030, que é mantido**.
Remover `Purchase` aqui deixaria o login sem a rota de sessão de checkout e a entidade de
usuário sem `purchased_plan_ids` — quebra de feature mantida.

**O que fiz:** `Purchase` fica; saíram apenas as suas amarras com o AI9-010
(`registrar_payment_success` e `Analytics::ServerConversion.compra_fechada`). A decisão
final sobre o model inteiro é do **Bloco 4**, quando AI9-001/002/003 saírem e sobrarem só
os consumidores de AI9-030 — e aí a pergunta é se o login por checkout continua fazendo
sentido no Safegold, que é decisão de produto, não de trim.

---

## O que NÃO saiu, de propósito (recusas com evidência)

| Item | Por que ficou |
| ---- | ------------- |
| `backend/app/channels/dashboard_channel.rb` | Catalogado como AI9-010, mas quem assina é `DashboardPage.tsx` (**AI9-033, MANTIDO**), `LeadsChatPage`, `LeadListDashboard`, `LeadsGeneralTab`, `LeadsChatwootTab`; e quem publica é `app/models/lead_message.rb`. Nada disso é AI9-010 |
| `backend/app/channels/public_events_channel.rb` | Catalogado como AI9-010, mas os publicadores restantes são `plan_scarcity_reset_job.rb` (AI9-002) e `models/coupon.rb` (`sidebar_coupon_changed`, AI9-003), e o assinante é `PlanSelector.tsx` (AI9-002). Sai no Bloco 4 |
| `backend/app/services/analytics_service.rb` + `backend/app/jobs/dashboard_kpis_broadcast_job.rb` | **Não é o analytics de `tracked_events`** — é o dashboard de vendas/assinaturas/leads (`Purchase`, `Subscription`, `Lead`). Não está na lista de caminhos do AI9-010 (que é `services/analytics/*`, o diretório) e é chamado pelos webhooks do Asaas. Sai com os Blocos 4/6 |
| `frontend/src/components/kpi/KpiCard.tsx` | 10 importadores, entre eles `DashboardPage.tsx` (AI9-033, mantido) |
| `frontend/src/components/alerts/AnomalyAlerts.tsx` e `charts/{RechartsBar,RechartsLine,RechartsPie,theme}` | Importados por `DashboardPage.tsx` (mantido); `charts/theme` também por `AnomalyAlerts` |
| `frontend/src/app/pages/admin/MobileMiniKpi.tsx` | Catalogado como AI9-010; o único importador é `MobilePlansPage.tsx` (AI9-002). Sai no Bloco 4 |
| `frontend/src/features/metrics/invalidateAnalytics.ts` | Único sobrevivente do diretório. Invalida a família de chaves `['analytics','analytics-dashboard','origens']` — e **`origens` é a chave da própria lista do `CanaisPage`** (AI9-006). Apagar quebraria uma tela que ainda vive. Sai no Bloco 6 |
| `frontend/src/lib/analytics/identidade.ts` (+ seu teste) | A âncora `visitor_id`/`session_id`. Importada por `lib/api/chatFlow.ts` (**AI9-007, MANTIDO**) e por `leadsPublicApi` em `endpoints.ts` |
| `analyticsApi.{dashboard,reportCsv,reportPdf}` em `endpoints.ts` | **Dívida consciente — ver o aviso abaixo** |

### Dívida deixada: o `DashboardPage` perde a fonte de dados

`frontend/src/app/pages/DashboardPage.tsx` é **AI9-033 (mantido)**, mas seu conteúdo é 100%
painel de marketing: consome `GET /api/v1/analytics/dashboard` — que era servido por
`Analytics::GetDashboardData`, apagado aqui — e renderiza vendas, assinaturas, leads,
cupons e `AnomalyAlerts`.

**Escolha:** mantive os 3 métodos (`dashboard`, `reportCsv`, `reportPdf`) em `analyticsApi`
para **não refatorar uma página mantida no meio do trim** (princípio 6b). Consequência
honesta: em runtime a chamada passa a dar 404, o `catch` da página seta erro e os cartões
mostram zero. Não é regressão de type-check nem de spec — é dívida de produto, registrada.
(`reportCsv`/`reportPdf` **já eram** 404 antes do trim: `AnalyticsService#report_csv/pdf`
existe, mas nenhuma rota o monta. Defeito pré-existente.)

**Para os Blocos 4/6 e o Phase 2:** tudo que o `DashboardPage` mostra (vendas → AI9-001/002,
cupons → AI9-003, leads → AI9-006) sai nesses blocos. A página precisa ser redefinida como
a home do Safegold — decisão de produto, não de remoção.

---

## Verificação do Bloco 2

| Verificação | Baseline (medido em HEAD `5656a8b7`) | Depois do bloco |
| ----------- | ------------------------------------ | --------------- |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **0 erros** | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | limpo | **limpo, 0 findings** |
| `cd backend && bundle exec rspec` | **1362 examples, 6 failures, 2 pending** | **1298 examples, 5 failures, 2 pending** |

**As 6 falhas do baseline não estavam listadas em lugar nenhum — só o número.** Para poder
afirmar "as mesmas 6", medi a lista: `git stash` do bloco inteiro, `rspec` em HEAD, `git
stash pop`. Resultado:

| # | Exemplo que falha no baseline | Depois do bloco |
| - | ----------------------------- | --------------- |
| 1 | `spec/models/lead_hub_push_spec.rb:37` | **sumiu — o spec era do AI9-013, removido nesta fila** |
| 2 | `spec/requests/api/v1/users_spec.rb:111` | continua falhando (intocado) |
| 3 | `spec/requests/api/v1/webhooks/meta_spec.rb:87` | continua falhando (intocado) |
| 4 | `spec/services/lead_cross_channel_service_spec.rb:35` | continua falhando (intocado) |
| 5 | `spec/services/operations/embeddings/generate_service_spec.rb:9` | continua falhando (intocado) |
| 6 | `spec/services/users_service_spec.rb:85` | continua falhando (intocado) |

**Nenhuma falha nova.** As 5 restantes são subconjunto exato das 6 do baseline. Os 64
examples a menos são os specs apagados junto com as features (analytics + hub).

### Notas de ambiente (para quem pegar o próximo bloco)

1. **`ruby`/`bundle` não estão no PATH do Git Bash** (Windows). Vivem no WSL, via `rvm`.
   O projeto exige **ruby 3.2.3** (o default do `rvm` é 3.4.9 e o Bundler recusa). O que
   funciona:
   `wsl.exe -d ubuntu-22.04 -- bash -lc "cd ~/workspace/ai9/backend && ~/.rvm/wrappers/ruby-3.2.3/bundle exec rspec"`.
   Note que o `.ruby-version` do repo diz `3.4.9` e o `Gemfile` diz `3.2.3` — **estão em
   conflito**; vale corrigir fora do trim.
2. **`.git/hooks/post-checkout` e `post-commit` (graphify) estão com CRLF** — o shebang vira
   `/bin/sh` com CR e o hook não roda: qualquer `git checkout`/`git worktree add` sai com
   erro. Defeito **pré-existente**. Contornei com `git -c core.hooksPath=/dev/null checkout`.
3. **`git stash push -u` + `pop` neste repo reescreveu ~694 arquivos com CRLF** e renomeou o
   arquivo versionado `Nota` (com U+F03A no fim) para `Nota:`. Detectei, comparei byte a
   byte (conteúdo idêntico módulo CRLF) e restaurei os 694 a partir do HEAD, mais o arquivo
   `Nota`; os 20 arquivos com mudança real de conteúdo foram auditados e estão em LF.
   **Não use `git stash` neste repo** — use `git worktree` (que também precisa do contorno
   do hook).

---

## Bloco 3 — Conteúdo (24/08/2026)

**Escopo:** AI9-019, AI9-020, AI9-015, AI9-017, AI9-004 (folhas → raiz) → **AI9-005 parcial**
(DEC-14: o login por WhatsApp **fica**).

**Verificação:** ver "Verificação do Bloco 3" no fim desta seção.

> **Nota de método.** Igual ao Bloco 2: quando o único consumidor de um arquivo removido
> é outro arquivo que morre **no mesmo bloco**, não editei o consumidor para "compilar no
> meio do caminho" (princípio 6b). Quando o consumidor sobrevive ao bloco (vive até o
> Bloco 5/7), a folha **não saiu** — está listada em "O que NÃO saiu, de propósito".

---

### AI9-019 — Transcrição de áudio/vídeo por IA (tarefa 3.1)

**Apagado — backend**
- `backend/app/controllers/api/v1/transcriptions.rb` — `POST /api/v1/transcriptions`
- `backend/app/services/post_transcription_service.rb` — pipeline download → ffmpeg → Whisper do `Post`
- `backend/app/jobs/post_transcription_job.rb`
- `backend/app/jobs/process_audio_transcription_job.rb` — transcrição de áudio recebido por WhatsApp
- `backend/db/migrate/20260325100923_add_can_transcribe_to_users.rb` — a coluna existia
  **só** para o gate de permissão desta feature (verificado: 100% dos usos eram
  `transcriptions.rb:29`, `process_audio_transcription_job.rb:11` e o CRUD de usuário)

**Apagado — frontend**
- `frontend/src/app/pages/TranscriptPage.tsx` — a tela de gravar/enviar áudio

**Editado**
- `backend/app/controllers/api/v1/base.rb` — `mount Api::V1::Transcriptions`
- `backend/db/schema.rb` — `t.boolean "can_transcribe"` na tabela `users`
- `backend/app/controllers/api/v1/users.rb` — os 2 `optional :can_transcribe` (create e update)
- `backend/app/services/users_service.rb` — `:can_transcribe` dos 2 `params.slice`
- `frontend/src/app/App.tsx` — o `lazy(import('@/app/pages/TranscriptPage'))` e a rota `transcript`
- `frontend/src/components/Sidebar.tsx` — o bloco "5. Transcrição" e o ícone `Mic` (ficou órfão)
- `frontend/src/hooks/useNavItems.ts` — o item `/transcript` e o ícone `Mic`
- `frontend/src/app/pages/UsersPage.tsx` — o checkbox "Pode transcrever áudios (IA) no
  WhatsApp" e o campo no payload de update
- `frontend/src/lib/api/types.ts` — `can_transcribe?: boolean` da interface de usuário

**Não editado de propósito (princípio 6b — morrem no mesmo bloco)**
- `backend/app/controllers/api/v1/posts.rb:233` (`PostTranscriptionService.transcribe!`) — AI9-004, tarefa 3.5
- `backend/app/controllers/api/whats/v1/webhooks.rb:115` (`ProcessAudioTranscriptionJob`) — AI9-005, tarefa 3.6
- `backend/app/services/blog/{draft_transcription_service,video_converter_service}.rb` e
  `backend/app/jobs/post_draft_transcription_job.rb` — catalogados como AI9-019, mas são o
  caminho de transcrição do **`PostDraft`**; saíram inteiros na tarefa 3.5 com o blog

**NÃO saiu — ver "O que NÃO saiu, de propósito":** `ai/audio_transcription_service.rb` e
`audio_converter_service.rb`.

---

### AI9-020 — Agenda / Google Calendar / Plane / Drive / briefing diário (tarefa 3.2)

Assistente pessoal do dono da agência: briefing diário por WhatsApp, CRUD de eventos no
Google Calendar, backlog no Plane, memória persistente do agente e varredura de pasta do
Google Drive.

**Apagado — backend**
- `backend/app/services/agenda/` inteiro — `memory_service.rb`, `phone_normalizer.rb`,
  `tools/calendar_tool.rb`, `tools/plane_tool.rb`
- `backend/app/services/google_drive_connection.rb`
- `backend/app/services/ai/tools/calendar_guard.rb` — a policy de acesso restrito ao
  calendário; 100% agenda (tasks.md 8.2 também o listava — foi antecipado aqui porque
  `Agenda::Tools::CalendarTool` deixou de existir)
- `backend/app/models/agenda_memory.rb`
- `backend/app/jobs/{agenda_briefing_job,calendar_event_notify_job,drive_ingestion_job}.rb`
- `backend/db/migrate/20260601000001_create_agenda_memories.rb`
- Specs: `spec/jobs/agenda_briefing_job_spec.rb`, `spec/services/agenda/{calendar_tool,plane_tool}_spec.rb`,
  `spec/services/ai/tools/calendar_guard_spec.rb`, `spec/services/google_drive_connection_spec.rb`

**Editado — backend**
- `backend/db/schema.rb` — a tabela `agenda_memories` inteira
- `backend/config/initializers/sidekiq.rb` — os crons `agenda_briefing` e `drive_ingestion`
- `backend/app/services/ai/tools/tool_executor.rb` (**AI9-007, MANTIDO**) — os `when` de
  `calendar_*`, `plane_*` e `memory_*`, o método privado `execute_calendar` e o kwarg
  `calendar_access:`. **Tinha de sair agora**: as classes `Agenda::*` e `CalendarGuard`
  deixaram de existir e o `case` referenciava as duas — `NameError` em qualquer agente com
  a capability ligada. Mesma lógica que o Bloco 2 aplicou ao `lead.rb`.
- `backend/app/services/ai/tools/tool_registry.rb` (**AI9-007**) — as constantes
  `CALENDAR_*` (5 + a versão restrita), `RESTRICTED_CALENDAR_TOOLS`, `PLANE_*`, `MEMORY_*`,
  as 3 entradas de `CAPABILITY_TOOLS` e o kwarg `calendar_access:` de `definitions_for`
- `backend/app/services/ai/agent_service.rb` (**AI9-007**) — a variável `calendar_access`
  (passo 5.1), os 3 blocos de instrução de tool (`CALENDÁRIO`, `PLANE`, `MEMÓRIA`) e os
  kwargs correspondentes em `tool_instructions_for`, `call_with_tools` e `ToolExecutor.execute`
- `backend/spec/services/ai/tools/tool_registry_spec.rb` — os contextos `calendar capability`
  e `multiple capabilities` (reescrito para `lead_capture` + `assets`, capabilities que
  continuam existindo) e o `unknown provider`, que usava `['calendar']`

**Editado — frontend**
- `frontend/src/features/chat-builder/components/AIAgentConfigPanel.tsx` — a constante
  `INTEGRATIONS` (as 3 integrações eram exatamente calendar/plane/memory), os helpers
  `capabilities`/`hasCapability`/`toggleCapability` e a seção "Integrações" inteira
- `frontend/src/features/chat-builder/api/builder.ts` — o comentário do campo
  `capabilities` (o campo **fica**: o backend ainda deriva `assets`/`lead_capture` dos
  flags legados `tools_enabled`/`extract_lead`)

**Não é o `PhoneNormalizer` global.** `Agenda::PhoneNormalizer` (removido) e
`PhoneNormalizer` (`app/services/phone_normalizer.rb`, **fica**) são classes distintas. O
global é usado por `SuperadminPhone`, `User#normalize_phone`, `whatsapp/admin_auth_resolver.rb`
e `db/seeds/superadmin_phones.rb` — nada disso é AI9-020.

**Não editado de propósito (princípio 6b)**
- `backend/app/services/blog/drive_ingestion_service.rb` e seu spec (únicos consumidores
  restantes de `GoogleDriveConnection`) — AI9-004, saem inteiros na tarefa 3.5

---

### AI9-015 — Showrooms (tarefas 3.3 e 3.3b)

Vitrines públicas de mídia por identificador (`/api/v1/public/showrooms?identifier=…`),
com avatar, logos, parceria e ordenação. **`Medium` NÃO saiu** — é AI9-016, mantida.

**Apagado — backend**
- `backend/app/controllers/api/v1/showrooms.rb` e `.../api/v1/public/showrooms.rb`
- `backend/app/controllers/api/entities/showroom.rb`
- `backend/app/models/showroom.rb`
- `backend/app/services/showroom_service.rb`
- `backend/update_showroom.rb` — script solto na raiz do backend, exclusivo da feature
- 6 migrations: `20260228132314_create_showrooms`, `20260228132340_add_showroom_id_to_media`,
  `20260228151116_add_avatar_and_partnership_to_showrooms`,
  `20260309174553_add_logo_url_to_showrooms`, `20260309180737_remove_logo_url_from_showrooms`,
  `20260309214017_add_location_to_showrooms`
- **`backend/db/seeds/brsw_showrooms.rb`, `brsw_showrooms_logos.rb` e `brsw_showrooms_media.rb`
  inteiros** — resolve a dívida herdada do Bloco 1 (as 3 `description:` citando "NavKit"
  nas linhas 111/135/171 morreram com o arquivo). Nenhum dos 3 era carregado pelo
  `db/seeds.rb`; eram seeds standalone.
- 6 specs: `spec/{models,services}/showroom*_spec.rb`,
  `spec/requests/api/v1/{,public/}showrooms_spec.rb`,
  `spec/controllers/api/entities/showroom_spec.rb`, `spec/factories/showrooms.rb`

**Apagado — frontend**
- `frontend/src/app/pages/ShowroomsPage.tsx`
- `frontend/src/features/marketing/ShowroomPostWidget.tsx` — **zero importadores**
  (verificado por grep no `src/` inteiro); o diretório `features/marketing/` ficou vazio e
  sumiu junto

**Editado — backend (a fronteira com o `Medium`, que fica)**
- `backend/db/schema.rb` — a tabela `showrooms`, a coluna `media.showroom_id`, o índice
  `index_media_on_showroom_id` e a FK `add_foreign_key "media", "showrooms"`
- `backend/app/models/medium.rb` — `belongs_to :showroom, optional: true`
- `backend/app/services/medium_service.rb` — `showroom_id:` nos 2 hashes (create e update)
- `backend/app/controllers/api/v1/media.rb` — os 2 `optional :showroom_id`
- `backend/app/controllers/api/entities/medium.rb` — o `expose :showroom_id`
- `backend/spec/controllers/api/entities/medium_spec.rb` — a expectativa de `showroom_id`
- `backend/app/controllers/api/v1/base.rb` — o `namespace :showrooms` e o mount público
- `backend/app/controllers/api/root.rb` — a regex de rota pública `^/api/v1/public/showrooms`
- `backend/db/seeds.rb` — o módulo de plano `'Módulo Showrooms'` (menu_key `showrooms`) e
  a chave `showrooms` de `saas_goat_modules`
- `backend/lib/tasks/export_startpoint.rake` — as 5 linhas que geravam o `Showroom.destroy_all`

**Editado — frontend**
- `frontend/src/app/App.tsx` — `lazy(import(ShowroomsPage))` + rota `showrooms`
- `frontend/src/components/Sidebar.tsx` e `frontend/src/hooks/useNavItems.ts` — a chave
  `showrooms` do `MENU_KEY_MAP` e o item `/showrooms` da lista de OG
- `frontend/src/components/Topbar.tsx` — o item `/showrooms`
- `frontend/src/components/SidebarModeToggle.tsx` — a descrição do modo "Conteúdo"
  (`'Galeria, showrooms e chatbot'` → `'Galeria e chatbot'`)
- `frontend/src/lib/api/endpoints.ts` — `showroomsApi` e `showroomsPublicApi` inteiros
- `frontend/src/lib/api/types.ts` — a interface `Showroom` e `Medium.showroom_id`
- `frontend/src/locales/{pt-br,en}/translation.json` — as 3 chaves `showroom_{badge,title,subtitle}`,
  **dívida do Bloco 1**: eram copy da landing campfire (AI9-021), sem nenhum consumidor em código

---

### AI9-017 — Pedidos, entregas, milestones, requisitos e especificações (tarefa 3.4)

**É esta tarefa que resolve a colisão de nome `Project`.** O `Project` do ai9 era
"projeto de entrega de conteúdo" (`PR-1234`, tem `deliveries`), nada a ver com o `Project`
de crédito do Safegold. A partir daqui o nome está **livre** para o Phase 2.

**AI9-017 não tinha frontend.** Varredura no `frontend/src` inteiro: nenhuma página,
nenhum `ordersApi`/`deliveriesApi`, nenhum tipo. Era um módulo 100% de API.

**Apagado — endpoints**
- `api/v1/{orders,deliveries,order_milestones,requirements,specifications}.rb`
- `api/v1/public/deliveries.rb` (o acesso por código de entrega)

**Apagado — entities**
- `api/entities/{order,order_milestone,delivery,delivery_item,delivery_attachment,requirement,specification,pricing}.rb`

**Apagado — models**
- `order.rb`, `order_milestone.rb`, `delivery.rb`, `delivery_item.rb`, `delivery_attachment.rb`,
  `requirement.rb`, `specification.rb`, **`project.rb`**, `pricing.rb`, `access_code.rb`

**Apagado — services**
- `orders_service.rb`, `deliveries_service.rb`, `order_milestones_service.rb`,
  `requirements_service.rb`, `specifications_service.rb`, `pricing_calculator.rb`,
  `scope_calculator.rb`

**Apagado — 14 migrations + 10 tabelas do `schema.rb`**
`create_orders`, `create_deliveries`, `fix_order_defaults_and_add_density_ratio`,
`create_specifications_and_requirements`, `create_pricings`, `recreate_pricings`,
`add_missing_columns_to_specifications_and_requirements`,
`rename_deliveries_to_order_milestones`,
`rename_deliveries_count_to_order_milestones_count_in_orders`, `create_projects`,
`create_new_deliveries`, `create_delivery_items`, `create_delivery_attachments`,
`create_access_codes`.
Tabelas fora do `schema.rb`: `orders`, `order_milestones`, `deliveries`, `delivery_items`,
`delivery_attachments`, `specifications`, `requirements`, `projects`, `pricings`,
`access_codes` — mais as 9 `add_foreign_key` correspondentes.

**Apagado — 33 specs/factories** (models, requests, services e factories de todas as
entidades acima)

**Editado**
- `backend/app/controllers/api/v1/base.rb` — os 5 mounts + o mount público de `Deliveries`
- `backend/app/controllers/api/root.rb` — a regex pública `^/api/v1/public/deliveries`

**Duas correções ao catálogo (`ai9-feature-selection.md`), com evidência**

| Item | Catálogo dizia | O código diz | O que fiz |
| ---- | -------------- | ------------ | --------- |
| `Pricing` + `PricingCalculator` | AI9-001 (Asaas, Bloco 4) | `Pricing belongs_to :order`; `PricingCalculator#call` só lê campos de `Order` e grava `order.pricings`. **Único chamador:** `Order#update_values` (`order.rb:96`). Nenhum arquivo de `asaas_*`/`payments/` o referencia | saiu com o AI9-017 |
| `ScopeCalculator` | AI9-002 (planos, Bloco 4) | opera sobre `order.specifications`. **Chamadores:** `Order#update_scope!` e `specifications_service.rb` (3×). Nada de `plans_*` o usa | saiu com o AI9-017 |
| `AccessCode` | AI9-030 (**login, MANTIDO**) | `belongs_to :resource, polymorphic:`, e os **únicos** `as: :resource` do repo são `Delivery` e `Project`. **Zero** referências em `app/services/auth/**`, `app/controllers/api/auth/**` e `models/user.rb`. O código de login é `LoginCode` + `LoginAttempt`, models distintos, intocados | saiu com o AI9-017 |

> A linha do AI9-030 no `ai9-feature-selection.md` diz "magic link, código via WhatsApp,
> OAuth Google e **access codes**" e lista `models/access_code.rb`. **Isso está errado**:
> `AccessCode` é o código de 6 dígitos que abre uma *entrega* para o cliente
> (`GET /api/v1/public/deliveries/:code`), não um código de login. Sua própria factory
> (`spec/factories/access_codes.rb`) fazia `resource { association :project }`. Mantê-lo
> deixaria um model sem nenhum `resource` possível e uma factory impossível de construir.
> **O login não foi tocado** — ver "Verificação do Bloco 3".

**Ficou de propósito: `SupportPlan`.** `Order belongs_to :support_plan`, mas `SupportPlan`
+ `support_plans_service.rb` + `api/v1/support_plans.rb` + a entity são catalogados como
**AI9-002** e saem no Bloco 4. Só a FK `orders → support_plans` saiu do schema.

**Não editado de propósito (princípio 6b)**
- `api/v1/comments.rb` (`values: ['Order']`, 2×) e `comments_service.rb:78`
  (`Order.find_by`) — o `Comment` é AI9-004 e o **único** `commentable` do repo era o
  `Order`; os 3 arquivos saem inteiros na tarefa 3.5

**Também saiu aqui (dívida da tarefa 3.2 encontrada depois)**
- `backend/lib/tasks/agenda.rake` — a task `agenda:setup`, que criava o ChatFlow
  "Assistente do Gui" com `capabilities: %w[calendar plane memory]`
- `backend/db/seeds/assistente_gui_agent.rb` — o mesmo agente, versionado como seed
  (não era carregado pelo `db/seeds.rb`)
- `backend/db/seeds/triagem_polemk_agent.rb` (**AI9-007, MANTIDO**) — saíram as chaves
  `capabilities: ['calendar']` e `calendar_access: 'restricted'`. **Tinha de sair**: com o
  toolset `calendar` fora do `ToolRegistry`, o `agent_service` ainda veria
  `capabilities.any? == true` e chamaria o provider com `tools: []` — que a OpenAI rejeita.
  Sem a chave, o agente cai no caminho `call_simple`. O texto do prompt continua citando
  `calendar_*`; é prosa, e a revisão dos seeds do chat é do Bloco 8.

---

### AI9-004 — Blog: posts, rascunhos, categorias, tags, comentários, curadoria e ingestão (tarefa 3.5)

O produto de conteúdo inteiro: posts com busca full-text, rascunhos com fila de curadoria,
ingestão por grupo de WhatsApp e por pasta do Drive, agendamento de publicação, chatbot
contextualizado por post e comentários públicos threadados.

**Apagado — endpoints (10)**
`api/v1/{posts,post_drafts,categories,tags,comments,blog_settings,superadmin_phones}.rb`
e `api/v1/public/{posts,categories,tags}.rb`

**Apagado — entities (8)**
`api/entities/{post,post_draft,post_summary,category,tag,comment,blog_setting,superadmin_phone}.rb`

**Apagado — models (9)**
`post.rb`, `post_draft.rb`, `post_tag.rb`, `tag.rb`, `category.rb`, `comment.rb`,
`blog_setting.rb`, `blog_intake_session.rb`, `superadmin_phone.rb`

**Apagado — services**
- `app/services/blog/` inteiro (6): `draft_transcription_service.rb`,
  `drive_ingestion_service.rb`, `intake_conversation_service.rb`, `intake_router_service.rb`,
  `post_draft_creator.rb`, `video_converter_service.rb`
- `app/services/whatsapp/` inteiro (1): `admin_auth_resolver.rb` — apesar do nome, decide
  **quem administra o Blog** por número de WhatsApp (via `SuperadminPhone`); o próprio
  comentário do arquivo diz "AI9-24 / Tarefa 1"
- `blog_chat_service.rb` (único chamador: `public/posts.rb`), `post_creation_service.rb`,
  `post_body_generator_service.rb`, `comments_service.rb`

**Apagado — jobs (4)**
`publish_scheduled_drafts_job.rb`, `purge_discarded_drafts_job.rb`,
`post_draft_transcription_job.rb`, `blog_intake_session_expiry_job.rb`

**Apagado — seeds**
`db/seeds/blog_agent_chat_flow.rb`, `db/seeds/superadmin_phones.rb`

**Apagado — 16 migrations + 9 tabelas do `schema.rb`**
`create_comments`, `change_user_id_null_in_comments`, `add_author_fields_to_comments`,
`create_posts`, `add_slug_to_posts`, `create_categories`, `create_tags`, `create_post_tags`,
`add_category_to_posts`, `add_search_vector_to_posts`, `create_superadmin_phones`,
`create_post_drafts`, `create_blog_settings`, `add_blog_intake_keyword_to_blog_settings`,
`create_blog_intake_sessions`, `add_drive_credentials_to_blog_settings`.
Tabelas: `posts`, `post_drafts`, `post_tags`, `tags`, `categories`, `comments`,
`blog_settings`, `blog_intake_sessions`, `superadmin_phones` — mais as 12 `add_foreign_key`.

**Apagado — 21 specs/factories**, incluindo `spec/services/blog/` inteiro e
`spec/services/whatsapp/admin_auth_resolver_spec.rb`

**Apagado — frontend (10 telas)**
`app/pages/posts/` inteiro (`PostByCategoryPage`, `PostByTagPage`, `PostChatbot`,
`PostComments`, `PostListPage`, `PostPage`), `app/pages/PostsPage.tsx`,
`app/pages/admin/{BlogSettingsPage,CurationQueuePage,SuperadminPhonesPage}.tsx`

**Editado — backend**
- `api/v1/base.rb` — os 10 mounts
- `api/root.rb` — as 3 regexes públicas (`posts`, `categories`, `tags`)
- `db/seeds.rb` — os 2 blocos `load` (`blog_agent_chat_flow.rb` e `superadmin_phones.rb`)
- `config/initializers/sidekiq.rb` — **o bloco de cron inteiro**: os 3 jobs que restavam
  (`publish_scheduled_drafts`, `purge_discarded_drafts`, `blog_intake_session_expiry`) eram
  todos do blog. Conferido que não há outro arquivo de agendamento no projeto — sobrou só a
  configuração de Redis do Sidekiq.
- `backend/db/schema.rb` — as 9 tabelas + 12 FKs

**Editado — `app/models/user.rb` (infra MANTIDA) — tinha de sair agora**
O `User` tinha `after_commit :invalidate_admin_auth_cache, if: :saved_change_to_phone?`, e o
método chamava `Whatsapp::AdminAuthResolver.cache_key`. Com o resolver apagado, **todo save
de usuário que mudasse o telefone levantaria `NameError`** — e trocar telefone é caminho de
login. O callback e o método privado saíram, mais o bloco de spec correspondente em
`spec/models/user_spec.rb` (`describe 'invalidação de cache de auth do admin (AI9-24)'`).
Mesmo raciocínio que o Bloco 2 aplicou ao `lead.rb`.

**Editado — frontend**
- `app/App.tsx` — 8 `lazy(import(...))` e 9 rotas (`posts`, `blog-settings`,
  `admin/blog/{configuracoes,admins,fila}`, `/blog`, `/blog/categoria/:slug`,
  `/blog/tag/:slug`, `/blog/:slug`)
- `components/Sidebar.tsx` — o bloco inteiro do **modo "blog"** (4 itens) e os ícones
  `FileText`, `Inbox`, `Settings2`, `ShieldCheck`, que ficaram órfãos
- `hooks/useNavItems.ts` — o item `/posts` e o ícone `FileText`
- `components/SidebarModeToggle.tsx` — o modo `blog` e o ícone `Newspaper`
- **`store/sidebarModeStore.ts`** — `'blog'` saiu do tipo `SidebarMode`. Como o store é
  `persist`ido em `localStorage`, quem tivesse o modo Blog selecionado ficaria com o menu
  **vazio**; por isso o `useSidebarMode()` passou a validar contra `VALID_MODES` e cair em
  `'all'` quando o valor guardado não existe mais
- `lib/api/endpoints.ts` — `blogSettingsApi`, `superadminPhonesApi`, `postsPublicApi`,
  `postsApi`, `postDraftsApi`, `categoriesApi`, `publicCategoriesApi`, `publicTagsApi`,
  o tipo `BlogSettingUpdate` e os 7 imports de tipo
- `lib/api/types.ts` — `BlogSetting`, `SuperadminPhone`, `PostDraftStatus`,
  `PostDraftSource`, `PostDraft`, `PostCategory`, `PostTag`, `Post`, `Comment`

**Resolvidas as pendências herdadas das tarefas 3.1/3.2** — `PostTranscriptionService`
(`posts.rb:233`), `Blog::DraftTranscriptionService`, `Blog::VideoConverterService`,
`PostDraftTranscriptionJob` e `GoogleDriveConnection` (`blog/drive_ingestion_service.rb`)
saíram todos com os arquivos que os chamavam.

**Não editado de propósito (princípio 6b)** — `api/whats/v1/webhooks.rb` (`BlogSetting`,
`Blog::PostDraftCreator`, `Whatsapp::AdminAuthResolver`, `Blog::IntakeRouterService`) e os
specs `webhooks_blog_intake_spec.rb` / `webhooks_group_intake_spec.rb`: são AI9-005 e saem
inteiros na tarefa 3.6.

---

### AI9-005 — WhatsApp / Evolution: **remoção PARCIAL** (tarefa 3.6 · DEC-14)

O usuário reverteu o DEC-13.4: **o login por WhatsApp fica**. Saiu o módulo de
**atendimento** (chats, grupos, inbox de mensagens); ficou o mínimo do **pareamento +
envio**, que é o que o código de login exige.

#### Os 7 endpoints de auth continuam intactos
`values: %w[email whatsapp]` em `code_validation.rb:27`, `magic_login.rb:25,70,106` e
`registration.rb:60,91,120` — **nenhum foi tocado** (a `tasks.md` fala em 6; são 7
declarações em 3 arquivos).

**Apagado — endpoints**
- `api/whats/v1/{chats,groups,messages}.rb` (mais os `namespace` correspondentes em
  `whats/v1/base.rb`)
- o recurso `messages-upsert` de `api/whats/v1/webhooks.rb` — era o funil de entrada de
  **lead** + **intake do blog** + **transcrição de áudio**, tudo removido nos blocos 2/3

**Apagado — services**
`polemk_chat_service.rb`, `polemk_group_service.rb`, `whats_message_service.rb`,
`whatsapp_notification_service.rb`

**Apagado — models e dados**
`polemk_chat_message.rb`, `polemk_instance_group.rb`, as migrations
`20250529235826_create_polemk_instance_groups` e `20250530160553_create_polemk_chat_messages`,
e as 2 tabelas do `schema.rb`

**Apagado — 13 specs/factories** (chats, grupos, mensagens, notificação, os 2 models e as
2 factories, mais `webhooks_{blog,group}_intake_spec.rb`, que testavam o `messages-upsert`)

**Editado — `evolution_connection.rb` (MANTIDO)**
Saíram `create_group` (que criava `PolemkInstanceGroup`, ~linha 156, incluindo o
`updateGroupPicture` e o `updateParticipant` hardcoded), `check_number`
(`/chat/whatsappNumbers`, só o `PolemkChatService` usava) e `get_media_base64`
(`/chat/getBase64FromMediaMessage`, só o `messages-upsert` e o
`ProcessAudioTranscriptionJob` usavam). **Ficaram intactos** `instance`, `instance_name`,
`send_message`, `send_media`, `set_webhook`, `list_webhooks` e o ciclo de vida da instância.

**Editado — outros**
- `app/services/whats_app_webhook_service.rb` — só o `ensure_default_group_for_instance`
  (criava o grupo padrão via `PolemkInstanceGroup`) e a chamada dele na linha 196
- `app/controllers/api/entities/polemk_instances.rb` — a exposição `messages`
  (últimas 50 `PolemkChatMessage`)
- `app/models/polemk_instance.rb` — as `has_many :polemk_instance_groups` e
  `:polemk_chat_messages` (+ as 2 asserções no `spec/models/polemk_instance_spec.rb`)
- `app/services/asaas_{charge,payment}_webhook_service.rb` (**AI9-001, Bloco 4**) —
  as 2 chamadas a `WhatsappNotificationService.send_sales_notification` (a de `charge`
  levava junto o `begin/rescue` que só existia para ela). **Tinha de sair agora**: o
  service deixou de existir e esses webhooks vivem até o Bloco 4. Os 3 specs de Asaas que
  estubavam a chamada foram ajustados.
- `frontend/src/lib/api/endpoints.ts` — `chatsApi` (só `checkNumber`; **zero
  consumidores** no `src/`)
- `frontend/src/app/pages/WhatsappPage.tsx` (**MANTIDA**) — o card "Mensagens", que lia
  `instanceInfo.instance.messages` (a exposição apagada acima)

#### O que NÃO saiu — e por quê (2 recusas com evidência)

**1. `whats_app_webhook_service.rb` FICA.** A `tasks.md` mandava remover. **O nome engana:
não é o webhook de atendimento.** Os 3 métodos públicos são
`process_connection_update`, `process_logout_instance` e `process_qrcode_updated` — ou seja,
é o serviço que:
- grava `qr_code`, `qr_expires_at`, `qr_session` e `connection_status` na `PolemkInstance`;
- faz o `broadcast` para o `WhatsappInstanceChannel`, que é **exatamente** como a
  `WhatsappPage.tsx` recebe o QR (o comentário na linha 142 da página diz: *"Sem
  polling/auto-connect: QR será atualizado por webhook (QRCODE_UPDATED)"*);
- enfileira o `EvolutionReconnectJob` (`whats_app_webhook_service.rb:193`) — o job que o
  DEC-14 manda manter **não tem nenhum outro gatilho no repo**.

Removê-lo mataria o pareamento por QR e o auto-reconnect — e, com eles, o login por
WhatsApp. Os 3 recursos correspondentes de `webhooks.rb` (`connection-update`,
`logout-instance`, `qrcode-updated`) ficaram pelo mesmo motivo.

**2. `polemk_webhook_service.rb`, o model `PolemkWebhook`, a tabela, a entity e o recurso
`config` de `webhooks.rb` FICAM.** A `tasks.md` mandava remover. Evidência:
`PolemkWebhookService.create_webhook` chama `EvolutionConnection.set_webhook` registrando
os eventos `CONNECTION_UPDATE`, `LOGOUT_INSTANCE` e `QRCODE_UPDATED` no servidor Evolution
— **é assim que o servidor aprende para onde mandar o QR code**. E a tela mantida a usa
diretamente: `WhatsappPage.tsx:302` chama `webhooksApi.config(...)`, e as linhas 117-140 e
321-329 leem `instanceInfo.instance.polemk_webhooks` (a associação `PolemkInstance
has_many :polemk_webhooks`). Sem esse caminho o pareamento não se completa.

> **Consequência a registrar:** o que sobrou do AI9-005 é maior que os ~677 LOC previstos
> pelo DEC-14. Somam-se ao escopo mantido `whats_app_webhook_service.rb` (~290 LOC após a
> poda), `polemk_webhook_service.rb` (89), o model/entity/tabela `PolemkWebhook` e os 4
> recursos de `webhooks.rb`. **Não é escopo a mais por escolha** — é o custo real de manter
> o pareamento por QR, que o próprio DEC-14 reconhece como obrigatório
> (*"sem pareamento, `PolemkInstance.first` é nil e o envio falha"*).

#### Verificação da cadeia de login (leitura de código)

| Passo | Arquivo | Estado |
| ----- | ------- | ------ |
| endpoint pede o código | `api/auth/v1/magic_login.rb:25` | `%w[email whatsapp]` intacto |
| serviço decide o canal | `auth/magic_login_service.rb:94-102` | intacto |
| canal e-mail | `auth/email_service.rb` | **não tocado no bloco** |
| canal WhatsApp | `magic_login_service.rb:100` → `EvolutionConnection.send_message` | intacto |
| resolve a instância | `evolution_connection.rb:15` → `PolemkInstance.first` | intacto |
| pareamento (QR) | `api/whats/v1/instances.rb` + `polemk_instance_service.rb` + `WhatsappPage.tsx` | intactos |
| entrega do QR | `webhooks.rb#qrcode-updated` → `WhatsAppWebhookService` → `WhatsappInstanceChannel` | **mantido (recusa 1)** |
| registro do webhook | `webhooks.rb#config` → `PolemkWebhookService` → `EvolutionConnection.set_webhook` | **mantido (recusa 2)** |
| instância viva | `evolution_reconnect_job.rb`, enfileirado por `whats_app_webhook_service.rb:193` | intactos |
| outros emissores | `auth/pre_register_service.rb:46`, `auth/visitor_signup_with_link_service.rb:146` | intactos |

---

## Referências residuais conhecidas — atualizado pelo Bloco 3

> **Lista viva.** Resolvida e retirada desta tabela pelo Bloco 3: as 3 `description:`
> citando "NavKit" em `db/seeds/brsw_showrooms.rb` — o arquivo inteiro morreu com o AI9-015.

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `backend/db/seeds/niche_plans.rb:83,102,121` | `menu_key: 'showrooms'` em 3 `find_or_create_feature` | Linhas de catálogo de plano (AI9-002); criam `plan_feature`, não referenciam código | Bloco 4 (arquivo inteiro) |
| `backend/db/seeds/plans_and_features.rb:499` | `subtitle` de plano citando "showrooms" | idem — copy comercial | Bloco 4 (arquivo inteiro) |
| `backend/db/seeds/maya_flow.json:67-332` | nó "Ver exemplos (Showroom)" e as arestas dele | Seed de fluxo de **demonstração** do chatbot (AI9-007, mantido). É JSON de conteúdo, não código | Bloco 8 (revisão dos seeds do chat) |
| `backend/db/seeds/triagem_polemk_agent.rb` | prompt de ~180 linhas instruindo `calendar_list_events`/`calendar_create_event` | As chaves `capabilities`/`calendar_access` **já saíram** (o agente cai em `call_simple`); o que resta é prosa do system prompt | Bloco 8 |
| `backend/db/seeds/goat_briefing_agent.rb:6` | comentário citando "Pricing::Engine" | Prosa sobre um funil futuro; `Pricing::Engine` nunca existiu no repo | — (comentário) |
| `backend/app/services/ai/audio_transcription_service.rb` | o service inteiro | **Recusa** — ver "O que NÃO saiu". Consumidor vivo: `ProcessMetaWebhookJob#transcribe_waba_audio` | Bloco 5 |
| `backend/app/services/audio_converter_service.rb` | o service inteiro | **Recusa** — ver "O que NÃO saiu". Consumidor único: `api/v1/operations.rb:250` | Bloco 7 |
| `backend/app/models/support_plan.rb` + `api/v1/support_plans.rb` + service + entity | o CRUD inteiro | Catalogado como **AI9-002**; `Order` era só um consumidor. Sem UI no front | Bloco 4 |
| `backend/app/services/phone_normalizer.rb` (+ `spec/services/phone_normalizer_spec.rb`) | o módulo inteiro | **Ficou sem consumidor** ao fim do bloco: era usado por `SuperadminPhone`, `Whatsapp::AdminAuthResolver` e o callback de `User` — os três saíram com o AI9-004. **Não removi**: é utilitário genérico de normalização de telefone (E.164 + 9º dígito), sem dono de feature, e o Safegold tem campos de telefone. O spec continua passando | — (decisão do Phase 2: virar o normalizador canônico ou sair) |
| `backend/db/schema.rb` — `work_projects`, `work_items`, `work_item_assignees`, `work_item_labels`, `work_cycles`, `work_labels`, `work_states`, `work_time_sessions`, `budgets` | 9 tabelas | **Órfãs pré-existentes**: nenhum model, nenhuma migration, zero referências no código. Entraram no `schema.rb` sem rastro. **Não são do trim** | — (fora do trim; vale uma limpeza separada) |
| `backend/app/services/analytics_service.rb`, `dashboard_kpis_broadcast_job.rb`, `models/purchase.rb`, `components/preview/*`, `MobileMiniKpi`, `PublicEventsChannel` | vários | Herdados dos Blocos 1 e 2 — evidência lá | Blocos 4/6 |
| `frontend/src/app/pages/DashboardPage.tsx` | chama `analyticsApi.dashboard` | Dívida do Bloco 2 | Blocos 4/6 + Phase 2 |
| `.git/hooks/{post-checkout,post-commit}` com CRLF · `.ruby-version` (3.4.9) × `Gemfile` (3.2.3) | — | Defeitos pré-existentes de ambiente | — (fora do trim) |

---

## O que NÃO saiu, de propósito — Bloco 3 (recusas com evidência)

| Item | A `tasks.md` mandava | O que o código diz | Sai em |
| ---- | -------------------- | ------------------ | ------ |
| `backend/app/services/ai/audio_transcription_service.rb` | sair com o AI9-019 | **Consumidor vivo fora do bloco**: `jobs/process_meta_webhook_job.rb:482` (`transcribe_waba_audio`) transcreve os áudios recebidos pelo WABA. Isso é **AI9-009**, que sai no Bloco 5. Apagar agora daria `NameError` em todo áudio recebido por Instagram/WhatsApp Business — e o spec do job **estuba** `transcribe_waba_audio`, então o `rspec` não teria acusado | Bloco 5 |
| `backend/app/services/audio_converter_service.rb` | sair com o AI9-019 | **Nem é do AI9-019**: nenhum arquivo do caminho de transcrição o chama. O **único** chamador do repo é `api/v1/operations.rb:250`, que converte áudio para mp3 no upload de asset — **AI9-014**, Bloco 7. Removê-lo agora degradaria um endpoint vivo para economizar 40 LOC dois blocos antes da hora | Bloco 7 |
| `backend/app/services/whats_app_webhook_service.rb` + os recursos `connection-update`, `logout-instance` e `qrcode-updated` | sair com o AI9-005 | **É o pareamento por QR, não o atendimento.** Grava `qr_code`/`connection_status` na `PolemkInstance`, faz o broadcast para o `WhatsappInstanceChannel` que a `WhatsappPage` escuta, e é o **único** ponto do repo que enfileira o `EvolutionReconnectJob` (linha 193) — job que o próprio DEC-14 manda manter. Remover mata o login por WhatsApp | **nunca** (enquanto o DEC-14 valer) |
| `backend/app/services/polemk_webhook_service.rb`, `models/polemk_webhook.rb` + tabela, `api/entities/polemk_webhook.rb` e o recurso `config` de `webhooks.rb` | sair com o AI9-005 | Registra na Evolution **para onde** mandar `QRCODE_UPDATED` / `CONNECTION_UPDATE` (via `EvolutionConnection.set_webhook`). A tela mantida usa direto: `WhatsappPage.tsx:302` chama `webhooksApi.config`, e as linhas 117-140 / 321-329 leem `instance.polemk_webhooks` | **nunca** (enquanto o DEC-14 valer) |
| `backend/app/models/support_plan.rb` e seu CRUD | — (não estava na fila) | `Order belongs_to :support_plan`, mas o `SupportPlan` é catalogado **AI9-002**. Só a FK `orders → support_plans` saiu do schema | Bloco 4 |
| `frontend/src/features/chat-builder/api/builder.ts` — o campo `capabilities` | — | O backend ainda deriva `assets` / `lead_capture` de `tools_enabled` / `extract_lead` e lê `agent_config['capabilities']`. Só o comentário foi corrigido | — (fica) |

---

## Verificação do Bloco 3

| Verificação | Baseline (medido em HEAD `51a7b686`) | Depois do bloco |
| ----------- | ------------------------------------ | --------------- |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **0 erros** | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | limpo | **limpo, 0 findings** |
| `cd backend && bundle exec rspec` | **1298 examples, 5 failures, 2 pending** | **987 examples, 5 failures, 1 pending** |

**A lista das 5 falhas — idêntica antes e depois. Nenhuma nova:**

| # | Exemplo | Antes | Depois |
| - | ------- | ----- | ------ |
| 1 | `spec/requests/api/v1/users_spec.rb:111` | falha | falha (intocado) |
| 2 | `spec/requests/api/v1/webhooks/meta_spec.rb:87` | falha | falha (intocado) |
| 3 | `spec/services/lead_cross_channel_service_spec.rb:35` | falha | falha (intocado) |
| 4 | `spec/services/operations/embeddings/generate_service_spec.rb:9` | falha | falha (intocado) |
| 5 | `spec/services/users_service_spec.rb:85` | falha | falha (intocado) |

Os **311 examples a menos** são os specs apagados junto com as features. O `pending` que
sumiu estava num spec removido. **Nenhuma das 5 pertence ao escopo deste bloco.**

> **Duas falhas novas apareceram na primeira rodada e foram corrigidas antes do commit:**
> `spec/models/polemk_instance_spec.rb:8` e `:9` (`have_many(:polemk_instance_groups)` e
> `have_many(:polemk_chat_messages)`), porque as duas `has_many` do `PolemkInstance` ainda
> apontavam para models apagados. Corrigido no model e no spec; a rodada seguinte voltou
> às 5 do baseline.

### Login ponta a ponta — conferido por leitura de código

- **E-mail:** `magic_login.rb` → `Auth::MagicLoginService#send_code` → `Auth::EmailService`.
  **Nenhum arquivo desse caminho foi tocado no bloco.**
- **WhatsApp:** `magic_login.rb:25/70/106` (`%w[email whatsapp]` intacto) →
  `magic_login_service.rb:100` → `EvolutionConnection.send_message` →
  `evolution_connection.rb:15` (`PolemkInstance.first`) → instância pareada por
  `api/whats/v1/instances.rb` + `WhatsappPage.tsx`, com o QR entregue por
  `webhooks.rb#qrcode-updated` → `WhatsAppWebhookService` → `WhatsappInstanceChannel`, e o
  webhook registrado na Evolution por `webhooks.rb#config` → `PolemkWebhookService`.
  **Cadeia íntegra.**
- Os outros emissores de código (`auth/pre_register_service.rb:46`,
  `auth/visitor_signup_with_link_service.rb:146`) e os 3 `rescue` de
  `EvolutionConnection::{InvalidResponseError,TimeoutError,ConnectionError}` em
  `magic_login_service.rb:51-56` seguem intactos.

## Notas do bloco 3

1. **Migrations: 40 arquivos apagados**, nenhuma migration de `drop` escrita (regra 4 do
   `design.md`). Saíram do `schema.rb` **23 tabelas** — `agenda_memories`, `showrooms`,
   `orders`, `order_milestones`, `deliveries`, `delivery_items`, `delivery_attachments`,
   `specifications`, `requirements`, `projects`, `pricings`, `access_codes`, `posts`,
   `post_drafts`, `post_tags`, `tags`, `categories`, `comments`, `blog_settings`,
   `blog_intake_sessions`, `superadmin_phones`, `polemk_chat_messages`,
   `polemk_instance_groups` — mais as colunas `users.can_transcribe` e `media.showroom_id`
   e 34 `add_foreign_key`.
2. **Rotas removidas do front:** `/transcript`, `/showrooms`, `/posts`, `/blog-settings`,
   `/admin/blog/configuracoes`, `/admin/blog/admins`, `/admin/blog/fila`, `/blog`,
   `/blog/categoria/:slug`, `/blog/tag/:slug`, `/blog/:slug`. Itens de nav removidos de
   `Sidebar`, `useNavItems` e `Topbar`, e o **modo "blog"** inteiro do `SidebarModeToggle`
   (com a guarda de `localStorage` no `sidebarModeStore`, para quem já o tinha escolhido).
3. **O cron do Sidekiq ficou vazio.** Os 5 jobs agendados (`agenda_briefing`,
   `drive_ingestion`, `publish_scheduled_drafts`, `purge_discarded_drafts`,
   `blog_intake_session_expiry`) eram todos de features removidas neste bloco; sobrou só a
   configuração de Redis. `plan_scarcity_reset_job`, `cleanup_login_codes_job` e
   `meta_token_health_job` **nunca estiveram** nesse hash (se reagendam sozinhos ou são
   manuais) — nada regrediu.
4. **Limpeza de fronteira em features mantidas.** Além do `user.rb` (ver AI9-004) e do
   `tool_executor`/`tool_registry`/`agent_service` (ver AI9-020), saiu o provider de
   credencial `google_calendar` de `api/v1/credentials.rb`, `models/credential.rb`,
   `types.ts`, `CredentialsPage.tsx` e `CreateCredentialModal.tsx` (com o ramo
   `isGoogleCalendar` inteiro): era a única credencial que o `Agenda::Tools::CalendarTool`
   consumia, e oferecê-la na UI depois do AI9-020 seria uma opção que não liga em nada.
   **Consequência a saber:** se houver linha `Credential` com `provider: 'google_calendar'`
   em alguma base, ela passa a falhar na validação ao ser salva.
5. **Ledger:** `AI9-004`, `AI9-015`, `AI9-017`, `AI9-019`, `AI9-020` → `removed`;
   `AI9-005` → `removed (parcial)`, com o escopo mantido descrito na própria linha.
6. **Reversão:** o bloco é um commit único; `git revert` restaura as 5 features inteiras e
   a parte de atendimento do AI9-005.

---

## Bloco 4 — Comercial (24/08/2026)

**Escopo:** AI9-003 (cupons/afiliados) → AI9-001 (Asaas) → AI9-018 (onboarding) →
**refatoração da navegação (4.4)** → AI9-002 (planos/checkout/feature-gating).

**Ordem obrigatória:** a 4.4 vem **antes** da 4.5 porque o menu lateral do console era
montado a partir de `plan_features`. Remover o AI9-002 primeiro deixaria o console inteiro
sem menu.

**Verificação:** ver "Verificação do Bloco 4" no fim desta seção.

> **Nota de método.** Igual aos Blocos 2 e 3: quando o único consumidor de um arquivo
> removido morre **no mesmo bloco**, não editei o consumidor para "compilar no meio do
> caminho" (princípio 6b). Como 4.1–4.5 saem num commit só, a maior parte das amarras
> comerciais morreu junto.

---

### AI9-003 — Cupons e programa de parceiros/afiliados (tarefa 4.1)

**Apagado — backend**
- `app/controllers/api/v1/coupons.rb`, `app/controllers/api/v1/public/coupons.rb`
- `app/controllers/api/v1/partner/dashboard.rb` (o diretório `partner/` inteiro)
- `app/controllers/api/entities/coupon.rb`
- `app/models/coupon.rb`, `app/services/coupon_service.rb`
- Migrations (6): `20251210171740_create_coupons_and_join_table`,
  `20251210171758_add_coupon_to_purchases`,
  `20251210191659_change_plan_id_to_bigint_in_coupons_plans`,
  `20251229140726_add_user_id_to_coupons`,
  `20251229143915_add_commission_to_purchases_and_coupons`,
  `20260402205127_add_show_in_sidebar_to_coupons`
- Specs (6): `factories/coupons.rb`, `models/coupon_spec.rb`,
  `requests/api/v1/coupons_spec.rb`, `requests/api/v1/partner/dashboard_spec.rb`,
  `requests/api/v1/public/coupons_spec.rb`, `services/coupon_service_spec.rb`

**Apagado — frontend**
- `app/pages/admin/CouponsPage.tsx`, `app/pages/CouponRedirectPage.tsx`
- `app/pages/partner/` inteiro (`DashboardPage`, `SalesPage`, `CouponsPage`)
- `components/PartnerMenu.tsx`, `store/couponStore.ts`

**Editado**
- `app/controllers/api/root.rb` — as 2 regex públicas (`/api/v1/coupons/validate`,
  `/api/v1/public/coupons/.*`)
- `app/controllers/api/v1/base.rb` — `namespace :coupons`, `Api::V1::Public::Coupons` e
  `mount Api::V1::Partner::Dashboard`
- `app/controllers/api/v1/users.rb` — os 4 `optional :coupon_*` (create e update)
- `app/services/users_service.rb` — `handle_coupon_association`, o helper `partner?` e as
  2 chamadas
- `app/models/user.rb` — `has_many :coupons`
- `frontend/src/app/App.tsx` — a **rota catch-all `/:code`**, a rota `/coupons`, as 3
  rotas `partner/*` e os 4 `lazy(...)` correspondentes
- `frontend/src/lib/api/endpoints.ts` — `couponsApi`, `couponsAdminApi`
- `frontend/src/lib/api/types.ts` — `Coupon`, `ValidateCouponResponse` e os campos
  `coupon_code` / `coupon_commission_percentage` do `User`
- `frontend/src/app/pages/DashboardPage.tsx` — o card "Cupons mais utilizados", o
  `CouponWidgetMenu` (navegava para `/admin/coupons`) e o `top_coupons` do mock
- `frontend/src/app/pages/UsersPage.tsx` — o bloco "Cupom do Parceiro" (código + comissão),
  as 3 `<option value="partner">`, o badge PARCEIRO e os 2 mocks de parceiro
- `frontend/src/app/pages/LoginPage.tsx` — o redirect `partner` → `/partner/dashboard`

**O papel `partner` saiu junto — com evidência**
`UserType.partner`, `UserType#partner?` e a entrada de seed
`{ name: 'partner', description: 'Parceiro - Acesso ao programa de afiliados' }`.
Os **únicos** usos do papel em todo o repo eram: as 3 telas `partner/*`, o menu do parceiro
(`Sidebar`, `Topbar`, `useNavItems`), o redirect do `LoginPage`, o filtro `%w[og client
partner]` de `users_service.rb` e o CRUD de cupom da `UsersPage`. Todos morreram aqui.
Os níveis de hierarquia de `free` (4) e `visitor` (5) **não foram renumerados** — mexer
neles quebraria linhas existentes.

---

### AI9-001 — Pagamentos e cobranças Asaas (tarefa 4.2)

**Apagado — backend**
- `app/controllers/api/asaas/` inteiro — `base`, `payments`, `invoices`, `sales`,
  `subscriptions`, `webhooks`
- `app/services/asaas_connection.rb`, `asaas_query_service.rb`, `asaas_webhook_service.rb`,
  `asaas_charge_webhook_service.rb`, `asaas_payment_webhook_service.rb`
- `app/services/sales_service.rb`, `app/services/payments/create_charge.rb` (o diretório
  `payments/` inteiro)
- `app/channels/payments_channel.rb`
- `app/controllers/api/entities/sale.rb`
- `db/migrate/20250811175031_add_asaas_to_user.rb` — criava `users.customer_id`,
  `users.subscription_id` e `users.plan_id`; as três eram 100% Asaas/planos
- `db/migrate/20250811164330_add_credit_card_to_user.rb` e
  `20250919224633_add_credit_card_brand_to_user.rb` — as **13 colunas de cartão** de
  `users` (`credit_card_*`, `cardholder_*`). Só o checkout Asaas as escrevia; guardar
  número e token de cartão em coluna aberta sem nenhum consumidor era risco puro
- Specs (10): `requests/api/asaas/**` (2), `services/asaas_*` (6),
  `services/sales_service_spec.rb`, `services/payments/create_charge_spec.rb`,
  `channels/payments_channel_spec.rb`

**Apagado — a dívida do Bloco 2, resolvida aqui**
- `app/services/analytics_service.rb` + `spec/services/analytics_service_spec.rb` +
  `analytics_service_coverage_spec.rb`
- `app/jobs/dashboard_kpis_broadcast_job.rb` + spec

> **Evidência.** O Bloco 2 manteve os dois porque "os consumidores reais são features
> mantidas". Ao abrir de fato: o **único** consumidor de `AnalyticsService` era
> `DashboardKpisBroadcastJob#perform` (`compute_kpis_realtime`), e os **únicos**
> enfileiradores do job eram `asaas_payment_webhook_service.rb:95,148,190` e
> `asaas_charge_webhook_service.rb:49` — ambos AI9-001. Com o Asaas fora, os dois ficaram
> com zero consumidor. Além disso `compute_kpis_realtime` soma `Purchase` + `Subscription`,
> que deixaram de existir.
> **`DashboardChannel` FICOU:** `app/models/lead_message.rb:148` ainda transmite por ele
> (AI9-006, Bloco 6) e 5 telas do front o escutam.

**Apagado — frontend**
- `app/pages/PaymentsPage.tsx`, `components/CreditCardForm.tsx`,
  `app/pages/__tests__/SalesPage.table.test.tsx`

**Editado**
- `app/controllers/api/root.rb` — `mount Api::Asaas::V1::Base`, as 2 regex
  `/asaas/v1/payments/charges`, **o bloco inteiro de autenticação do webhook Asaas**
  (`asaas_webhook_paths` + `ASAAS_CLIENT_ACCESS_TOKEN`) e a descrição do Swagger
- `app/channels/application_cable/connection.rb` — `allow_public_checkout_subscription?`
  (usava `Purchase.by_any_id`; já estava sem chamador desde a morte do `PaymentsChannel`)
- `backend/.env.example` — as 18 ENVs `ASAAS_*` e o cabeçalho "Integration APIs"
- `backend/db/seeds.rb` — o `ClientApplication` de nome `'ASAAS'`
- `backend/spec/spec_helper.rb` — os 4 `add_filter` de arquivos Asaas no SimpleCov
- `frontend/src/lib/api/endpoints.ts` — `paymentsApi`, `salesApi`, `chargesApi`
- `frontend/src/lib/api/types.ts` — `Payment`, `CreatePaymentRequest`, `Sale`

---

### AI9-018 — Onboarding guiado + templates (tarefa 4.3)

**Apagado — backend**
- `app/controllers/api/v1/setup.rb`, `app/controllers/api/v1/onboarding_templates.rb`
- `app/controllers/api/entities/onboarding_template.rb`
- `app/models/onboarding_template.rb`, `app/services/onboarding_templates_service.rb`
- Migrations (4): `20260327194814_add_onboarding_fields_to_plans`,
  `20260327202545_remove_old_onboarding_settings_from_plans`,
  `20260327202635_create_onboarding_templates`,
  `20260327205102_add_toggles_to_onboarding_templates`
- Specs (3): `factories/onboarding_templates.rb`, `models/onboarding_template_spec.rb`,
  `requests/api/v1/setup_spec.rb`

**Apagado — frontend**
- `app/pages/SetupPage.tsx`, `app/pages/AdminOnboardingTemplatesPage.tsx`

**Editado**
- `app/controllers/api/v1/base.rb` — `namespace :setup` e `mount Api::V1::OnboardingTemplates`
- `db/schema.rb` — a tabela `onboarding_templates` e a FK `onboarding_templates → plans`
- `frontend/src/app/App.tsx` — as rotas `setup` e `onboarding-templates` + os `lazy(...)`
- `frontend/src/lib/api/endpoints.ts` — `onboardingTemplatesAdminApi`
- `frontend/src/app/pages/DashboardPage.tsx` — o `import { SetupPage }`, que já era
  **import morto** (nenhum uso no arquivo)
- `Api::Entities::User` — o `expose :has_onboarding` (fazia `Plan.joins(:onboarding_template)`)

---

### Tarefa 4.4 — a navegação deixou de depender de `plan_features`

**O que existia.** Três cópias da mesma lógica de menu, todas derivando os itens de
`user.features[].menu_key` (que o `Api::Entities::User` calculava a partir dos planos
comprados/assinados) e traduzindo via um `MENU_KEY_MAP` duplicado:

| Arquivo | O que fazia | Estado |
| ------- | ----------- | ------ |
| `hooks/useNavItems.ts` | `MENU_KEY_MAP` + `usePlanPreviewStore` + `isOG`/`isPartner` + planos adquiridos | **refatorado** |
| `components/Sidebar.tsx` | uma **segunda** cópia do `MENU_KEY_MAP` e da mesma lógica | **passou a consumir `useNavItems`** |
| `components/Topbar.tsx` | uma **terceira** cópia, com zero importadores desde o Bloco 1 | **removido** |

**Como ficou.** `hooks/useNavItems.ts` virou a fonte única:

```ts
export const CONSOLE_NAV_ITEMS: NavItem[] = [ /* 9 itens fixos */ ]

export function useNavItems(): NavItem[] {
  const { mode: sidebarMode } = useSidebarMode()
  return sidebarMode === 'all'
    ? CONSOLE_NAV_ITEMS
    : CONSOLE_NAV_ITEMS.filter(i => !i.modes || i.modes.includes(sidebarMode))
}
```

Os 9 itens são exatamente as rotas de console que sobraram no `App.tsx`:
`/dashboard`, `/admin/canais`, `/admin/omnichannel`, `/admin/leads`, `/operations`,
`/media`, `/admin/chat/flows`, `/users`, `/admin/credentials`.
**Nada consulta plano, assinatura, compra ou feature.** O filtro por **modo** do
`SidebarModeToggle` (AI9-033, mantido) continua funcionando.

A `Sidebar` virou só renderização: perdeu o `MENU_KEY_MAP`, o `PlanSelector`, o
`usePlanPreviewStore`, os blocos `isOG`/`isPartner`, o dedup por path, o filtro por modo
duplicado e um `console.log` de debug de papel. A `MobileBottomBar` já lia de
`useNavItems` — as duas telas passaram a ver o mesmo menu de graça.

**Ponto de extensão deixado explícito** (comentado no próprio hook): a nav definitiva do
Safegold é **por papel + membership de projeto** (DEC-18, `authorization-matrix.md`) e é
trabalho do **Phase 3**. Para plugá-la basta acrescentar `roles?: string[]` ao `NavItem`,
preencher nos 9 itens e filtrar dentro de `useNavItems()` — **nenhum consumidor muda**.
Nenhum sistema de papéis foi construído agora, de propósito.

**`PermissionsSyncService` — removido, com evidência.** Era o item que a tarefa mandava
"revisar". Revisão feita: os pontos de entrada eram `Purchase` (3×), `Subscription`,
`Auth::CheckoutSessionService` (2×), `PlansService` (2×), `AsaasPaymentWebhookService` e
`POST /api/v1/permissions/sync` — **todos AI9-001/002**. E o mecanismo interno era
`plan.plan_features → PlanFeaturePermission → Permission`. Sem `Plan` ele não tem de onde
tirar permissão nenhuma: não sobra função.

**O que FICOU da infra de permissão** (é o gancho do DEC-18):
- `Permission`, `UserPermission` + tabelas — consumidos por `api/v1/downloads.rb:17,52`
  (AI9-016, **mantido**) e por `GET /api/v1/permissions/me`
- `PermissionsChannel`, `PermissionAuditLog`, `PermissionConflict` + tabelas e entities
- Saiu só o join de plano: model `PlanFeaturePermission` + tabela + FKs, e a coluna
  `permission_audit_logs.plan_id` (a `plans` deixou de existir, então a FK quebraria o
  `db:schema:load`). A migration `20251201170000_create_permissions.rb` foi **editada**,
  não apagada — ela cria 5 tabelas, 4 das quais ficam.

**`ClientRoute` — removido, com evidência.** Era feature-gating puro: bloqueava
`user_type == 'free'`, dava `toast.error('Seu plano atual não permite acesso a esta área.
Atualize seu plano!')` e redirecionava para `/plans-redirect`. Sem planos não há para onde
redirecionar — e `/dashboard` estava **dentro** dele, então apontar o redirect para
`/dashboard` criaria loop infinito. As 7 rotas que ele protegia passaram a depender de
`ProtectedRoute` (autenticação) e, onde já havia, de `OgRoute`/`VisitorRoute` (papel).
**Consequência a saber:** hoje qualquer usuário autenticado alcança `/dashboard`, `/users`,
`/operations`, `/media` e `/admin/omnichannel`. A restrição correta é a do DEC-18 e é do
Phase 3.

---

### AI9-002 — Planos, assinaturas, checkout e feature-gating (tarefa 4.5)

**Apagado — backend (endpoints e entities)**
- `api/v1/{plans,plan_features,my_subscription,checkout,support_plans}.rb`
- `api/auth/v1/checkout.rb` (o `POST /auth/v1/checkout/session`)
- `public/v1/plans.rb` (o catálogo público)
- `api/entities/{plan,plan_feature,purchase,subscription,support_plan}.rb`

**Apagado — models (8) e concern**
`plan.rb`, `plan_feature.rb`, `plan_feature_assignment.rb`, `plan_feature_permission.rb`,
`purchase.rb`, `subscription.rb`, `support_plan.rb`, `user_feature_usage.rb` e
`models/concerns/acts_as_limited.rb` (o registry de recursos limitáveis — **nenhum model
chamava `limitable_as`**; o único leitor era `plan_features_service.rb`).

**Apagado — services (7) e job**
`plans_service.rb`, `plan_features_service.rb`, `subscription_management_service.rb`,
`feature_usage_service.rb`, `support_plans_service.rb`, `auth/checkout_session_service.rb`,
`permissions_sync_service.rb` e `jobs/plan_scarcity_reset_job.rb`.

**Apagado — seeds e scripts (dívida do Bloco 1 e do Bloco 3, INTEIROS)**
`db/seeds/niche_plans.rb`, `db/seeds/plans_and_features.rb`,
`script/update_feature_descriptions.rb`, `script/cleanup_plans.rb`,
`script/upgrade_plans.rb`, `lib/tasks/plans.rake`, `plan_agent_redirect.rb`,
`scratch_plans.rb`, `plans_dump.txt`, `test_features.rb`.
Com os dois seeds morreram as linhas que os Blocos 1 e 3 deixaram de propósito:
`find_or_create_feature("NavKit Spatial UX")`, o `campfire:` e os 3
`menu_key: 'showrooms'` + o `subtitle` citando showrooms.

**Apagado — `db/seeds/goat_briefing_agent.rb`, com evidência**
É seed de **chatbot** (AI9-007, mantido), mas a **primeira coisa** que ele faz é
`planos = Plan.where(is_active: true)` seguido de `abort` se não houver nenhum, e monta o
system prompt inteiro a partir do catálogo de planos e preços. Sem `Plan` ele levanta
`NameError` na carga. A capability dele era `%w[lead_capture checkout]` — e `checkout`
deixou de existir. O `load` correspondente saiu do `db/seeds.rb`.

**Apagado — migrations (23)**
`20250809000001_create_plans`, `20250809000002_create_plan_features`,
`20250809000003_create_plan_feature_assignments`, `20250811000001_create_subscriptions`,
`20250811142320_add_identifier_to_plan`, `20250913003113_create_purchases`,
`20250913010750_add_values_to_plan`, `20250913232948_add_installment_count_to_purchase`,
`20250929163826_add_subtitle_to_plans`, `20250929201607_add_installment_limits_to_plans`,
`20251001130838_update_plans_precision`, `20251003184925_add_site_title_to_plans`,
`20251201172000_add_user_to_purchases`, `20260112231205_create_support_plans`,
`20260116153324_add_smart_id_to_purchases`, `20260312164004_add_details_to_plan_features`,
`20260314134000_add_menu_key_to_plan_features`,
`20260315140000_add_target_plan_identifier_to_chat_flows`,
`20260327201856_remove_build_zip_link_from_plans`, `20260405120000_add_scarcity_to_plans`,
`20260409092137_add_config_to_plan_feature_assignments`,
`20260409133239_add_niche_to_plans`, `20260803150004_add_lead_to_purchases`.

**Apagado — specs (20)**
7 factories, 7 model specs, 6 request specs, 6 service specs (contagem por arquivo:
`factories/{plans,plan_features,plan_feature_assignments,plan_feature_permissions,purchases,subscriptions,support_plans}`,
`models/{plan,plan_feature,plan_feature_assignment,plan_feature_permission,purchase,subscription,support_plan}_spec`,
`requests/api/v1/{plans,plan_features,my_subscription,checkout,support_plans}_spec`,
`requests/api/auth/v1/checkout_spec`, `requests/public/v1/plans_preview{,_niches}_spec`,
`services/{plans_service,plans_service_expanded,plan_features_service,subscription_management_service,support_plans_service,permissions_sync_service}_spec`,
`services/auth/checkout_session_service{,_coverage}_spec`).

**Apagado — frontend (telas e componentes)**
`AdminPlansPage`, `AdminPlanFormPage`, `AdminFeaturesPage`, `CheckoutPage`,
`PlansRedirectPage`, `MobilePlansPage`, `MobilePlanFormPage`, `MobileFeaturesList`,
`PlanSelector`, `UpgradeModal`, `UpgradeRequiredModal`, `ClientRoute`, `Topbar`,
`components/preview/*` (3 componentes + teste), `store/planPreviewStore.ts` (+ teste),
`hooks/usePlanPreview.ts`, `hooks/usePlanFeatures.ts` e 4 testes de tela.

**`SupportPlan` saiu — fecha a recusa do Bloco 3**
O Bloco 3 recusou removê-lo por ser AI9-002 (só a FK `orders → support_plans` saiu).
Saíram agora: `api/v1/support_plans.rb`, `entities/support_plan.rb`, `models/support_plan.rb`,
`services/support_plans_service.rb`, a migration, a tabela, 2 specs, a factory e o bloco
`should_perform_support_plans` do `db/seeds.rb`. Ele nunca teve tela.

**`Purchase` saiu — fecha a recusa do Bloco 2**
O Bloco 2 o manteve porque 2 dos 9 consumidores pareciam ser do AI9-030 (login):
`auth/checkout_session_service.rb` e `Api::Entities::User#purchased_plan_ids`. Revendo com
a regra "quem consome define o dono": o `CheckoutSessionService` é o **pós-checkout do
Asaas** (`payment_id`/`asaas_id`/`subscription_id`) e o `purchased_plan_ids` é insumo do
menu por plano. Os dois são AI9-001/002 e morreram aqui — então o `Purchase` saiu inteiro,
com a tabela, a migration e `PermissionsSyncService.grant_for_purchase`.

**`components/preview/*` saiu — fecha a dívida do Bloco 1**
Eram **7** importadores, não 10 (3 páginas já haviam morrido nos Blocos 1–3):
`PaymentsPage` e `SetupPage` morreram neste bloco; `DashboardPage`, `MediaPage`,
`UsersPage`, `OperationsPage` e `LeadsChatPage` foram **desacopladas**. O desacoplamento
foi barato porque os 3 componentes só produziam saída em modo preview:
`PreviewBadge` e `PreviewCta` retornam `null` quando `!isPreviewMode`, e o
`PreviewInfoCard` estava sempre dentro de um `{isVisitor && ...}`. Bastou remover o badge,
o card e o CTA de cada página — nenhuma lógica de dados foi tocada.

**Editado — fronteira com o chatbot (AI9-007, MANTIDO)**
- `api/v1/chat_flows.rb` + `chat_flows_service.rb` + `models/chat_flow.rb` +
  `entities/chat_flow.rb` — o endpoint `GET /api/v1/flows/by_plan`, o método
  `ChatFlowsService.by_plan`, o scope `for_plan` e a coluna
  `chat_flows.target_plan_identifier` (com a migration e o índice). Escolhia **qual agente
  atende qual plano**; o único consumidor era o `PlanSelector`, que morreu. No front saíram
  `apiClient.getFlowByPlan` e `chatFlowsApi.getFlowByPlan`, e a regex pública de `root.rb`.
- `ai/tools/tool_executor.rb` e `ai/tools/tool_registry.rb` — a tool `send_checkout_link`
  (o `when`, o `execute_send_checkout_link`, a constante `SEND_CHECKOUT_LINK` e a
  capability `'checkout'`). **Tinha de sair agora**: ela fazia `Plan.find_by` e
  `Purchase.create!` — `NameError` em qualquer agente com a capability ligada. Mesma
  lógica que o Bloco 3 aplicou às tools de calendário. O spec do registry foi ajustado.

**Editado — fronteira com o login e usuários (AI9-030, MANTIDO)**
- `app/models/user.rb` — `belongs_to :plan`, `has_many :subscriptions/:purchases/:coupons/
  :user_feature_usages`, o `delegate :identifier, to: :plan` e os 6 helpers de plano
  (`entrepreneur?`, `creator_plan?`, `has_feature?`, `feature_config`, `features_list`)
- `app/controllers/api/entities/user.rb` — `plan_id`, `purchased_plan_ids`,
  `active_subscription_plan_ids`, `has_onboarding`, `features` e os 8 `expose` de cartão
- `app/controllers/api/v1/controller_helpers.rb` — a mensagem do `restrict_visitor_access!`
  deixou de dizer "Upgrade necessário"
- `app/models/user_type.rb`, `app/services/users_service.rb` — ver AI9-003

**Editado — schema (12 tabelas fora)**
`coupons`, `coupons_plans`, `onboarding_templates`, `plan_feature_assignments`,
`plan_feature_permissions`, `plan_features`, `plans`, `purchases`, `subscriptions`,
`support_plans` — mais **12 `add_foreign_key`** e as colunas `users.{customer_id,
subscription_id, plan_id}` + as 13 de cartão, `permission_audit_logs.plan_id` e
`chat_flows.target_plan_identifier`. **Nenhuma migration de `drop` foi escrita** (regra 4
do `design.md`).

---

## Referências residuais conhecidas — atualizado pelo Bloco 4

> **Lista viva.** Resolvidas e retiradas desta tabela pelo Bloco 4: os 3
> `menu_key: 'showrooms'` de `niche_plans.rb`, o `subtitle` de `plans_and_features.rb`, o
> comentário "Pricing::Engine" de `goat_briefing_agent.rb`, `support_plan.rb` + CRUD,
> `analytics_service.rb`, `dashboard_kpis_broadcast_job.rb`, `models/purchase.rb`,
> `components/preview/*` e a dívida da `DashboardPage` com `plan_features` — todos os
> arquivos morreram.

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `backend/db/seeds/maya_flow.json:110,156` | prosa citando "pagamentos Asaas" e "Checkout transparente" | Seed de fluxo de **demonstração** do chatbot (AI9-007, mantido). JSON de conteúdo, não código | Bloco 8 (revisão dos seeds do chat) |
| `backend/db/seeds/{laura_agent,goat_agent}.rb` | system prompt citando "Asaas (pagamentos)" | Idem — prosa de agente de demonstração | Bloco 8 |
| `backend/db/seeds/triagem_polemk_agent.rb` | prompt citando ferramentas de calendário | Herdado do Bloco 3 | Bloco 8 |
| `backend/app/models/lead.rb` + `entities/lead.rb` + `lead_service.rb` + `schema.rb` | as 7 colunas `checkout_*_at` do funil | São marcos do funil do **Lead** (AI9-006), não do checkout de plano | Bloco 6 |
| `frontend/src/app/pages/DashboardPage.tsx` | KPIs de "Total de vendas", "Novas assinaturas", `sales_breakdown`, `conversion_rates` e o mock de visitor | Dívida do Bloco 2 (AI9-010). A fonte de dados já estava morta desde lá; o Bloco 4 só tirou o card de cupons | Bloco 6 + Phase 2 |
| `frontend/src/components/seo/SEO.tsx` | `keywords="checkout, payments, saas..."` | **Órfão desde o Bloco 1** (zero importadores) — componente do site público, não do console | Bloco 8 ou limpeza de órfãos |
| `frontend/src/app/pages/dictionaries.ts` | copy de nicho citando "Asaas" e "planos SAAS" | **Órfão desde o Bloco 1** (zero importadores) — dicionário da landing por nicho (AI9-021/025) | Bloco 8 ou limpeza de órfãos |
| `frontend/src/hooks/useChatActions.ts` | `actions.viewPricing` / `contactSales` | Helpers genéricos de CTA do chat (AI9-007); apontam para **agentes**, não para planos. Usados por `ChatCTA.tsx` | — (ficam) |
| `backend/app/models/permission_audit_log.rb`, `permission_conflict.rb` (+ tabelas e entity) | os models inteiros | **Ficaram sem consumidor** ao sair o `PermissionsSyncService`. Não removi: são a infra de auditoria/conflito de permissão que o DEC-18 vai plugar, e `Permission`/`UserPermission` continuam vivos ao lado | — (decisão do Phase 3, junto com a matriz de autorização) |
| `backend/app/services/phone_normalizer.rb` | o módulo inteiro | Herdado do Bloco 3 — utilitário sem dono | — (Phase 2) |
| `backend/app/services/ai/audio_transcription_service.rb` | o service inteiro | Herdado do Bloco 3 — consumidor vivo em `ProcessMetaWebhookJob` | Bloco 5 |
| `backend/app/services/audio_converter_service.rb` | o service inteiro | Herdado do Bloco 3 — consumidor único em `api/v1/operations.rb:250` | Bloco 7 |
| `backend/db/schema.rb` — 9 tabelas `work_*` / `budgets` | 9 tabelas | Órfãs **pré-existentes** — flag 7 de `upstream-flags.md` | — (fora do trim) |
| `POST /auth/v1/magic_login/request_code` responde 500 (`current_ip` indefinido) | — | **Defeito pré-existente** do AI9-030, escondido por stub de spec — flag 8 de `upstream-flags.md` | — (fora do trim; decisão de quem mantém o ai9) |
| banco de **dev** (`sfg9_dev`) ainda tem as tabelas e colunas removidas | — | Só o banco de **teste** foi recarregado (`RAILS_ENV=test db:schema:load`), que é o que os portões usam. O dev tem dados de trabalho e não foi destruído | — (rodar `db:schema:load` no dev quando convier) |
| `.ruby-version` (3.4.9) × `Gemfile` (3.2.3) · hooks do git em CRLF | — | Defeitos pré-existentes de ambiente | — (fora do trim) |

---

## O que NÃO saiu, de propósito — Bloco 4 (recusas com evidência)

| Item | A `tasks.md` / o catálogo diziam | O que o código diz | Sai em |
| ---- | -------------------------------- | ------------------ | ------ |
| `Permission`, `UserPermission` + tabelas, entities e `PermissionsChannel` | são "infra compartilhada" do AI9-002 | **Consumidor vivo fora do bloco:** `api/v1/downloads.rb:17,52` (AI9-016, **mantido**) checa `UserPermission` para liberar download, e `GET /api/v1/permissions/me` + `Api::Entities::User#permissions` servem o console. Nada disso passa por plano. É também o gancho natural da matriz do DEC-18 | **nunca** (viram a base da autorização do Phase 3) |
| `PermissionAuditLog`, `PermissionConflict` + tabelas | consumidos só pelo `PermissionsSyncService` | Verdade — ficaram órfãos. Mas são **auditoria e conflito de permissão**, não catálogo de plano: o DEC-18 prevê exatamente esse tipo de registro. Apagá-los agora é jogar fora infra que o Phase 3 vai reconstruir. Saiu só a coluna `plan_id` do audit log, que era a única amarra com o AI9-002 | — (decisão do Phase 3) |
| `DashboardChannel` (+ spec) | catalogado junto do `DashboardKpisBroadcastJob` | `app/models/lead_message.rb:148` transmite por ele a cada mensagem de lead (AI9-006), e 5 telas do front o escutam (`DashboardPage`, `LeadsChatPage`, `LeadListDashboard`, `LeadsChatwootTab`, `LeadsGeneralTab`). Só o **job de KPI** morreu | Bloco 6 avalia o resto |
| As 7 colunas `leads.checkout_*_at` e o dicionário de funil de `lead.rb` | parecem "checkout" (AI9-002) | São marcos do funil do **Lead**: `checkout_who_at`, `checkout_identity_at`, `checkout_contract_at`… descrevem passos de um formulário de pedido, e quem os escreve é `lead_service.rb` / `mark_funnel_event!`. Dono é o AI9-006 | Bloco 6 |
| `db/seeds/maya_flow.json`, `laura_agent.rb`, `goat_agent.rb` | citam Asaas/checkout na prosa | São **conteúdo** de fluxo/prompt do chatbot mantido, não código que resolve constante. Nenhum deles referencia `Plan`, `Purchase` ou `AsaasConnection`. O `goat_briefing_agent.rb`, que **referenciava**, saiu | Bloco 8 |
| `frontend/src/components/seo/SEO.tsx` e `app/pages/dictionaries.ts` | têm copy comercial | **Não são do AI9-002**: são resíduo da landing (AI9-021/025), órfãos desde o Bloco 1 — zero importadores. Puxá-los para cá seria pegar arquivo de outro bloco pelo texto | Bloco 8 / limpeza de órfãos |
| `frontend/src/hooks/useChatActions.ts` (`viewPricing`, `contactSales`) | citam "planos"/"preços" | Disparam **agentes de chat** por id (`'pricing'`, `'sales'`), não leem `Plan`. Consumidos por `ChatCTA.tsx` (AI9-007) | — (ficam) |
| `UserType` níveis 4 (`free`) e 5 (`visitor`) | ficariam com buraco no 3 | Renumerar mexeria em `user_types` já gravados e em `higher_than?`. O buraco no nível 3 é inócuo | — |

---

## Verificação do Bloco 4

| Verificação | Baseline (medido em HEAD `64172a12`) | Depois do bloco |
| ----------- | ------------------------------------ | --------------- |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **0 erros** | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | limpo | **limpo, 0 findings** |
| `cd backend && bin/rails zeitwerk:check` | **All is good!** | **All is good!** |
| `cd backend && bundle exec rspec` | **987 examples, 5 failures, 1 pending** | **763 examples, 3 failures** |
| `node node_modules/vitest/vitest.mjs run` (dentro do WSL) | 5 failures | **5 failures — as mesmas** |

**A lista das falhas do `rspec` — subconjunto exato do baseline. Nenhuma nova:**

| # | Exemplo | Baseline | Depois |
| - | ------- | -------- | ------ |
| 1 | `spec/requests/api/v1/users_spec.rb:111` | falha | **PASSA** (ver abaixo) |
| 2 | `spec/requests/api/v1/webhooks/meta_spec.rb:87` | falha | falha (intocado) |
| 3 | `spec/services/lead_cross_channel_service_spec.rb:35` | falha | falha (intocado) |
| 4 | `spec/services/operations/embeddings/generate_service_spec.rb:9` | falha | falha (intocado) |
| 5 | `spec/services/users_service_spec.rb:85` | falha | **PASSA** (ver abaixo) |

**Por que 2 falhas do baseline ficaram verdes.** As duas exercitavam `user.destroy!`
(`UsersService.destroy` e `DELETE /api/v1/users/:id`). O `User` tinha
`has_many :user_feature_usages, dependent: :destroy` — e a tabela `user_feature_usages`
**não existe**: não há migration que a crie e ela não está no `schema.rb` (era um model
órfão do AI9-002). Todo destroy de usuário levantava `ActiveRecord::StatementInvalid`, que
o `rescue StandardError` do service convertia em `success: false`. A associação saiu com o
AI9-002 e o destroy voltou a funcionar. **Ganho real, não mascaramento** — nenhum spec foi
alterado para isso.

Os **224 examples a menos** são os specs apagados junto com as features. As duas correções
acima explicam a diferença de falhas; as 3 restantes são as mesmas do baseline, todas fora
do escopo deste bloco.

**As 5 falhas do `vitest` são pré-existentes e de auth:** 2 em
`hooks/__tests__/useAuth.requestMagicLogin.test.tsx`, 2 em
`features/auth/__tests__/CodeValidation.test.tsx`, 1 em
`features/auth/__tests__/MagicLogin.test.tsx`. Nenhum dos arquivos que elas exercitam
(`MagicLogin.tsx`, `CodeValidation.tsx`, `useAuth.ts`, `authStore.ts`, `lib/api/auth.ts`)
aparece no diff do bloco. **O `vitest` passou a rodar**: o impedimento registrado no
`design.md` (`@rollup/rollup-win32-x64-msvc` ausente) era do Node **do Windows** — dentro
do WSL o `@rollup/rollup-linux-x64-gnu` está instalado e a suíte roda. A única falha que
foi minha (`MobileChatBar > fallback quando rota não mapeada`, por causa da troca do
`DEFAULT_HINT`) foi corrigida antes do commit.

### O console navegando sem `plan_features` — conferido NO BROWSER

Não por leitura. Subi `bin/rails s` + `vite`, autentiquei de verdade (emitindo o refresh
token pelo `Auth::TokenService`, porque o `request_code` está quebrado — flag 8) e li o DOM:

- `Object.keys(user)` do `authStore`, vindo do `Api::Entities::User` real:
  **`features`, `plan_id`, `purchased_plan_ids` e `has_onboarding` não existem mais**
  (`hasFeatures: false, hasPlanId: false, hasPurchased: false, hasOnboarding: false`).
- `document.querySelectorAll('aside nav a')` → **9 links**, exatamente os
  `CONSOLE_NAV_ITEMS`: `/dashboard`, `/admin/canais`, `/admin/omnichannel`, `/admin/leads`,
  `/operations`, `/media`, `/admin/chat/flows`, `/users`, `/admin/credentials`.
- Clique em "Usuários" → navegou para `/users`, a tela carregou dados reais da API e o
  filtro de tipo mostra só "Todos / OG / Cliente" (sem "Parceiro").
- Console do browser: nenhum erro de módulo — só `ERR_CONNECTION_REFUSED` antes de o
  backend subir.

## Notas do bloco 4

1. **Migrations: 36 arquivos apagados**, nenhuma migration de `drop` escrita. Saíram do
   `schema.rb` **12 tabelas** — `coupons`, `coupons_plans`, `onboarding_templates`,
   `plan_feature_assignments`, `plan_feature_permissions`, `plan_features`, `plans`,
   `purchases`, `subscriptions`, `support_plans` — mais 12 `add_foreign_key` e 17 colunas
   (`users.customer_id/subscription_id/plan_id`, as 13 de cartão de `users`,
   `permission_audit_logs.plan_id`, `chat_flows.target_plan_identifier`). Uma migration foi
   **editada em vez de apagada**: `20251201170000_create_permissions.rb`, porque cria 5
   tabelas e 4 delas ficam.
2. **Rotas removidas do front:** `/checkout/:identifier`, `/plans-redirect`, `/payments`,
   `/vendas`, `/plans`, `/plans/new`, `/plans/:id/edit`, `/features`,
   `/onboarding-templates`, `/coupons`, `/setup`, `/partner/dashboard`, `/partner/sales`,
   `/partner/coupons` e a **catch-all `/:code`**. Sem a catch-all, uma URL desconhecida
   agora não renderiza nada em vez de tentar resolver um cupom.
3. **Endpoints removidos:** `/asaas/v1/**` inteiro, `/auth/v1/checkout/session`,
   `/public/v1/plans`, `/api/v1/{plans,plan_features,my_subscription,checkout,support_plans,
   coupons,public/coupons,setup,onboarding_templates}`, `/api/v1/partner/dashboard`,
   `POST /api/v1/permissions/sync` e `GET /api/v1/flows/by_plan`. A allowlist pública do
   `root.rb` perdeu 6 entradas e o bloco de autenticação do webhook Asaas inteiro.
4. **Nenhum spec foi afrouxado para passar.** Os 4 specs editados
   (`user_spec`, `permission_audit_log_spec`, `permissions_spec`, `tool_registry_spec`)
   passaram a afirmar o novo contrato — o de `permissions_spec` agora exige **404** no
   `/sync`, provando que o endpoint sumiu.
5. **Ledger:** `AI9-001`, `AI9-002`, `AI9-003`, `AI9-018` → `removed`. Restam 3
   `to-remove`: AI9-006 (Bloco 6), AI9-009 (Bloco 5) e AI9-014 (Bloco 7).
6. **Reversão:** o bloco é um commit único; `git revert` restaura as 4 features inteiras e
   devolve a navegação por `plan_features`.
7. **Ambiente:** os 17 arquivos que o working tree tinha reescrito em **CRLF** (defeito
   pré-existente, sem mudança de conteúdo — provado com `git diff --ignore-cr-at-eol`
   vazio) foram normalizados para LF **in place** com `sed`, sem `git stash` e sem
   `git checkout`, antes de qualquer edição.

---

## Bloco 5 — Meta / Instagram (24/08/2026)

**Escopo:** `AI9-009` (integrações Meta: automação de comentário, resposta pública, DM
privada, webhooks, saúde do token) + o item **herdado do Bloco 3**
(`ai/audio_transcription_service.rb`).

**Verificação:** ver "Verificação do Bloco 5" no fim desta seção.

> **Nota de método.** Ao contrário dos Blocos 2–4, aqui **não** deu para deixar o
> consumidor morrer junto: os consumidores vivos de `Integration` e `Meta::*` estão em
> arquivos do **AI9-006**, que só sai no Bloco 6. Como cada bloco tem de ficar verde
> sozinho, as **pernas Meta** desses arquivos foram amputadas agora — o que é correto pelo
> dono: o canal Instagram/Messenger/WABA é AI9-009, não AI9-006.

---

### AI9-009 — Integrações Meta (Instagram / Facebook / WABA) (tarefas 5.1 e 5.2)

**Apagado — backend (endpoints)**
- `app/controllers/api/v1/integrations.rb` (426 LOC) — CRUD + os endpoints de teste
  (`test`, `test_private_reply`, `test_private_reply_buttons`, `test_dm`,
  `test_comment_webhook`, `test_dm_inbound`)
- `app/controllers/api/v1/webhooks/meta.rb` (o diretório `webhooks/` inteiro) — verificação
  `GET` + recepção `POST` do webhook da Graph API
- `app/controllers/api/v1/comment_keywords.rb` (110 LOC) — **ver "quem consome define o
  dono" abaixo**

**Apagado — backend (models)**
- `app/models/integration.rb`, `app/models/instagram_comment_keyword.rb`,
  `app/models/instagram_comment_reply_sent.rb`

**Apagado — backend (services e jobs)**
- `app/services/meta/` inteiro (4 arquivos, 1.179 LOC):
  `instagram_comment_automation_service.rb`, `public_comment_reply_service.rb`,
  `private_reply_service.rb`, `send_message_service.rb`
- `app/jobs/process_meta_webhook_job.rb` (555 LOC), `app/jobs/meta_token_health_job.rb`
- `config/initializers/meta_token_health.rb` — agendava o job de saúde do token no boot

**Apagado — backend (migrations e schema)**
- 5 migrations, **todas exclusivas do AI9-009**: `20260310055335_create_integrations`,
  `20260310102602_create_instagram_comment_keywords`,
  `20260310102708_create_instagram_comment_reply_sents`,
  `20260319120001_add_integration_and_operation_to_instagram_comment_reply_sents`,
  `20260323233047_make_bot_id_nullable_on_instagram_comment_reply_sents`
- 3 tabelas fora do `schema.rb`: `integrations`, `instagram_comment_keywords`,
  `instagram_comment_reply_sents`; mais 3 `add_foreign_key`. **Nenhuma migration de `drop`.**

**Apagado — specs (9 arquivos)**
- `factories/{integrations,instagram_comment_keywords,instagram_comment_reply_sents}.rb`
- `models/{integration_spec,instagram_comment_keyword_spec,instagram_comment_reply_sent_spec}.rb`
- `jobs/process_meta_webhook_job_spec.rb` (502 LOC)
- `services/meta/` inteiro (3 arquivos, 686 LOC)
- `requests/api/v1/webhooks/` inteiro — **é onde vivia a 1ª das 3 falhas do baseline**

**Apagado — frontend**
- `app/pages/admin/IntegrationsPage.tsx` (1.170 LOC) — a tela "Canais"
- `app/pages/admin/InstagramSettingsPage.tsx` (159 LOC) — **zero importadores**, órfã
- `components/admin/IntegrationTestModal.tsx` (601 LOC)
- `features/integrations/` inteiro (`CreateIntegrationModal.tsx`)
- `features/chat-builder/components/CommentKeywordsPanel.tsx` (240 LOC) — **zero
  importadores**, órfão

**Editado — backend**
- `app/controllers/api/v1/base.rb` — os `namespace :webhooks` e `namespace :integrations`
- `app/controllers/api/root.rb` — a regex pública do webhook `meta` da allowlist
- `app/models/chat_flow.rb` — as 3 `has_many` da **tarefa 5.2**
  (`instagram_comment_keywords`, `instagram_comment_reply_sents`, `integrations`)
- `app/models/operation.rb` — `has_many :instagram_comment_reply_sents, dependent: :nullify`
  (**não estava na tasks.md** — ver "falhas novas corrigidas antes do commit")
- `app/controllers/api/v1/leads.rb` — o endpoint `POST /leads/:id/private_reply` inteiro
  (64 LOC): buscava `Integration.find_by(platform: 'instagram')` e chamava
  `Meta::PrivateReplyService`
- `app/services/omnichannel/dispatch_service.rb` — **−179 LOC**: os canais `instagram`,
  `messenger` e `waba`, os 3 `dispatch_via_meta_*`, `find_integration`,
  `determine_whatsapp_type`, `effective_bot_id`/`find_bot_from_context`,
  `recipient_id_for_{instagram,messenger}`, `standardize_result` (ficou sem chamador) e a
  exceção `NoIntegrationError`. `BUTTON_CHANNELS`/`TEMPLATE_BODY_LIMIT` ficaram vazias:
  **nenhum** canal restante renderiza botão. Sobraram Evolution e web.
- `app/services/omnichannel/inbound_processor_service.rb` — **−66 LOC**: `find_integration`
  e todo o ramo "bot da integração" / "canal Apenas Humanos" de `find_or_create_session`.
  Sem `Integration.bot_id` não existe canal vinculado a um bot nem canal só-humano; a
  escolha de flow passa a ser **keyword match → flow default**, como já era no widget.
- `app/jobs/process_inbound_reply_job.rb` — comentário citando `ProcessMetaWebhookJob`
- `lib/tasks/export_startpoint.rake` — ver "defeito herdado do Bloco 4", abaixo
- `.env.example` — o bloco `META_WEBHOOK_VERIFY_TOKEN` (6 linhas de comentário + a chave)
- `docs/META_CAPI_SETUP.md` **apagado** — documentava `FACEBOOK_PIXEL_ID` /
  `FACEBOOK_ACCESS_TOKEN` do Meta CAPI, que morreu com o AI9-010 no Bloco 2. Varredura no
  repo inteiro: as duas ENVs não aparecem em nenhum arquivo de código

**Editado — frontend**
- `app/App.tsx` — o `lazy(IntegrationsPage)` e as rotas `admin/integrations` e
  `admin/omnichannel`
- `hooks/useNavItems.ts` — o item **"Canais"** (`/admin/omnichannel`) e o ícone `Share2`.
  O menu do console vai de **9 para 8** itens
- `lib/api/endpoints.ts` — o `integrationsApi` inteiro (132 LOC, 9 métodos) e
  `leadsApi.privateReply`
- `lib/api/types.ts` — `Integration`, `IntegrationProvider`, `IntegrationPlatform`,
  `IntegrationStatus`, `CreateIntegrationRequest`, `UpdateIntegrationRequest`,
  `CommentKeyword`, `CreateCommentKeywordRequest`, `UpdateCommentKeywordRequest`
- `app/pages/LeadsChatPage.tsx` — o modo **Private Reply**: o banner de lead de comentário,
  o toggle, a `privateReplyMutation`, o estado `privateReplyMode` e os 3 ramos de
  `if (privateReplyMode)` no input/botão de enviar. O import `Reply` do lucide

**Editado — specs**
- `spec/services/omnichannel/dispatch_service_spec.rb` — saíram os 4 contextos Meta
  ("with an Instagram lead", "with a Messenger lead", "with Instagram lead but no
  integration", "when Meta API returns an error") e a expectativa
  `expect(Meta::SendMessageService).not_to receive(:call)`. **Os contextos de Evolution,
  web, mídia, erro e compatibilidade continuam intactos**
- `spec/services/omnichannel/quick_replies_degrade_spec.rb` — saiu o contexto "Instagram"
  (era o único que testava **manter** os botões). Ficou o caso do **rebaixamento**, que é o
  comportamento que não pode regredir

---

### AI9-019 (herdado do Bloco 3) — `ai/audio_transcription_service.rb`

Apagado. O Bloco 3 recusou removê-lo porque `process_meta_webhook_job.rb:482` transcrevia o
áudio recebido pelo WABA com ele. Com o job apagado nesta tarefa, a varredura
`AudioTranscriptionService|Ai::AudioTranscription` no repo inteiro (backend + frontend)
**não devolve nenhuma linha**. 125 LOC.

---

## "Quem consome define o dono" — 3 arquivos que o catálogo pôs no lugar errado

| Arquivo | Onde estava catalogado | O que o código diz | O que fiz |
| ------- | ---------------------- | ------------------ | --------- |
| `app/controllers/api/v1/comment_keywords.rb` | **AI9-007** (`ai9-feature-selection.md:38` lista `api/v1/{chat,chat_flows,flow_executions,comment_keywords}.rb` como chatbot) | As 4 rotas operam **exclusivamente** sobre `bot.instagram_comment_keywords`. Sem o model, o arquivo não faz nada. Bônus: **não está montado em `base.rb`** — é endpoint morto desde antes do trim | Removido no Bloco 5 |
| `features/chat-builder/components/CommentKeywordsPanel.tsx` | `features/chat-builder/` = AI9-007 | Renderiza CRUD de `CommentKeyword` (Instagram). **Zero importadores** — nenhuma tela do chat-builder o monta | Removido no Bloco 5 |
| `app/pages/admin/IntegrationsPage.tsx` na rota `/admin/omnichannel` | a rota se chama "omnichannel" (AI9-006) | O componente é **o mesmo** `IntegrationsPage` catalogado em AI9-009, montado em duas rotas. Era a tela de tokens da Graph API | Removido no Bloco 5, com as duas rotas |

---

## Defeito herdado do Bloco 4, corrigido de passagem

`lib/tasks/export_startpoint.rake:7` montava
`[Credential, Integration, ClientApplication, Operation, SupportPlan, Plan, PlanFeature,
PlanFeatureAssignment, ChatFlow]`. **`SupportPlan`, `Plan`, `PlanFeature` e
`PlanFeatureAssignment` foram apagados no Bloco 4** e a referência ficou pendurada. O
`next unless defined?(model)` que existe logo abaixo **nunca protegeu nada**: o `NameError`
acontece ao montar o array literal, antes do loop. A task já estava quebrada em `ecee2f3f`.
Como eu tinha de editar o arquivo de qualquer forma (para tirar o `Integration`), tirei os
4 mortos junto e registrei aqui. `Operation` sai no Bloco 7.

---

## Falhas novas que apareceram e foram corrigidas ANTES do commit

| Falha | Causa | Correção |
| ----- | ----- | -------- |
| `spec/requests/api/v1/operations_spec.rb:55` (DELETE operation) | `app/models/operation.rb:8` tinha `has_many :instagram_comment_reply_sents, dependent: :nullify` — apontando para uma tabela que acabara de sair do `schema.rb`. Todo `operation.destroy` levantava `ActiveRecord::StatementInvalid` | Associação removida |
| `spec/services/operation_service_spec.rb:82` (destroy operation) | Mesma causa | Mesma correção |

**A `tasks.md` não menciona esta associação** — a tarefa 5.2 só cita as 3 do `chat_flow`.
Um `Operation` sem ela é o estado correto: a dedupe de reply de comentário é 100% AI9-009.

---

## O que NÃO saiu, de propósito — Bloco 5 (recusas com evidência)

| Item | Por que parecia AI9-009 | O que o código diz | Sai em |
| ---- | ----------------------- | ------------------ | ------ |
| `config/initializers/devise.rb` (`config.omniauth :facebook`) e `OAUTH_FACEBOOK_REDIRECT_URI` no `.env.example` | citam Facebook/Meta | É **OAuth de login** (AI9-030, **mantido**) — `api/auth/v1/oauth.rb`. Nada a ver com a Graph API de páginas/Instagram. **Instrução explícita de não tocar em autenticação** | **nunca** |
| `Operation#private_reply_enabled` / `private_reply_messages` / `private_reply_dm_text` / `private_reply_dm_buttons` (colunas, entity, `OperationsPage.tsx`) | são a configuração das DMs de Private Reply do Instagram | Ficaram **órfãs** ao sair o `Meta::PrivateReplyService`, mas moram na tabela `operations` e no CRUD de `Operation` — puxá-las agora seria abrir a migration do AI9-014 dentro do Bloco 5, com o resto de `Operation` ainda de pé | **Bloco 7** (o `Operation` inteiro) |
| `source_type: 'instagram'` em `Lead`, `Canal::SOURCE_TYPES_CONHECIDOS`, `Identificavel#ig_username`, `lead_cross_channel_service.rb`, `db/seeds.rb` e o badge do `LeadsChatPage` | contêm a palavra "instagram" | É a **origem do lead** (AI9-006), não a integração Meta: string de catálogo, não chamada de API. `Canal` lista `site chat terminal whatsapp instagram manychat facebook` — o `manychat` prova que a lista é de procedência, não de integração | **Bloco 6** |
| `ACK_CHANNELS = %w[instagram messenger facebook whatsapp waba]` em `ai/tools/tool_executor.rb` | lista plataformas Meta | É a lista de canais **assíncronos** que recebem a mensagem de espera do agente (o widget do site tem indicador de digitação próprio). É AI9-007, e o Bloco 8 é quem mexe em `tool_executor` | **Bloco 8** |
| `db/seeds/{laura_agent,laura_flow.json,triagem_polemk_agent,goat_canais}.rb` | a prosa dos agentes de demonstração vende "comment-to-DM no Instagram" | **Conteúdo**, não código: nenhum resolve `Integration`, `Meta::*` ou `InstagramComment*`. Mesma decisão que o Bloco 4 tomou para `maya_flow.json` / `goat_agent.rb` | **Bloco 8** (revisão dos seeds do chat) |
| `src/locales/en/translation.json` ("WhatsApp Integration", "Complete Asaas integration"…) | a palavra "integration" | Copy da **landing** (AI9-021/025), órfã desde o Bloco 1 | Bloco 8 / limpeza de órfãos |

---

## Referências residuais conhecidas — atualizado pelo Bloco 5

> Resolvidas e retiradas da lista do Bloco 4 pelo Bloco 5:
> `ai/audio_transcription_service.rb` (o consumidor morreu aqui) e a linha de
> `lib/tasks/export_startpoint.rake` com os 4 models do AI9-002.

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `backend/app/models/operation.rb` + `entities/operation.rb` + `OperationsPage.tsx` + `schema.rb` | as 4 colunas `private_reply_*` de `operations` | Órfãs desde o Bloco 5; moram na tabela do AI9-014 | Bloco 7 |
| `backend/app/services/omnichannel/dispatch_service.rb` | `BUTTON_CHANNELS` / `TEMPLATE_BODY_LIMIT` vazias e o parâmetro `bot_id` sem uso | O service inteiro é AI9-006 | Bloco 6 |
| `tools/graphify/semantic-layer.json` | nós `FACEBOOK_PIXEL_ID`, `FACEBOOK_ACCESS_TOKEN`, "Meta Conversions API" | Artefato do **grafo**, não código da app. O `backend/docs/META_CAPI_SETUP.md` que os documentava foi apagado neste bloco (órfão do AI9-010 desde o Bloco 2) | — (fora do trim) |
| `LoginCode.mask_destination` não existe → `request_code` responde 500 ao bater o teto de envio | — | **Defeito pré-existente** do AI9-030 — flag **9** de `upstream-flags.md`. Não corrigido por instrução explícita de não tocar em auth | — (fora do trim) |
| (as demais linhas da tabela do Bloco 4 seguem válidas) | — | — | — |

---

## Verificação do Bloco 5

| Verificação | Baseline (medido em HEAD `ecee2f3f`) | Depois do bloco |
| ----------- | ------------------------------------ | --------------- |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **0 erros** | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | limpo | **limpo, 0 findings** |
| `cd backend && bin/rails zeitwerk:check` | **All is good!** | **All is good!** |
| `cd backend && bundle exec rspec` | **763 examples, 3 failures** | **667 examples, 2 failures** |
| `node node_modules/vitest/vitest.mjs run` (dentro do WSL) | 5 failures (auth) | **5 failures — as mesmas** |

**A lista das falhas do `rspec`. A 1ª das 3 do baseline SUMIU com a feature:**

| # | Exemplo | Baseline | Depois do Bloco 5 |
| - | ------- | -------- | ----------------- |
| 1 | `spec/requests/api/v1/webhooks/meta_spec.rb:87` | falha | **NÃO EXISTE MAIS** — o arquivo saiu com o AI9-009 |
| 2 | `spec/services/lead_cross_channel_service_spec.rb:35` | falha | falha (intocado — AI9-006, Bloco 6) |
| 3 | `spec/services/operations/embeddings/generate_service_spec.rb:9` | falha | falha (intocado — AI9-014, Bloco 7) |

**Nenhuma falha nova.** As 2 que apareceram na primeira rodada
(`operations_spec.rb:55` e `operation_service_spec.rb:82`) foram corrigidas antes do commit
— ver a tabela acima. Os **96 examples a menos** são os 9 arquivos de spec apagados com a
feature mais os contextos Meta podados dos 2 specs de omnichannel.

**Duas intermitências, ambas pré-existentes, ambas confirmadas:**

1. `spec/services/omnichannel/agent_cadence_spec.rb:59` falhou 1 vez em 5 rodadas da suíte
   completa — e falhou também no **worktree do baseline `ecee2f3f`**, com a mesma
   frequência (1 em 6). `tool_executor.rb` não está no diff deste bloco.
2. `spec/requests/api/auth/v1/magic_login_spec.rb:25` passou a falhar **de forma
   determinística** depois de eu rodar a suíte 6 vezes seguidas — é o teto de envio do
   magic code entrando em ação e batendo no `LoginCode.mask_destination` inexistente
   (**flag 9**). Some sozinha 15 minutos depois, ou limpando
   `redis-cli --scan --pattern '*code_request*' | xargs -r redis-cli del`. O número acima
   foi medido com o contador frio.

### O que sobrou de rota, conferido EXECUTANDO

`bin/rails runner` sobre `Api::Root.routes` (145 rotas montadas, aplicação carregada de
verdade): o filtro por `integration|meta|webhook|private_reply` devolve **só** os 6
webhooks de `whats/v1` (AI9-005, mantido parcial, DEC-14). **Nenhuma rota de
`/api/v1/integrations`, `/api/v1/webhooks/meta` ou `/leads/:id/private_reply` sobreviveu**,
e a aplicação sobe sem `NameError` — que é o que o `zeitwerk:check` sozinho não prova para
o Grape, porque as rotas são montadas em tempo de carga do `Api::Root`.

---

## Bloco 6 — Leads e omnichannel (24/08/2026)

**Escopo:** `AI9-006` (lead, jornada, mensagens, canais/origens, inbox, dispatch, inbound) —
**o hub do grafo do ai9** — mais os dois itens **herdados do Bloco 4**: os KPIs de
vendas/assinaturas da `DashboardPage` e as 7 colunas `leads.checkout_*_at`.

**Verificação:** ver "Verificação do Bloco 6" no fim desta seção.

> **A decisão que define este bloco.** `Lead` e `LeadMessage` não eram só o CRM: eram
> também **a persistência de conversa do chatbot** (AI9-007, MANTIDO). `Ai::AgentService`
> lia o histórico de `lead.messages` e gravava cada turno lá; `ChatSession#garantir_lead!`
> criava o lead no primeiro input; `PublicChatService` e `/api/v1/public/chat/*` eram um
> chat de captação inteiro sobre `Lead`.
>
> Optei por **remover o `Lead` de verdade** (model + tabela), e não por mantê-lo como
> armazém de conversa. Motivo: manter significaria importar para o Safegold um model de
> CRM de marketing de 587 LOC com o funil inteiro (`current_stage`, `discovery_level`,
> `enchantment_level`, `closing_level`, `score`, UTMs, ids de anúncio) — exatamente o tipo
> de armadilha semântica que este trim existe para evitar, e o DEC-13.2 já decidiu que o
> chatbot vira **assistente interno** que não captura lead.
>
> **Consequência assumida, e é a maior herança do Bloco 8:** o agente ficou **sem memória
> de conversa**. Não construí um armazém substituto de propósito — escolher onde o
> assistente interno grava o turno a turno (tabela própria? `chat_sessions.context`?
> amarrada ao `User` autenticado, que o lead nunca teve?) é decisão de produto do Bloco 8,
> não efeito colateral de uma remoção. Ver "Herança para o Bloco 8", abaixo.

---

### AI9-006 — Leads e omnichannel (tarefa 6.1)

**Apagado — backend (endpoints e entities)**
- `app/controllers/api/v1/leads.rb` (570 LOC), `lead_messages.rb` (181), `origens.rb` (71)
- `app/controllers/api/v1/public/leads.rb` (74)
- `app/controllers/api/entities/{lead,lead_message,canal}.rb` (279 + 68 + 21)

**Apagado — backend (models)**
- `app/models/lead.rb` (587 LOC), `lead_message.rb` (159), `canal.rb` (89)
- `app/models/concerns/filtravel_por_origem.rb` (65), `identificavel.rb` (131)

**Apagado — backend (services, jobs, canais)**
- `app/services/lead_service.rb` (344), `lead_message_service.rb` (151),
  `lead_cross_channel_service.rb` (473), `lead_sandbox_service.rb` (327)
- `app/services/leads/` inteiro (`upsert_from_chat.rb`)
- `app/services/omnichannel/` inteiro (`dispatch_service.rb`, `inbound_processor_service.rb`)
- `app/jobs/omnichannel_dispatch_job.rb`, `process_inbound_reply_job.rb`
- `app/channels/lead_chat_channel.rb`

**Apagado — backend (o chat público de captação)**
- `app/services/public_chat_service.rb` (215) — criava o lead na primeira mensagem e
  disparava o n8n
- `app/controllers/api/v1/public/chat_callback.rb` (96) — escrevia
  `current_stage`/`discovery_level`/`enchantment_level`/`closing_level` no lead
- `app/controllers/public/` inteiro (`public/v1/chat.rb`) — **um segundo namespace público
  que ninguém tinha catalogado**, montado em `root.rb:117`, três endpoints sobre
  `PublicChatService`
- `app/channels/public_chat_channel.rb` — streamava por `lead.session_uuid`

**Apagado — backend (migrations, tabelas e seeds)**
- 21 migrations exclusivas do AI9-006 (`create_leads`, `create_canais`,
  `level_up_leads_to_padrao_facil`, `goat_alcanca_o_modelo_de_pessoa`,
  `sessao_de_chat_nasce_sem_lead`, `change_lead_messages_id_to_uuid`, as de coluna…)
- 3 tabelas fora do `schema.rb`: `leads`, `lead_messages`, `canais`; mais 2
  `add_foreign_key` e as colunas `chat_sessions.lead_id` e `agent_runs.lead_id`.
  **Nenhuma migration de `drop`.**
- **3 migrations foram EDITADAS em vez de apagadas**, porque criam objetos de features
  mantidas: `20260207213520_create_chat_sessions` (perdeu `t.references :lead`),
  `20260601000002_create_agent_runs` (perdeu `lead_id` + índice) e
  `20260207234044_add_flow_intelligence_columns` (mexia em `chat_flows` **e** em
  `leads.custom_fields`)
- `db/seeds/goat_canais.rb` apagado; o bloco de leads de demonstração de `db/seeds.rb`
  (~350 LOC, 8 leads com mensagens) removido, sobrando só a criação das `Operation`

**Apagado — specs (18 arquivos)**
- `factories/{leads,lead_messages}.rb`
- `models/{lead_spec,lead_message_spec}.rb`, `channels/lead_chat_channel_spec.rb`
- `requests/api/v1/{leads_spec,lead_messages_spec}.rb`,
  `requests/api/v1/public/{leads_spec,chat_spec,chat_callback_spec}.rb`
- `services/{lead_service_spec,lead_service_expanded_spec,lead_message_service_spec,
  lead_cross_channel_service_spec}.rb` — **a 2ª das 3 falhas do baseline vivia aqui**
- `services/leads/upsert_from_chat_spec.rb`, `services/omnichannel/` inteiro (4 arquivos),
  `services/public_chat_service_spec.rb`
- `requests/chat_lead_no_primeiro_input_spec.rb`
- `spec/jobs/test_webhook.rb` — **não era spec**: script solto que chamava
  `ProcessMetaWebhookJob` (apagado no Bloco 5) e contava `Lead`/`LeadMessage`. Resíduo que
  o Bloco 5 deixou passar

**Apagado — frontend**
- `features/leads/` inteiro (`LeadsPage`, `LeadListDashboard`, `LeadsGeneralTab`,
  `chatwoot/` com 4 arquivos, `components/MobileLeadsChat`)
- `components/leads/` inteiro (6 componentes + `flow/LeadFlowEditor` + 8 nós de fluxo)
- `app/pages/LeadsChatPage.tsx`, `app/pages/admin/CanaisPage.tsx` (+ o teste dela)
- `features/chat-builder/components/SaveToLeadNode.tsx`
- `components/alerts/AnomalyAlerts.tsx`, `features/metrics/invalidateAnalytics.ts`,
  `app/pages/admin/MobileMiniKpi.tsx` — os três **órfãos do AI9-010** desde o Bloco 2

**Editado — backend**
- `app/controllers/api/v1/base.rb` — os mounts de `Leads`, `LeadMessages`, `Origens`,
  `Public::Leads` e `Public::ChatCallback`
- `app/controllers/api/root.rb` — a regex pública `^/api/v1/public/leads.*$`, o
  `mount Public::V1::Chat` e a prosa do bloco anti-bypass
- `app/controllers/api/v1/public/chat.rb` — saíram `GET session`, `GET messages` e
  `POST message`; ficaram `resolve_assets` (AI9-014) e `routing` (AI9-007)
- `app/controllers/api/v1/flow_executions.rb` — `lead_name`/`lead_email` e os
  `includes(:lead)`
- `app/models/operation.rb` — `has_many :leads` e `#update_leads_count!` (o único
  escritor da coluna `leads_count`)
- `app/services/operation_service.rb` — `total_leads` e `operations_distribution` de
  `dashboard_stats`
- `app/services/auth/{visitor_auth_service,visitor_signup_with_link_service}.rb` —
  o `create_or_update_lead` dos dois. **São arquivos de AUTH (AI9-030, mantida)**, mas o
  método era CRM puro: criava um `Lead` com `current_stage: 'discovery'` a cada login de
  visitante. Nada da cadeia de autenticação foi tocado
- `lib/tasks/export_startpoint.rake` já tinha sido corrigido no Bloco 5

**Editado — o chatbot (AI9-007, mantido) — o mínimo para os portões**
- `app/models/chat_session.rb` — `belongs_to :lead` e `garantir_lead!`
- `app/controllers/api/v1/chat.rb` — `Lead.by_any_id`, o merge de metadata no lead, o
  `garantir_lead!` do `POST /chat/input`, os params `tracking_session_id`/`visitor_id` e o
  `lead_id` da resposta. **A reutilização de sessão saiu junto**: era indexada pelo lead
  (`ChatSession.where(lead: lead)`), e `where(lead: nil)` casaria com qualquer sessão órfã
  — entregaria a conversa de um estranho. Agora é sempre sessão nova
- `app/services/ai/agent_service.rb` — `save_message`, `build_history`, `lead_id`/`channel`
  do `AgentRun`, o auto-login por e-mail do lead no redirect e a capability `lead_capture`
- `app/services/ai/tools/tool_registry.rb` — a capability `lead_capture` inteira
  (`CAPTURE_LEAD` + `REDIRECT_TO_DASHBOARD`)
- `app/services/ai/tools/tool_executor.rb` — `execute_capture_lead`,
  `execute_redirect_to_dashboard` e o `send_lookup_ack` com `DEFAULT_ASSET_ACKS`/
  `ACK_CHANNELS` (a mensagem de espera era despachada ao **canal do lead** e persistida
  como `LeadMessage`)
- `app/services/ai/nodes/{input,base_node,redirect}.rb` — `update_lead_if_matching`, o
  fallback de `{{variavel}}` para atributo do lead e o fallback de e-mail
- `app/services/ai/flow_engine.rb` — o tipo de nó `save_to_lead`
- `app/services/ai/telemetry.rb` — o campo `lead:` do resumo do `AgentRun`

**Editado — frontend**
- `app/App.tsx` — as rotas `admin/leads` e `admin/canais` e os 2 `lazy(...)`
- `hooks/useNavItems.ts` — os itens **"Leads"** e **"Origens"**. O menu vai de **8 para 6**
- `lib/api/endpoints.ts` — `leadsApi`, `leadsPublicApi`, `leadMessagesApi`, `origensApi`,
  `analyticsApi`, os tipos `Canal`/`OrigemFamilia` e `lead_name`/`lead_email` das sessões
- `lib/api/types.ts` — `Lead` (63 campos) e `LeadMessage`
- `lib/api/chatFlow.ts` / `hooks/useChatFlow.ts` — o `lead_id` da sessão, o "resume" por
  lead no `localStorage` (`ai9_chat_lead`, `ai9_lead_id`) e os
  `tracking_session_id`/`visitor_id` do input
- `features/chat-builder/` — o nó `save_to_lead` no `ChatBuilderPage`, no `NodesSidebar` e
  no `PropertiesPanel`; o toggle **"Extrair dados de Lead automaticamente"** do
  `AIAgentConfigPanel`; o `extract_lead` do `builder.ts`; e o cartão "Informações do Lead"
  do `ExecutionDetailPage` (virou "Sessão")
- `components/{Layout,SidebarModeToggle,VisitorRoute}.tsx`, `chat/MobileChatBar.tsx` — as
  referências de rota/copy a `/admin/leads`

---

### Herdado do Bloco 4 — a `DashboardPage` (tarefa 6.1)

A tela foi **reescrita para um estado vazio honesto**. Ela era inteiramente montada sobre
`GET /api/v1/analytics/dashboard` — endpoint que **morreu no Bloco 2** com o AI9-010 — e
mostrava KPIs de **vendas** (AI9-001), **assinaturas** (AI9-002) e **leads** (AI9-006):
"Total de Vendas", "Novas Assinaturas", "Leads Convertidos", "Transações", "Vendas
Mensais", "Crescimento de Assinaturas", "Distribuição de Leads", "Resumo de Vendas &
Leads", as duas taxas de conversão e os alertas. Nenhuma das quatro features existe mais.

O caminho de visitante servia um **mock** (`total_sales: 12450.90`, `leads_converted: 28`,
`available_sources: ['Instagram', 'Site', …]`) — números inventados numa tela de produção.

Não inventei indicadores novos: o painel do Safegold nasce dos dados do legado no Phase 2 e
o **DEC-09 é explícito** em não construir dashboard nem série histórica nesta fase.

Saíram junto, por ficarem sem consumidor: `analyticsApi` (3 métodos, incluindo os exports
CSV/PDF de um endpoint morto), `AnomalyAlerts`, `invalidateAnalytics.ts`, `MobileMiniKpi` e
o **`DashboardChannel`** (back + front + spec) — nada publicava em `dashboard:kpis` desde
que o `DashboardKpisBroadcastJob` saiu no Bloco 4, e o último assinante era a própria
`DashboardPage`. O Bloco 4 tinha deixado explícito: "Bloco 6 avalia o resto".

### Herdado do Bloco 4 — as 7 colunas `leads.checkout_*_at`

Resolvidas por absorção: saíram com a tabela `leads` inteira, junto com o dicionário de
funil de `lead.rb` e o `mark_funnel_event!` de `lead_service.rb`. O Bloco 4 tinha razão em
recusar — eram marcos do funil do **Lead**, não do checkout de plano.

---

## Falhas novas que apareceram e foram corrigidas ANTES do commit

| Falha | Causa | Correção |
| ----- | ----- | -------- |
| `zeitwerk:check` → `uninitialized constant Api::V1::Public::ChatCallback` | o `mount` continuava em `base.rb` depois de eu apagar o arquivo | mount removido |
| `spec/models/agent_run_spec.rb:7` | `it { is_expected.to belong_to(:lead).optional }` | expectativa removida (a coluna saiu) |
| `spec/models/operation_spec.rb:5` | `it { is_expected.to have_many(:leads) }` | trocada por `have_many(:operation_assets)` — o describe não podia ficar vazio |
| `spec/services/ai/tools/tool_executor_spec.rb` (4 exemplos) | o `before` estubava `Omnichannel::DispatchService`, que deixou de existir | stub removido |

---

## O que NÃO saiu, de propósito — Bloco 6 (recusas com evidência)

| Item | Por que parecia AI9-006 | O que o código diz | Sai em |
| ---- | ----------------------- | ------------------ | ------ |
| `spec/requests/api/v1/meta_spec.rb` | o nome diz "Meta" | **"Meta" aqui é metaprogramação, não Meta/Facebook**: o arquivo exercita `Api::V1::ControllerHelpers` num `TestApi` montado no próprio spec. Nada a ver com AI9-009 — o Bloco 5 conferiu antes de deixar | **nunca** |
| `components/charts/{RechartsBar,RechartsLine,RechartsPie}.tsx` e `charts/theme.ts` (`LEAD_SOURCE_ORDER`, `leadSourceColor`) | o pie renderiza "distribuição de leads" e a paleta é por fonte de lead | São **wrappers genéricos de gráfico**, sem dependência de nenhuma feature removida. Ficaram órfãos aqui, mas o painel do Safegold (Phase 2) precisa de gráfico, e apagar/reescrever é trabalho daquele painel, não desta remoção. Só a **copy** (`{value} leads`) é resíduo | Phase 2 |
| `components/kpi/KpiCard.tsx` | vinha da `DashboardPage` | **Consumidor vivo fora do bloco:** `FlowListPage`, `MobileFlowListPage` e `ExecutionViewerPage` (AI9-007, mantido) | — (fica) |
| `components/mobile/{MobileKPI,MobileChartCard}.tsx` | KPIs | **Órfãos pré-existentes** (zero importadores desde antes do Bloco 6) — não são meus | limpeza de órfãos |
| `Permission` / `UserPermission` / `PermissionsChannel` | — | Recusa do Bloco 4, ainda válida: `api/v1/downloads.rb` (AI9-016) os usa | **nunca** |
| `app/services/phone_normalizer.rb` | utilitário de telefone, cheirava a lead | Herdado do Bloco 3, sem dono; **não** era consumido por `Lead` (o `Lead` normalizava por conta própria). Continua com 0 consumidores e 1 spec | Phase 2 |
| `useChatActions.ts` (`viewPricing`, `contactSales`) | CTAs de venda | Recusa do Bloco 4, ainda válida: disparam **agentes** por id, não leem plano nem lead | — (fica) |
| `db/seeds/{laura_agent,laura_flow.json,maya_flow.json,triagem_polemk_agent,goat_agent}.rb` | a prosa vende captura de lead e CRM | **Conteúdo** de agente de demonstração; nenhum resolve `Lead`. Mesma decisão dos Blocos 4 e 5 | Bloco 8 |
| `AIChatWidget.tsx` (2.657 LOC) e `publicChat.ts` | falam com `/api/v1/public/chat/*`, que perdeu 3 endpoints | **É o widget do chatbot mantido** (AI9-007) e o DEC-13.2 manda mantê-lo. Reapontá-lo do chat público de captação para o `/api/v1/chat` autenticado é **construir no chatbot** — proibido para mim, e é literalmente a 8.5 | **Bloco 8** |

---

## Herança para o Bloco 8 — o que eu **não** construí, e onde está

| # | O que falta | Onde exatamente | Por quê é do Bloco 8 |
| - | ----------- | --------------- | -------------------- |
| 1 | **Memória de conversa do agente** | `app/services/ai/agent_service.rb`, passo "2/3" (comentário no lugar do antigo `save_message`/`build_history`). `history = []` hoje | Escolher o armazém do assistente interno é decisão de produto (DEC-13.2), não efeito colateral de remover o CRM |
| 2 | **Retomada de sessão** | `app/controllers/api/v1/chat.rb` (`GET /chat/session` cria sempre sessão nova) e `frontend/src/hooks/useChatFlow.ts` (`initSession`) | A chave de retomada era o lead. O assistente interno tem `User` autenticado — o lead nunca teve. É reescrita, não remoção |
| 3 | **`channel` da telemetria** | `agent_service.rb`, `agent_run_attrs` (hoje sem `channel`) | Vinha de `lead.source_type`. O assistente interno tem um canal só (o console); quem definir isso define o valor |
| 4 | **O widget apontando para o caminho autenticado** | `frontend/src/components/chat/AIChatWidget.tsx` + `src/lib/api/publicChat.ts` → `/api/v1/public/chat/{session,messages,message}` (agora 404) | É a 8.5 inteira: "confirmar que o essencial continua vivo … e o widget de chat" |
| 5 | Prosa dos seeds de agente citando lead/CRM/Asaas/Instagram | `db/seeds/{maya_flow.json,laura_agent.rb,laura_flow.json,goat_agent.rb,triagem_polemk_agent.rb}` | Herança acumulada dos Blocos 4, 5 e 6 |

**Já feito por mim, do que estava listado no Bloco 8** (para não ser feito duas vezes):
**8.1** inteira (nó `save_to_lead` no back e no flow builder), **8.2** na parte de `Lead`
(`capture_lead`, `redirect_to_dashboard`, a capability `lead_capture` em `tool_executor` e
`tool_registry`), **8.3** nas colunas `chat_session.lead_id` e `agent_run.lead_id`
(`chat_flow.operation_id` e `agent_run.operation_id` ficam para o Bloco 7) e a maior parte
da **8.4** (`input.rb`, `redirect.rb`, `base_node.rb`, `telemetry.rb`, `agent_service.rb`,
`flow_engine.rb`). Sobrou de 8.4 apenas prosa em comentário.

---

## Referências residuais conhecidas — atualizado pelo Bloco 6

> Resolvidas e retiradas da lista do Bloco 5: as 7 colunas `leads.checkout_*_at`, os KPIs
> da `DashboardPage`, o `DashboardChannel` e `BUTTON_CHANNELS`/`TEMPLATE_BODY_LIMIT` do
> `dispatch_service` (o arquivo inteiro saiu).

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `backend/app/models/operation.rb` + `entities/operation.rb` + `schema.rb` | a coluna `operations.leads_count` (e o `set_default_leads_count`) | Perdeu o escritor (`update_leads_count!`) neste bloco. Mora na tabela do AI9-014 | Bloco 7 |
| `backend/app/models/operation.rb` + `OperationsPage.tsx` | as 4 colunas `private_reply_*` | Herdado do Bloco 5 | Bloco 7 |
| `frontend/src/components/charts/*` + `theme.ts` | wrappers de gráfico órfãos e a copy "N leads" | Genéricos; o painel do Phase 2 precisa deles | Phase 2 |
| `frontend/src/components/mobile/{MobileKPI,MobileChartCard}.tsx` | componentes órfãos | **Pré-existentes** — zero importadores antes do Bloco 6 | limpeza de órfãos |
| `frontend/src/lib/analytics/identidade.ts` (+ teste) | `sessionId()` / `visitorId()` do rastreio | Ficou sem os 2 consumidores (`endpoints.ts` e `chatFlow.ts`) neste bloco. É resíduo do AI9-010 (Bloco 2), não do AI9-006 | limpeza de órfãos |
| `frontend/src/app/pages/dictionaries.ts`, `components/seo/SEO.tsx`, `locales/en/translation.json` | copy da landing | Órfãos desde o Bloco 1 | Bloco 8 / limpeza |
| `backend/app/services/phone_normalizer.rb` | o módulo inteiro | Herdado do Bloco 3, sem dono | Phase 2 |
| `LoginCode.mask_destination` não existe → 500 no teto de envio | — | Flag **9** de `upstream-flags.md` | fora do trim |
| `backend/db/schema.rb` — 9 tabelas `work_*` / `budgets` | inclui `work_projects.lead_id`, que aponta para `users`, não para `leads` | Órfãs **pré-existentes** — flag 7 | fora do trim |
| `.ruby-version` (3.4.9) × `Gemfile` (3.2.3) · hooks em CRLF | — | Pré-existentes | fora do trim |

---

## Verificação do Bloco 6

| Verificação | Depois do Bloco 5 | Depois do Bloco 6 |
| ----------- | ----------------- | ----------------- |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **0 erros** | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | limpo | **limpo, 0 findings** |
| `cd backend && bin/rails zeitwerk:check` | **All is good!** | **All is good!** |
| `cd backend && bundle exec rspec` | **667 examples, 2 failures** | **500 examples, 1 failure** |
| `node node_modules/vitest/vitest.mjs run` (dentro do WSL) | 5 failures (auth) | **5 failures — as mesmas** |

**A lista das falhas do `rspec`. A 2ª das 3 do baseline SUMIU com a feature:**

| # | Exemplo | Baseline `ecee2f3f` | Depois do Bloco 6 |
| - | ------- | ------------------- | ----------------- |
| 1 | `spec/requests/api/v1/webhooks/meta_spec.rb:87` | falha | **NÃO EXISTE MAIS** (Bloco 5) |
| 2 | `spec/services/lead_cross_channel_service_spec.rb:35` | falha | **NÃO EXISTE MAIS** — o arquivo saiu com o AI9-006 |
| 3 | `spec/services/operations/embeddings/generate_service_spec.rb:9` | falha | falha (intocado — AI9-014, Bloco 7) |

**Nenhuma falha nova.** As 6 que apareceram na primeira rodada foram corrigidas antes do
commit (tabela acima). Os **167 examples a menos** são os 18 arquivos de spec apagados com
a feature mais os contextos de captura de lead podados dos specs do chatbot.

### Conferido EXECUTANDO — servidor de pé, `curl` de verdade

Não por leitura. `bundle exec rails s -p 3009` com o schema recarregado, um `ChatFlow`
padrão criado e as chaves de rate limit do Redis limpas:

| Chamada | Resposta | O que prova |
| ------- | -------- | ----------- |
| `GET /chat/session` | **200** + `{"session_id":1,"responses":[{"type":"text","content":"Ola do console"},{"type":"end"}]}` | **O chatbot sobe e roda sem `Lead`.** A sessão nasce, o `FlowEngine` percorre o nó e devolve o payload — sem `garantir_lead!`, sem `belongs_to :lead` |
| `POST /chat/input` `{session_id:1, input:"oi"}` | **201** + `responses` | O turno é processado ponta a ponta. Era o caminho que mais mexi |
| `POST /auth/v1/magic_login/request_code` | **422 `{"error":"Usuário não encontrado"}`** | **O login atravessou a cadeia inteira** — `current_ip`, brute-force, rate-limit e o service. Editei `visitor_auth_service` e `visitor_signup_with_link_service`; a autenticação continua intacta |
| `GET /api/v1/operations` | **401** | O gate de auth continua de pé e o endpoint mantido continua montado |
| `GET /api/v1/leads` | **404** | A feature sumiu de verdade da tabela de rotas |
| `GET /api/v1/canais` | **404** | Idem |
| `GET /api/v1/public/chat/session` | **404** | O chat público de captação sumiu; `resolve_assets` e `routing` continuam |

`Api::Root.routes` foi de **145 para 113** rotas montadas, e o filtro por
`lead|canai|origen|public.chat` devolve **só** `resolve_assets` e `routing`.

**Por que isto importa:** o `zeitwerk:check` carrega as classes, mas não prova que o Grape
consegue montar as rotas nem que um turno de chat atravessa `ChatSession` → `FlowEngine` →
resposta sem tocar num `Lead` que não existe mais. Foi exatamente o erro que custou caro no
Bloco 3 (verificar lendo) e que o Bloco 4 pagou.

---

## Bloco 7 — Operations + base de conhecimento e embeddings (24/08/2026)

**Escopo:** `AI9-014` (`Operation`, `OperationAsset`, `OperationKnowledge`, busca semântica
por `pgvector`) — **a colisão de nome mais perigosa do trim** — mais o item **herdado do
Bloco 3**: `audio_converter_service.rb`.

**Verificação:** ver "Verificação do Bloco 7" no fim desta seção — é o bloco que **zera** o
`rspec`.

> **Por que a colisão importa.** `Operation` no ai9 é um **agrupador de campanha de
> marketing**: tem `keywords`, `leads_count`, `private_reply_messages`, `public_reply_
> messages` e uma base de conhecimento com embeddings. No Safegold, "operação" é **operação
> de crédito estruturado**. Deixar este model de pé seria entregar ao Phase 2 um nome já
> ocupado por outro significado — e um `Operation.find_by(key: ...)` que parece financeiro e
> não é. Agora o nome está livre.

---

### AI9-014 — Operations, assets, conhecimento e embeddings (tarefa 7.1)

**Apagado — backend**
- `app/controllers/api/v1/operations.rb`, `app/controllers/api/v1/public/operation_assets.rb`
- `app/controllers/api/entities/{operation,operation_asset}.rb`
- `app/models/{operation,operation_asset,operation_knowledge}.rb`
- `app/services/operation_service.rb`
- `app/services/operations/` inteiro — `intent_detector_service.rb` (detecção de intenção
  por embedding) e `embeddings/generate_service.rb` (**a 3ª das 3 falhas do baseline vivia
  aqui**)
- `app/jobs/generate_embedding_job.rb`
- `app/services/audio_converter_service.rb` — **herdado do Bloco 3**

**Apagado — migrations, extensão e tabelas**
- 9 migrations, todas exclusivas do AI9-014: `create_operations`,
  `enable_pgvector_extension`, `create_operation_knowledges`, `create_operation_assets`,
  `add_operation_to_chat_flows`, `add_alt_text_to_operation_assets`,
  `add_private_reply_messages_to_operations`, `add_public_reply_messages_to_operations`,
  `add_dm_config_to_operations`
- 3 tabelas fora do `schema.rb` (`operations`, `operation_assets`,
  `operation_knowledges`), 3 `add_foreign_key`, as colunas `chat_flows.operation_id` e
  `agent_runs.operation_id`, e **o `enable_extension "vector"`** — o `pgvector` existia
  só para as duas colunas `embedding vector(1536)`. **Nenhuma migration de `drop`.**
- `20260601000002_create_agent_runs` foi **editada** (perdeu `operation_id` + índice);
  a tabela é do AI9-007. Com isso a **8.3 da `tasks.md` fica cumprida por inteiro**
  (`chat_flow.operation_id` e `agent_run.operation_id` aqui; os dois `lead_id` no Bloco 6)

**Apagado — specs (11 arquivos)**
- `factories/{operations,operation_assets,operation_knowledges}.rb`
- `models/{operation_spec,operation_asset_spec,operation_knowledge_spec}.rb`
- `requests/api/v1/operations_spec.rb`, `requests/api/v1/public/operation_assets_spec.rb`
- `services/operation_service_spec.rb`, `services/operations/` inteiro (2 arquivos)
- `jobs/generate_embedding_job_spec.rb`, `services/ai/tools/asset_search_spec.rb`

**Apagado — frontend**
- `app/pages/admin/OperationsPage.tsx`, `app/pages/admin/OperationManagerPanel.tsx`
- `lib/api/operationAssets.ts`, `hooks/useAssetsResolver.ts`, `lib/assetShortcode.ts`
- `features/chat-builder/components/AssetPicker.tsx`
- `components/chat/MediaPreviewCard.tsx`
- `components/chat/ParsedMessageContent.tsx` — **zero importadores**, órfão que existia só
  para renderizar `[asset:XXX]`

**Editado — backend**
- `app/controllers/api/v1/base.rb` — os mounts de `Operations` e `Public::OperationAssets`
- `app/controllers/api/root.rb` — a regex pública `^/api/v1/public/operation_assets.*$`
- `app/controllers/api/v1/public/chat.rb` — `GET resolve_assets`. **Sobrou só `routing`**
- `app/controllers/api/entities/chat_flow.rb` — `expose :operation_id`
- `app/controllers/api/v1/chat_flows.rb` — os 2 `optional :operation_id`
- `app/services/chat_flows_service.rb` — `:operation_id` dos 2 `params.slice`
- `app/models/{chat_flow,agent_run}.rb` — os `belongs_to :operation`
- `lib/tasks/export_startpoint.rake` — `Operation` da lista de export
- `db/seeds.rb` — a flag `should_perform_operations` e o bloco que criava as 5
  `Operation` de demonstração

**Editado — o chatbot (AI9-007, mantido) — o mínimo para os portões**
- `app/services/ai/flow_matcher.rb` — `match_by_operation` (semântico, via
  `Operations::IntentDetectorService`) e `match_by_operation_keyword` (via
  `Operation#matches_text?`). O `.match` passou a ser **só** o casamento por
  `chat_flows.keywords`, que é do próprio AI9-007
- `app/services/ai/agent_service.rb` — a injeção de `OperationKnowledge` no system prompt
  (era o **RAG do agente**), o `agent_run_attrs[:operation_id]`, a capability `assets` e as
  instruções de tool correspondentes
- `app/services/ai/tools/tool_executor.rb` — `execute_search_operation_assets` e
  `execute_list_all_operation_assets` (busca por `nearest_neighbors`/cosseno sobre
  `OperationAsset`). **O arquivo ficou sem nenhuma tool** — ver a decisão abaixo
- `app/services/ai/tools/tool_registry.rb` — a capability `assets`. `CAPABILITY_TOOLS`
  ficou `{}`

**Editado — frontend**
- `app/App.tsx` — a rota `operations` e o `lazy(...)`
- `hooks/useNavItems.ts` — o item **"Operações"**. O menu vai de **6 para 5**
- `lib/api/endpoints.ts` — `operationsAdminApi` (12 métodos: CRUD + assets + knowledge) e
  as interfaces `OperationAsset`/`OperationKnowledge`
- `lib/api/types.ts` — a interface `Operation` (com os 4 campos `private_reply_*`, que o
  Bloco 5 tinha deixado explicitamente para cá)
- `components/chat/AIChatWidget.tsx` — o resolvedor de shortcodes, os
  `MediaPreviewCard`/`MediaPreviewSkeleton` nos 2 pontos de render, os 4 pares
  `resolvedAssets`/`loadingShortcodes` passados adiante e o `hasOperation` do roteador
- `hooks/useAgentRouter.ts` + `components/layouts/PublicSplitLayout.tsx` — o parâmetro
  `hasOperation` (um agente vinculado a operação não podia ser sobreposto pelo roteador)
- `features/chat-builder/` — o seletor **"Operação Vinculada (Knowledge & Assets)"** do
  `AIAgentConfigPanel` e do `FlowSettingsModal`, o `AssetPicker` do `PropertiesPanel`, e
  todo o estado `operationId` do `ChatBuilderPage` e do `builder.ts`

---

### AI9-019 (herdado do Bloco 3) — `audio_converter_service.rb`

Apagado. O Bloco 3 recusou removê-lo com a evidência de que o **único** chamador do repo
era `api/v1/operations.rb:250` — endpoint que saiu nesta tarefa. Varredura no repo depois
da remoção: `AudioConverter` não aparece em nenhum arquivo.

---

## A decisão sobre `ToolExecutor` e `ToolRegistry` — ficam vazios, de propósito

Com `lead_capture` fora (Bloco 6) e `assets` fora (Bloco 7), **o agente ficou sem nenhuma
ferramenta registrada**. Duas saídas eram possíveis:

1. apagar `ToolExecutor` e `ToolRegistry`;
2. manter os dois como plumbing vazio.

Escolhi **(2)**, e a evidência é o que mora dentro deles: `ToolRegistry.format_specs`
traduz uma spec de tool para os **três formatos de provider** — `input_schema` do
Anthropic, `type: 'function'` da OpenAI e `functionDeclarations` do Google — e o
`agent_service` chama `chat_completion_with_tools` quando há capability. Isso **é** o motor
multi-provider que o DEC-13.2 manda manter; apagá-lo seria jogar fora o mecanismo, não a
feature. Os dois arquivos ficaram com o cabeçalho explicando o estado e são o ponto de
extensão declarado do assistente interno (Bloco 8).

Os specs dos dois foram **reescritos para afirmar o novo contrato**, não afrouxados:
`CAPABILITY_TOOLS == {}`, `definitions_for` ignora capability inexistente em silêncio em
vez de estourar, e `ToolExecutor.execute` devolve `{ success: false, message: 'Unknown
tool' }` para as 4 tools removidas — o que **prova que elas sumiram**.

---

## Falhas novas que apareceram e foram corrigidas ANTES do commit

| Falha | Causa | Correção |
| ----- | ----- | -------- |
| `spec/models/agent_run_spec.rb:9` | `belong_to(:operation).optional` | expectativa removida |
| `spec/services/ai/agent_service_spec.rb` — contexto "RAG Context Injection" (2 ex.) | testava a injeção de `OperationKnowledge` | contexto removido |
| `spec/services/ai/agent_service_spec.rb` — 6 exemplos restantes | o `before` global estubava `GenerateEmbeddingJob`, que deixou de existir | stub removido |
| `spec/services/ai/flow_matcher_spec.rb` — 14 exemplos | `let(:operation)`, `create(:chat_flow, operation:)` e os describes de `match_by_operation` | describes de operação removidos; os de `match`/`match_by_keyword` mantidos intactos |
| `spec/services/ai/tools/tool_executor_spec.rb` — 9 exemplos | testavam as 2 tools de asset | arquivo reescrito para o contrato do despachante vazio |
| `spec/services/ai/tools/tool_registry_spec.rb` — 5 exemplos | esperavam a capability `assets` | arquivo reescrito para o contrato do registro vazio |

---

## O que NÃO saiu, de propósito — Bloco 7 (recusas com evidência)

| Item | Por que parecia AI9-014 | O que o código diz | Sai em |
| ---- | ----------------------- | ------------------ | ------ |
| `app/services/ai/tools/{tool_executor,tool_registry}.rb` | ficaram sem nenhuma tool | É o **motor multi-provider de tool calling** (AI9-007), não a ferramenta. Ver a seção acima | — (ficam) |
| `GET /api/v1/public/chat/routing` | mora no arquivo que perdeu `resolve_assets` | Lê `ChatFlow.where(kind: 'ai_agent')` e `mapped_routes` — é roteamento de **agente por rota**, AI9-007 puro. Conferido executando: responde **200** | — (fica) |
| gems `pgvector` e `neighbor` no `Gemfile` | existiam só para as colunas `embedding` | **Não removi**: mexer no `Gemfile`/`Gemfile.lock` obriga a um `bundle install` que pode travar todo o resto do trim, e uma gem sem uso não é referência pendurada em código. A **extensão** `vector` saiu do `schema.rb`, que é o que importa para carregar o banco | Phase 2 (junto com a decisão de busca semântica no Safegold) |
| `db/seeds/triagem_polemk_agent.rb` (linhas 100-102) | o prompt manda o agente usar `search_operation_assets` / `list_all_operation_assets` | **Conteúdo** de agente de demonstração, mesma decisão dos Blocos 3, 4, 5 e 6 para os outros seeds de prompt. Agora aponta para tools inexistentes — mais um motivo para a revisão dos seeds do chat ser feita de uma vez | **Bloco 8** |
| `config/boot.rb` ("expensive operations") e `handleAddAsset` do `OperationManagerPanel` | contêm a palavra | Falso positivo de grep; o `boot.rb` é comentário do bootsnap e o painel foi apagado | — |

---

## Referências residuais conhecidas — atualizado pelo Bloco 7

> Resolvidas e retiradas da lista do Bloco 6: `operations.leads_count`, as 4 colunas
> `private_reply_*` e `audio_converter_service.rb` — os três arquivos/tabelas morreram.

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `backend/Gemfile` | gems `pgvector` e `neighbor` sem uso | Ver a recusa acima | Phase 2 |
| `backend/db/seeds/{triagem_polemk_agent,laura_agent,laura_flow.json,maya_flow.json,goat_agent}.rb` | prosa de agente citando tools, CRM, Asaas, Instagram e calendário | Conteúdo de demonstração; herança acumulada dos Blocos 3 a 7 | Bloco 8 |
| `backend/app/services/phone_normalizer.rb` | o módulo inteiro, sem consumidor | Herdado do Bloco 3 | Phase 2 |
| `frontend/src/components/charts/*` + `theme.ts` | wrappers de gráfico órfãos | Genéricos; o painel do Phase 2 precisa deles | Phase 2 |
| `frontend/src/components/mobile/{MobileKPI,MobileChartCard}.tsx`, `lib/analytics/identidade.ts` (+ teste), `app/pages/dictionaries.ts`, `components/seo/SEO.tsx`, `locales/en/translation.json` | órfãos de blocos anteriores | Não são deste bloco | Bloco 8 / limpeza de órfãos |
| `backend/app/models/permission_audit_log.rb`, `permission_conflict.rb` | models sem consumidor | Decisão do Phase 3 (DEC-18) | Phase 3 |
| `LoginCode.mask_destination` não existe → 500 no teto de envio | — | Flag **9** de `upstream-flags.md` | fora do trim |
| `backend/db/schema.rb` — 9 tabelas `work_*` / `budgets` | órfãs | Flag **7** | fora do trim |
| `.ruby-version` (3.4.9) × `Gemfile` (3.2.3) · hooks em CRLF | — | Pré-existentes | fora do trim |

---

## Verificação do Bloco 7 — **o `rspec` ZEROU**

| Verificação | Baseline `ecee2f3f` | Bloco 5 | Bloco 6 | **Bloco 7** |
| ----------- | ------------------- | ------- | ------- | ----------- |
| `tsc --noEmit` | 0 erros | 0 erros | 0 erros | **0 erros** |
| `eslint src --ext ts,tsx` | limpo | limpo | limpo | **limpo** |
| `bin/rails zeitwerk:check` | All is good! | All is good! | All is good! | **All is good!** |
| `bundle exec rspec` | **763 ex., 3 falhas** | 667 ex., 2 falhas | 500 ex., 1 falha | **417 ex., 0 falhas** |
| `vitest run` (dentro do WSL) | 5 falhas (auth) | 5 falhas | 5 falhas | **5 falhas — as mesmas** |
| `vite build` | — | — | — | **✓ built in 3.84s** |

**As 3 falhas do baseline sumiram uma a uma, cada uma no seu bloco — que era exatamente o
critério de aceite:**

| # | Exemplo | Feature | Sumiu no |
| - | ------- | ------- | -------- |
| 1 | `spec/requests/api/v1/webhooks/meta_spec.rb:87` | AI9-009 | **Bloco 5** |
| 2 | `spec/services/lead_cross_channel_service_spec.rb:35` | AI9-006 | **Bloco 6** |
| 3 | `spec/services/operations/embeddings/generate_service_spec.rb:9` | AI9-014 | **Bloco 7** |

**Nenhuma falha nova.** As 36 que apareceram na primeira rodada foram todas corrigidas
antes do commit (tabela acima), e **nenhum spec foi afrouxado**: os dois arquivos
reescritos (`tool_executor_spec`, `tool_registry_spec`) passaram a **afirmar o contrato
novo**, incluindo que as 4 tools removidas devolvem `success: false`.

### Conferido EXECUTANDO — servidor de pé, `curl` de verdade

| Chamada | Resposta | O que prova |
| ------- | -------- | ----------- |
| `GET /chat/session` | **200** + `{"session_id":2,"responses":[{"type":"text","content":"Ola do console"},{"type":"end"}]}` | **O chatbot roda sem `Lead` E sem `Operation`.** Sessão, `FlowEngine` e payload intactos |
| `POST /chat/input` | **201** + `responses` | Turno completo ponta a ponta |
| `POST /auth/v1/magic_login/request_code` | **422 `Usuário não encontrado`** | Login intacto depois dos três blocos |
| `GET /api/v1/operations` | **404** | A feature sumiu da tabela de rotas |
| `GET /api/v1/public/chat/resolve_assets` | **404** | O resolvedor de assets sumiu |
| `GET /api/v1/public/chat/routing` | **200** | O que eu **recusei** remover continua servindo |
| `GET /api/v1/media` | **401** | AI9-016 (mantido) vivo atrás do gate de auth |
| `GET /api/v1/flows` | **401** | AI9-007 (mantido) vivo atrás do gate de auth |

`Api::Root.routes`: **145 → 113 → 94** ao longo dos três blocos.

**E o `vite build` completou.** É a prova que faltava do lado do front: o `tsc` valida
tipos, mas não resolve os `import()` dinâmicos das rotas — o build resolve todos e
empacotou 3.84 s sem um único módulo faltando, depois de eu ter apagado 26 arquivos de
frontend nos três blocos.

### O menu do console ao fim dos três blocos

`CONSOLE_NAV_ITEMS` foi de **9 para 5** itens, e cada saída tem uma rota que morreu junto:

| Item | Rota | Saiu no |
| ---- | ---- | ------- |
| Canais | `/admin/omnichannel` | Bloco 5 (AI9-009) |
| Origens | `/admin/canais` | Bloco 6 (AI9-006) |
| Leads | `/admin/leads` | Bloco 6 (AI9-006) |
| Operações | `/operations` | Bloco 7 (AI9-014) |

**Ficaram os 5:** `/dashboard`, `/media`, `/admin/chat/flows`, `/users`,
`/admin/credentials` — exatamente as features mantidas com tela (AI9-033, 016, 007, 030 e
008).

---

## Bloco 8 — Desacoplar o chatbot: AI9-007 fica, **adaptado** (25/08/2026)

**Este bloco é diferente dos sete anteriores.** Os Blocos 1 a 7 removeram 27 features. Este
**não remove nenhuma** — adapta a que fica. O chatbot (`AI9-007`) é uma das 8 mantidas, e o
DEC-13.2 definiu o uso: **assistente de ajuda ao usuário interno, dentro do console. Não
captura lead, não faz marketing.**

O sucesso não se mede por linha apagada. Mede-se pelo assistente **responder ponta a ponta,
executando** — e ele responde. A transcrição está no fim desta seção.

---

### O que eu confirmei que já estava feito (e não refiz)

O agente dos Blocos 5–7 tinha entregado boa parte deste bloco. Conferi item a item antes de
tocar em qualquer coisa:

| Item | Estado real | Como conferi |
| ---- | ----------- | ------------ |
| **8.1** nó `save_to_lead` | ✅ feito | `services/ai/nodes/save_to_lead.rb` não existe; `grep -r save_to_lead` no repo inteiro: **0 ocorrências** (back, catálogo de nós e flow builder) |
| **8.2** ferramentas sobre lead | ✅ feito | `CAPABILITY_TOOLS == {}` no `ToolRegistry`; `lead_capture` (Bloco 6) e `assets` (Bloco 7) fora. Os 2 arquivos ficam vazios de propósito — recusa do Bloco 7, ainda válida |
| **8.3** as 4 colunas | ⚠️ **incompleto** | as colunas saíram, mas o **model não** — ver abaixo |
| **8.4** refs a `Lead` em `services/ai/**` | ⚠️ quase | sobrava prosa em 3 cabeçalhos — ver abaixo |

#### A 8.3 estava marcada como resolvida e não estava

`app/models/agent_run.rb` ainda declarava:

```ruby
belongs_to :lead, optional: true
```

O model `Lead` saiu no Bloco 6. A coluna `agent_runs.lead_id` saiu do `schema.rb` no mesmo
bloco. **A associação sobreviveu aos dois.**

Por que ninguém viu: `belongs_to` é preguiçoso — só resolve a constante `Lead` quando a
associação é **acessada**. Ninguém acessa. Então o arquivo carrega, o `zeitwerk:check` diz
"All is good!", o `rspec` fica verde, e a referência pendurada atravessa dois blocos
inteiros. É exatamente a família do tropeço do `LoginCode.mask_destination` registrado no
Bloco 7: **portão verde não é prova de que o caminho funciona.** Removida aqui.

#### O que sobrou da 8.4: a prosa dos 3 providers

Os cabeçalhos de `google_provider.rb`, `openai_provider.rb` e `anthropic_provider.rb`
diziam, os três, a mesma linha:

```
# Supports tool/function calling for AI lead generation.
```

Corrigida nos três. O que continua com a palavra "lead" em `services/ai/**` é **registro
histórico deliberado** dos Blocos 6 e 7 — comentário explicando o que saiu e por quê. Isso
fica; apagar o registro é perder o rastro.

---

### 1. O histórico de conversa — DEC-20, o coração do bloco

**O problema herdado.** `Lead`/`LeadMessage` eram *também* a persistência de conversa do
chatbot. Saíram com o CRM no Bloco 6 e o `agent_service.rb` ficou com `history = []` fixo:
o assistente não lembrava da mensagem anterior. O agente do Bloco 6 **não improvisou
substituto**, e fez certo — escolher onde o assistente grava a conversa é decisão de
produto, não efeito colateral de remoção.

**A decisão (DEC-20): memória/Redis, sem tabela nova.** Cumprida à risca — **zero
migration para o histórico, zero model, zero tabela.**

`app/services/ai/conversation_memory.rb` (novo):

| Decisão | Valor | Por quê |
| ------- | ----- | ------- |
| **Onde** | `Rails.cache` | Em dev e prod é `ActiveSupport::Cache::RedisCacheStore` — o **mesmo Redis** que o `Rack::Attack` usa como store. Nenhuma dependência nova: se o Redis está de pé para o rate limit, está para isto |
| **Chave** | `ai9:chat:history:u<user_id>:s<session_id>` | Namespace próprio (o store é compartilhado, e operação precisa conseguir limpar só o que é do assistente com `--scan --pattern`). **Inclui o usuário** — ver a seção 5 |
| **TTL** | **2 horas**, deslizante | Piso: a duração de um atendimento de ajuda real — o usuário abre o widget, tenta uma tela, volta e pergunta de novo; 5 ou 15 min fariam o assistente esquecer **no meio**, que é o defeito que a classe existe para corrigir. Teto: o DEC-20 diz "vive na sessão e expira" — TTL longo transformaria o Redis em persistência de conversa por vias travessas, virando a tabela que o DEC-20 recusou, sem índice e sem backup. 2h cobre um turno de trabalho contínuo sem virar armazenamento. Cada escrita renova |
| **Teto** | 40 mensagens, cortando pelo fim | Janela de contexto, **não** retenção: sem ele uma conversa longa estoura o `max_tokens` do provider, e o erro apareceria como resposta truncada, não como erro de memória |
| **Falha** | fail-soft | Redis fora degrada para "agente sem memória" (o comportamento de antes deste bloco) e nunca derruba a resposta |

Em `agent_service.rb`: `history = []` virou `ConversationMemory.history_for(session)` mais
o turno corrente; a gravação acontece **depois** do `extract_options`, de propósito — o que
volta ao modelo no turno seguinte é o texto limpo, porque guardar o marcador `[opcoes: ...]`
cru ensinaria o modelo a repeti-lo como se fosse conteúdo.

#### O que o chatbot perdeu de propósito

Não são omissões. São escolhas registradas no DEC-20, e eu **não** as construí:

| O que | Consequência prática | Por que não é beco sem saída |
| ----- | -------------------- | ---------------------------- |
| **Retomada de sessão** | fechou a aba, a conversa não volta | O `ChatSession` continua existindo e agora tem `user_id`. Retomar é `where(user:).order(:updated_at).first` no dia em que for requisito |
| **Trilha auditável** | não há registro do que o assistente respondeu | Uma `ChatMessage` ligada à `ChatSession` é **aditiva** — não quebra nada do que foi construído agora. Se o assistente passar a orientar decisão de crédito, a trilha vira requisito e o caminho está aberto |

`GET /chat/session` continua criando **sempre** sessão nova. O dono que a sessão ganhou
neste bloco existe para **isolar**, não para retomar.

---

### 2. Telemetria: `channel = 'console'` (DEC-20)

O campo vinha de `lead.source_type` e ficou nulo desde o Bloco 6. Passa a ser a constante
`Ai::AgentService::CHANNEL = 'console'`. Constante e não coluna derivada: o DEC-13.2 define
**um** uso, portanto **um** canal. Enquanto vinha do lead o campo distinguia
landing/WhatsApp/Instagram — nada disso existe mais.

---

### 3. Religar o widget — os 3 endpoints que respondiam 404

O agente do Bloco 6 **recusou corretamente** mexer aqui: reapontar o widget é *construir* no
chatbot. Feito agora.

**O que estava quebrado, e por que ninguém notava.** O `AIChatWidget` tinha dois modos. O
modo `"support"` inteiro estava morto, por três motivos que se somavam:

1. os endpoints `/api/v1/public/chat/{message,messages,session}` saíram no Bloco 6 com o
   AI9-006 (eram o chat público de captação, que criava `Lead` e gravava `LeadMessage`) e
   respondiam **404**;
2. `PublicChatChannel`, que o widget assinava via `useChannel`, **não existe** em
   `app/channels/` — saiu junto;
3. os **4** call sites do widget (`Layout`, `ChatBuilderPage` e os dois do
   `PublicSplitLayout`) passam `mode="flow"`. Nenhum passa `"support"`.

O pior deles não estava nem sob a guarda de modo: um `useQuery(["chat-session-status"])`
chamando `publicChatApi.getSession()` com `enabled: !!isOpen` — **um 404 silencioso a cada
abertura do widget**, cujo resultado (`sessionData`) nunca era lido por ninguém.

| Arquivo | O que mudou |
| ------- | ----------- |
| `lib/api/publicChat.ts` | Perdeu 4 dos 5 métodos: `sendMessage`, `getMessages`, `getSession` (os 3 do chat de captação) e `resolveAssets` (`/public/chat/resolve_assets`, 404 desde o Bloco 7, e **sem nenhum consumidor** no front). Sobrou `getRouting` — AI9-007 puro, não toca em sessão nem em lead, continua **200** |
| `components/chat/AIChatWidget.tsx` | O `mode="support"` saiu inteiro: a query 404, o `useChannel` do canal inexistente, o `sendMutation` morto, `supportMessages`/`backendMessages`, e o tipo da prop virou `mode?: "flow"`. `isLoading={isSending}` (state que nada mais setava) virou `isLoading={isUploading}` |
| `lib/api/chatFlow.ts` | `getPublic`/`postPublic`/`postPublicForm` → `get`/`post`. Os helpers `*Public` mandam `X-Skip-Auth: 1`, que faz o interceptor **não** anexar o access token e **não** tentar refresh no 401 — com o endpoint agora autenticado, a conversa morreria no primeiro access expirado |
| `hooks/useChatFlow.ts` | Recuperação de 404: sessão do `sessionStorage` que pertença a outro usuário (trocou de login na mesma aba) é descartada e outra é aberta, em vez de travar o widget num id inalcançável |

**Conferido no navegador** (Playwright, `vite` + backend de pé): o widget abre, conversa, e
a aba de rede mostra **só** `/chat/session` **200** e `/chat/input` **201**. Nenhum 404,
zero erro de console.

---

### 4. Os seeds de agente — não era prosa velha, era configuração morta

A tarefa pedia "limpar a prosa comercial". Ao abrir os arquivos, o problema era maior:

| Seed | O que o prompt vendia | O que a **configuração** dizia |
| ---- | --------------------- | ------------------------------ |
| `laura_agent.rb` | "plataforma SaaS omnichannel de captura e qualificação de leads", comment-to-DM do Instagram, CRM, Asaas, "agendar demo" | `extract_lead: true` + `tools_enabled: true` |
| `goat_agent.rb` | "boilerplate SaaS definitivo… de Auth a Pagamento (Asaas) e WhatsApp" | `extract_lead: true` + `tools_enabled: true` |
| `triagem_polemk_agent.rb` | portfólio/showroom da Fábrica Polemk, "agendar reunião na agenda oficial" | `extract_lead: true` + `tools_enabled: true`, e o prompt manda chamar `calendar_list_events` / `calendar_create_event` |
| `laura_flow.json`, `maya_flow.json` | "capturar e qualificar leads pelo Instagram e WhatsApp", planos, preço, demo | flows de captação |
| `data_agent_flow.json` | "rastreamento, pixel, UTM" | AI9-010, removido no Bloco 2 |

`extract_lead` mapeava para a capability `lead_capture`, **removida no Bloco 6**.
`tools_enabled` mapeava para `assets`, **removida no Bloco 7**. As `calendar_*` saíram no
**Bloco 3**. Nenhuma das três existe mais no `ToolRegistry` — os seeds configuravam
capabilities inexistentes e mandavam o modelo chamar ferramentas que devolveriam
`success: false`.

Por isso **não** foram reescritos: os 6 arquivos saíram, junto com os 3 blocos
correspondentes de `db/seeds.rb`. Recuperáveis do histórico do git (até `e347376d`) se o
flow de produção do Polemk precisar ser restaurado em outro lugar.

No lugar, **um** agente: `db/seeds/assistente_console_agent.rb`, `is_default: true`, com o
prompt que o DEC-13.2 pede — explica tela, campo e mensagem de erro do console; **não**
vende, **não** fala de plano/preço/demo, **não** pede nome/e-mail/telefone (pedir cadastro
*é* comportamento de captura de lead), **não** agenda reunião, e não dá orientação de
decisão de crédito. Sem `capabilities`: o `ToolRegistry` está vazio de propósito.

---

### 5. Fora do escopo original: **o assistente não tinha dono de conversa**

Levantado pelo coordenador. Confirmei os três pontos no código **e executando** — os três
eram verdade, e se somavam num vazamento real.

#### A evidência

| # | Defeito | Onde | Prova |
| - | ------- | ---- | ----- |
| 1 | **`ChatSession` ficou SEM DONO** | `schema.rb` — só `chat_flow_id`, `current_step_id`, `context`, timestamps | O dono era o `lead`. A 8.3 tirou `chat_session.lead_id` **corretamente**, mas nada ocupou o lugar |
| 2 | **IDOR** | `api/v1/chat.rb:132` e `:211` — `ChatSession.find(params[:session_id])` | Id **inteiro sequencial** vindo do parâmetro, sem nenhuma checagem de dono: trocar o número lia e continuava a conversa de outra pessoa |
| 3 | **O endpoint era PÚBLICO** | `api/root.rb` — `%r{^/api/v1/chat(/.*)?$}` e `%r{^/chat(/.*)?$}` na allowlist | Herança do chat de captação. Confirmado executando: `GET /chat/session` sem token respondia **200** enquanto `/api/v1/media` respondia 401 |

Sobre a contradição que o coordenador mandou resolver: **as duas afirmações eram
verdadeiras ao mesmo tempo.** O comentário do Bloco 6 em `api/v1/public/chat.rb` está certo
— o caminho vivo do assistente **é** o `/api/v1/chat`. O que ele não disse é que esse
caminho, apesar do prefixo `/api/v1`, estava na allowlist pública do `Api::Root`. "Vivo" e
"autenticado" não eram a mesma coisa.

**Por que isto é do Bloco 8 e não do Phase 3:** o DEC-13.2 define o chatbot como assistente
do usuário interno. Assistente interno sem dono de conversa não é refinamento faltando, é a
feature errada. E implementar o histórico chaveado só pela sessão propagaria o vazamento
para a memória da conversa.

#### O que foi feito

| Mudança | Arquivo |
| ------- | ------- |
| As 2 entradas de chat **saíram** da allowlist pública | `app/controllers/api/root.rb` |
| `before { authenticate_user! }` + `helpers Api::V1::ControllerHelpers` | `app/controllers/api/v1/chat.rb` |
| `sessao_do_dono!` → `current_user.chat_sessions.find_by(id:)` → **404**. Substituiu os 2 `ChatSession.find(params[...])` | idem |
| `rescue_from ActiveRecord::RecordNotFound` → 404 (sem ele, `ChatFlow.find` virava **500** no `rescue_from :all` do `Api::Root`) | idem |
| A sessão nasce com dono: `current_user.chat_sessions.create!` | idem |
| Em `/chat/upload`, a checagem de dono foi para **antes** das validações de arquivo | idem |
| `belongs_to :user, optional: true` + comentário do porquê do `optional` | `app/models/chat_session.rb` |
| `has_many :chat_sessions, dependent: :destroy` | `app/models/user.rb` |
| A chave do Redis inclui o usuário | `app/services/ai/conversation_memory.rb` |

**A migration:** `20260824120000_add_user_to_chat_sessions` — `user_id`, índice e FK.
Dois detalhes que custaram tempo e ficam registrados:

- **`type: :uuid` é obrigatório.** `users.id` é `uuid` (`gen_random_uuid()`), não bigint. Um
  `add_reference` sem o tipo é recusado com `PG::DatatypeMismatch: foreign key constraint
  cannot be implemented`.
- **`null: true` de propósito.** As sessões criadas antes desta coluna têm `user_id` nulo.
  Ficam órfãs e inalcançáveis pelo escopo do dono — que é o comportamento certo: não há como
  adivinhar de quem eram.

Isto **não contraria o DEC-20**: o que o DEC-20 descartou foi a tabela de **mensagens**. Uma
coluna numa tabela que já existe é o mínimo para o isolamento existir.

**Por que `/chat/upload` mudou de ordem.** Na ordem original o MIME e o tamanho eram
validados antes da sessão ser buscada. Com `session_id` alheio e arquivo inválido a resposta
era **422** — e 422 diz "sua imagem não presta", o que **confirma que a sessão existe**. Quem
não é dono não pode distinguir sessão inexistente de sessão de terceiro. Medido antes (422) e
depois (404).

---

### O que eu **recusei** fazer — Bloco 8

| Item | Por que parecia trabalho meu | O que o código/medição diz | Fica para |
| ---- | ---------------------------- | -------------------------- | --------- |
| **Remover `Ai::Nodes::Redirect#auto_auth`** | Existia para o chat público de captação: cria/loga um visitante a partir do e-mail no contexto da conversa (`Auth::VisitorAuthService`). Com o assistente autenticado, quem conversa **já está logado** — logar de novo não faz sentido. **Está órfão.** | Mas ele é **configuração de fluxo**, não código morto: um nó `redirect` com `data.auto_auth` no flow builder ainda o dispara, e o flow builder é AI9-007 mantido. Apagar é mudar o contrato do builder, que é decisão de produto — a mesma razão pela qual o Bloco 6 não escolheu o armazém do histórico | Phase 2 |
| **Remover `secure_auth_nodes!`** de `api/v1/chat.rb` | Foi escrito porque "este endpoint é PÚBLICO", e não é mais | O endpoint deixou de ser público, mas o vazamento não era só isso: refresh no **corpo** vai para log de proxy e é legível por XSS, autenticado ou não. Fica, com o comentário corrigido | — (fica) |
| **`PublicSplitLayout.tsx`** (269 LOC) | Usa `publicChatApi` e monta o widget duas vezes | **Órfão pré-existente**: `grep` no `src` inteiro dá **zero** importadores fora dele mesmo. Não é resíduo deste bloco, e apagá-lo é limpeza de órfãos | limpeza de órfãos |
| **Atualizar as listas de modelos OpenAI e Google** | Estão no mesmo array que a lista Anthropic que eu corrigi | **Não medi aquelas APIs.** Corrigi a Anthropic porque bati em `GET /v1/models` com a chave do projeto e vi os 404. Afirmar sobre as outras duas sem medir é exatamente o erro que esta migração já pagou duas vezes | Phase 2 |
| **Escopar `api/v1/flow_executions.rb` por dono** | Faz `ChatSession.find(params[:session_id])` e lista todas as sessões | É o **visualizador de execuções do admin** (`/admin/chat/executions`, atrás de `authenticate!` e de `VisitorRoute`). Escopar por `current_user` quebraria a tela: o ponto dela é ver a execução dos outros. O gate certo é papel, não dono — e mexer nisso é redesenhar a tela | Phase 2 |

---

### Verificação do Bloco 8

| Verificação | Depois do Bloco 7 | Depois do Bloco 8 |
| ----------- | ----------------- | ----------------- |
| `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | 0 erros | **0 erros** |
| `cd frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | limpo | **limpo** |
| `cd backend && bin/rails zeitwerk:check` | All is good! | **All is good!** |
| `cd backend && bundle exec rspec` | 417 examples, **0 failures** | **440 examples, 0 failures** |
| `node node_modules/vitest/vitest.mjs run` | 5 failures (auth) | **5 failures — as mesmas** |

**A lista das falhas do `rspec`: nenhuma.** Segundo bloco consecutivo com a suíte verde.

**Os 23 exemplos a mais** são todos novos e todos afirmam contrato deste bloco:

| Arquivo | + | O que provam |
| ------- | - | ------------ |
| `spec/services/ai/conversation_memory_spec.rb` | 11 | chave com usuário, acúmulo em ordem, corte no `MAX_MESSAGES`, TTL explícito no `write`, sessão órfã não grava, isolamento entre usuários, fail-soft, `clear` |
| `spec/requests/api/v1/chat_spec.rb` | 6 | dono gravado na sessão; **401** sem token em `GET session` e `POST input`; **404** para sessão de outro em `input` e `upload`; sessão órfã inalcançável |
| `spec/services/ai/agent_service_spec.rb` | 6 | `channel = 'console'`; turno corrente chega ao provider; turno gravado; **o 2º turno chega com o 1º junto**; conversa de A não vaza para B; o marcador `[opcoes:]` não volta ao modelo |

> **Nota sobre `:null_store`.** `config/environments/test.rb` usa `cache_store = :null_store`
> — escrita é no-op e leitura devolve nil. Os specs de memória trocam por um `MemoryStore` de
> verdade. Sem isso eles passariam **provando que o null_store não guarda nada**, que é o
> defeito, não o contrato.

**As 5 falhas do `vitest` são as mesmas de sempre, todas de auth e pré-existentes:**
`useAuth.requestMagicLogin` (2), `CodeValidation` (2), `MagicLogin` (1).

---

### Conferido EXECUTANDO — servidor de pé, `curl` de verdade

`bundle exec rails s -p 3009`, dois usuários reais com token, o `assistente-console`
semeado e uma `Credential` Anthropic de verdade.

#### O portão que mais importa: **o assistente lembra**

```
--- A, mensagem 1 ---
> Meu nome e Vinicius e eu estou na tela de Midias.

Oi, Vinicius.
Não tenho a descrição detalhada da tela de Mídias aqui, então prefiro não chutar campo
ou botão que talvez não exista.
O que você precisa fazer nela? Se me disser a ação (subir um arquivo, localizar algo,
entender um erro que apareceu), eu te ajudo com o que tenho ou te aponto quem procurar.

--- A, mensagem 2 ---
> Qual e o meu nome e em que tela eu disse que estou?

Você se apresentou como Vinicius.
E disse que está na tela de Mídias.
```

A segunda resposta demonstra que ele lembrou da primeira. Era o aceite do bloco.

#### E o de B não vê nada de A

```
--- B, mensagem 1, na sessão dele ---
> Qual e o meu nome?

Não tenho essa informação. O contexto que recebo traz só data, hora e a rota em que você
está — nada sobre a identidade de quem está logado.
```

#### As quatro provas de isolamento

| Chamada | Resposta | O que prova |
| ------- | -------- | ----------- |
| `GET /chat/session` **sem token** | **401** | O assistente exige login. Antes deste bloco: 200 |
| `POST /chat/input` **sem token** | **401** | idem |
| `POST /chat/upload` **sem token** | **401** | idem |
| `POST /chat/input` com `session_id` de A e **token de B** | **404** `{"error":"not_found"}` | O IDOR fechou |
| `POST /chat/upload` com `session_id` de A e **token de B** | **404** | E na ordem certa: antes da correção era **422**, que confirmava a existência da sessão |
| `POST /chat/upload` na **própria** sessão, arquivo inválido | **422** | A validação de arquivo continua funcionando para o dono |

#### O resto do sistema

| Chamada | Resposta | O que prova |
| ------- | -------- | ----------- |
| `GET /chat/session` com token | **200** + welcome do `assistente-console` | Sessão nasce **com dono** (`user_id` conferido no banco) |
| `POST /chat/input` com token | **201** + resposta do agente | Turno ponta a ponta, provider real |
| `POST /auth/v1/magic_login/request_code` (e-mail inexistente) | **422** `{"error":"Usuário não encontrado"}` | **O login continua vivo.** Atravessou `current_ip`, brute-force, rate-limit e o service — e não 500 |
| `GET /api/v1/public/chat/routing` (sem token) | **200** | O que o Bloco 7 recusou remover continua público e servindo |
| `GET /api/v1/media` / `/api/v1/flows` sem token | **401** | O gate de auth do resto do console, intacto |
| `GET /api/v1/media` / `/api/v1/flows` com token | **200** | AI9-016 e AI9-007 vivos |
| `GET /api/v1/leads` · `/api/v1/operations` | **404** | Os Blocos 6 e 7 continuam removidos |
| `/api/v1/public/chat/{session,messages,resolve_assets}` | **404** | Os 3 (4 com `resolve_assets`) que o widget chamava. Agora ele não chama mais |

#### E no navegador — o widget conversando de verdade

Não só `curl`: `vite` de pé, login real pelo fluxo de código mágico com o usuário A,
`/dashboard?welcome=true` para abrir o widget.

```
[Assistente] Oi! Sou o assistente do console. Em que tela você está e o que precisa entender?
[Vinicius ] Meu nome e Vinicius e o meu numero da sorte e 77.
[Assistente] Anotado, Vinicius. Só um aviso: eu não guardo essas informações entre
             conversas, então o 77 não fica salvo em lugar nenhum.
             Você está no dashboard agora. Se quiser, me diga qual painel, campo ou
             mensagem está te travando aí que eu explico.
[Vinicius ] Qual e o meu numero da sorte que eu te falei?
[Assistente] Você disse 77.
             Vale lembrar: isso vale só dentro desta conversa. Se a janela for fechada,
             eu não recupero.
```

Ele descreveu o DEC-20 sozinho, sem ninguém ter escrito isso no prompt.

**A aba de rede do widget, do carregamento ao segundo turno:**

```
GET  /api/v1/flows/contextual?user_type=admin&route_path=/dashboard  200
GET  /chat/session?flow_id=2&metadata=...                            200
POST /chat/input                                                     201
POST /chat/input                                                     201
```

**Nenhum 404. Zero erro de console.** Antes deste bloco, abrir o widget disparava um 404 em
`/api/v1/public/chat/session` toda vez.

---

### O achado que nenhum portão pegava: **o catálogo de modelos estava morto**

Isto não estava na `tasks.md` de ninguém. Apareceu porque o aceite deste bloco exigia
**conversar de verdade** — e na primeira tentativa o assistente respondeu, nos três turnos:

```
Desculpe, ocorreu um erro ao processar sua mensagem. Tente novamente.
```

O log do servidor:

```
[AgentService] Error: RuntimeError - Anthropic API error: 404 - model: claude-3-5-sonnet-20241022
```

Conferido contra `GET https://api.anthropic.com/v1/models` com a chave do `.env`:
`claude-3-5-sonnet-20241022` e `claude-3-haiku-20240307` **não existem mais**. E esse id
estava em **três** lugares ao mesmo tempo: o default do `anthropic_provider.rb`, o
`agent_config.model` de todos os seeds, e o seletor de modelo do flow builder.

**Nenhum portão pegava, e nem podia:** o `rspec` estuba o provider com WebMock, o
`zeitwerk:check` só carrega classes, o `tsc` só valida tipos. Um `AI9-007` "mantido" que
responde erro em 100% dos turnos passaria por todos eles.

É a lição mais cara desta migração acontecendo pela **terceira** vez — depois do login que
respondia 500 e do `LoginCode.mask_destination`. **Portão verde não é prova de que o caminho
funciona.**

| Correção | Onde |
| -------- | ---- |
| `DEFAULT_MODEL = 'claude-opus-5'` | `anthropic_provider.rb` |
| `MODELOS_APOSENTADOS` — 7 ids reapontados para o default, em vez de propagados (um agente gravado no banco com um deles continuaria quebrado para sempre) | idem |
| `SEM_AMOSTRAGEM` — a família 5 / 4.7+ rejeita `temperature`/`top_p`/`top_k` com **400**, e o provider mandava `temperature: 0.7` **sempre**. Seria o próximo erro depois de trocar o id | idem |
| Seletor de modelo do flow builder | `AIAgentConfigPanel.tsx` |
| `model` do seed | `assistente_console_agent.rb` |

As listas de **OpenAI e Google não foram tocadas** — ver a tabela de recusas.

---

### Referências residuais conhecidas — atualizado pelo Bloco 8

> Resolvidas e retiradas da lista do Bloco 7: os 3 endpoints 404 do `AIChatWidget`/
> `publicChat.ts`, a prosa dos seeds de agente, e o `belongs_to :lead` do `AgentRun`.

| Onde | O quê | Por que ficou | Sai em |
| ---- | ----- | ------------- | ------ |
| `app/services/ai/nodes/redirect.rb` | `auto_auth` + `Auth::VisitorAuthService` | **Órfão a partir deste bloco** — o assistente autenticado não precisa logar ninguém. É contrato do flow builder, não código morto | Phase 2 |
| `frontend/src/components/layouts/PublicSplitLayout.tsx` | 269 LOC | **Órfão pré-existente**, zero importadores | limpeza de órfãos |
| `AIAgentConfigPanel.tsx` — listas OpenAI/Google | ids possivelmente aposentados | Não medi aquelas APIs | Phase 2 |
| `api/v1/flow_executions.rb` | `ChatSession.find(params[:session_id])` sem escopo de dono | Visualizador de execuções do **admin**, autenticado e atrás de `VisitorRoute`. O gate certo é papel, não dono | Phase 2 |
| `frontend/src/components/charts/*` + `theme.ts` | wrappers órfãos e a copy "N leads" | Herdado do Bloco 6 | Phase 2 |
| `frontend/src/components/mobile/{MobileKPI,MobileChartCard}.tsx` | órfãos | **Pré-existentes** | limpeza de órfãos |
| `frontend/src/lib/analytics/identidade.ts` (+ teste) | `sessionId()` / `visitorId()` | Resíduo do AI9-010 (Bloco 2) | limpeza de órfãos |
| `frontend/src/app/pages/dictionaries.ts`, `components/seo/SEO.tsx`, `locales/en/translation.json` | copy da landing | Órfãos desde o Bloco 1 | limpeza |
| `backend/app/services/phone_normalizer.rb` | o módulo inteiro | Herdado do Bloco 3, sem dono | Phase 2 |
| `Gemfile` — `pgvector` e `neighbor` | gems sem uso | Recusa do Bloco 7, ainda válida | Phase 2 |
| `backend/db/schema.rb` — 9 tabelas `work_*` / `budgets` | órfãs **pré-existentes** | flag 7 | fora do trim |
| **`sfg9_dev` tem fisicamente as tabelas que saíram do `schema.rb`** | `leads`, `operations`, `coupons`, `canais`… | Os Blocos 1–7 editaram o `schema.rb` à mão e **nunca** rodaram `drop`. Descoberto aqui: um `db:migrate` re-dumpa o banco real e **desfaz o trim inteiro do `schema.rb`**. Por isso a coluna deste bloco foi aplicada à mão nos dois bancos e o `schema.rb` editado à mão, mantendo a convenção dos blocos anteriores | **atenção no Phase 2** |
| `.ruby-version` (3.4.9) × `Gemfile` (3.2.3) · hooks em CRLF | — | Pré-existentes | fora do trim |

---

### Armadilha registrada para quem vier depois

**Nunca rode `bin/rails db:migrate` neste repo sem conferir o `git diff db/schema.rb`
logo em seguida.** O banco de desenvolvimento (`sfg9_dev`) ainda contém fisicamente tudo o
que os Blocos 1 a 7 removeram — eles editaram o `schema.rb` à mão e não emitiram nenhuma
migration de `drop`. Um `db:migrate` re-dumpa o estado real e reintroduz **485 linhas** no
`schema.rb`: a extensão `vector`, `agent_runs.operation_id`, `chat_flows.operation_id`, as
tabelas `canais`, `coupons`, `coupons_plans` e todo o resto do trim.

Aconteceu aqui, foi revertido com `git checkout db/schema.rb`, e a coluna deste bloco foi
aplicada assim:

1. `schema.rb` editado à mão (coluna, índice, FK e o `version:`);
2. `ALTER TABLE` + `CREATE INDEX` + FK aplicados no `sfg9_test` via `psql`;
3. a versão `20260824120000` inserida em `schema_migrations` dos dois bancos, para o
   `maintain_test_schema!` não tentar recarregar o schema inteiro no banco de teste.

---

# Fechamento do Phase 1b — tarefas 9.1 a 9.4 (26/08/2026)

## 9.1 — O commit de cada bloco

Até aqui este documento registrava o **baseline** de cada bloco (o HEAD contra o qual as
verificações foram medidas), mas não o commit **do próprio bloco**. Sem isso o `git revert`
prometido em cada seção "Reversão" não tinha alvo escrito.

| Bloco | Features | Commit | Baseline medido contra | Diff |
| ----- | -------- | ------ | ---------------------- | ---- |
| 1 — Folhas visuais + landing | AI9-021…029, 031, 032 (11) | **`b6e65303`** | `7c359a04` | 193 arquivos, −23.196 linhas |
| 1 — follow-up (as 25 referências residuais) | — | **`774d44b0`** | — | 8 arquivos |
| 2 — Analytics | AI9-010, 011, 012, 013 (4) | **`dbcca3c9`** | `5656a8b7` | 119 arquivos, −18.844 |
| 3 — Conteúdo | AI9-019, 020, 015, 017, 004 + AI9-005 parcial (5 + 1) | **`e06be801`** | `51a7b686` | 299 arquivos, −19.353 |
| 4 — Comercial | AI9-003, 001, 018, 002 (4) | **`f2de14af`** | `64172a12` | 246 arquivos, −20.985 |
| 5 — Meta / Instagram | AI9-009 (1) | **`779473df`** | `ecee2f3f` | 64 arquivos, −11.737 |
| 6 — Leads e omnichannel | AI9-006 (1) | **`586f3b65`** | `ecee2f3f` | 170 arquivos, −17.314 |
| 7 — Operations + embeddings | AI9-014 (1) | **`96517a1a`** | `ecee2f3f` | 84 arquivos, −7.463 |
| 8 — Chatbot desacoplado | AI9-007 **adaptado**, não removido | **`483ee19a`** (+ `e347376d`) | `ecee2f3f` | 37 arquivos |
| Fechamento do Phase 1b | — | **`c2589093`** | — | — |

**Os 35 IDs `AI9-*`, e por que dois números diferentes descrevem o mesmo conjunto.** O gate
do trim (DEC-13 + DEC-14) fala em **"8 mantidas, 27 removidas"**; o razão registra **28
`removed` e 7 `kept`**. A diferença é **AI9-005**: o gate o conta entre as mantidas (o login
por WhatsApp ficou, DEC-14), o razão o registra como **`removed (parcial)`** porque chats,
grupos, mensagens e o inbox saíram. Os 7 `kept` são AI9-**007** (`kept (adaptado)`), 008,
016, 030, 033, 034 e 035. 28 + 7 = 27 + 8 = **35**.

## 9.2 — QA pelo avesso: o que eu **procurei**, não só o que achei

Varredura de 26/08/2026 sobre `backend/{app,config,db,lib,spec,docs}`, `frontend/{src,public}`,
`tools/`, `scripts/`, `config/`, `specs/` e a raiz do repositório — **1.122 arquivos**, 29
famílias de termo, uma por feature removida. O que foi procurado, feature a feature:

| Procurei | Como |
| -------- | ---- |
| **Rota de backend** sobrevivente | varredura dos `mount` de `api/root.rb` e `api/v1/base.rb`, e **cruzamento da allowlist de rota pública de `Api::Root` contra os `resource` realmente declarados** |
| **Rota de frontend** sobrevivente | `App.tsx` gera as rotas a partir de `consoleNavigation.tsx` — mesma lista para menu e roteador, então rota órfã e item de menu órfão são impossíveis por construção. Conferido: `useNavItems.ts:115` filtra `element !== null`, então área não entregue **não aparece no menu** |
| **Código morto** (backend) | constante Ruby de `app/{services,jobs,channels,controllers,models,mailers,validators,lib}` que não aparece em nenhum outro arquivo do projeto |
| **Código morto** (frontend) | módulo `.ts`/`.tsx` de `src/` sem nenhum importador, e **import declarado e nunca usado** (o `eslint` desta configuração **não** pega este segundo caso) |
| **Tabela órfã** | `create_table` do `schema.rb` que nenhuma migration cria e nenhum model usa |
| **Item de menu quebrado** | ver "rota de frontend" |
| **Tradução órfã** | as 14 chaves de `frontend/src/locales/{pt-br,en}/translation.json` cruzadas contra todo o `src/` |
| **Job agendado órfão** | as 6 entradas de `config/schedule.yml` cruzadas contra `app/jobs/` |
| **Política de autorização sem dono** | `Sfg::Attachments::POLICIES`, `Authorization::Matrix::RESOURCES`, os guards de rota do front e os canais do Action Cable — procurando o padrão do `public_brand`: **regra que diz "sim" sem olhar quem pergunta, e sem consumidor** |
| **Entrada em `attachments.yml`** | os 6 catálogos declarados cruzados contra os models que chamam `sfg_attachment` |
| **Config morta** | `.env.example`, `.env.secrets.example`, `sidekiq.yml`, `spec_helper.rb` (filtros do SimpleCov) cruzados contra quem lê |

### Resultado — o que está limpo, com a prova

| Verificação | Resultado |
| ----------- | --------- |
| `frontend && node node_modules/typescript/bin/tsc --noEmit` | **0 erros** (baseline do trim: 305) |
| `frontend && node node_modules/eslint/bin/eslint.js src --ext ts,tsx` | **0 findings** |
| `backend && bundle exec rspec` | **1.887 examples, 2 failures** (baseline do trim: 1.362 examples, 6 failures). As 2 são de fatia, não do trim — ver abaixo |
| Tabela de feature removida sobrevivendo no `schema.rb` | **nenhuma**. Sem `leads`, `lead_messages`, `canais`, `operations`, `coupons`, `plans`, `subscriptions`, `posts`, `showrooms`, `tracked_events`, `orders`, `onboarding_*` |
| Tradução órfã | **nenhuma**. As 14 chaves têm consumidor ou nota explicando por que existem |
| Job agendado órfão | **nenhum**. As 6 classes de `schedule.yml` existem em `app/jobs/` |
| Entrada órfã em `config/attachments.yml` | **nenhuma**. E o catálogo `app_theme` saiu **com a política `public_brand` junto** (OPS-499) — o precedente foi respeitado |
| Rota de frontend órfã / item de menu quebrado | **nenhum**, por construção (menu e roteador são o mesmo registro) |

**As 8 features mantidas continuam de pé**: o login por e-mail **e** por WhatsApp (DEC-14)
tem os 7 `%w[email whatsapp]` intactos e as 6 rotas de `magic_login`/`code_validation` na
allowlist; o chatbot desacoplado (DEC-13.2) responde autenticado em `/api/v1/chat/*`, com
`/api/v1/public/chat` reduzido ao `routing`.

### As 2 falhas do `rspec` — nenhuma é do trim

1. `spec/jobs/propagate_global_template_coordination_spec.rb:69` — coordenação de propagação
   de padrão global (OPS-466). Fatia S11/S4.
2. `spec/lib/sfg/etl/engine_spec.rb:319` — **o portão de schema está vermelho, e o motivo
   merece linha própria**: `Sfg::Etl::TargetBaseline.undeclared_tables` acusa `user_types`,
   que **tem** migration (`20241201000001_create_user_types.rb`). O portão lê as migrations
   por *replay* do DSL e envolve cada arquivo num `rescue StandardError; next`
   (`app/lib/sfg/etl/target_baseline.rb:48-56`); a migration usa `enable_extension` e um
   `reversible do |dir| … execute <<-SQL`, o replay levanta, e **o arquivo inteiro é
   descartado em silêncio**. Consequência que importa mais que o falso positivo: **uma
   migration que o replay não consiga ler faz o portão deixar de enxergar as tabelas dela** —
   é o mesmo `rescue` mudo que esta migração combateu em outros lugares. **Dono: S14.**

### Resíduo NOVO encontrado — arquivo e linha

O Bloco 8 já mantinha uma lista de referências residuais conhecidas (logo acima). Nada do
que está aqui embaixo estava nela.

#### A. Da natureza do `public_brand` — regra que diz "sim" sem dono

| # | Onde | O quê |
| - | ---- | ----- |
| **R-01** | `backend/app/controllers/api/root.rb:23`, `:25`, `:26` | **Três entradas de bypass de autenticação apontando para rotas que não existem mais.** A allowlist de `public_paths` ainda libera `/whats/v1/webhooks/messages-upsert`, `/send-message` e `/messages-update`; `api/whats/v1/webhooks.rb` declara **só** `connection-update`, `logout-instance`, `qrcode-updated` e `config` — os três outros saíram com AI9-005/AI9-006. Hoje a rota 404 antes de importar, então **não vaza nada**; o problema é o mesmo do `public_brand`: no dia em que alguém redeclarar um `resource 'messages-upsert'`, ele nasce **sem autenticação** e ninguém vai notar, porque a linha da allowlist já estava lá |
| **R-02** | `backend/app/channels/public_events_channel.rb:1-11` | **Canal de Action Cable órfão, público e sem autorização.** `stream_from "public_events"` sem nenhuma checagem; nada no repositório inteiro publica nesse stream (resíduo de AI9-010/AI9-012). E `ApplicationCable::Connection#connect` faz `self.current_user = user if user.present?` — **não chama `reject_unauthorized_connection`** —, então uma conexão anônima é aceita e pode assinar este canal. Os canais do Safegold (`permissions`, `renegotiation`, `project_progress`) todos autorizam; este é o único que não |
| **R-03** | `frontend/src/components/VisitorRoute.tsx:32-36` | **Guard VIVO que decide por tipos de usuário que o DEC-41 removeu.** Protege as 3 rotas `/admin/chat/*` e libera com `typeSlug === 'client'`, `t.includes('cliente')` ou `t.includes('visit')`. O DEC-41 listou o que limpar e **o backend foi limpo** (`api/v1/base.rb:13`, `controller_helpers.rb:191`, `user.rb:235` têm a nota da remoção); **o front não**. `cliente` é palavra corrente do domínio Safegold — um papel futuro com esse nome abre a área administrativa do chatbot por casamento de substring |

#### B. Superfície viva de feature removida

| # | Onde | O quê |
| - | ---- | ----- |
| **R-04** | `backend/app/controllers/api/v1/downloads.rb` (montado em `api/v1/base.rb:159`) | Endpoint **vivo e documentado no Swagger** que entrega `ai9_build_basic.zip` / `ai9_build_full.zip` e responde *"Acesso negado. **Adquira o plano Básico ou Completo**"*. É superfície do **AI9-002** (planos e feature-gating), removido no Bloco 4. As chaves `download_basic`/`download_full` existem **só em `spec/factories/permissions.rb`** — não estão no seed de permissões do Safegold —, então o endpoint responde **403 para todo usuário real, sempre**. Nota lateral: o razão justificava manter `Permission`/`UserPermission` *porque* `downloads.rb` os usava; a justificativa está velha (hoje quem usa é `Authorization::PermissionResolver`), mas **a infra continua certa de manter** |
| **R-05** | `frontend/src/lib/api/endpoints.ts:3-6` | `import { sessionId as sessionIdDaVisita, visitorId as visitorIdDaPessoa } from "@/lib/analytics/identidade"` — **os dois são importados e nunca usados** (zero outras ocorrências no arquivo). É o **único** importador de `lib/analytics/`, e é o que mantém `identidade.ts` + `identidade.test.ts` (10 KB, AI9-010) vivos no bundle. O `eslint` desta configuração **não** reporta import não usado, e o `tsc` também não — por isso passou nos dois portões |
| **R-06** | `backend/config/sidekiq.yml:8` | Fila `<APP_NAME>_transcriptions`. **Nenhum job enfileira nela** — `transcription` não aparece em `app/`, `lib/` nem em nenhum outro ponto de `config/`. Resíduo do AI9-019 (Bloco 3) |
| **R-07** | `backend/spec/spec_helper.rb:7,8,10,11` | Quatro `add_filter` do SimpleCov apontando para caminhos **apagados**: `polemk_chat_service.rb` e `polemk_group_service.rb` (AI9-005, Bloco 3), `/app/services/n8n/` (AI9-032, Bloco 1) e `/app/services/fake_data/` |

#### C. Órfãos de front que os blocos não catalogaram

| # | Onde | O quê |
| - | ---- | ----- |
| **R-08** | `frontend/src/app/pages/ClientDashboardPage.tsx` | Página inteira do tipo `client`, removido pelo DEC-41. **Zero importadores** |
| **R-09** | `frontend/src/components/OgRoute.tsx` | Guard **órfão** (zero importadores). Só aparece em comentários de `RoleRoute.tsx:20`, `consoleNavigation.tsx:423` e `AuditTrailPage.tsx:30` — todos avisando **para não usá-lo**, porque casa `includes('admin')` no nome de exibição do papel. Aviso contra código que já não existe é aviso que envelhece mal |
| **R-10** | `frontend/src/hooks/useIsDemoMode.ts` | Órfão. Retorna "quem **não** é OG vê dado falso" — a regra do AI9-002 (*"mesmo após a compra de um plano, quando visitor vira client"*). Se alguém reusar isto sem ler, Admin, Gerente e Colaborador passam a ver dado de mentira num sistema financeiro |
| **R-11** | `frontend/src/components/chat/ChatCTA.tsx` e `ChatOverlay.tsx` | Órfãos do chat público de captação (AI9-006) e da landing (AI9-021). `ChatOverlay` é o **único** consumidor de `src/stores/useFinaleStore.ts` (o "Finale" da campfire) — os dois caem juntos |

#### D. Arquivos de outro produto que o trim não alcançou

| # | Onde | O quê |
| - | ---- | ----- |
| **R-12** | `config/goat-robot.json` | **3.788 linhas, 137 KB, versionado.** Export de workflow n8n do roteador do produto "goat": ativações por comentário e DM do **Instagram**, **WABA**, Evolution, e chamadas a `POST /api/v1/leads`, `/leads/:id/executions`, `/leads/:id/messages/bulk`. É AI9-032 + AI9-006 + AI9-009 num arquivo só. Nenhum código da app o lê (só o graphify o indexa). Traz também um host `ngrok` e `api-goat.polemk.com` |
| **R-13** | `specs/blog_vsl.md` (28,5 KB) e `specs/n8n_lma_refactor.md` | Especificações **completas** de features removidas: o blog/VSL (AI9-004) com transcrição por Whisper (AI9-019) e `PublicChatService`/`Lead` (AI9-006); e o refactor do n8n (AI9-032) sobre `PUT /api/v1/leads/:id` |
| **R-14** | raiz do repositório | `README_TRACKING.md` ("Guia de Rastreamento & Utm_Params — **Plataforma Goat (AI9)**", AI9-029 — o Bloco 1 apagou os 3 docs de `backend/docs/` e deixou este); `AI9-29.md` (ticket do Plane sobre os endpoints públicos de **Posts/Blog**, AI9-004); `MEDIA_GUIDE.md` (identificadores de mídia **da Landing Page**, AI9-021); `patch_sidebar.js` (script que edita `frontend/src/store/planPreviewStore.ts`, arquivo apagado com o AI9-002); `specs_fix_plan.md` ("31 Specs Falhando… pré-existentes às alterações do **blog**"); `filters.json` e `filters2.json` (respostas HTTP cruas salvas de `/api/analytics/v1/events/filters`, AI9-010, uma delas um stack trace de 404); `Nota` (0 byte, não versionado) |
| **R-15** | `README.md:3,147,207-211` e `.env.secrets.example:20-22` | O README do repositório ainda descreve o produto como *"Sistema completo… incluindo integrações com **Asaas (pagamentos)** e Evolution API"*, documenta `ASAAS_API_KEY`/`ASAAS_API_URL` na tabela de variáveis e cita `N8N_WEBHOOK_...`; o `.env.secrets.example` ainda declara `ASAAS_API_KEY`. AI9-001 saiu inteiro no Bloco 4 |
| **R-16** | `backend/.env.example:244-246` (o arquivo está sendo editado por outra fatia; confira por `grep -n N8N`) | `N8N_WEBHOOK_ADD_DISCORD`, `N8N_WEBHOOK_REMOVE_DISCORD` e `N8N_API_KEY` no **contrato de configuração** — e o contrato existe justamente para que o nome da variável signifique alguma coisa. **Zero leitores** em `app/`, `lib/`, `config/` e `frontend/src/` |

#### E. Catálogos com linha para dono que não existe

| # | Onde | O quê |
| - | ---- | ----- |
| **R-17** | `backend/app/services/authorization/matrix.rb:98` | `'app_themes' => %w[CRUD CRUD - R]`. A **DEC-55** não porta a área de temas: não há tabela, model, tela nem upload. A linha continua na matriz do DEC-18. **Não removi**: a matriz é contrato aprovado pelo usuário e mexer nela sem DEC é exatamente o que o registro proíbe. Fica anotado, dono: S0 + usuário |
| **R-18** | `backend/app/services/authorization/matrix.rb:91` e `backend/db/etl/load_order.yml` | `'resource_kinds'` na matriz e o conversor `ResourceKinds → ResourceKind` no plano de carga — para uma tabela que o dump provou vazia e que a migration da S8 decidiu **não criar**. `geolocations`, no mesmo arquivo, está corretamente em `do_not_migrate`, com a razão escrita: é o tratamento que falta ao `resource_kinds`. Dono: S6/S8 |
| **R-19** | `backend/app/lib/sfg/attachments.rb:67,75` | As políticas `owner` e `og_admin` não são escolhidas por **nenhuma** entrada de `config/attachments.yml`. Diferente do `public_brand`, **não são armadilha** (as duas olham o usuário) — ficam registradas só para não virarem uma |

### As 30 tabelas órfãs do `schema.rb` — conferidas, e **não** são do trim

`achievements`, `user_achievements`, `drops`, `point_events`, `budgets`, `budget_items`,
`budget_members`, 15 `fly_*` e 8 `work_*`: nenhuma migration as cria, nenhum model as usa.
Já estavam catalogadas (**ETL-S14-03** no `improvements-log.md`, mais a linha do Bloco 8
acima) e estão na allowlist nominal `Sfg::Etl::TargetBaseline::INHERITED_ORPHANS`, que faz
uma órfã **nova** derrubar o portão e mantém as antigas **visíveis**. Reconferido aqui: são
exatamente 30, e nenhuma pertence às 27 features removidas.

> Correção de contagem: o **ETL-S14-03** decompõe as 30 como "`fly_*` **16**, `work_*` 8,
> `budget*` 3, `achievements`, `user_achievements`, `drops`, `point_events`" — que soma **31**.
> Contadas no `schema.rb`: `fly_*` são **15**. O total de 30 está certo; a decomposição, não.

## 9.3 — Nenhum `to-remove` restante

`.migration-ai9/parity-ledger.md` não tem nenhuma linha em `to-remove`. Estado dos 35 IDs
`AI9-*`: **28 `removed`** (AI9-005 é `removed (parcial)`, DEC-14) e **7 `kept`** (AI9-007
`kept (adaptado)`, mais 008, 016, 030, 033, 034, 035).
