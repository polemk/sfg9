## Objetivo
Deixar vídeo e topbar simétricos, ajustar o header do card para alinhar com a base da topbar, aplicar padding direito no bloco de texto para ficar menor que o vídeo e padronizar a tipografia da carta.

## Alterações por arquivo
- `frontend/src/components/campfire/Topbar.tsx`
  - Ajustar margem direita do link "Entrar" para alinhar com a direita do vídeo (`mr-[calc(var(--header-card-w)+24px)]`).
  - Remover paddings do wrapper e manter branding colado à esquerda.
  - Confirmar `flex items-center` para alinhamento vertical.

- `frontend/src/styles/tokens-campfire.css`
  - Definir `--topbar-h: 72px` (se necessário, ajustar até alinhar perfeitamente).
  - Manter `--header-card-w` aumentado (+60px) e usá-lo para compensações (`lg:pr`/`mr`).

- `frontend/src/components/campfire/HeaderCard.tsx`
  - Header do card com altura exata da topbar: `h-[var(--topbar-h)]` em `div` do cabeçalho (está em 10–13).
  - Borda separadora já existe; validar opacidade e posição.
  - Aumentar logo “{ai9}” +25% (já aumentado; garantir proporção e line-height).

- `frontend/src/components/campfire/HeroCampfire.tsx`
  - No bloco de texto `max-w-3xl` (linha 28), adicionar padding-right somente em `lg` para o texto ficar ligeiramente menor que o vídeo: `lg:pr-6` (ou `pr-[24px]`).
  - Manter reserva da coluna do card: `lg:pr-[var(--header-card-w)]` no container externo.

- `frontend/src/components/campfire/MediaShowcase.tsx`
  - Aplicar margens simétricas no vídeo: `lg:ml-[-48px] lg:mr-[48px]` e manter `lg:pr-[var(--header-card-w)]` para não conflitar com o card.
  - Garantir que a direita do vídeo coincida com a direita do botão “Entrar” (usar `calc(var(--header-card-w)+24px)` como referência, ajustar caso necessário).

- `frontend/src/components/campfire/LetterCard.tsx`
  - Padronizar tamanhos: alinhar `h2`, `h3`, `p` às mesmas escalas usadas no hero (ex.: `h2 text-4xl md:text-5xl`, `p text-base md:text-lg` com `campfire-body`).
  - Ajustar `space-y` para harmonizar com o restante e aumentar linha (`leading-relaxed`) se necessário.

## Verificações
- Desktop, Tablet, Mobile: sem sobreposições; direita do vídeo coincide com direita do “Entrar”; base da topbar alinhada com divisor do card.
- Carta com tipografia equivalente ao restante do site.
- Responsividade preservada; offsets simétricos do vídeo.

## Observações
- Se `--topbar-h: 72px` não alinhar 100%, ajustarei finamente (74–76px) e recalibrarei `h-[var(--topbar-h)]` do header do card para casar pixel a pixel.
