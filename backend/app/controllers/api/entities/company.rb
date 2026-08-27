# frozen_string_literal: true

module Api
  module Entities
    # S4 / BE-050, BE-057 — **empresa**.
    #
    # `carriers_count` e `risk_controls_count` vêm da opção `usage`, calculada
    # **uma vez** pelo endpoint para a página inteira. Calcular aqui dentro seria
    # uma consulta por linha — é o N+1 que a tela de empresas do legado tinha.
    class Company < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :project_id, documentation: { type: 'String', desc: 'Projeto dono. NUNCA aceito no corpo (C1)' }
      expose :title, documentation: { type: 'String', desc: 'Razão social. Única por projeto' }
      expose :has_safegold_management,
             documentation: { type: 'Boolean',
                              desc: 'CARIMBO do projeto (DEC-112). É a ÚNICA filha ressincronizada quando a marca muda' }
      expose :carriers_count,
             documentation: { type: 'Integer', desc: 'Portadores conectados ao projeto' } do |_c, options|
        options[:carriers_count].to_i
      end
      # **Só os limites** — não a soma dos dependentes.
      #
      # Isto já mostrou **43** onde o banco tinha **4**: a contagem somava todos
      # os dependentes que bloqueiam a exclusão (limites + renegociações +
      # recebíveis) e o campo dizia que eram limites. Número errado na tela de um
      # sistema de crédito é pior que tela quebrada — ninguém reporta.
      expose :risk_controls_count,
             documentation: { type: 'Integer', desc: 'Limites de risco da empresa (só eles)' } do |c, options|
        ((options[:usage] || {})[c.id] || {})['RiskControl'].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
