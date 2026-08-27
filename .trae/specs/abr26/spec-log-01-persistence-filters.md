# Tarefa Log 01: Backend - Paginação, Filtros Dinâmicos e Compatibilidade

**Sprint:** 1 - Fundações & Persistência de Logs
**Estimativa:** 1.5 dia(s)
**Tipo:** Backend

---

## Contexto
O atual módulo de log e analytics salva eventos e renderiza os dados na UI de EventLogger e numa aba legada de Analytics. O problema atual é triplo: a ausência de opções no filtro da interface, a quebra de rolagem infinita/recuperação de logs (faltando paginação apropriada) e um estado quebrado na aba "Analytics Antiga" por conta de mudanças recentes.

Para melhorar o monitoramento em "Study History" versus "Live Stream", precisamos reestruturar os endpoints de busca do Event Logger garantindo que eles aceitem cursores/offset sem matar o banco e criar rotas para alimentar as caixas de seleção (filtros) do frontend.

---

## Onde começa
- Model `TrackedEvent` já armazena os eventos brutos.
- Service `Analytics::ListEvents` já existe, porém de forma monolítica ou sem paginação/opções de filtro avançadas.

## Onde termina
- Rotas de Grape servindo a nova e velha abstração.
- Endpoints de paginação disponíveis para uso no React (`useInfiniteQuery`).
- Endpoint retornando dinamicamente os valores de eventos únicos possíveis (ex: nomes de eventos ou tipos de browsers) para o filtro da UI.

---

## O que precisa ser feito

### No Backend

1. **Refatorar `Analytics::ListEvents` para Paginação**
   - Alterar ou criar uma variante do serviço para suportar paginação em cursor ou baseada em `page`/`per_page`.
   - Adicionar as opções de filtro para tipos de eventos (ex: *click*, *page_view*, *form_submit*), período de data, e/ou ID de usuário na query do ActiveRecord.
   - Retornar meta-informações necessárias, como `total`, `current_page`, `next_page` no Entity Grape.

2. **Criar Serviço e Endpoint de Opções de Filtro (`Analytics::GetFilterOptions`)**
   - Rota: `GET /api/v1/analytics/filters`
   - O serviço deve recuperar do banco as opções distintas (ex: `TrackedEvent.distinct.pluck(:name)`) e enviá-las para que os combos de UI se popularizem com eventos que de fato existem na base.

3. **Restaurar Compatibilidade da Aba Analytics Legada**
   - Verificar as consultas no `Analytics::GetDashboardData` ou serviço equivalente usado pela aba anterior para que não retorne `500` ou dados errados.
   - Caso a estrutura da base tenha mudado, adaptar a consulta (por exemplo, contagem de acessos por dia, DAU, etc.) retornando no contrato Grape esperado pela UI legada.

---

## Observações importantes
> [!TIP]
> Em bancos postgres volumosos, `distinct.pluck` pode ser custoso. Caso a tabela tenha milhões de linhas, utilize uma query agregada otimizada ou crie uma tabela auxiliar/cache Redis (`SET`) para guardar os "nomes de eventos conhecidos" e popular os dropdowns de filtro instantaneamente.

> [!WARNING]
> Certifique-se de que o Service Grape retorne *apenas Entities*, e não objetos do ActiveRecord cru, seguindo estritamente as regras de `backend.md`.

---

## Critérios de aceite
1. O dev deve mostrar que requisições ao endpoint de listagem de eventos com `page=1` e `page=2` trazem resultados distintos (paginação funcional).
2. O dev deve testar a filtragem (enviando `name=click`) e demonstrar que a listagem reflete o filtro corretamente.
3. O dev deve chamar a rota `/api/v1/analytics/filters` e receber opções de filtros (array de categorias ou nomes preenchidos).
4. O dev deve mostrar a "Aba Analytics Antiga" renderizando corretamente as métricas, validando compatibilidade.

---

## Dependências
- Nenhuma dependência estrutural anterior.

## Próxima tarefa
- **Tarefa Log 02:** Integrar esta API paginada e os filtros criados ao Frontend React utilizando `useInfiniteQuery`.
