## Objetivo
- Renomear a seção do painel administrativo de "Pagamentos" para "Vendas".
- Substituir a tela atual por uma lista em formato de tabela com as vendas realizadas (pagamento único e assinatura), com paginação, filtros básicos e status.

## Escopo e Impacto
- Frontend (React .tsx): atualização de rotas/labels e criação de tabela de vendas.
- Backend (Rails + Grape): novo endpoint unificado para listar vendas (one‑time e subscription) com paginação, seguindo o padrão Services + Entities.
- Não alterar o fluxo de checkout; apenas a visão administrativa.

## Mudanças no Frontend
- Atualizar rotas/labels:
  - `frontend/src/app/App.tsx`: manter a rota existente `'/payments'` e adicionar alias `'/vendas'` apontando para a mesma página.
  - `frontend/src/app/pages/PaymentsPage.tsx`: alterar título/labels visíveis para "Vendas". Opcionalmente renomear o componente para `SalesPage` mantendo compatibilidade.
- Criar tabela de vendas:
  - Novo componente `frontend/src/features/sales/SalesTable.tsx` exibindo colunas: `ID`, `Cliente`, `Tipo` ("Único"/"Assinatura"), `Método` (PIX/Cartão), `Valor`, `Status`, `Criado em`.
  - Paginação server-side (`page`, `perPage`) e ordenação client-side simples.
  - Filtros básicos: `status` e `tipo`.
- Cliente de API:
  - `frontend/src/lib/api/endpoints.ts`: adicionar `salesApi.list(page, perPage, filters)` consumindo `GET /asaas/v1/sales`.
  - Hook `useSalesList` com React Query para carregar a tabela, estados de loading/error e retry.
- UX:
  - Header usando `PageHeader` com título "Vendas".
  - Badges para `status` e `tipo`; valores humanizados pt-BR.
  - Toastr padronizado em erro e skeletons no carregamento.

## Mudanças no Backend
- Controller Grape:
  - `backend/app/controllers/api/asaas/v1/base.rb`: montar `Sales`.
  - Novo arquivo `backend/app/controllers/api/asaas/v1/sales.rb` com endpoint:
    - `GET /sales` → lista unificada de vendas com paginação; `desc` completa, validação de parâmetros, e documentação swagger.
    - Controllers finos: `process_service_response(SalesService.index(params))` e `set_pagination_headers`.
- Service:
  - `backend/app/services/sales_service.rb` seguindo o padrão:
    - `include ApiResponseHandler`.
    - Consulta ao modelo `Purchase` (cobranças únicas e assinaturas) com filtros (`status`, `tipo`), paginação (`page`, `per_page`) e ordenação por `created_at desc`.
    - Mapeia para Entity e retorna via `success_response({ sales: Api::Entities::Sale.represent(collection), total }, 200)`.
- Entity:
  - `backend/app/entities/api/entities/sale.rb` com campos: `id`, `customer_name`, `customer_email`, `amount`, `currency`, `status`, `type` (`one_time`/`subscription`), `method` (`pix`/`credit_card`), `subscription_id` (quando existir), `external_id` (id Asaas), `created_at`.
- Padrão de Erros e Documentação:
  - Validar parâmetros no Grape e responder via `validation_error_response`.
  - Documentar via `grape-swagger` com exemplos de resposta e códigos HTTP.

## Dados e Fonte da Verdade
- Usar o modelo `Purchase` atualizado pelos webhooks Asaas:
  - Webhook (`backend/app/controllers/api/asaas/v1/webhooks.rb`) já atualiza e faz broadcast via `PaymentsChannel`.
  - Consulta única em `SalesService.index` evita bater diretamente na Asaas e garante desempenho.

## Realtime (Opcional)
- Na tabela, revalidar a query (refetch) ao receber eventos em `PaymentsChannel` (`type: 'payment_update'`) para refletir mudanças de status em tempo real.

## Testes
- Backend:
  - Request spec para `GET /asaas/v1/sales` (paginação, filtros, envelope/entidade).
  - Unit spec para `SalesService.index` (combinação de tipos e status).
- Frontend:
  - Testes de renderização do `SalesTable` com estados loading/empty/error.
  - Integração simples do hook `useSalesList` com mock de API.

## Segurança e Qualidade
- Responder com envelope padrão (`data/meta/errors`) e cabeçalhos de paginação.
- Lints (`rubocop`, `eslint`), tipos estritos (TS), sem `any`.
- Sem exposição de segredos; apenas dados agregados de `Purchase`.

## Arquivos/Pontos de Alteração
- Frontend:
  - `frontend/src/app/App.tsx`
  - `frontend/src/app/pages/PaymentsPage.tsx` (ou novo `SalesPage.tsx`)
  - `frontend/src/features/sales/SalesTable.tsx`
  - `frontend/src/lib/api/endpoints.ts`
- Backend:
  - `backend/app/controllers/api/asaas/v1/base.rb`
  - `backend/app/controllers/api/asaas/v1/sales.rb`
  - `backend/app/services/sales_service.rb`
  - `backend/app/entities/api/entities/sale.rb`
  - `backend/app/models/purchase.rb` (apenas leitura)

## Entregáveis
- Tela "Vendas" com tabela paginada e filtros.
- Endpoint `GET /asaas/v1/sales` com documentação swagger.
- Testes backend/frontend verdes e lints limpos.

## Rollback
- Mantida rota `'/payments'` por compatibilidade; alias `'/vendas'` pode ser removido facilmente.
- Endpoint novo é aditivo; sem remoção de rotas existentes.