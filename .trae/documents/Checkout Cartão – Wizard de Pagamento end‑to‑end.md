## Páginas do Wizard
1. Método de Pagamento
- Duas opções: PIX e Cartão de Crédito (foco no cartão).
- Cards clicáveis com ícone, título, descrição e preço (à vista e parcelado quando aplicável).
- Seleção persiste no estado e habilita botão Continuar.

2. Revisão: Dados do Cartão
- Seções:
  - Resumo do plano (nome, preço, parcelas selecionadas).
  - Dados do titular: CPF/CNPJ, CEP, Rua, Número, Bairro, Cidade, Estado, País, Telefone (usar PhoneInputGroup), E‑mail.
  - Dados do cartão: Número, Nome no Cartão, Validade (MM/AA), CVV.
- Botão "Usar meus dados" preenche do usuário logado (quando houver), mantendo público sem exigir login.
- Validações: formatos básicos, obrigatórios, máscara visual (sem enviar máscara; envio normalizado).

3. Confirmação Pagamento Cartão
- Tela de sucesso com timeline completa, mostrando: Valor total, parcelas, método, cartão mascarado, e e‑mail de confirmação.
- Botão para acessar Dashboard (se houver login) ou voltar para home.

## API & Ações
- Endpoint público: `POST /asaas/v1/payments/charges`.
- Payload mapeado:
  - `plan_id`: id/identifier do plano atual
  - `method`: `credit_card`
  - `installments`: inteiro (1 = à vista)
  - `buyer`: {
    name, email, whatsapp (DDI+digits), cpf_cnpj,
    card_holder_name, card_number (digits), card_expiry_month, card_expiry_year, card_cvv,
    cardholder_name, cardholder_cpf, cardholder_postal_code, cardholder_address_number, cardholder_phone
  }
- Resposta esperada: `{ purchase: Api::Entities::Purchase, method: 'credit_card' }`.
- Erros: toasts padronizados; manter UX consistente.

## Implementação Frontend
- Atualizar `paymentsApi` com métodos:
  - `createCharge(data)` → `POST /asaas/v1/payments/charges` (público via `apiClient.getPublic`/`postPublic` se existir; caso contrário usar client padrão sem Authorization).
  - `getCharge(id)` → `GET /asaas/v1/payments/charges/:id`
- `CheckoutPage.tsx`:
  - Adicionar estado `step` (`cadastro` → `pagamento` → `revisao` → `confirmacao`).
  - Método de pagamento: grid com 2 cards, mantendo design do primeiro card.
  - Revisão: formulário com componentes existentes (Input, PhoneInputGroup, Button). Botão "Finalizar Pagamento" dispara `createCharge` com método `credit_card`.
  - Confirmação: renderizar dados do retorno (valor, parcelas, método, máscara de cartão).
- Persistência: manter dados do comprador entre passos; normalizações antes do POST.

## Design & UX
- Reutilizar classes do primeiro passo (bg-card, border-border, rounded-2xl, tipografia, texto secundário).
- Timeline já aplicada: avançar índices conforme step.
- Botões: `Button variant="uiverse"` (consistente com projeto).
- Acessibilidade: labels, foco visível, mensagens de erro amigáveis.

## Verificação
- Testar fluxo end‑to‑end em dev: selecionar Cartão → preencher dados → enviar → ver confirmação.
- Logs no console para payload (em dev) e tratamento de erro.

Confirma o plano para eu implementar as telas e integrações agora?