## Análise de Permissions

- Mapeamento existente: `PlanFeaturePermission` relaciona cada `PlanFeature` a uma `Permission`; unicidade composta e validações garantem integridade.
- Sincronização pronta: `PermissionsSyncService.sync_for_plan(plan)` é chamada após alterações de plano; `grant_for_purchase`/`revoke_for_purchase` disparam em mudanças de status de `Purchase`.
- Conflitos cobertos: `PermissionConflict` impede co-existências indesejadas; serviço verifica e audita.
- Observabilidade: auditoria (`PermissionAuditLog`) e broadcast via `PermissionsChannel` já implementados.
- Conclusão: não são necessários ajustes de backend em `Plan`/`PlanFeature` para suportar a experiência; recomenda-se apenas expor claramente no frontend o `permission.key` de cada feature (read-only) para evitar confusões e garantir visibilidade do impacto.

## Objetivo

Entregar experiência completa no painel administrativo (exclusiva para OG) para cadastrar, listar, editar e excluir Planos e suas Features, seguindo padrões de UI existentes, com associação e ordenação de features por plano.

## Endpoints & Contratos

- Planos: `GET/POST/PUT/PATCH/DELETE /api/v1/plans`, com filtros (`q`, `billing_kind`, `only_active`, `only_free`, `only_popular`) e paginação (`page`, `per_page`). Associação por `features_ids` e ordenação por `features_orders`.
- Features: `GET/POST/PUT/PATCH/DELETE /api/v1/plan_features`, filtros `q`, `only_active`, paginação.
- Tipagem: gerar tipos a partir do Swagger e consumir em `endpoints.ts`.

## Autorização OG

- Guardar rotas com `OgRoute` (unificar critério de OG usando `user.user_type === 'og'` como fonte de verdade).
- Menu (`Topbar`) mostra seções apenas para OG; alinhar com o mesmo critério.

## Páginas — Planos

- Lista de Planos
  - Filtros rápidos: busca (`q`), `billing_kind`, flags (`active/free/popular`).
  - Tabela com colunas: `title`, `price`, `billing_kind`, `active`, `free/popular`, `features_count`, ações.
  - Paginação e estado de loading/empty/error padronizados.
- Criar/Editar Plano
  - Campos: `title`, `identifier`, `price`, `billing_kind`, `active`, `free`, `popular`, rich text (`description`/`price_text`/`baseline_text`).
  - Associação de features: seletor com múltipla escolha + ordenação (drag & drop) refletindo `features_orders`.
  - Resumo de permissões: mostrar `permission.key` read-only ao lado de cada feature selecionada.
- Excluir Plano
  - Modal de confirmação; feedback de sucesso/erro; invalidar/incrementar cache.

## Páginas — Features

- Lista de Features
  - Filtros: `q`, `only_active`; colunas: `title`, `active`, `permission.key` (read-only), ações.
- Criar/Editar Feature
  - Campos: `title`, `identifier`, `active`, rich text `description`.
  - Exibir (read-only) `permission.key` vinculado; orientação: alterações de permissão são feitas fora (se necessário), não no CRUD de features.
- Excluir Feature
  - Modal de confirmação; impedir exclusão se estiver associada a planos (mensagem clara); seguir resposta padronizada de erro.

## UX/Estilo

- Reutilizar `Layout`, `Topbar`, `PageHeader`, `Button`, `Input`, `Tooltip` e padrões de cards.
- Toasts padronizados para sucesso/erro; skeletons; mensagens empty com dicas.
- Aderir aos temas dark/light via tokens CSS já definidos.

## Dados & Estado

- `@tanstack/react-query` para `useQuery`/`useMutation`, invalidation granular por rota.
- Paginação com cabeçalhos `X-Total-Count` e `Link` (se expostos); caso contrário, paginação local.
- Form state com controlled inputs; mascaras conforme necessário.

## Erros & Segurança

- Validar parâmetros no cliente alinhado ao contrato; exibir envelope padronizado de erros.
- Rate-limit já coberto no backend; no frontend, debouncing de busca.
- Não permitir usuários não-OG acessar nem ver menus/rotas.

## Testes

- Unit (frontend): componentes de tabela, formulários e hooks de data (React Query) com Vitest/RTL.
- Integração: fluxo CRUD end-to-end com mocks de API, estados de erro/sucesso.

## Entregáveis

- Novas rotas admin: `/admin/plans` e `/admin/features` (protegidas por `ProtectedRoute` + `OgRoute`).
- Páginas com CRUD completo; associação e ordenação de features em planos.
- Tipos e endpoints atualizados; documentação resumida no README da área admin.
- Testes automatizados e lint sem avisos.