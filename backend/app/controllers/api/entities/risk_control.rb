# frozen_string_literal: true

module Api
  module Entities
    # S5 / BE-230..BE-241 — **limite de risco**.
    #
    # Os valores monetários saem como **número**, não string formatada: a
    # formatação da lista é da tela (`Intl.NumberFormat('pt-BR')`). O que sai
    # formatado do servidor é só o payload do **console de exposição**
    # (`Risk::AggregateService`), e por um motivo específico: é lá que vivem os
    # rótulos do D-95 que a DEC-01 manda preservar, e deixá-los para o front
    # significaria uma segunda implementação da mesma composição (C2).
    #
    # `is_legacy_shape` é **DB-240 / DEC-43**: a linha veio do modelo pré-2022,
    # sem tipo de limite. Ela some de todos os agregados enquanto o ETL não a
    # converter, e a tela mostra o rótulo "Legado" (FE-243) para que isso não
    # seja descoberto por diferença de número.
    class RiskControl < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      # **Coagido a `""`, nunca `nil`.** A coluna é nula no banco (a linha
      # herdada do legado pode vir sem título) e o cliente declara `title: string`.
      # Um tipo que mente faz o `tsc` virar carimbo: já derrubou uma tela desta
      # base com `Cannot read properties of null (reading 'trim')`, com o
      # type-check verde. A regra: ou a entity coíbe, ou o tipo declara `| null`.
      expose :title, documentation: { type: 'String', desc: 'Cópia do título do portador, reescrita em todo save.' } do |c|
        c.title.to_s
      end

      expose :company_id, documentation: { type: 'String' }
      expose :company_title, documentation: { type: 'String' } do |c|
        c.company&.title
      end

      expose :carrier_id, documentation: { type: 'String' }
      expose :carrier_title, documentation: { type: 'String' } do |c|
        c.carrier&.title
      end
      expose :carrier_group_title, documentation: { type: 'String', desc: 'Grupo econômico do portador, quando houver.' } do |c|
        c.carrier&.group&.title
      end

      expose :risk_operation_type_id, documentation: { type: 'String' }
      expose :risk_operation_type_title, documentation: { type: 'String' } do |c|
        c.risk_operation_type&.title
      end
      expose :has_pre_faturamento,
             documentation: { type: 'Boolean', desc: 'Do tipo. Decide se os campos de Saldo Inicial aparecem (FE-245).' } do |c|
        c.risk_operation_type&.has_pre_faturamento || false
      end

      expose :limite, documentation: { type: 'String', desc: 'Decimal(14,2). Zero é válido.' }
      expose :taxa, documentation: { type: 'String', desc: 'Decimal(7,4), em % a.m.' }
      expose :original_balance,
             documentation: { type: 'String', desc: 'Saldo inicial liquidável. Só editável na criação.' }
      expose :original_balance_pre,
             documentation: { type: 'String', desc: 'Saldo inicial pré-faturamento. Só editável na criação.' }

      expose :is_active, documentation: { type: 'Boolean' }
      # **DEC-112** — agora é COLUNA (`boolean null: false`), carimbada da
      # empresa em todo save. O `== true` some junto com a derivação: não há mais
      # `nil` para escapar para um campo declarado `boolean` no cliente.
      expose :has_safegold_management,
             documentation: { type: 'Boolean', desc: 'CARIMBO copiado da empresa. Nunca ressincronizado (D-30).' }

      expose :is_legacy_shape,
             documentation: { type: 'Boolean', desc: 'DB-240/DEC-43 — linha do modelo pré-2022, sem tipo. Some dos agregados.' } do |c|
        c.risk_operation_type_id.nil?
      end

      expose :dependents_count,
             documentation: { type: 'Integer', desc: 'Operações e posições que bloqueiam a exclusão (422 real, D-24).' } do |c, options|
        (options[:usage] || {})[c.id].to_i
      end

      expose :created_at
      expose :updated_at
    end
  end
end
