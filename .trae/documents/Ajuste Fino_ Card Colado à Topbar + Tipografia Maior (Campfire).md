## Objetivo
- Colar o card “O que está incluído” exatamente sob a topbar, alinhado ao container, com animação sutil ao mostrar/ocultar.
- Aumentar a tipografia do corpo de texto nas seções Campfire para ficar proporcional à referência.

## Implementação Proposta
### 1) Posicionamento do Card
- Definir variável CSS `--topbar-h` baseada na altura real da topbar (`h-16 ≈ 64px`).
- Aplicar ao card: `position: fixed; top: var(--topbar-h); right: calc((100vw - 1152px)/2); width: 380px; z-index alto`.
- Ajustar o contêiner das seções com `lg:pr-[420px]` (já existe) para reservar o espaço do card.

### 2) Animação Mostrar/Esconder
- Criar utilitários CSS:
  - `.campfire-card-in { opacity: 1; transform: translateY(0); transition: opacity 180ms ease, transform 180ms ease; }`
  - `.campfire-card-out { opacity: 0; transform: translateY(8px); pointer-events: none; }`
- Alternar classes conforme visibilidade de `#plans` (já usamos IntersectionObserver); manter regra de esconder em mobile.

### 3) Tipografia Maior
- Adicionar classe `.campfire-body` em `tokens-campfire.css` com `font-size: clamp(17px, 1.05vw, 20px); line-height: 1.6;` e `letter-spacing` sutil.
- Aplicar `.campfire-body` aos wrappers das seções (`HeroCampfire`, `LetterCard`, `WhatIsIt`, `WhyNotSlack`, `TakeCloserLook`, `FitsInPlaces`, `SystemRequirements`).
- Manter headings atuais; se necessário, elevar `h2` para `text-4xl` e `h3` para `text-2xl` nas seções principais.

### 4) Verificação
- Desktop: card colado sob a topbar sem gap; anima transição ao entrar/saír da viewport de planos; textos de parágrafo maiores.
- Mobile: card oculto; tipografia permanece maior mas dentro da responsividade.

## Arquivos a editar
- `frontend/src/components/campfire/Topbar.tsx` (setar `--topbar-h` via style no wrapper).
- `frontend/src/components/campfire/HeroCampfire.tsx` (usar `top: var(--topbar-h)`, classes `.campfire-card-in/out`).
- `frontend/src/styles/tokens-campfire.css` e `frontend/src/styles/globals.css` (utilitários de animação e tipografia).
- Aplicar `.campfire-body` nos containers das seções Campfire.

## Próximo Passo
- Implementar os ajustes acima e validar visualmente no preview para garantir que o card está exatamente encaixado sob a topbar e que a tipografia reflete a referência.