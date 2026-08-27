# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-150…BE-153 — o borderô.
    #
    # Os ~33 derivados são expostos **pelo mesmo entity que serve a prévia**
    # (`ReceivableDerived`). Uma definição, dois usos — contrato C2.
    class ReceivableEntry < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :date, documentation: { type: 'Date', desc: 'Data do borderô' }
      expose :data_credito, documentation: { type: 'Date', desc: 'Data de crédito. Pode ser nula' }
      expose :nro_bordero,
             documentation: { type: 'String', desc: 'Número do borderô. STRING: produção tem `F-76`, `48-49`, `1540962/20`' }
      expose :description, documentation: { type: 'String', desc: 'Descrição visível na lista' }
      expose :observacoes,
             documentation: { type: 'String', desc: 'Observações. Visível por DEC-52 — no legado nenhuma view a lia' }
      expose :contrato,
             documentation: { type: 'String', desc: 'Contrato. Sempre nulo em produção (28.131/28.131); sem tela' }
      expose :has_safegold_management, documentation: { type: 'Boolean', desc: 'Marca do projeto, recarimbada em todo save' }

      expose :company_id, documentation: { type: 'String' }
      expose :carrier_id, documentation: { type: 'String' }
      expose :wallet_id, documentation: { type: 'String' }
      expose :receivable_kind_id, documentation: { type: 'String' }
      expose :resource_source_id, documentation: { type: 'String' }
      expose :risk_operation_type_id,
             documentation: { type: 'String', desc: 'Derivado do subtipo. NUNCA EXECUTADO EM PRODUÇÃO (DEC-103b)' }
      expose :risk_operation_subtype_id,
             documentation: { type: 'String', desc: 'Opcional ("Não associar"). NUNCA EXECUTADO EM PRODUÇÃO' }
      expose :user_id, documentation: { type: 'String', desc: 'Autor. Vem da sessão' }

      # Os títulos vêm juntos para a lista não fazer 4 consultas por linha.
      # O `includes` do `SearchService` é o que sustenta isto — sem ele, são
      # 200 consultas numa página de 50 (Princípio 9).
      expose :company_title, documentation: { type: 'String' } do |e|
        e.company&.title
      end
      expose :carrier_title, documentation: { type: 'String' } do |e|
        e.carrier&.title
      end
      expose :wallet_title, documentation: { type: 'String' } do |e|
        e.wallet&.title
      end
      expose :receivable_kind_title, documentation: { type: 'String' } do |e|
        e.receivable_kind&.title
      end
      expose :resource_source_title, documentation: { type: 'String' } do |e|
        e.resource_source&.title
      end

      # As entradas digitáveis.
      expose :valor_bruto, documentation: { type: 'BigDecimal' }
      expose :vlr_bruto_recusado, documentation: { type: 'BigDecimal' }
      expose :qtd_titulos, documentation: { type: 'Integer' }
      expose :qtd_recusada, documentation: { type: 'Integer' }
      expose :prz_med_pond_emp, documentation: { type: 'BigDecimal', desc: 'Prazo médio ponderado da empresa, em dias' }
      expose :prz_med_pond_bco, documentation: { type: 'BigDecimal', desc: 'Prazo médio ponderado do banco, em dias' }
      expose :float_acordado, documentation: { type: 'BigDecimal', desc: 'Float acordado, em dias' }
      expose :cst_efetivo_acordado, documentation: { type: 'BigDecimal', desc: 'Custo efetivo acordado, % a.m.' }
      expose :nominal_tax,
             documentation: { type: 'BigDecimal', desc: 'Taxa nominal informada. NÃO é validada contra as checagens (Q-B10)' }
      expose :recompra, documentation: { type: 'BigDecimal' }
      expose :retencao, documentation: { type: 'BigDecimal' }
      expose :fomento, documentation: { type: 'BigDecimal' }
      expose :outros, documentation: { type: 'BigDecimal' }

      expose :taxes, using: Api::Entities::ReceivableTax,
                     documentation: { type: 'Array', desc: 'Tarifas do borderô' }

      # **DEC-120** — o borderô tem tarifa de valor desconhecido (`NaN` no
      # legado, carregado como NULO). Os totais são do que se sabe, não do todo,
      # e a tela precisa dizer isso.
      expose :has_unknown_tax,
             documentation: { type: 'Boolean', desc: 'Tem tarifa de valor DESCONHECIDO (DEC-120): os totais são parciais' } do |e|
        e.unknown_tax?
      end

      expose :derived, documentation: { type: 'Object', desc: 'Os 37 valores calculados. Mesmo formato da prévia (C2)' } do |e|
        Api::Entities::ReceivableDerived.represent(e).as_json
      end

      expose :created_at
      expose :updated_at
    end
  end
end
