# Tarefa LOG.2: Scroll Infinito e População de Filtros (Frontend)

**Sprint:** 1 — Fundações do Histórico e Correção de Filtros
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto
O `EventLoggerPage.tsx` está exibindo apenas eventos recentes devido a uma query limitada, impedindo que o usuário possa voltar no tempo. A tela possui botões de filtro (Event Type, Niche) mas estão vazios pois dependiam de states locais. Vamos mudar a tabela para carregar automaticamente o passado (Scroll Infinito) e plugar os filtros dinâmicos vindos da API.

---

## Onde começa
- Tabela de Eventos construída.
- Selects da UI renderizados mas inativos.
- Backend já devolve `facets` e suporta `before_id` (visto na Spec LOG.1).

## Onde termina
- A rolagem até o final da lista recarrega automaticamente dados anteriores da base de dados.
- Dropdowns de EventType/Niche contêm opções validadas, baseadas na realidade da conta do lojista/usuário.

---

## O que precisa ser feito

### No Frontend
1. **Trocar a Consulta React Query:**
   - Em vez de usar a query básica com `fetcher`, criar/utilizar um hook baseado no `useInfiniteQuery`.
   - Mapear a rota `getNextPageParam` retornando o `next_cursor` provido pela Spec LOG.1.
2. **Componente de Intersecção:**
   - Adicionar uma `<div ref={observerRef}></div>` oculta no final da lista mapeada de eventos.
   - Usar um `useEffect` e o `IntersectionObserver` para disparar `fetchNextPage()` assim que a `div` for vista na tela.
3. **Plugar os Filtros:**
   - Aproveitar o objeto `facets` obtido do primeiro request.
   - Iterar nas Select Boxes de "Tipo de Evento" e "Nicho". Ao alterar um valor, resetar o scroll infinito e reinjetar no request.

---

## Critérios de aceite
1. Seleções de Niche ou Type disponíveis refletem o que existe no banco (facets).
2. Rolar a tabela até o final dispara uma tag de `Loading...` curta e injeta os novos eventos na UI sem perder os anteriores.

---

## Dependências
- Spec LOG.1 (Backend)

## Próxima tarefa
- Spec LOG.3 (Separação entre tela "Live" e "Histórico")
