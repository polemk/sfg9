# Tarefa 061.1: Eventos Acumulados com Infinite Scroll e Filtros

**Sprint:** 2 — Explorador de Comportamento
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto

Atualmente o analista tem acesso a uma aba restrita no Event Logger onde não consegue consultar eventos anteriores a um limite arbitrário (limit set by current frontend fetching limits without pagination support) e as opções de filtro não funcionam de maneira unificada e infinita para recuperar informações passadas, tornando o log de comportamento quase inútil.
Vamos mudar a tabela para carregar de forma acumulada e contínua com Infinite Scroll.

---

## Onde começa

- `EventLoggerPage` no frontend React, que provavelmente faz requisição via Axios/Zustand ou algo simples com limit fixo.
- Spec 060.1 completa (Backend fornecendo endpoints paginados).
- Spec 060.2 completa (Backend enviando dados das opções de dropdown para o filtro).

## Onde termina

- Uma UI com scroll contínuo e filtros funcionando baseados em opções vivas vindas da API (ex: `event_type`, `niche`), melhorando a análise comportamental.

---

## O que precisa ser feito

### No Frontend

1. **Migração do Fetch para Paginado:** Refatorar o fetch da página de métricas/analytics para usar chamadas paginadas (React Query - `useInfiniteQuery` é a abordagem recomendada pelas rules, ou adaptações usando Axios puro + estados de "hasMore" & "page").
2. **Implementação de Intersection Observer:** Conectar a rolagem do container final à ativação do callback da próxima página de dados.
3. **Mapeamento de Filtros UI:** Modificar a UI de filtro superior para carregar valores retornados pelo endpoint de extração dinâmica.
4. **Debounce:** Aplicar debounce de 300-500ms em buscas ou preenchimento manual de filtro de search que interaja com o backend de logs.

### Componentes chave (Exemplo)

- `EventLoggerPage.tsx` ou similar.
- Criar Hook próprio: `useInfiniteEvents(filters)`.
- Fazer a passagem de filtros combinada nos argumentos do GET de endpoint de listagem.

---

## Observações importantes

- Nunca resetar o scroll position para zero quando novos eventos antigos forem carregados na lista inferior, prender sempre a posição relativa correta (funcionamento padrão de Infinite Scroll com adição final de Nodes na lista React).
- Os logs carregados no endpoint são estáticos (dados passados). O Live events (novo módulo futuro) será tratado depois. O foco aqui é estudo retroativo.

---

## Critérios de aceite

1. Abrir a aba, visualizar os primeiros X logs da tela.
2. Fazer Scroll-Down, ver loading skeleton (ou spinner menor).
3. Novas linhas surgem no fim da lista com registros mais antigos vindos da API, sem sobresscrever os acima ou resetar view (paginação).
4. Selecionar na Dropdown de Tipo o evento 'HeatmapClick'.
5. O Array inteiro é zerado e inicia apenas com 'HeatmapClick', novamente aplicando scroll infinito.

---

## Dependências

- Specs 060.1 e 060.2.

## Próxima tarefa → Spec 061.2 (Live Events View)
