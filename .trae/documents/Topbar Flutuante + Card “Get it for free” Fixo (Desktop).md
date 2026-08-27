## Objetivo
- Deixar a topbar flutuante (sempre visível no topo com blur/rounded) e fixar o card “Get it for free” no desktop, espelhando o comportamento visual do Campfire, sem alterar funcionalidades.

## Alterações Propostas
- Topbar (arquivo: `frontend/src/components/campfire/Topbar.tsx`):
  - Tornar o contêiner `fixed` com `top-0 left-0 right-0 z-50` (atual é `top-3`).
  - Manter `rounded-full bg-card/60 backdrop-blur-sm border` e aumentar leve opacidade para leitura.
  - Adicionar sombra sutil em scroll (classe condicional `shadow-md`) com utilitário leve (hook simples que adiciona classe após rolagem > 8px) — sem comprometer performance.
  - Preservar links, switch de tema e CTA “Entrar”.
  - Inserir `pt-[72px]` na primeira seção de conteúdo (hero) para evitar sobreposição com a topbar fixa.

- Hero Card “Get it for free” (arquivo: `frontend/src/components/campfire/HeroCampfire.tsx`):
  - Transformar o `aside` em sticky/fixo no desktop:
    - Usar `lg:sticky lg:top-24` para comportamento fixo ao rolar dentro do viewport.
    - Alternativa pontual: `lg:fixed lg:top-24 lg:right-[calc((100vw-1200px)/2)]` quando quisermos alinhamento rígido à margem do container; default ficará com `sticky` por ser mais simples e responsivo.
  - Em mobile/tablet, manter fluxo normal (`position: static`) para UX fluida.
  - Garantir `rounded-2xl border bg-card p-6 shadow-sm` e z-index apropriado (`lg:z-40`).

## Estilo e Tokens
- Reutilizar tokens já adicionados (`tokens-campfire.css`) e classes utilitárias existentes.
- Sem dependências novas; apenas Tailwind e CSS atual.

## Acessibilidade
- Topbar com navegação clara e foco visível; card com `aria-label` descritivo.
- Manter contrastes; respeitar `prefers-reduced-motion` já definido.

## Verificação
- Desktop: topbar sempre no topo e card “Get it for free” permanece à vista durante rolagem de hero/overview.
- Mobile/tablet: card volta ao fluxo; topbar ocupa pouco espaço; hero tem `pt` para não ficar oculto.
- CTA de pagamento continua apontando para `https://pika.polemk.com/payments`.

## Entregáveis
- Atualizações em `Topbar.tsx` e `HeroCampfire.tsx` com classes e (se necessário) pequeno hook de sombra.
- Ajuste de padding inicial no herói.
- Sem mudanças de API ou funcionalidade.

## Próximo Passo
- Aplicar as mudanças propostas e validar no preview local (layout, responsividade e comportamento do card no desktop).