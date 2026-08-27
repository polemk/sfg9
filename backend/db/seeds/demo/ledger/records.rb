# frozen_string_literal: true

module Demo
  class Ledger
    # Os registros do razão. **Ruby puro, zero ActiveRecord** — é o que permite
    # testar as 7 regras de coerência hoje, sem nenhuma tabela de domínio existir,
    # e é o que faz o número do painel e o número da lista virem do mesmo objeto.
    #
    # Os nomes de campo aqui são os do **negócio**, não os do banco. A tradução
    # para coluna mora no escritor de cada agregado — assim, uma coluna que mude de
    # nome (`order` → `sequence`, DB-236) custa uma linha, não uma reescrita.
    module Records
      Carrier = Struct.new(
        :key, :title, :bank_code, :financial_agent, :group, :net_worth,
        :senior_accounts, :subordinated_accounts, :subordinated_percent,
        :city, :uf, :rate_range, :limit_factor, :refusal_rate, :available_from,
        keyword_init: true
      )

      Client = Struct.new(
        :index, :slug, :name, :formal, :cnpj_root, :segment, :sub_segment,
        :city, :uf, :responsible, :tier, :company_count, :carrier_keys,
        :base_volume, :closing_date, :active_from, :story,
        keyword_init: true
      )

      Company = Struct.new(:key, :client, :title, :branch, :cnpj, keyword_init: true)

      Control = Struct.new(
        :key, :client, :company, :carrier, :modality, :limite, :taxa,
        :target_utilization, keyword_init: true
      )

      Month = Struct.new(
        :offset, :date, :year, :month, :label, :trend, :seasonality, :factor,
        keyword_init: true
      )

      Bordero = Struct.new(
        :nro, :client, :company, :carrier, :control, :month, :date,
        :wallet, :receivable_kind, :resource_source,
        :qtd_titulos, :qtd_recusada, :qtd_final,
        :valor_bruto, :vlr_bruto_recusado, :vlr_bruto_final,
        :prz_med_pond_emp, :prz_med_pond_bco,
        :float_acordado, :float_calculado, :diferenca_float,
        :cst_efetivo_acordado,
        :nominal_tax, :tarifa_desagio, :tarifa_advalorem, :tarifa_iof,
        :tarifa_outras, :valor_total_tarifas, :valor_liquido,
        keyword_init: true
      )

      Operation = Struct.new(
        :contract_number, :client, :company, :carrier, :control, :month,
        :issue_date, :due_date, :operation_value, :agreed_rate, :state,
        :movements, :balance, keyword_init: true
      )

      Movement = Struct.new(
        :operation, :sequence, :type_key, :credit_type, :date, :value, :balance,
        keyword_init: true
      )

      StructuredOperation = Struct.new(
        :contract_number, :client, :company, :carrier, :modality, :issue_date,
        :due_date, :operation_value, :agreed_rate, :is_ended, :balance,
        keyword_init: true
      )

      # A transferência pré → antecipação de um limite com pré-faturamento. O
      # razão diz onde e quanto; quem grava as duas pontas é
      # `Risk::TransferService` (ver `Ledger::Operations.static_transfers`).
      StaticTransfer = Struct.new(:control, :value, :date, keyword_init: true)

      Provider = Struct.new(:key, :client, :title, :cnpj, :city, :uf, keyword_init: true)

      Renegotiation = Struct.new(
        :key, :client, :company, :provider_name, :title, :kind, :state,
        :renegotiation_date, :operation_interest_rate,
        :original_value, :original_pending_value, :additional_value, :total_debt,
        :paid_value, :remaining_value, :paid_percent,
        :installments_count, :paid_installments, :overdue_installments,
        :first_due_date, :last_due_date, :installments,
        keyword_init: true
      )

      RenegotiationInstallment = Struct.new(
        :renegotiation, :number, :due_date, :main_value, :total_value,
        :paid_value, :is_paid, :is_overdue, :pending_value,
        keyword_init: true
      )

      Guarantee = Struct.new(
        :key, :client, :carrier, :guarantee_type, :title, :value, :observation,
        keyword_init: true
      )

      # `project_specific` distingue o lançamento de um indicador **do projeto**
      # (`indicators.scope = "project"`) do de um indicador do catálogo global.
      # O escritor precisa do sinal para saber em qual dos dois cadastros
      # procurar: a chave do global é única, a do específico só é única DENTRO
      # do projeto.
      IndicatorEntry = Struct.new(
        :client, :indicator_key, :indicator_title, :value_type, :year, :month,
        :value, :project_specific, keyword_init: true
      )

      # ------------------------------------------------------------------
      # Disponibilidades (S11)
      # ------------------------------------------------------------------
      # `path` é a chave natural da árvore: `"1.2.3"` de posição, estável entre
      # execuções. O escritor casa por **título normalizado** dentro do pai, que
      # é o que o índice único do banco cobra.
      AvailabilityTemplate = Struct.new(
        :key, :path, :parent_path, :level, :position, :title,
        :operation_type, :deadline_type,
        :is_adjusted, :is_cumulative, :is_mandatory, :is_global, :scale,
        keyword_init: true
      ) do
        def leaf? = scale.present?
      end

      # Uma célula da grade: padrão-folha × empresa × data. Os nós de cima e a
      # consolidação geral **não** entram aqui — quem os materializa é o
      # `after_save` do model, que é o mesmo caminho da gravação pela tela.
      AvailabilityEntry = Struct.new(
        :client, :company, :template_key, :date, :value, keyword_init: true
      )

      # ------------------------------------------------------------------
      # Atendimento (S2) — mensagens administrativas e observadores
      # ------------------------------------------------------------------
      AdminMessage = Struct.new(
        :key, :public_token, :private_token, :sender_name, :sender_email,
        :message, :state, :context, :is_read, :is_favorite, :is_internal,
        :handled_by, :created_at, :read_at, :notes,
        keyword_init: true
      )

      MessageNote = Struct.new(
        :message, :description, :author_name, :author_email, :from_admin,
        :unread, :created_at, keyword_init: true
      )

      Observer = Struct.new(
        :name, :email, :is_internal, :contexts, keyword_init: true
      )

      # ------------------------------------------------------------------
      # Cobranças (S6) — o pacote e os recibos que o compõem
      # ------------------------------------------------------------------
      Charge = Struct.new(
        :key, :client, :date, :state, :receipts,
        :value, :risk_operations_value, :structured_operations_value,
        :total_operations_value, :receipts_count, :risk_operations_count,
        :structured_operations_count,
        keyword_init: true
      )

      # `remuneration` é a linha da tabela de preço que produziu `fee` e `title`.
      # O escritor a usa para resolver `receipts.remuneration_id` — a coluna que
      # o `Charges::ReceiptGenerator` sempre preenche e que o seed deixava nula
      # enquanto `remunerations` não existia.
      ChargeReceipt = Struct.new(
        :charge, :client, :operation, :remuneration, :kind, :title, :fee,
        :operation_value, :value, :date, keyword_init: true
      )

      # ------------------------------------------------------------------
      # Remuneração (S8) — a tabela de preço da gestora com cada cliente
      # ------------------------------------------------------------------
      # Uma linha por **(cliente, classe, modalidade)**, que é exatamente o
      # índice único `(project_id, operation_type_type, operation_type_id)` do
      # banco (DB-284). `kind` é `LIQ` ou `EST`; `modality` é a chave da
      # modalidade (`:fomento`…), e é o escritor quem a traduz para o id do
      # tipo em `risk_operation_types` **ou** em `structured_operation_types`.
      #
      # `value` é a taxa em %, e é a **mesma** que o recibo copia para `fee`:
      # os dois saem de `Billing.fee_for`, para que a tela de Remunerações e a
      # de recibos nunca mostrem duas taxas para o mesmo par cliente × tipo.
      Remuneration = Struct.new(
        :key, :client, :kind, :modality, :operation_type_class, :title, :value,
        keyword_init: true
      )
    end
  end
end
