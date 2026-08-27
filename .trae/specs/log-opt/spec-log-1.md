# Tarefa LOG.1: Melhoria na Paginação e Filtros (Backend)

**Sprint:** 1 — Fundações do Histórico e Correção de Filtros
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto
O endpoint `Analytics::ListEvents` atualmente busca os eventos logados, mas a página frontend não possui as opções (facets) corretas para preencher os dropdowns de filtros dinamicamente. Além disso, precisamos garantir a paginação baseada em cursor (`before_id`) em vez de offset/limit tradicionais, para que o "Scroll Infinito" da UI funcione e não tenhamos gargalos de performance (N+1).

---

## Onde começa
- `Analytics::ListEvents` já existe e aplica filtros textuais/básicos (`event_type`, `niche`, `user_id`).
- Paginação baseada em limit já opera parcialmente.

## Onde termina
- O endpoint retorna, além do array de `events`, uma chave `facets` agrupando os valores únicos disponíveis na base para que a interface construa os menus.
- O endpoint processa `before_id` devolvendo os registros estritamente mais antigos que o ID passado.

---

## O que precisa ser feito

### No Backend
1. **Facet Extraction:**
   No final do serviço `Analytics::ListEvents`, realizar um `distinct.pluck` rápido ou agregação em `event_type` e `niche` (focados no range pesquisado, ou tabelas globais) para devolver as opções disponíveis de filtro.
2. **Cursor Pagination:**
   Se `params[:before_id]` estiver presente, injetar `where('id < ?', params[:before_id])` na chain do ActiveRecord.
   O payload final deve ser semelhante a:
   ```json
   {
     "data": {
       "events": [...],
       "facets": {
         "event_types": ["click", "view", "conversion"],
         "niches": ["beauty", "tech"]
       },
       "next_cursor": "uuid-do-ultimo-evento"
     }
   }
   ```

---

## Critérios de aceite
1. Fazer requisição GET com filtros e verificar se os `facets` vêm preenchidos corretamente.
2. Fazer requisição passando um `before_id` e checar se apenas registros mais antigos são retornados.

---

## Dependências
- Nenhuma.

## Próxima tarefa
- Spec LOG.2 (Implementação do Frontend Infinite Scroll usando os novos facets).
