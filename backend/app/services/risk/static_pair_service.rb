# frozen_string_literal: true

module Risk
  # S5 / BE-241, OPS-233 — **o par estático do limite**.
  #
  # Quando o tipo do limite tem `has_pre_faturamento`, criar o limite abre
  # **duas** operações de risco ligadas por `pair_id`:
  #
  # | operação | subtipo | `original_balance` recebe |
  # | -------- | ------- | ------------------------- |
  # | pré-faturamento | `is_pre = true` | `original_balance_pre` do limite |
  # | antecipação | `is_pre = false` | `original_balance` do limite |
  #
  # **A troca é a parte fácil de errar** (`../sfg/app/models/risk_control.rb:31,48`):
  # a operação **pré** recebe o `original_balance_pre` e a **antecipação** recebe
  # o `original_balance`. Inverter põe o saldo inicial no bucket errado do painel.
  #
  # As duas nascem `operation_value: 0`, `balance: 0`, `agreed_rate` = a taxa do
  # limite, observação "Criado automaticamente para o limite" e **sem
  # movimento** — por isso `Calculator#balance_on` devolve **0** para elas em
  # qualquer data (golden `L2`), e o saldo inicial configurado **não** entra em
  # nenhum agregado até alguém lançar um movimento. É assim que o painel calcula
  # hoje.
  #
  # ### B-08 — as datas são nulas, não sentinelas
  #
  # O legado usa `DateTime.dinosaurs` / `DateTime.mars` (ano −2000 / +2000) para
  # manter o par dentro de toda janela. Aqui `is_static = true` e as datas ficam
  # **nulas**; o predicado da janela (`RiskOperation.on_date`) tem o ramo
  # `is_static`. Mesmo conjunto de resultados, sem data falsa no banco.
  #
  # ### Transacional: o limite não é gravado se o par não puder nascer
  #
  # Roda no `after_create` do `RiskControl`, ou seja **dentro** da transação do
  # `save`. Tipo com `has_pre_faturamento` e sem os dois subtipos levanta
  # {IncompleteSubtypes}, a transação volta atrás e o limite **não existe**. No
  # legado o `pre_st.id` estouraria `NoMethodError` — e o limite já estaria
  # gravado, porque o `after_create` roda depois do INSERT e o 500 acontecia com
  # a linha no banco (o controller então chamava `@risk_control.destroy`, o que
  # só funciona quando o erro é de validação).
  class StaticPairService
    OBSERVATION = 'Criado automaticamente para o limite'

    # Fica no corpo da classe (e **não** dentro de `class << self`): declarada lá
    # dentro, a constante viveria na singleton class e
    # `Risk::StaticPairService::IncompleteSubtypes` — que é como o
    # `Risk::ControlService` a resgata — levantaria `NameError`. Foi o teste de
    # transacionalidade que pegou isso.
    class IncompleteSubtypes < StandardError
      def initialize(type)
        super("O tipo de limite «#{type.title}» usa pré-faturamento mas não tem os dois subtipos " \
              '(pré e antecipação). O par estático do limite não pode ser aberto.')
      end
    end

    class << self
      include ApiResponseHandler

      def call!(control)
        type = control.risk_operation_type
        return nil unless type&.has_pre_faturamento?

        pre_subtype = type.subtypes.find_by(is_pre: true)
        ant_subtype = type.subtypes.find_by(is_pre: false)
        raise IncompleteSubtypes, type if pre_subtype.nil? || ant_subtype.nil?

        pre = build_static(control, pre_subtype, control.original_balance_pre)
        ant = build_static(control, ant_subtype, control.original_balance)
        pre.save!
        ant.save!

        # O par se conhece nos dois sentidos. `update_columns` porque não há
        # nada a validar aqui e um `save` reentraria nas callbacks.
        pre.update_columns(pair_id: ant.id, updated_at: Time.current)
        ant.update_columns(pair_id: pre.id, updated_at: Time.current)

        [pre, ant]
      end

      private

      def build_static(control, subtype, original_balance)
        RiskOperation.new(
          title: subtype.title,
          user_id: control.user_id,
          project_id: control.project_id,
          company_id: control.company_id,
          carrier_id: control.carrier_id,
          risk_control_id: control.id,
          operation_type_id: control.risk_operation_type_id,
          operation_subtype_id: subtype.id,
          original_balance: original_balance,
          operation_value: 0,
          balance: 0,
          agreed_rate: control.taxa,
          observation: OBSERVATION,
          is_static: true,
          issue_date: nil,
          due_date: nil
        )
      end
    end
  end
end
