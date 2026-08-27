# Tarefa 060.1: Paginação Otimizada de Eventos

**Sprint:** 1 — Infraestrutura de Dados e Filtros
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto

A tela atual de Event Logger não suporta carregar eventos antigos ou infinitos; ela tenta trazer uma quantidade grande de uma vez ou a view fica restrita. O analista não consegue voltar no tempo ou estudar os dados de maneira estruturada.
A ideia é que os dados do Event Logger tenham uma paginação limpa (ou infinite scroll no frontend) a partir do backend.

---

## Onde começa

- Controller `Analytics::ListEvents` ou similiar no Grape ou Rails Controllers existe atualmente e traz as métricas/logs, mas de forma travada e possivelmente não paginada corretamente.

## Onde termina

- Rota de visualização de logs retornando objetos de paginação corretos (`page`, `per_page`, `X-Total-Count`, e/ou cursores de tempo) baseando-se em `created_at DESC` para as métricas.

---

## O que precisa ser feito

### No Backend

1. **Atualizar Listagem:** Modificar o serviço (ex: `AnalyticsService` ou `EventsService`) para aceitar parâmetros de `page` e `per_page`.
2. **Implementar Filtros Dinâmicos na Consulta:** Aplicar scopes para filtragem via SQL, suportando queries como:
   - `where(event_type: params[:event_type])` se enviado.
   - Filtrar logs por URL/nicho/UTMs caso presentes no filtro do request.
3. **Formatos Grape/JSON:** Adicionar nas Entities correspondentes informações ricas sobre a paginação (`total_count`, `total_pages`).

### Exemplo do Service / Padrão:

Deve seguir rigorosamente o `backend.md`, chamando `set_pagination_headers` no controller do Grape, enquanto o service em si retorna `data`, `total`.

---

## Observações importantes

- Eventos crescem muito rápido no banco de dados. Tenha certeza de que as queries de count estão usando índices corretos.
- Evite queries pesadas na paginação se a tabela já estiver superlotada (considere paginação baseada em keyset/cursor caso a performance com offset esteja ruim).

---

## Critérios de aceite

1. Uma chamada GET para listar eventos com `?page=1&per_page=20` traz exatamente 20 eventos mais recentes.
2. É retornado via header `X-Total-Count`.
3. Os filtros (`event_type`, etc.) se fornecidos aplicam restrições no retorno total e na paginação corretamente.

---

## Dependências

- Nenhuma.

## Próxima tarefa → Spec 060.2 (Filtros Metadados)
