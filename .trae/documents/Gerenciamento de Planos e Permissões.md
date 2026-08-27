## Objetivo
Implementar sincronização imediata entre planos, features e permissões do usuário, com auditoria completa e propagação em tempo real.

## Modelagem
- Permissão (`permissions`): `key` único, `title`, `description`.
- Mapeamento feature→permissão (`plan_feature_permissions`): `plan_feature_id`, `permission_id`.
- Permissões do usuário (`user_permissions`): `user_id`, `permission_id`, `source` (plan|manual), `source_id` (plan_id ou feature_id), `granted_at`, `revoked_at` (nulo quando ativa).
- Conflitos de permissão (`permission_conflicts`): `permission_id`, `conflicts_with_id` (par único).
- Auditoria (`permission_audit_logs`): `user_id`, `plan_id`, `change_type` (grant|revoke|sync), `permissions_added[]`, `permissions_removed[]`, `actor_id`/`actor_type`, `reason`, `source_event` (purchase_done|feature_added|plan_deleted|manual_sync), `metadata` JSON, `created_at`.

## Migrações
- Criar tabelas acima com índices: por `user_id`, `permission_id`, pares únicos e FKs.
- Constraints: unicidade de `permissions.key`; `plan_feature_permissions` único por par; `user_permissions` único por par ativo (revoked_at nulo).

## Services
- `PermissionsSyncService` (include ApiResponseHandler):
  - `grant_for_purchase(purchase)`: quando `status == DONE`, concede permissões do plano ao `purchase.user`.
  - `revoke_for_purchase(purchase)`: em cancelamento/expiração, revoga permissões do plano.
  - `sync_for_plan(plan)`: após editar features, calcula diff e atualiza permissões de todos usuários com `purchase DONE` para o plano.
  - `sync_for_user(user)`: recomputa a visão de permissões do usuário a partir de planos ativos.
  - Aplica validações de conflito antes de gravar; gera logs em `permission_audit_logs`.
- `PlansService` (já existente): após `create/update/destroy` de features, chamar `PermissionsSyncService.sync_for_plan(plan)`.
- `PurchasesService` (ou callbacks em `Purchase`): após transições de status, chamar `grant_for_purchase`/`revoke_for_purchase`.

## Controllers (API)
- `Api::V1::Permissions`:
  - `GET /api/v1/permissions/me` → lista permissões do usuário corrente.
  - Admin: `POST /api/v1/permissions/sync` (por `user_id` ou `plan_id`) → dispara sincronização; retorna entidades padronizadas.
- Ajustar `Api::V1::Plans`/`PlanFeatures` para documentar que alterações propagam permissões.
- Swagger: detalhar success/failure, exemplos, entidades de resposta (Permissions, PermissionAuditLog).

## Entities
- `Api::Entities::Permission`: id, key, title, description.
- `Api::Entities::UserPermission`: permission (embed), source, granted_at, revoked_at.
- `Api::Entities::PermissionAuditLog`: campos de auditoria, incluindo arrays de permissions adicionadas/removidas.

## Realtime
- `PermissionsChannel` (Action Cable): stream por `user_id`.
  - Eventos: `permissions_changed` com lista atual de permissões e diff.
  - Disparado pelo `PermissionsSyncService` após qualquer alteração.
- Opcional: `NotificationsChannel` já existente/planejado pode carregar payloads de permissões.

## Auditoria
- Todas operações do `PermissionsSyncService` gravam uma entrada em `permission_audit_logs` com ator (usuário/admin/sistema), razão e evento de origem.
- Idempotência: operações de grant/revoke verificam estado antes de escrever.

## Validações de Conflito
- Definir regras na tabela `permission_conflicts`.
- `PermissionsSyncService` impede co-existência, revogando as conflitantes antigas ou retornando erro validado (configurável por política: preferir novo plano ou rejeitar alteração).

## Testes Automatizados
- Unit (models/services):
  - `grant_for_purchase` concede permissões corretas e respeita conflitos.
  - `sync_for_plan` aplica diff e grava auditoria.
  - `revoke_for_purchase` revoga e audita.
- Request (Grape):
  - `POST /plans` + add/remove features → dispara sync; `GET /permissions/me` reflete alterações.
  - Admin `POST /permissions/sync`.
- Canal (Action Cable):
  - Broadcast `permissions_changed` com payloads esperados.

## Seeds
- Criar permissões padrão mapeadas às features seed:
  - `console_access`, `whats_integration`, `payments_integration`, `smart_navigation`, `theme_toggle`, `priority_support`.
- Preencher `plan_feature_permissions` para `AI9 Pro` e `AI9 Start` conforme já criado.

## Segurança & Consistência
- Transações: operações de sync/grant/revoke em transações DB com locking otimista.
- Idempotência: chaves únicas e checagens evitam duplicidade.
- Rate-limit opcional em endpoints admin de sync.

## Observabilidade
- Logs estruturados com `request_id`; auditoria detalhada.
- Alertas em caso de falha de broadcast ou inconsistência detectada.

## Entrega
- Implementação completa das migrações, models, services, controllers, entities, canal realtime e seeds.
- Docs Swagger atualizadas com exemplos e códigos.
- Testes automatizados cobrindo sincronização end-to-end.