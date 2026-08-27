## Objetivo
- Unificar a primeira dobra (hero) inspirada no Campfire/ONCE com o módulo de planos já existente, mantendo funcionalidades e identidade visual.

## Escopo
- Manter: botões/links, logotipo/identidade, integração de pagamento/checkout e PlansComparison.
- Adotar: layout, tipografia, hierarquia e fluidez do Campfire como referência visual.

## Arquitetura de UI (componentes)
- `Topbar`: logo atual + alternância de tema + links mínimos (Overview/Depoimentos/Changelog opcionais).
- `HeroCampfire`: layout em duas colunas (texto forte à esquerda; cartão “What’s included?/Get it” à direita) com CTA primário de pagamento.
- `MediaShowcase` (placeholder): área para imagem/vídeo curto abaixo do hero (sem alterar a funcionalidade de pagamento).
- `PlansSection`: usar `PlansComparison` existente com ajustes de estilo para harmonizar com o hero (cores, tipografia, espaçamento).

## Arquivos a criar/alterar
- Criar `src/components/campfire/Topbar.tsx`.
- Criar `src/components/campfire/HeroCampfire.tsx` (texto + CTA + card lateral).
- Criar `src/components/campfire/MediaShowcase.tsx` (imagem estática/iframe com lazy‑load).
- Atualizar `src/app/pages/HomePage.tsx` para compor: `Topbar` + `HeroCampfire` + `MediaShowcase` + `PlansComparison` + `Footer`.
- Criar `src/styles/tokens-campfire.css` com variáveis de cor e tipografia inspiradas (sem copiar assets proprietários).
- Ajustar `tailwind.config` se necessário para fontes e escala tipográfica.

## Conteúdo e identidade
- Manter marca `{APP_NAME}` como hoje.
- Copy do hero adaptada ao produto (foco em “Crie e lance com velocidade”, “open source/updates” conforme aplicável).
- CTA principal: `href="https://pika.polemk.com/payments"` (mesma integração).

## Responsividade
- Desktop: duas colunas (hero + card), showcase em largura média.
- Tablet: empilhar card sob o texto com espaçamento consistente.
- Mobile: tipografia reduzida, CTA sempre visível, showcase com lazy‑load.

## Desempenho
- Imagens com `loading="lazy"` e formatos otimizados (webp/png): placeholder simples inicialmente.
- Remover efeitos pesados; usar transições de 150–200ms e `prefers-reduced-motion`.
- Reutilizar React Query em `PlansComparison` sem mudanças no contrato.

## Acessibilidade
- Hierarquia `h1 → h2`, labels e `aria-*` nos CTAs.
- Suporte `prefers-color-scheme` e `prefers-reduced-motion`.

## Animações sutis
- Hover/press nos botões; fade pequeno no card lateral; scroll‑shadow discreto.

## Fluxo de trabalho
1) Wireframes (Desktop/Tablet/Mobile): entregar imagens SVG simples ou JSX estático em `src/wireframes/HomeCampfire.tsx`.
2) Protótipo funcional: implementar componentes e composição no `HomePage.tsx` com estilos.
3) Testes de usabilidade: roteiro + coleta de feedback (links de CTA e legibilidade).
4) Ajustes finais: refinamento de copy, espaçamentos e cores.

## Testes
- Unit: render e acessibilidade de `HeroCampfire` e `Topbar`.
- Integração: `HomePage` monta hero + planos e mantém funcionamento dos CTAs.

## Critérios de aceite
- CTA de pagamento funcional e visível na primeira dobra.
- Logotipo e tema preservados.
- Planos carregando e comparando sem regressões.
- Layout consistente nas 3 breakpoints principais.
- LCP e CLS dentro de boas práticas.

## Próximo passo
- Ao aprovar, implemento os componentes, estilos e ajustes em `HomePage.tsx`, entrego wireframes e o protótipo funcional para validação antes do refinamento final.