# frozen_string_literal: true

module Api
  module Entities
    # S9 / BE-196 — forma da renegociação na API.
    #
    # Substitui o `to_json` **sobrescrito** do legado (`renegotiation.rb:242-250`),
    # que declarava `def to_json` sem `*args` — assinatura errada — e por isso
    # levantava `ArgumentError` sempre que o Rails o chamava com opções de
    # serialização. O único campo que ele acrescentava, `installment_status`, está
    # aqui, exposto de propósito.
    #
    # **`overdue_installments` é servido AO VIVO** (OPS-190 / D-B6). A coluna
    # continua persistida — a listagem precisa dela para ordenar e o dashboard da
    # S15 a lê —, mas a resposta prefere a contagem apurada na consulta quando ela
    # vem junto (`options[:overdue_counts]`). O número não muda; muda **quando**
    # fica correto: no legado ele era fotografia de um cron diário, até 24 h
    # desatualizada, e uma renegociação liquidada nunca mais era reprocessada.
    class Renegotiation < Grape::Entity
      expose :id
      expose :project_id
      expose :provider_id
      expose :company_id
      expose :title
      expose :provider_name, documentation: { desc: 'Nome do fornecedor, carimbado na gravação' }
      expose :company_title do |r|
        r.company&.title
      end
      expose :kind
      expose :integration_key
      expose :renegotiation_date
      expose :observation
      expose :origin
      expose :monetary_correction
      expose :has_safegold_management

      # --- Cadastro ---------------------------------------------------------
      expose :original_value
      expose :original_pending_value
      expose :additional_value
      expose :total_debt
      expose :desagio_value
      expose :correct_value, documentation: { desc: 'Sempre igual a total_debt (D-47, Q-B24)' }
      expose :interest_rate_correction, documentation: { desc: 'Existe e nunca é lida (D-47)' }
      expose :grace_period, documentation: { desc: 'Existe e nunca é lida (D-47)' }
      expose :operation_interest_rate

      # --- Agregados --------------------------------------------------------
      expose :installments_main_value
      expose :installments_interest_value
      expose :installments_main_value_with_interest
      expose :installments_monetary_correction_value
      expose :installments_main_value_with_interest_cm
      expose :main_value
      expose :paid_value_with_interest_cm
      expose :late_payment_value
      expose :paid_value, documentation: { desc: 'R$ Pago — CONTA a mora' }
      expose :pending_main_value, documentation: { desc: 'Pode ficar NEGATIVO (Q-B22)' }
      expose :remaining_value, documentation: { desc: 'R$ A Pagar — soma com piso em zero; IGNORA a mora' }
      expose :paid_percent
      expose :total_value_with_desagio
      expose :current_installment_value,
             documentation: { desc: 'Valor Parcela do mês — SOBRESCRITO pelo VP quando há juros (D-46)' }
      expose :current_value, documentation: { desc: 'VP da dívida' }

      expose :installments_count
      expose :paid_installments
      expose :due_installments, documentation: { desc: 'total - pagas. INCLUI as vencidas (Q-B23)' }
      expose :overdue_installments do |r, options|
        contagens = options[:overdue_counts]
        contagens.is_a?(Hash) ? contagens.fetch(r.id, 0) : r.overdue_installments
      end

      expose :first_due_date
      expose :last_due_date
      # "Data próxima": a próxima parcela em aberto com vencimento hoje ou no
      # futuro. **Vencida nunca é "próxima"** — mesma regra do legado.
      expose :next_due_date do |r, options|
        proximas = options[:next_due_dates]
        proximas.is_a?(Hash) ? proximas[r.id] : nil
      end
      # **BE-211 — "Valor da próxima parcela".** O legado renderizava esta
      # coluna na listagem (`list/_widget.html.erb:22`, via
      # `calculate_next_installment_value`) e ela tinha sumido: o cálculo não
      # existia em ponta nenhuma do ai9. Achado pela conferência de paridade.
      #
      # `main_value_with_interest_cm` da MESMA parcela que dá a `next_due_date`,
      # como no legado — principal com juros e correção monetária, e não o
      # `main_value` seco.
      #
      # **Zero quando não há parcela futura em aberto**, e não nulo: é o
      # `return 0.00` do legado (`renegotiation.rb:164`), e a coluna é dinheiro
      # numa tabela — nulo viraria célula vazia onde o legado mostra R$ 0,00.
      expose :next_installment_value,
             documentation: { desc: 'Valor da próxima parcela em aberto; 0 quando não há' } do |r, options|
        valores = options[:next_installment_values]
        (valores.is_a?(Hash) ? valores[r.id] : nil) || 0
      end

      expose :state
      expose :beauty_state, documentation: { desc: '"42.5% Pago" quando há pagamento' }
      expose :installment_status, documentation: { desc: 'Consistente | Inconsistente — do LANÇAMENTO (BE-210)' }
      expose :unposted_value, documentation: { desc: 'total_debt - (principal + juros lançados)' }

      expose :attachments_count

      expose :created_at
      expose :updated_at
    end
  end
end
