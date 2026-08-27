# Tarefa 3.1: New Lead List Dashboard

**Sprint:** 3 - Lead Management UI
**Estimativa:** 2 dia(s)
**Tipo:** Frontend + Backend

---

## Contexto
Agora que os Leads estão fluindo, quer seja via nós manuais (SaveToLead) ou por extração mágica do AI Agent (Tool Use), nossos usuários (Admin / Tenants) precisarão auditar e manusear esse volume de Leads. O estado atual da interface para listar leads engajados geralmente é difuso ou inexistente. Precisamos de uma "Inbox" ou "Tabela de Leads" muito polida, priorizando quem possui maior pontuação de interações.

---

## Onde começa
- Aos donos de chatbots faltam telas gerenciais eficientes para visualizar quem já converteu.
- Tabelas existentes podem ter visões padrão ou não suportar `Sort` nativo por "Última Interação" ou "Qtd de Mensagens".

## Onde termina
- Uma tela maravilhosa em `React (TypeScript)` usando `shadcn/ui` localmente chamada "Leads" com Tailwind + Glassmorphism ou Neon acccents que condizem com nosso Design System.
- Uma tabela com DataTables listando os Leads com os dados processados: Nome, Email, Resumo de Origem (LeadFlow origin) e `message_count`.
- Filtros interativos para ordenar por `recent` ou `volume_of_messages`.

---

## O que precisa ser feito

### No Backend
- **Endpoint Analítico:** Um endpoint REST em `Api::V1::Admin::LeadsController#index`.
- Ele deve aceitar query params para `sort=recent|volume`, `limit=50`, `page`.
- **Querying:** Use Eager Loading para relacionamentos. O volume de mensagens pode precisar de um `COUNT(lead_messages.id)`. Utilize Subqueries, LATERAL joins, ou counter_caches (`messages_count`) na tabela de Leads para não derrubar a performance (Pois O(n) contas na exibição são fatais).
- Retornar o wrapper Grape Entity paginado em `{ leads: [...], meta: { ... } }`.

### No Frontend
- **Rota e Page:** Em `/admin/leads`, plugar componente `LeadListDashboard.tsx`.
- **Componentes Tailwind-Patterns:** 
  - Estrutura em `#grid-container` responsivo usando Container Queries.
  - O header no padrão "Premium" ou "Neon Dark" subtil, evitando borders excessivos (uso de `divide-y divide-zinc-800`).
  - Barra de Ferramentas (Filters): Select `Filtro de Período` e `SortBy`.
  - Tabela: Cabeçalho limpo. A linha (`tr`) pode ter efeito `hover:bg-zinc-800/50 transition-colors` e apresentar um Badges na coluna de "Status" caso haja Custom Fields mapeados (e.g.: "Hot Lead").

---

## Observações importantes
- **Performance:** Se a base tem 100k leads, certifique-se de que a paginação seja Offset ou Cursor based verdadeira e a ordenação esteja abrigada num INDEX composto no banco postgresql (e.g. `idx_leads_created_updated` ou `idx_messages_count`).
- **UX Psychology:** O usuário quer sentir que "tá lucrando" usando a ferramenta. Dar um destaque (bold, cor accent) nos Leads Criados a partir da Extração de Inteligência Artificial aumenta o ROI percebido do software.

---

## Critérios de aceite
1. Backend: Implementar index na tabela Leads via ActiveRecord com paginação, expondo no grape.
2. Criar pelo menos 3 Leads seed no DB se necessário via rails console associados ao Admin atual.
3. No Frontend, clicar no Menu Lateral "Leads".
4. Visualizar a requisição disparando sem erros (200 OK).
5. Tabela é renderizada trazendo dados limpos.
6. Ao clicar no sorter de "Última Mensagem", a ordem se altera corretamente (ASC/DESC).
7. Cores, hover states e skeletons loaders condizem perfeitamente com um layout premium B2B sem parecer template genérico Vercel (Avoid "Lazy Design Indicators", priorize custom aesthetics).

---

## Dependências
- Backend: As entidades Node / Lead atualizadas pelas tarefas anteriores.

## Próxima tarefa
- Fim da Sprint 3. (Deploy de Release Preview).
