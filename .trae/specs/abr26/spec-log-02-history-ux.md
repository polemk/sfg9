# Tarefa Log 02: Frontend - Live Monitor, Study History & Infinite Scroll

**Sprint:** 2 - Live Monitor vs Study History (UX e Frontend)
**Estimativa:** 2 dia(s)
**Tipo:** Frontend

---

## Contexto
No atual módulo visual `EventLoggerPage.tsx`, os eventos são exibidos como uma lista genérica focando puramente no "elemento HTML clicado". Isso dificulta muito investigar o comportamento histórico dos visitantes. 

A solução proposta é dividir a tela em duas grandes áreas: 
1. **Live Monitor**: (já existente/operante usando websockets) que exibe o que está acontecendo "agora".
2. **Study History**: a nova aba de investigação. Aqui usaremos um visual aprimorado e paginação em scroll infinito, consumindo as rotas backend refatoradas para exibir dados de "trilha do usuário" (origem, UTM, jornada temporal), em vez de apenas o nome técnico do elemento.

---

## Onde começa
- `EventLoggerPage.tsx` está operante mas apresenta um UX fraco para estudo analítico.
- Rotas Backend (da Tarefa Log 01) já oferecem suporte à paginação (ex: `page=X`) e listagem de opções para filtros dinâmicos.

## Onde termina
- O `EventLoggerPage.tsx` terá 2 tabs ou views distintas: Live e History.
- Aba "History" rodando `useInfiniteQuery` via React Query e carregando novos blocos de logs na descida da página (Intersection Observer).
- Filtros visuais estarão listando categorias/nomes corretos vindos da API.

---

## O que precisa ser feito

### No Frontend

1. **Separação Abstrata (Tabs)**
   - Introduzir o uso de Tabs (`radix-ui/tabs` ou equivalente do `shadcn/ui`) para alternar entre `Live` e `History`.
   - Garantir que a aba antiga de "Analytics" (que foi corrigida no backend) seja renderizada corretamente caso seja agrupada no mesmo painel.

2. **Integração de Filtros (Filters Header)**
   - Buscar os valores dinâmicos batendo em `/api/v1/analytics/filters` e preencher os combos (ex: `Select` do Radix) permitindo filtragem múltipla ou unitária por tipo, data, etc.

3. **Integração Infinite Scroll (`useInfiniteQuery`)**
   - Configurar o `react-query` para bater na listagem paginada (`GET /api/v1/analytics/events?page=...`).
   - Usar `IntersectionObserver` (ou a biblioteca `react-intersection-observer`) atrelado a um ref na base da lista. Quando esse ref entrar em cena, disparar o `fetchNextPage()`.

4. **Nova Componentização do Evento (EventCard/EventRow)**
   - Criar um componente (`EventCard` ou `EventTimelineRow`) para exibir a carga do evento de forma humanizada.
   - Mostrar a "Jornada do Usuário": Quais UTMs trouxeram ele? Que página ele estava antes? Em vez de um dump JSON, extrair do metadata as props de contexto e desenhar uma timeline intuitiva.

---

## Observações importantes
> [!TIP]
> Em listas renderizadas com *Infinite Scroll*, atente-se à performance de renderização no React. Como os logs tendem a crescer infinitamente na DOM, dependendo da necessidade de estudo, estude adicionar virtualização da lista (ex: `@tanstack/react-virtual` ou similar) se começar a engasgar o scroll, embora o limite inicial possa bastar com paginação normal.

> [!WARNING]
> Mantenha a tipagem rígida no arquivo de endpoints do Axios (`endpoints.ts`) para que os responses de Paginação e os filtros da Nova API fiquem devidamente documentados com seus `interfaces`.

---

## Critérios de aceite
1. O dev deve mostrar a seleção de abas (Live, History, Analytics) e demonstrar que a mudança de aba interrompe renders desnecessários de websockets onde não deve.
2. O dev deve rolar o mouse na aba "History" até o final e comprovar o trigger da próxima página carregando logs históricos (infinite scroll).
3. O dev deve mudar um filtro (ex: "apenas views") e a tela deve dar "refetch" trazendo a lista filtrada, com as opções disponíveis refletindo os eventos reais que vêm do banco.
4. O componente da listagem deve formatar dados amigavelmente, escondendo JSON cru em favor de informações de Jornada e UTM.

---

## Dependências
- Tarefa Log 01 (Rotas paginadas e API de filtros prontos no Backend).

## Próxima tarefa
- **Tarefa Log 03:** Correções pontuais no Heatmap e visões adicionais.
