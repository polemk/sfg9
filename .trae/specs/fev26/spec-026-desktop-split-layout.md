# Tarefa 4.2: Side-by-Side Desktop Layout

**Sprint:** 4 - Agent UI Redesign & Embedded Navigation
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto
O layout de chat flutuante (bolha no canto inferior direito) é bom para suportes esporádicos. No entanto, o núcleo do produto V4 centraliza a experiência de vendas e atendimento IA através de um *layout estático side-by-side (lado a lado)*. Na versão desktop, a tela principal (Homepage) será dividida: o site (com seu conteúdo rolável, seções informativas e CTAs) fica do lado esquerdo, e o painel ativo do Agente IA (ChatBox) fica fixo ocupando a porção direita da tela, atuando como o principal vendedor proativo que enxerga o mesmo contexto do Lead.

---

## Onde começa
A `HomePage.tsx` atual renderiza seções empilhadas (`Hero`, `Features`, etc.) com 100% de largura (full-width), e o `AIChatWidget` flutua de modo absoluto gerido no `Layout.tsx`.

## Onde termina
A versão Desktop aplicará uma divisão responsiva: o `Layout.tsx` possuirá um "Slot" à direita onde o `AIChatWidget` vai ancorar na `HomePage`. A rolagem da esquerda (site) ocorre independente do Chat à direita. Os CTAs (botões "Saiba mais", "Falar com corretor", "Ver menu") no lado esquerdo não mudam a página, eles **trocam** o agente ou enviam dicas silenciosas para o agente ativo da direita se apresentar com aquele contexto (Intent).

---

## O que precisa ser feito

### No Frontend

1. **Reestruturação CSS/Tailwind do Container Principal (`HomePage.tsx` / `Layout.tsx`)**:
   Implementar um invólucro (Wrapper) tipo CSS Grid (`grid-cols-1 md:grid-cols-[1fr_400px]` ou proporções `60/40`) apenas quando não estamos no admin (para o public facing view).
   - O lado Esquerdo recebe `h-[calc(100vh-navbar)] overflow-y-auto`.
   - O lado Direito (`aside`) renderizará o `AIChatWidget` em modo Tela Cheia do Container, sem a "bolha de minimizar".

2. **Hook de Mapeamento de Rota (`useRouteAgent()` ou expansão do `ChatContext`)**:
   - Como os bots foram mapeados (Tarefa 4.1), no carregamento (`useEffect` via `useLocation` do `react-router`), pesquisar entre todos os Agentes carregados qual `agent.mapped_routes.includes(currentPath)`. Pôr esse Agente no Contexto Principal do React (`currentAgentId`).
   - Se a navegação do usuário for de `/` (Agente A) para `/vendas` (Agente B), a UI do chat fará a transição recarregando o cérebro sem o usuário perceber a troca de domínio sistêmico (preservando History da Session de forma harmoniosa se pertinente ou resetando com saudação condizente ao novo funil).

3. **Interatividade com Botões do Site**:
   - Ações que antes fariam `navigate('/contato')` passarão a invocar o contexto: `chatActions.triggerFlow(AGENT_ID)`.
   - O botão atualizará o contexto, e se a UI for "Smart", enviará um "O Lead clicou em Preços via Interface" invisível via log / payload inicial para a LLM, provocando uma saudação: "Percebi que quer saber nossos preços! Tenho três planos..."

### No Backend
Não se aplica estruturalmente, as lógicas vitais do RAG já existem.

---

## Observações importantes
- Para não poluir as páginas internas (Dashboard Admin), envolva o layout estático exclusivamente sob as *Public Visitor Routes* (`VisitorRoute`).
- Esconda o antigo botão de Bolinha (Toggle Flutuante do Chat) quando o Widget for instanciado no Sidebar de Desktop da Home. Essa regra de Layout Flex é melhor resolvida via `tailwind` escondendo (`hidden md:flex`, `block md:hidden`).

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. No Desktop (Resolução > 1024px), o site abre metade esquerdo, Chat metade direito, rolando esquerdos mas chat intacto.
2. Acessar `/` abre o Agent padrão XYZ e a frase de entrada dele aparece.
3. Apertar num Botão Genérico de Call-To-Action ("Ver Apartamentos") do site imediatamente muda a aba e o Cérebro de IA no Widget para o Agente ZZZ com uma *Initial Message* de "Olha esses apês!", não perdendo o foco do Layout na página em vigor.
4. O Admin Dashboard continua operando 100% de tela ilesa, ignorando o comportamento do grid esmagador.

---

## Dependências
- Backend (Toda a Tarefa 4.1 `mapped_routes` executada para as lógicas REST existirem na orquestração Front-end).

## Próxima tarefa
Tarefa 4.3: Mobile Responsive Layout & Toggle (`spec-027-mobile-split-layout.md`)
