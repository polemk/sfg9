## Objetivo
- Replicar o comportamento visual do Campfire: topbar fixa full‑width colada nas laterais, com apenas borda inferior; card “Get it for free” fixo na lateral direita do container; carta com composição tipográfica fluida.

## Alterações de Topbar
- Converter a topbar em barra fixa: `position: fixed; top: 0; left: 0; right: 0; z-index alto`.
- Remover bordas superior/laterais; manter somente `border-bottom` bem definida.
- Remover cantos arredondados e caixas flutuantes; usar fundo `bg-card`/leve blur.
- Dimensões idênticas ao modelo: altura ~64–72px; padding horizontal alinhado ao container (`max-w-6xl`).
- Adicionar seção “Planos e Preços” na topbar:
  - Item de navegação “Planos e Preços” com hover/active.
  - Ao clicar/hover, abrir painel (dropdown) com os mesmos itens/estados da referência (lista simples de opções + links “Overview/Testimonials/Changelog” permanecem).
  - Estilo: fontes, cores e espaçamentos inspirados (negritos de títulos, cinzas nos subtítulos, foco visível).

## Card “Get it for free” (aside)
- Tornar fixo no desktop: `position: fixed` com `top` abaixo da topbar (ex.: 96px) e `right` alinhado à borda interna do container.
- Cálculo de alinhamento do container: `right: calc((100vw - 1152px) / 2)` (usa `max-w-6xl` ≈ 1152px) para posição idêntica ao Campfire.
- Tamanho/proporções: largura ~360–400px; padding interno ~24px; sombra suave e borda sutil.
- Não se mover durante o scroll (desktop); em mobile/tablet volta ao fluxo normal.

## Carta (letter)
- Remover “card” quadrado; ocupar largura de leitura (ex.: `max-w-3xl`) à esquerda do container.
- Estruturar como seção tipográfica: título (H2), subtítulo (H3), corpo (parágrafos), listas quando conveniente.
- Ajustar tipografia (peso/linhas), espaçamento vertical (ritmo consistente), alinhamento à esquerda.

## Técnicos
- Componentes/arquivos a editar:
  - `src/components/campfire/Topbar.tsx`: barra full‑width com `border-b` apenas + item “Planos e Preços” e dropdown.
  - `src/components/campfire/HeroCampfire.tsx`: transformar o `aside` em `fixed` no desktop com alinhamento ao container; fallback para mobile.
  - `src/components/campfire/LetterCard.tsx`: nova composição tipográfica sem bordas/quadrado.
  - `src/styles/tokens-campfire.css` e utilitários em `globals.css`: classes para `border-b` forte, sombras, medidas e alinhamento.

## Responsividade e A11y
- Desktop: topbar fixa; card fixo; carta com tipografia confortável.
- Tablet/mobile: dropdown acessível, card volta ao fluxo; espaçamentos reescalados.
- Foco visível, contraste AA, `prefers-reduced-motion` respeitado.

## Verificação
- Conferir alinhamento lateral da topbar e do card exatamente no container.
- Testes de presença/estados (Vitest/RTL) para: item “Planos e Preços”, abertura do dropdown, posicionamento fixo do card, hierarquia typográfica da carta.

## Próximo passo
- Implementar as alterações acima e validar no preview local (incluindo medidas exatas e comportamento de scroll).