# frozen_string_literal: true

module Api
  module Entities
    # S8 / **BE-280**…**BE-295** — a operação estruturada.
    #
    # ## Os saldos saem com o SINAL, e isso é DEC-01
    #
    # `original_balance` e `balance` são gravados **negativos**
    # (`structured_operation.rb:37`) e a tela os mostra assim (FE-299, Q-R20).
    # Não "corrija" o sinal na serialização: é a mesma convenção do
    # `limite_utilizado_on` do painel de risco, e mudá-la aqui faria a tela do
    # ai9 discordar da do legado sobre o mesmo registro.
    #
    # ## `balance` é DECORATIVO (T-D6 / BE-292)
    #
    # Ele é resetado para `original_balance` em **todo** save, e nada no legado
    # inteiro dá baixa nele. É exposto porque a tela do legado o exibe — não
    # porque signifique saldo corrente.
    #
    # ## A formatação NÃO acontece aqui (OPS-289)
    #
    # Valores saem crus. O legado formatava no servidor, com monkey-patch em
    # `Integer`/`Float`/`BigDecimal` e um `rescue` que engolia a falha e
    # devolvia o número sem máscara. No ai9 quem formata é o front, com
    # `Intl.NumberFormat('pt-BR')`.
    class StructuredOperation < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Em branco na criação recebe `carrier.title`' }
      expose :project_id, documentation: { type: 'String', desc: 'DERIVADO da empresa em todo save' }
      expose :company_id
      expose :company_title, documentation: { type: 'String' } do |op|
        op.company&.title
      end
      expose :carrier_id
      expose :carrier_title, documentation: { type: 'String' } do |op|
        op.carrier&.title
      end
      expose :operation_type_id
      expose :operation_type_title, documentation: { type: 'String' } do |op|
        op.operation_type&.title
      end
      expose :contract_number, documentation: { type: 'String', desc: 'Sem unicidade — ausência replicada (Q-R7)' }
      expose :issue_date, documentation: { type: 'Date', desc: 'Pode ser nula na leitura de registro antigo' }
      expose :due_date, documentation: { type: 'Date' }
      expose :operation_value, documentation: { type: 'BigDecimal', desc: 'Capital. É o multiplicando da remuneração.' }
      expose :original_balance,
             documentation: { type: 'BigDecimal', desc: 'Saldo inicial, NEGATIVO por convenção do legado (DEC-01)' }
      expose :balance,
             documentation: { type: 'BigDecimal',
                              desc: 'DECORATIVO: resetado para `original_balance` em todo save; nada dá baixa nele (T-D6)' }
      expose :agreed_rate,
             documentation: { type: 'BigDecimal',
                              desc: '**NÃO é a taxa que remunera** — quem remunera é `remunerations.value` (BE-295)' }
      expose :observation, documentation: { type: 'String', desc: 'text no ai9; varchar(255) no legado' }
      expose :is_on_variable, documentation: { type: 'Boolean', desc: 'Sem consumidor de cálculo (BE-295)' }
      expose :is_ended,
             documentation: { type: 'Boolean',
                              desc: 'Sem consumidor: operação encerrada CONTINUA candidata a recibo (Q-R18)' }
      expose :receipt_id,
             documentation: { type: 'String', desc: 'Preenchido = já faturada = fora de `available_for_receipt`' }
      expose :has_receipt, documentation: { type: 'Boolean', desc: 'Bloqueia a exclusão (BE-287)' } do |op|
        op.has_receipt?
      end
      expose :user_id, documentation: { type: 'String', desc: 'AUTOR — da sessão, nunca do corpo (DB-297)' }
      expose :updated_by_id, documentation: { type: 'String', desc: 'ÚLTIMO EDITOR — a metade que o legado sobrescrevia' }
      expose :created_at
      expose :updated_at
    end
  end
end
