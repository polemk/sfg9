# Tarefa 1: API Pública de Planos com `menu_key`

**Sprint:** 1 — Visitor Preview
**Estimativa:** 0.5 dia
**Tipo:** Backend

---

## Contexto

O visitor que entra no console precisa ver quais recursos cada plano oferece. Para isso, o frontend precisa saber quais itens do menu correspondem a cada plano. Hoje o model `Plan` e `PlanFeature` já existem com relação many-to-many via `PlanFeatureAssignment`, mas não há um campo que conecte uma feature a um item específico do menu do sidebar.

O campo `menu_key` resolve isso: é uma string na `plan_features` que mapeia a feature para uma rota do console (ex: `"leads"` → `/admin/leads`). Com isso o frontend filtra o menu dinamicamente conforme o plano selecionado — mesmo padrão do "comandae" que troca modo e filtra o que aparece.

---

## Onde começa

- `Plan` existe com scopes `active`, `ordered`, campos `color`, `is_popular`, `allows_console_access`
- `PlanFeature` existe com `key`, `label`
- `PlanFeatureAssignment` faz o join com `sort_order`
- Endpoint `Api::V1::Plans` existe mas é OG-only (autenticado)
- Seeds em `db/seeds/plans_and_features.rb`

## Onde termina

- Coluna `menu_key` existe em `plan_features` com index
- Endpoint público retorna planos ativos com features agrupadas incluindo `menu_key`
- Seeds atualizados com `menu_key` para features existentes
- Cache de 15min no endpoint (planos mudam raramente)

---

## O que precisa ser feito

### No Backend

**Migration:** Adicionar coluna `menu_key` (string, nullable) na tabela `plan_features` com index.

**Mapa de menu_keys esperado:**

| menu_key | Rota no Console | Descrição |
| :--- | :--- | :--- |
| `leads` | `/admin/leads` | Gestão de leads |
| `analytics` | `/admin/metrics` | Analytics e KPIs |
| `omnichannel` | `/admin/omnichannel` | Canais de comunicação |
| `operations` | `/operations` | Gestão de operações |
| `users` | `/users` | Gestão de usuários |
| `chatbot` | `/admin/chat/flows` | Chatbot e flows |
| `credentials` | `/admin/credentials` | Credenciais de IA |
| `gallery` | `/media` | Galeria de mídia |
| `showrooms` | `/showrooms` | Showrooms |
| `sales` | `/payments` | Vendas |

**Endpoint:** `GET /api/v1/public/plans/preview` — montar dentro do namespace público existente (sem autenticação). Retorna apenas planos `active` e `ordered`, com features ordenadas pelo `sort_order` da assignment. Usar `Rails.cache.fetch` com TTL de 15 minutos.

**Response esperada:**
```json
{
  "plans": [{
    "id": "uuid",
    "identifier": "pro",
    "title": "Plano Pro",
    "subtitle": "Para quem quer crescer",
    "price": 297.0,
    "pix_price": 267.0,
    "color": "#39ff14",
    "is_popular": true,
    "is_free": false,
    "features": [
      { "key": "lead_capture", "menu_key": "leads", "label": "Captura de Leads" }
    ]
  }]
}
```

**Seeds:** Popular `menu_key` para features existentes. Features que não mapeiam para o menu (ex: feature genérica "Suporte prioritário") ficam com `menu_key: null` — o frontend ignora essas no filtro.

---

## Observações importantes

- Features sem `menu_key` devem aparecer na response normalmente (são listadas no card do plano, só não filtram o menu).
- O cache precisa ser invalidado quando planos ou features são atualizados pelo admin. Verificar se já existe callback de invalidação ou adicionar `Rails.cache.delete('public/plans/preview')` nos models.
- Dashboard não precisa de `menu_key` — ele é sempre visível independente do plano (lógica fica no frontend).

---

## Critérios de aceite

1. `rails db:migrate` roda sem erro
2. `curl localhost:3000/api/v1/public/plans/preview` retorna JSON com planos e `menu_key` nas features
3. Planos inativos não aparecem na response
4. Features sem `menu_key` aparecem com `menu_key: null`
5. Segunda request no mesmo minuto é servida do cache
6. Endpoint funciona sem autenticação
7. Testes RSpec cobrindo: response shape, filtro de inativos, cache, sem auth

---

## Dependências

Nenhuma — pode iniciar imediatamente.

## Próxima tarefa → Spec 02 (Store Zustand + Preview Mode)
