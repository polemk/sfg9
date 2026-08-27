## Visão Geral
- Evoluir o dashboard atual (`frontend/src/app/pages/DashboardPage.tsx`) para uma visão unificada, com gráficos, tabelas, KPIs em tempo real, filtros e exportações.
- Integrar dados provenientes de vendas/assinaturas (módulo Asaas) e leads (módulo v1) seguindo os padrões Services + Entities + Grape.
- Garantir responsividade, desempenho, acessibilidade (WCAG) e atualização automática.

## Backend — API de Analytics
- Criar endpoint: `GET /api/v1/analytics/dashboard` (Grape) com documentação completa (summary, detail, HTTP codes, params, exemplos) e filtros: `periodo={day|week|month|quarter|year}`, `date_from`, `date_to`, `region`, `product_type`.
- Service: `app/services/analytics_service.rb` (seguindo padrão):
  - Consolida dados de `SalesService` (vendas e assinaturas) e `LeadService` (leads).
  - Retorna Entities agregadas: `Api::Entities::Analytics::Dashboard` com:
    - `sales_monthly`: série mensal (para barras), incluindo rótulos e valores.
    - `subscriptions_growth`: série temporal (para linhas), acumulado ou variação.
    - `leads_distribution`: por fonte (para pizza).
    - `top_products`: itens com `name`, `volume`, `amount`, `rank`.
    - `lead_conversion_by_channel`: `channel`, `leads`, `converted`, `rate`.
    - `metrics_summary`: `{ cac, ltv, retention_rate, arpu }`.
    - `kpis_realtime`: `{ total_sales, new_subscriptions, leads_converted }`.
  - Implementa validação de parâmetros e retorna via `success_response`/`error_response`.
- Entities:
  - `app/controllers/api/entities/analytics/dashboard.rb` (estrutura do payload agregado).
  - Sub-entidades aninhadas (sales, subscriptions, leads, tables) para manter contrato claro.
- Atualização em tempo real:
  - `app/channels/dashboard_channel.rb`: publica diffs de KPIs quando `Purchase/Subscription/Lead` mudam.
  - `ApplicationCable::Connection` já valida JWT; restringir por roles.
- Exportações:
  - `GET /api/v1/analytics/dashboard/report.csv` com base nos filtros (gera CSV server-side).
  - `GET /api/v1/analytics/dashboard/report.pdf` para PDF (proposta: adicionar `prawn` como gem para renderização simples). Documentar ambos.
- Performance:
  - Cache leve (`Rails.cache.fetch` 30–60s) para agregações pesadas, invalidado por eventos.
  - Paginação e `sort_by/sort_dir` em `top_products` e `lead_conversion_by_channel`.

## Frontend — UI e Interações
- Página: `DashboardPage.tsx` (refatorar mantendo rotas atuais) com layout responsivo.
- Filtros:
  - Componente `DashboardFilters.tsx` com controles de período, região e tipo de produto; sincroniza querystring.
- Gráficos (sem novas libs por padrão):
  - Barras: `BarChart.tsx` (SVG) para `sales_monthly`.
  - Linhas: `LineChart.tsx` (SVG) para `subscriptions_growth`.
  - Pizza: `PieChart.tsx` (SVG) para `leads_distribution`.
  - Todos com tooltips acessíveis, `aria-label`, descrição e legenda.
  - Observação: Opcionalmente, se aprovado, usar `recharts` para recursos avançados.
- Tabelas:
  - `TopProductsTable.tsx`: sort client-side, paginação, colunas responsivas.
  - `LeadConversionTable.tsx`: exibe taxas por canal, ordenável.
  - `MetricsSummaryTable.tsx`: mostra CAC, LTV, retenção, ARPU.
- KPIs e indicadores:
  - `KpiCards.tsx`: total de vendas, novas assinaturas, leads convertidos.
  - `PerformanceIndicators.tsx`: comparação vs metas configuradas (`settings`), com ícones/up-down.
  - `AnomalyAlerts.tsx`: destaca tendências/alertas (limiares definidos em config).
- Atualização automática:
  - Hook `useAutoRefresh.ts` que consulta `analyticsApi.dashboard` em intervalo configurável (ex.: 30s), com `AbortController` e backoff.
  - Integração com Action Cable via `useChannel('DashboardChannel')` para empurrar KPIs em tempo real.
- Exportações:
  - Botões `ExportCSV` e `ExportPDF`:
    - CSV: gera via Blob no cliente para dados visíveis.
    - PDF: chama endpoint `/report.pdf` e baixa arquivo.
- Estado e HTTP:
  - `src/lib/api/endpoints.ts`: adicionar `analyticsApi.dashboard`, `analyticsApi.reportCsv`, `analyticsApi.reportPdf`.
  - Reutilizar `axios` pré-configurado em `client.ts` (interceptores JWT/refresh).

## Acessibilidade (WCAG)
- Navegação por teclado em filtros/tabelas; foco visível.
- Alternativas textuais para gráficos (`aria-describedby` com resumo numérico).
- Contraste adequado (usar tokens de tema existentes).
- Tabelas com `scope`/`th` corretos, e textos para leitores de tela.

## Desempenho
- Evitar re-renderizações: memoização dos componentes de gráfico e tabela.
- Consultas agregadas com cache curto e paginação.
- Lazy-loading de seções (split por componente) se necessário.

## Testes e Qualidade
- Backend: RSpec de services (cálculos) e requests do endpoint de analytics; cobertura ≥ 90%.
- Frontend: Vitest para hooks e componentes (gráficos, tabelas, KPIs) e testes de acessibilidade básicos.
- Lint: `rubocop` e `eslint`; sem offenses.
- Swagger: publicar em `/swagger_doc` atualizado; visualizar em `/docs`.

## Entregáveis por Arquivo
- Backend:
  - `backend/app/controllers/api/v1/analytics.rb` (controller Grape)
  - `backend/app/services/analytics_service.rb`
  - `backend/app/controllers/api/entities/analytics/dashboard.rb` (+ subentities)
  - `backend/app/channels/dashboard_channel.rb`
- Frontend:
  - `frontend/src/app/pages/DashboardPage.tsx` (refatorado)
  - `frontend/src/components/dashboard/DashboardFilters.tsx`
  - `frontend/src/components/charts/BarChart.tsx`
  - `frontend/src/components/charts/LineChart.tsx`
  - `frontend/src/components/charts/PieChart.tsx`
  - `frontend/src/components/tables/TopProductsTable.tsx`
  - `frontend/src/components/tables/LeadConversionTable.tsx`
  - `frontend/src/components/tables/MetricsSummaryTable.tsx`
  - `frontend/src/components/kpi/KpiCards.tsx`
  - `frontend/src/components/kpi/PerformanceIndicators.tsx`
  - `frontend/src/components/alerts/AnomalyAlerts.tsx`
  - `frontend/src/hooks/useAutoRefresh.ts`
  - `frontend/src/lib/api/endpoints.ts` (novas funções)

## Observações Técnicas
- Caso seja preferível usar uma lib de gráficos (ex.: `recharts`), incluiremos e ajustaremos a acessibilidade e performance.
- Para PDF, sugerimos `prawn` (leve) no backend; alternativa: exportar via impressão do navegador, mas perde padronização.
- Metas de performance e limites de alerta podem viver em um arquivo de configuração versionado.

## Próximo Passo
- Confirmar este plano (especialmente escolha entre gráficos SVG custom versus biblioteca e adoção de `prawn` para PDF). Após confirmação, implemento as mudanças e valido end-to-end.
