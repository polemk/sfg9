# frozen_string_literal: true

module Risk
  # S7 / **BE-275** — a **transferência pré ↔ antecipação**.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # A tabela `risk_movements` e o par estático nunca existiram em produção
  # (`analise-dump-producao.md` §1: `create_risk_movements` e
  # `create_risk_operations` estão entre as 24 migrations que não subiram). A
  # fonte é `../sfg/app/models/risk_movement.rb:45-65`. Golden `M2` trava a
  # leitura dessa fonte — **não** um comportamento observado.
  #
  # ## O que a transferência é
  #
  # Num limite de tipo **com pré-faturamento** a S5 abre um par estático: a
  # operação `is_pre` e a operação de antecipação, ligadas por `pair_id`.
  # Transferir é tirar da pré e pôr na antecipação:
  #
  # | operação | tipo de movimento | `credit_type` | sinal | saldo depois |
  # | -------- | ----------------- | ------------- | ----- | ------------ |
  # | pré (`is_pre`) | Valor Transferido | `C` | **−1** | −10.000,00 |
  # | antecipação (par) | Transferência Recebida | `D` | **+1** | +10.000,00 |
  #
  # Mesma data, mesmo valor, mesma observação, `pair_id` cruzado.
  #
  # ## Q-R11 — o sentido é UM só, e isso é replicado
  #
  # `:46` — a contrapartida só nasce quando `movement_type_id == transferência
  # enviada` **e** `risk_operation.is_pre?`. Lançar "Valor Transferido" a partir
  # da **antecipação** grava o movimento e **não** gera contrapartida nenhuma.
  # Parece esquecimento e é o comportamento: o fluxo do produto é pré →
  # antecipação. **Replicado** (default registrado no `proposal.md`).
  #
  # ## O que muda: validar ANTES, em transação
  #
  # No legado o par nasce no `after_create` do movimento original — ou seja,
  # **depois** do INSERT. Se a operação não tiver `pair_operation` (par estático
  # incompleto, dado de carga, limite antigo), `pair_operation.id` levanta
  # `NoMethodError`, o request morre em 500 **e o movimento de saída fica
  # gravado**: meia transferência, com o saldo da pré errado para sempre e nada
  # do outro lado.
  #
  # Aqui a existência do par é verificada **antes**, e as duas linhas nascem na
  # mesma transação: ou as duas, ou nenhuma.
  class TransferService
    NOT_PRE = 'Transferência só sai de operação de subtipo pré-faturamento.'
    NO_PAIR = 'Esta operação não tem par de antecipação. A transferência não pode ser lançada ' \
              'sem a contrapartida — verifique o limite que abriu o par estático.'

    class << self
      include ApiResponseHandler

      def call(operation:, attrs:, actor: nil)
        return { status: 422, error: NOT_PRE } unless operation.is_pre?

        par = operation.pair_operation
        return { status: 422, error: NO_PAIR } if par.nil?

        saida = build(operation, RiskMovementType.transfer_out, attrs, actor)
        entrada = build(par, RiskMovementType.transfer_in, attrs, actor)

        # Validação das DUAS antes de gravar qualquer uma.
        return unprocessable(saida) unless saida.valid?
        return unprocessable(entrada) unless entrada.valid?

        RiskMovement.transaction do
          saida.save!
          entrada.save!
          # O par se conhece nos dois sentidos. `update_columns` porque não há
          # nada a validar e um `save` reentraria no `after_commit` de espelho,
          # que reescreveria os dois de volta.
          saida.update_columns(pair_id: entrada.id, updated_at: Time.current)
          entrada.update_columns(pair_id: saida.id, updated_at: Time.current)
        end

        # As duas cadeias são refeitas depois do commit das duas linhas — o
        # `after_commit` do model já faz a da saída; a da entrada é explícita
        # porque o `pair_id` foi escrito por `update_columns`.
        par.save

        { status: 201, data: saida.reload }
      rescue RiskMovementType::MissingFunctionalType => e
        { status: 422, error: e.message }
      end

      private

      def build(operation, tipo, attrs, actor)
        RiskMovement.new(
          risk_operation_id: operation.id,
          movement_type_id: tipo.id,
          date: attrs[:date],
          movement_value: attrs[:movement_value],
          observation: attrs[:observation],
          balance: 0,
          user_id: actor&.id
        )
      end

      def unprocessable(record)
        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end
    end
  end
end
