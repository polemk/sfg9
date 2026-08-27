# Tarefa LOG.4: Correção de Limites de Scroll no Heatmap

**Sprint:** 3 — Otimização do Heatmap Avançado
**Estimativa:** 1.5 dias
**Tipo:** Frontend + Backend

---

## Contexto
O Heatmap atual (visualização das zonas quentes e cliques da Landing Page) só funciona no primeiro "Viewport" de tela, ou apresenta deslocamentos agressivos nos eixos Y quando os usuários dão muito scroll. Além disso, múltiplos cliques no mesmo ponto só geram círculos soltos em vez de uma grande área "quente", desvirtuando o que é ser um Heatmap.

---

## Onde começa
- `HeatmapPage.tsx` existe e desenha HTML5 Canvas em cima de um iframe.
- Backend já coleta posições X e Y do visitante.

## Onde termina
- O Canvas escala dinamicamente acompanhando toda a altura (`scrollHeight`) do Iframe.
- Densidade visual de cores onde muitos pontos batem próximos uns dos outros.

---

## O que precisa ser feito

### No Frontend (Tracker e Admin)
1. **Captura Absoluta:**
   Ao registrar um clique (`document.addEventListener`), captar além do `e.clientX` / `clientY`, o valor do documento completo, por exemplo: `Y = e.pageY || e.clientY + document.documentElement.scrollTop`.
2. **Dimensionamento do Canvas:**
   No `HeatmapPage.tsx`, no `useEffect` de resize do iframe, resgatar a altura real do conteúdo via `postMessage` (se CORS for um problema, injetar no `onload`) ou assegurar que a altura do Iframe represente o site inteiro (`100% height` em modo scroll total).
3. **Cluster de Densidade (Opcionalidade Visual):**
   Ao invés de pintar círculos azuis estáticos, aplicar a lógica real de um heatmap: usar `globalAlpha` nos círculos, desenhando todos pretos num canvas oculto, e usando um algoritmo de colorização (como simpleheatmap) em cima da máscara de alpha, onde maior alpha = vermelho, menor = azul. Se complexo demais para esta spec, pelo menos aumentar o tamanho radial caso haja colisão entre os raios na renderização base.

---

## Critérios de aceite
1. Eventos gravados num botão no rodapé do site renderizam perfeitamente em cima desse botão no view administrativo de Heatmap.
2. Dois pontos muito colados possuem cor mais "densa/escura" ou cobrem uma área maior do que um clique solitário.

---

## Dependências
- Nenhuma de outras specs, isolado em Heatmap.
