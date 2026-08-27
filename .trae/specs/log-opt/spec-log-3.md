# Tarefa LOG.3: Reestruturação da UI do Event Logger

**Sprint:** 2 — Separação de Live View vs Acumulado
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto
O usuário precisa de um local rápido para debugar o que está acontecendo agora (como um logcat via WebSocket), e outro local de pesquisa profunda onde a página analisa históricos, aplica filtros e perfis de sessão. Se tudo ocorrer na mesma tela, o buffer do WebSocket bagunça as queries de scroll infinito e confunde o foco. A separação por Abas resolve isso.

---

## Onde começa
- Hooks `useEventStream` (WebSocket) funcionando.
- Hook de Scroll Infinito (Spec LOG.2) operante.

## Onde termina
- A URL `/admin/logger` possui um *Tabs/SegmentedControl* entre "Live Monitor" e "Study History".
- Cada tab lida estritamente com sua própria fonte de verdade.

---

## O que precisa ser feito

### No Frontend
1. **Isolar os Contextos (Tabs):**
   - Importar o componente de Tabs do shadcn/ui ou radix-ui.
   - Em "Live Monitor", renderizar uma tela preta/estilo terminal, injetando puramente os blocos iterados de `useEventStream`. Esta aba não precisa ter os dropdowns complexos de busca.
   - Em "Study History", mover a grande tabela desenvolvida nas Sprints anteriores. Nela fica proibida a injeção em tempo real que desordena a listagem. A base dela é exclusivamente o React Query via API REST, estático até se rolar.

---

## Critérios de aceite
1. Entrar na página de Eventos: 2 opções visíveis no topo (Live, History).
2. Na tab Live: Novos eventos estouram no topo da tela conforme cliques ocorrem em paralelo em outro navegador.
3. Na tab History: Interface limpa, com filtros. Não "pisca" e não altera a ordem dos itens ao menos que uma nova busca/filtro manual seja invocada.

---

## Dependências
- Spec LOG.2 concluída.

## Próxima tarefa
- Spec LOG.4 (Ajuste Final de Heatmap)
