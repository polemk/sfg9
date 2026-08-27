# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-188 — recibo.
    #
    # ⚠ NUNCA EXECUTADO EM PRODUÇÃO (DEC-103b).
    #
    # `date` pode ser **nula**: vem de `operation.issue_date`, e a operação
    # estática do par pré/antecipação tem data nula por desenho (B-08 da S5).
    # A tela precisa aguentar isso (FE-184).
    class Receipt < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID. Nulo quando é só candidato' }
      expose :temp_id,
             documentation: { type: 'String', desc: 'Identidade do candidato ANTES de existir: RCP-<projeto>-<kind>-<remun>-<op>' }
      expose :charge_id, documentation: { type: 'String', desc: 'Pacote. Nulo enquanto não faturado' }
      expose :operation_id, documentation: { type: 'String' }
      expose :operation_type, documentation: { type: 'String', desc: 'RiskOperation | StructuredOperation' }
      expose :remuneration_id, documentation: { type: 'String', desc: 'Remuneração usada. Model da S8' }
      expose :kind, documentation: { type: 'String', desc: 'LIQ (risco) | EST (estruturada)' }
      expose :title, documentation: { type: 'String', desc: 'Título delegado da remuneração' }
      expose :fee, documentation: { type: 'BigDecimal', desc: 'Taxa em %, 0-100. Sem validação de faixa (DEC-37)' }
      expose :operation_value, documentation: { type: 'BigDecimal', desc: 'FOTOGRAFIA do valor da operação' }
      expose :value, documentation: { type: 'BigDecimal', desc: 'A receita: operation_value × (fee/100), truncada em 2 (D-B14)' }
      expose :date, documentation: { type: 'Date', desc: 'FOTOGRAFIA da emissão. PODE SER NULA (operação estática)' }
      expose :operation_title, documentation: { type: 'String', desc: 'FOTOGRAFIA do título da operação' }
      expose :created_at
      expose :updated_at
    end
  end
end
