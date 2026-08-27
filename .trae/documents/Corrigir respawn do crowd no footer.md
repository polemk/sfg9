## Diagnóstico
- Respawns surgem no meio da tela, não fora dela, gerando “recarregamentos” visíveis.
- Causa: o progresso aleatório do tween é aplicado em toda nova inclusão de peep, inclusive após `onComplete`, fazendo o personagem reaparecer no meio do caminho.
- Referência esperada: progresso aleatório apenas na população inicial para espalhar o crowd; respawns iniciam sempre off‑screen.

## Mudanças Propostas
1. Remover `walk.progress(Math.random())` de `addPeepToCrowd` e manter respawns iniciando no `startX` off‑screen definido por `resetPeep`.
2. Aplicar o progresso aleatório somente na inicialização:
   - Em `initCrowd()`, após `addPeepToCrowd()`, chamar `peep.walk!.progress(Math.random())` para cada peep inicial.
3. Manter velocidades/easing idênticos à referência:
   - `xDuration = 10`, `yDuration = 0.25`, `ease: 'none'`, `timeScale(randomRange(0.5, 1.5))`.
4. Garantir consistência de spawn off‑screen:
   - Confirmar `resetPeep` com `startX = -peep.width` e `startX = stage.width + peep.width`; manter como está (igual à referência).

## Validação
- Em `HomePage`, abrir a página e observar:
  - Nenhum personagem surge no meio após completar um percurso; todos entram pela borda correspondente.
  - Velocidade idêntica à referência (duração total ~10s por travessia; passos vertical yoyo ~0.25s).
- Testar redimensionamento: após `resize`, crowd se repovoa e permanece sem respawns no meio.

## Referências de Código
- `frontend/src/components/campfire/FooterCrowd.tsx`
  - `addPeepToCrowd`: linhas 71–79 (remover `.progress(Math.random())`).
  - `initCrowd`: linhas 96–98 (chamar `.walk.progress(Math.random())` apenas aqui).
  - `resetPeep`: linhas 48–59 (spawn off‑screen, manter).