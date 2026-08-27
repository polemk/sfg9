## Contexto Atual
- Webhook de pagamentos únicos: `backend/app/services/asaas_charge_webhook_service.rb:15` atualiza a `Purchase` para `DONE` e chama `ensure_user_account!`.
- Serviço de criação de cobrança: `backend/app/services/payments/create_charge.rb:131-138` confirma cartão, marca `DONE` e chama `ensure_user_account!`.
- Criação/atualização de usuário a partir da compra: `backend/app/models/purchase.rb:288-339` (método efetivo) popula nome, CPF/CNPJ e `customer_id`; evita sobrescrever dados existentes.
- Permissões por compra: callback `after_update` em `Purchase` dispara `PermissionsSyncService.grant_for_purchase` quando `status == 'DONE'` (`backend/app/models/purchase.rb:341-349`).
- Assinaturas via webhook: `backend/app/services/asaas_payment_webhook_service.rb:71-87` ativa assinatura; ainda não sincroniza permissões do usuário.
- Frontend Checkout: `frontend/src/app/pages/CheckoutPage.tsx` exibe sucesso, assina realtime, mas só oferece botão para “Acessar Dashboard” (não há redirect automático nem auto‑login).

## Regras a Implementar
- Usuário logado que conclui compra: redirecionar para `/dashboard` após 5s.
- Usuário deslogado que conclui compra:
  - Se e‑mail ou telefone já cadastrado: redirecionar para `/login`.
  - Se não cadastrado: criar conta com todas as informações do checkout, gerar sessão JWT e redirecionar para `/dashboard`.
- Contas existentes: atualizar com infos do checkout, exceto `email` e `whatsapp`.
- Após compra/assinatura: garantir criação/atualização de permissões conforme plano.
- Usuário logado: pré‑preencher automaticamente os campos nas telas do checkout, com opção de editar.
- Tipo de usuário criado: `client`.

## Alterações de Backend
- Criar `Auth::CheckoutSessionService` (service puro, com comentários explicativos):
  - Entrada: `payment_id` (preferencial) ou `purchase_identifier`.
  - Passos:
    1) Localizar `Purchase` (`DONE`).
    2) Executar `purchase.ensure_user_account!` para criar/associar usuário.
    3) Determinar se a conta já existia (heurística: `user.created_at < purchase.created_at` ou `user_id` prévio).
    4) Se já existia: retornar `requires_login: true`.
    5) Se foi criada agora: emitir tokens via `Auth::TokenService.generate_tokens(user)` e retornar `Api::Entities::AuthSession`.
    6) Garantir permissões: opcionalmente chamar `PermissionsSyncService.sync_for_user(user)` por segurança.
- Expor endpoint Grape `POST /auth/v1/checkout/session`:
  - `desc` com `summary`, `detail`, HTTP codes e entidade de resposta.
  - `params` validando `payment_id` ou `purchase_identifier`.
  - Chamar o service e `process_service_response` conforme padrão do projeto.
- Ampliar `Purchase.ensure_user_account!` para mapear todos os campos disponíveis do checkout:
  - Popular `cpf_cnpj`, `customer_id`, e (se presentes no payload do cartão) `cep`, `street`, `number`, `district`, `city`, `state`, `cardholder_*`, sem sobrescrever `email` e `whatsapp`.
  - Garantir `user_type` como `client` (via `UserType.find_by(name: 'client')`).
  - Remover referência legada a `Livetat::Auth::User` e usar o `User` local.
- Assinaturas (webhook): em `handle_payment_confirmed` (`backend/app/services/asaas_payment_webhook_service.rb:71-87`), chamar `PermissionsSyncService.sync_for_user(subscription.user)` para alinhar permissões ao plano.

## Alterações de Frontend
- Pré‑preenchimento para usuário logado:
  - Consultar `GET /auth/v1/sessions/status` ao carregar o checkout.
  - Se logado, preencher `buyerName`, `buyerEmail`, `whatsappValue`, `buyerCpf` e campos de endereço disponíveis; manter editável.
- Redirect após sucesso:
  - Se logado: `setTimeout(5000)` e redirecionar para `/dashboard`.
  - Se deslogado:
    - Chamar `POST /auth/v1/checkout/session` com `payment_id` retornado de `create_charge`.
    - Se `requires_login`: redirecionar para `/login`.
    - Senão: salvar `access_token` + `refresh_token` via cliente de auth, marcar sessão e redirecionar `/dashboard`.
- Atualizar `chargesApi`/`authApi` com método `checkoutSession` e usar no `CheckoutPage.tsx` na transição para `paymentStatus==='success'` (tanto cartão quanto PIX via webhook realtime).

## Segurança e Validação
- Usar `payment_id` como prova de posse gerada no servidor; aceitar `purchase_identifier` apenas como fallback.
- Exigir `Purchase.status == 'DONE'` e janela temporal curta (ex.: 30 min) para auto‑login.
- Nunca sobrescrever `email` e `whatsapp` em contas existentes; apenas preencher campos faltantes.
- Tokens JWT emitidos com TTL padrão; refresh token incluso.

## Testes
- Backend:
  - Service: casos para conta existente vs recém‑criada; emissão de tokens; erros de `payment_id` inválido; janela temporal.
  - Endpoint Grape: params, respostas e entidades.
  - Assinaturas: confirmar `sync_for_user` em `PAYMENT_CONFIRMED`.
- Frontend:
  - CheckoutPage: fluxo logado (5s redirect), fluxo deslogado (auto‑login), fluxo existente (redirect `/login`), PIX via websocket.

## Observações de Implementação
- Todos os trechos novos terão comentários explicando suas funcionalidades, conforme as regras do projeto.
- Respostas de services seguirão o padrão `success_response`/`error_response` e Entities.

## Resultado Esperado
- Ao concluir o checkout, o usuário é levado de forma adequada para `/dashboard` ou `/login`, com conta criada/atualizada, sessão JWT emitida quando permitido e permissões aplicadas ao plano.

## Solicitação
- Confirmar este plano para eu implementar no backend e frontend conforme descrito. Com a confirmação, eu codifico as mudanças, adiciono comentários nos códigos e valido com testes.