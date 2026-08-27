## Visão Geral
Implementar alinhamentos e responsividade iguais à referência: topbar e vídeo simétricos, card +60px com conteúdo compensado, seleção de planos atualizando preço, tipografia +35% sem mexer no HTML, e feedback visual consistente.

## Arquivos a alterar
- `frontend/src/styles/tokens-campfire.css` (variáveis: `--topbar-h`, `--header-card-w`, corpo tipográfico)
- `frontend/src/styles/globals.css` (tipografia base, espaçamentos de linha, botão default `.btn`)
- `frontend/src/components/campfire/Topbar.tsx` (margem direita do “Entrar”, paddings da barra, alinhamentos)
- `frontend/src/components/campfire/HeaderCard.tsx` (logo 25%, borda separadora, select de planos + preço dinâmico + transição, checks circulares)
- `frontend/src/components/campfire/HeroCampfire.tsx` (escala de H1, bloco de texto, reservar coluna do card)
- `frontend/src/components/campfire/MediaShowcase.tsx` (margens negativas e simétricas, pr para não conflitar com o card)

## 1) Margem do botão “Entrar”
- Ajustar `className` do link “Entrar” para `mr-[calc(var(--header-card-w)+24px)]` e, em breakpoints:
  - `sm:mr-[calc(var(--header-card-w)-8px)]`, `md:mr-[calc(var(--header-card-w)+16px)]`, `lg:mr-[calc(var(--header-card-w)+24px)]`.
- Remover paddings do wrapper da topbar (`px-0`) e deixar branding “@polemk/ai9” colado à esquerda do container.
- Validar visualmente em mobile/tablet/desktop (sem sobreposição do card).

## 2) Redimensionamento do card (+60px)
- Atualizar `--header-card-w` em `tokens-campfire.css` de `300px` → `360px`.
- Garantir `lg:pr-[var(--header-card-w)]` nas seções (Hero, Media) para compensar a coluna do card.
- Ajustar padding interno do card para evitar sobreposição (p.ex. `p-6` -> manter, mas validar se precisa `p-7` no desktop).

## 3) Ajustes na toolbar
- Elevar `--topbar-h` para alinhar a base da topbar com a linha divisora do header do card (p.ex. `104px`).
- No wrapper da topbar: `flex items-center justify-between`, `px-0`, `md:px-0` para remover espaçamentos, mantendo simetria com o conteúdo.
- Alinhar verticalmente os itens e validar que a base da topbar encosta exatamente na borda superior do card (separador interno do card adiciona referência visual).

## 4) Redimensionamento da logo (card)
- Aumentar a logo “{ai9}” em 25%: `text-[1.25rem] md:text-[1.5rem]`.
- Manter proporção e cores; preservar legibilidade em dark/light.

## 5) Seleção de planos (preço dinâmico)
- Estado por id: `selectedId` e derivado `selected = useMemo(() => plans.find(...))`.
- Inicialização: ao carregar `plans`, setar `selectedId` para o primeiro plano (se existir).
- Preço:
  - `one_time`: `R$ {price.toFixed(2)}`;
  - `subscription`: `R$ {price.toFixed(2)}/mês`;
  - Sem seleção: `—`.
- Feedback visual: transição suave no preço (`transition-opacity`, `fade-in`) e skeleton quando carregando.
- CTA “Baixar o código” leva para `/checkout/{identifier|id}` do plano selecionado; fallback `/plans` se não houver seleção.
- Validação: garantir que o id do select corresponde ao plano exibido; se mismatch, mostrar `—` e desabilitar CTA.

## 6) Aumento de tipografia (+35%) sem mexer no HTML
- Em `tokens-campfire.css`: `.campfire-body { font-size: clamp(23px, 1.42vw, 27px); line-height: 1.65; }`.
- Ajustar heading principal do Hero usando `clamp` para refletir +35% mantendo hierarquia (já aplicado com `text-[clamp(3.5rem,7vw,5.5rem)]`).
- Atualizar `.btn { font-size: calc(0.875rem * 1.35) }` em `globals.css`.
- Revisar parágrafos e espaçamentos: `mt-4`/`mb-4` onde necessário para legibilidade.

## 7) Vídeo: simetria e coincidência com “Entrar”
- Em `MediaShowcase.tsx`: aplicar `lg:ml-[-40px] lg:mr-[40px]` e manter `lg:pr-[var(--header-card-w)]`.
- Validar que a lateral direita do vídeo coincide com a margem do “Entrar”. Ajustar `[-40px]` para `[-48px]` se necessário.

## 8) Check circular nos itens do card
- Substituir ícone por círculo verde `h-5 w-5` com miolo branco `h-3 w-3` centralizado; `space-y-3`.

## 9) QA e responsividade
- Testar em `sm`, `md`, `lg`:
  - Sem sobreposição do card; “Entrar” alinha com vídeo.
  - Seleção de plano atualiza preço sempre; CTA correta.
  - Tipografia mantém legibilidade e hierarquia.
  - Base da topbar alinhada com divisor do card.

## Entregáveis
- Código atualizado nos arquivos listados.
- Verificação visual nos três breakpoints e correções finas nos offsets de margem caso necessário.
