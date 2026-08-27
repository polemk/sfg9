# frozen_string_literal: true

module Api
  module Entities
    # S7 / **FE-269, FE-270** — **movimento** da cadeia de saldos.
    #
    # ### `credit_type` sai como `'C'`/`'D'`, não como o rótulo do enum
    #
    # O `enum` de `RiskMovementType` faz `tipo.credit_type` devolver `'debit'`.
    # O contrato com a tela, com o legado e com o ETL é `'C'`/`'D'` — por isso
    # é `credit_type_code` que é exposto. A S5 já tinha levado essa mordida uma
    # vez, num request spec.
    #
    # ### O sufixo `C`/`D` é da TELA, e o número vem pronto daqui
    #
    # `FE-270` renderiza `R$ 1.234,56C`. O sufixo é **formatação replicada** (é
    # como o operador lê o extrato hoje); `balance` e `movement_value` chegam
    # calculados pelo `Risk::Calculator` — nenhum componente React soma saldo
    # (contrato **C2**).
    class RiskMovement < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :risk_operation_id, documentation: { type: 'String' }
      expose :sequence, documentation: { type: 'Integer', desc: 'Reatribuído a partir de 1 a cada recálculo. Era `order` no legado.' }
      expose :date, documentation: { type: 'Date' }

      expose :movement_type_id, documentation: { type: 'String' }
      expose :movement_type_title, documentation: { type: 'String' } do |m|
        m.movement_type&.title
      end
      expose :credit_type, documentation: { type: 'String', desc: "'C' = crédito (−1) · 'D' = débito (+1)" } do |m|
        m.movement_type&.credit_type_code
      end
      expose :credit_type_description, documentation: { type: 'String' } do |m|
        m.movement_type&.credit_type_description
      end
      expose :movement_value_sign, documentation: { type: 'Integer', desc: '−1 crédito · +1 débito' } do |m|
        m.movement_type&.credit_type_value
      end
      expose :is_transfer, documentation: { type: 'Boolean', desc: 'Tipo readonly na edição quando verdadeiro.' } do |m|
        m.movement_type&.is_transfer || false
      end

      expose :movement_value, documentation: { type: 'String', desc: 'Decimal(14,2). Sempre positivo (B-05).' }
      expose :balance, documentation: { type: 'String', desc: 'Saldo ACUMULADO depois deste movimento. Vem pronto.' }

      expose :observation, documentation: { type: 'String' } do |m|
        m.observation.to_s
      end

      expose :pair_id, documentation: { type: 'String', desc: 'O espelho da transferência na operação par.' }
      expose :receivable_id, documentation: { type: 'String', desc: 'Borderô que gerou o movimento (S6).' }

      expose :user_id, documentation: { type: 'String' }
      expose :user_name, documentation: { type: 'String' } do |m|
        m.author&.name
      end

      expose :created_at, documentation: { type: 'DateTime' }
      expose :updated_at, documentation: { type: 'DateTime' }
    end
  end
end
