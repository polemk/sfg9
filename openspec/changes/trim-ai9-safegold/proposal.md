# Proposal: enxugar a base ai9 para o Safegold (Phase 1b)

## Why

O repositório `sfg9` foi criado a partir da **base ai9 completa**, que embarca um produto
SaaS de marketing/conteúdo inteiro. O legado que está sendo migrado — o **Safegold**, um
sistema de crédito e risco — não tem nada disso.

Sem este trim, o Safegold herdaria em silêncio a superfície inteira do ai9: telas, rotas,
endpoints, models e itens de menu que o cliente nunca pediu. Pior, o Phase 2 (mapa de
migração) e o Phase 3 (tematização e implementação) gastariam esforço em código que será
deletado — e é exatamente por isso que a skill posiciona esta etapa **antes** do mapa.

Há ainda duas **colisões de nome** que contaminariam a migração se ficassem:

- `Operation` no ai9 é agrupador de campanha de marketing — **não** é a *operação de
  risco* nem a *operação estruturada* do Safegold (IDs 230–309 do inventário).
- `Project` no ai9 é projeto de entrega de conteúdo — **não** é o *projeto de crédito*,
  que é o agregado central do legado (IDs 080–119).

## What Changes

Das **35 features ai9-only** levantadas em `.migration-ai9/ai9-feature-selection.md`
(~100k LOC), o usuário decidiu item a item (DEC-13.1):

**Mantidas (7)** — 1 por escolha de produto, 6 por serem infra transversal:
`AI9-007` chatbot (**adaptado**, ver abaixo), `AI9-008` credenciais de IA, `AI9-016`
upload/mídia, `AI9-030` login, `AI9-033` shell de navegação, `AI9-034` países/DDI,
`AI9-035` docs OpenAPI.

**Removidas (28)** — todo o produto SaaS de marketing/conteúdo: comercial (Asaas,
planos/checkout, cupons, onboarding), captação (leads/omnichannel, Meta/Instagram,
analytics próprio, Painel TV, heatmap, hub brsw), conteúdo (blog, WhatsApp/Evolution,
showrooms, pedidos/entregas, transcrição, agenda), `Operations`, e o site institucional
com seus enfeites (campfire, 3D, terminal, easter egg, Brazilian Software, NavKit,
preview de site, design demo, guia de rastreamento, audio visualizer, MCP n8n).

Três consequências decididas junto:

1. **O chatbot fica desacoplado** (DEC-13.2). Uso definido: **assistente interno no
   console**. Saem o nó `save_to_lead`, as ferramentas de lead do agente e as FKs
   `lead_id`/`operation_id`. Ficam o motor multi-provider, o flow builder, a execução de
   fluxo, a telemetria e o widget.
2. **A rota `/` passa a apontar para a tela de login** (DEC-13.3), já que remover o
   AI9-021 libera a raiz e o Safegold é sistema interno.
3. **O login perde o canal WhatsApp** (DEC-13.4) — consequência necessária de remover o
   AI9-005 mantendo o AI9-030. Segue funcionando por e-mail, que é como o legado já
   notificava.

## Impact

- **Afetado:** `backend/app/{controllers,models,services,jobs}`, `frontend/src`,
  `backend/db/migrate` + schema, rotas, navegação, seeds.
- **Ordem:** 8 blocos, dependência primeiro, **um commit reversível por bloco**, build
  verde antes de seguir. Detalhe em `design.md` e `tasks.md`.
- **Não afetado:** nada do legado `sfg` (é read-only), e nenhuma feature legada migrada —
  este trim mexe **apenas** no scaffold da base ai9.
- **Paridade:** a garantia é **assimétrica**. "Nada se perde" protege as features do
  legado; estas 28 são perda **intencional**, autorizada item a item. Ledger:
  `to-remove` → strip executado → QA verifica → `removed`. Um `to-remove` pendente
  **bloqueia o fechamento da migração**.
- **Risco principal:** remover um bloco quebra outro que fica. Mitigação: ordem por
  dependência derivada do grafo, `pnpm type-check` + `rspec` a cada bloco, e reversão por
  commit isolado.
