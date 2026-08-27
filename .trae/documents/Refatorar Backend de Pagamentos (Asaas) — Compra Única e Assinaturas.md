## Objetivo

Preparar o backend para pagamento único (PIX/Cartão) e assinaturas (cartão), usando a integração já disponível em `AsaasConnection`, migrando as lógicas legadas para Services finos + Controllers Grape, com Entities padronizadas e webhooks consistentes.

## Situação Atual (Levantamento)

* Integração Asaas: `backend/app/services/asaas_connection.rb` cobre customer, charge, pixQrCode, tokenize card, payWithCreditCard, subscriptions (create/update/cancel), get status.

* Fluxo legado de compra única: `payment_controller.rb` cria customer, `Purchase`, cobra PIX/cartão, processa webhook, envia notificações WhatsApp, trata referral code.

* Fluxo legado de assinaturas: `subscriptions_controller.rb` cria customer/token/assinatura, atualiza cartão, cancela, configura invoice, persiste dados em `Subscription` e `User`.

* Webhooks: `AsaasPaymentWebhookService` já processa eventos de assinatura (confirmado/atraso/estorno) e notifica via ActionCable.

* Observação: método de invoice citado no legado (`configure_subscription_invoice`) não está em `AsaasConnection`; existem controllers `api/asaas/v1/invoices.rb` que podem ser usados para essa responsabilidade.

## Decisão de Modelagem

* Manter modelos distintos: `Purchase` (compra única) e `Subscription` (recorrente).

  * Razões: entidades Asaas e webhooks são diferentes; FSM/estados e prazos não se unem bem; simplifica regras de inadimplência/overdue e cancelamento.

* `User` guarda IDs/token do Asaas quando aplicável (customer\_id, subscription\_id, credit\_card\_token, brand, etc.).

* `Criar User` e logar automaticamente quando o pagamento e feito e concluido.

## Endpoints (Grape) — API-first

* `/asaas/v1/payments` (compra única)

  * `POST /charges` — cria cobrança (PIX/cartão) e retorna `Purchase` + dados do método (QR/confirmado).

  * `GET /charges/:id` — consulta status.

  * `GET /charges/:id/pix_qrcode` — QR Code PIX.

  * `POST /charges/:id/pay_credit_card` — captura com cartão tokenizado.

* `/asaas/v1/subscriptions` (recorrente)

  * `POST /` — cria assinatura com cartão (novo customer ou reutiliza).

  * `PUT /:id/credit_card` — atualiza cartão.

  * `DELETE /:id` — cancela.

* `/asaas/v1/webhooks` — recebe eventos de pagamento/assinatura e aciona `AsaasPaymentWebhookService` (assinaturas) e um novo `AsaasChargeWebhookService` (compras únicas), atualizando `Purchase`.

## Services (fino, regras de negócio)

* `Payments::CreateCharge` — orquestra compra única:

  * cria/resolve `customer` no Asaas a partir do buyer

  * cria `Purchase` local (cycle=UNIQUE, billing\_type PIX/CREDIT\_CARD, installment\_count quando houver)

  * se PIX: `create_charge` + `pixQrCode` e retorna payload

  * se Cartão: `tokenize_card` + `create_charge` + `payWithCreditCard` e atualiza status

  * aplica `referral_code` (param/typed) e `ensure_user_account!` quando pago

* `Payments::GetChargeStatus`, `Payments::GetPixQRCode`, `Payments::PayWithCard`

* `Subscriptions::Create` — cria assinatura:

  * atualiza dados de cartão/titular no `User`

  * cria/reaproveita `customer`

  * tokeniza cartão

  * `create_subscription` e cria `Subscription` local com identifier (externalReference)

  * configura invoice via `api/asaas/v1/invoices` controller/service

  * atualiza `User` com `customer_id`, `subscription_id`, `credit_card_token`

* `Subscriptions::UpdateCard`, `Subscriptions::Cancel`

* `AsaasChargeWebhookService` — processa `PAYMENT_CONFIRMED/RECEIVED/OVERDUE/REFUNDED` para `Purchase` e notifica (similar ao já existente para assinatura).

## Entities (Grape)

* `Api::Entities::Purchase` — id, identifier, status, billing\_type, value, cycle, installment\_count, asaas\_id, meta.

* `Api::Entities::Subscription` — id, identifier, status (ACTIVE/EXPIRED/INACTIVE), plan, asaas\_id, next\_due, meta.

* Controllers nunca chamam `present`; sempre `process_service_response` conforme padrões do projeto.

## Migrações (portar para `backend/db/migrate`)

* `add_asaas_to_user` — `customer_id`, `subscription_id` etc.

* `add_credit_card_to_user` — dados do cartão/titular (sem guardar CVV), conformidade.

* `add_credit_card_brand_to_user` — `credit_card_brand`.

* `add_identifier_to_plan` — `identifier` único.

* `create_subscriptions` — tabela `subscriptions` com `identifier`, `user_id`, `plan_id`, `asaas_id`, `status`, `cycle`, `value`, timestamps.

* Todas com UUID, reversíveis e idempotentes.

## Webhooks & Notificações

* Unificar endpoint `/asaas/v1/webhooks` para pagamentos e assinaturas; roteamento por `event`/payload.

* Compra única: atualizar `Purchase.status` (PENDING→DONE/FAILED) e enviar WhatsApp via `EvolutionConnection` (mensagens já em `payment_controller.rb`).

* Assinaturas: já coberto por `AsaasPaymentWebhookService` com `NotificationsChannel`.

## Segurança & Qualidade

* Validação Grape de `buyer`/`card`/`installments` e `Idempotency-Key` em POST sensíveis.

* Nunca armazenar CVV; mascarar número; rate limit em webhooks.

* Logs estruturados; erros padronizados conforme `ApiResponseHandler`.

## Testes (RSpec)

* Unit: Services de Payments/Subscriptions.

* Request: Endpoints Grape de `/asaas/v1/*` e webhooks.

* Cobertura mínima 90% (SimpleCov), e2e feliz/erro.

## Passos de Implementação

1. Criar Entities `Purchase` e `Subscription` (Grape).
2. Implementar Services `Payments::*` e `Subscriptions::*` migrando lógicas dos controllers legados.
3. Expor endpoints em `api/asaas/v1/*` usando thin controllers.
4. Portar migrações antigas para `backend/db/migrate` com UUID/idempotência.
5. Ajustar `AsaasConnection` (se necessário) para endpoint de invoice (ou usar controller existente `invoices`).
6. Implementar `AsaasChargeWebhookService` e montar em `/asaas/v1/webhooks` ao lado do já existente de assinaturas.
7. Escrever testes unitários e de request, garantir padrão de erros.
8. Documentar no Swagger (grape-swagger) e validar em `/docs`.

## Escolha Final (purchase vs subscriptions)

* Usar modelos separados: `Purchase` para compra única e `Subscription` para recorrência. Isso segue o desenho do Asaas e simplifica estados, webhooks e auditoria.

Confirma que seguimos com essa implementação? Depois de confirmar, aplico os Services, Controllers e migrações conforme acima.
