## Visão Geral
- Implementar UX de PIX com duas etapas: “Revisão PIX” e “Finalização PIX”, alinhadas às telas fornecidas.
- Na confirmação, criar a cobrança via API e exibir QR Code PIX (imagem e código Copia e Cola), com timer de expiração e ações de copiar.
- Monitorar confirmação do pagamento (polling do status) e mostrar telas de sucesso/erro equivalentes às do cartão, com detalhes específicos do PIX.

## Backend (Aproveitar existente)
- Endpoint de criação já retorna dados para PIX:
  - `backend/app/services/payments/create_charge.rb:68-90` retorna `pix.encodedImage`, `pix.payload`, `pix.expirationDate` e `purchase`.
- Status do pagamento por cobrança:
  - `backend/app/controllers/api/asaas/v1/payments.rb:48-55` fornece `GET /asaas/v1/payments/charges/:id` para consultar status no Asaas.
- Nenhuma mudança estrutural necessária no backend; somente consumir corretamente as respostas.

## Frontend – Revisão PIX
- Na etapa “Revisão”, quando `method==='pix'`, exibir bloco:
  - Card do plano com preço à vista (`plan.pix_price` se disponível), etiqueta “À vista - PIX”.
  - Caixa informativa: “Pagamento via PIX — Na próxima etapa você receberá o QR Code para pagamento”.
  - Botões: “Voltar” e “Finalizar Pagamento”.
- Ação “Finalizar Pagamento”:
  - Chamar `POST /asaas/v1/payments/charges` com `{ plan_id, method: 'pix', buyer }` e cabeçalho `X-Skip-Auth: 1`.
  - Em caso de sucesso, guardar no estado:
    - `pixPayload`, `pixEncodedImage`, `pixExpirationDate`, `asaasPaymentId` (de `purchase.asaas_id`).
  - Avançar para etapa “Finalização PIX”.

## Frontend – Finalização PIX
- Layout:
  - Título “Finalize o Pagamento”.
  - Exibir QR Code (imagem base64 `pixEncodedImage`) em um container.
  - Campo de texto com `pixPayload` (Copia e Cola) com botão “Copiar”.
  - Banner de expiração com contador “Código expira em 29:59” baseado em `pixExpirationDate`.
  - Resumo: “Valor total” (formato moeda) e “Forma de pagamento: PIX”.
- Interações:
  - Botão “Copiar código” com feedback (toast). 
  - Contagem regressiva até `pixExpirationDate`; ao expirar, marcar estado como “expired” e oferecer ação de refazer.

## Monitoramento de Status
- Polling leve (por exemplo, a cada 5–10s) usando `GET /asaas/v1/payments/charges/:id` com `asaasPaymentId`:
  - Status alvo: `CONFIRMED` ou `RECEIVED` → sucesso.
  - Erros ou `OVERDUE/CANCELLED/REFUNDED` → falha.
- Encerrar polling imediatamente ao sucesso/erro.

## Telas de Sucesso/Erro (PIX)
- Sucesso:
  - Ícone “check”, texto “Pagamento Confirmado!”.
  - Bloco com: Valor, Forma: PIX, Código (abreviado), Expiração (data/hora), ID da compra se útil.
  - Mensagem “Enviamos um e-mail de confirmação para: <email>”.
  - Botão “Acessar Dashboard”.
- Erro:
  - Ícone/estado “erro”, mensagem com detalhe vindo da API.
  - Ações: “Tentar novamente” ou “Voltar à revisão”.

## Implementação Técnica (Frontend)
- Em `CheckoutPage.tsx`:
  - Estados adicionais: `pixPayload`, `pixEncodedImage`, `pixExpirationDate`, `asaasPaymentId`, `pixStatus` (`idle|awaiting|success|failed|expired`), `pollingIntervalId`.
  - Handler do botão “Finalizar Pagamento” para `pix`: seta `pixStatus='awaiting'`, dispara criação de charge e transiciona.
  - Componente/branch UI para “Finalização PIX” com QR, copy, contador e resumo.
  - Efeito de polling: `useEffect` que, se `pixStatus==='awaiting'`, chama o status endpoint e atualiza `pixStatus`.
  - Reuso das telas de sucesso/erro existentes com conteúdo adaptado para PIX.
- Utilitários:
  - Formatação de moeda e data/hora.
  - Função de cálculo do tempo restante até expiração.

## Acessibilidade & UX
- Focus visível nos botões “Copiar”, anúncios ARIA após copiar.
- Feedbacks de loading e toasts em erros de rede.
- Texto de ajuda explicando que a confirmação é automática após o pagamento.

## Validação
- Testar com plano real `ONE001` e buyer de exemplo.
- Simular sucesso via webhook ou pagar com PIX; alternativamente, mockar status `CONFIRMED` para validar telas.
- Garantir que o polling para ao concluir.

## Entregáveis
- Checkout com etapas “Revisão PIX” e “Finalização PIX” funcionais.
- Telas de sucesso/erro equivalentes às do cartão, com dados específicos do PIX.
- Polling de status robusto e contador de expiração.