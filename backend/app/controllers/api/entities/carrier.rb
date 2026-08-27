# frozen_string_literal: true

module Api
  module Entities
    # S3 / BE-067, BE-068 — portador (contraparte financiadora).
    #
    # Duas coisas que o formato garante e que o legado não garantia:
    #
    # - **`bank_code` é STRING no JSON** (DC-12). Serializar como número faria
    #   `001` virar `1` no último passo, depois de o banco ter preservado.
    # - **`subordinated_accounts_percent` é somente leitura** (DC-09): sai daqui
    #   derivado e não é aceito de volta pelo endpoint. A fórmula é a **do
    #   legado**, replicada (DEC-30): subordinadas ÷ **sênior** × 100, e `0`
    #   quando sênior é 0 — que é a guarda de divisão por zero do próprio legado,
    #   promovida do JS para o servidor.
    class Carrier < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Razão social. Duplicado é permitido (BE-071).' }
      expose :resume, documentation: { type: 'String' }
      expose :integration_key, documentation: { type: 'String' }
      expose :is_active, documentation: { type: 'Boolean' }

      expose :group_id, documentation: { type: 'String', desc: 'UUID do grupo' }
      expose :group_title, documentation: { type: 'String' } do |c|
        c.group&.title
      end

      expose :financial_agent,
             documentation: { type: 'String', desc: 'FIDC / Securitizadora / Factoring / Cliente' }
      expose :bank_code, documentation: { type: 'String', desc: 'Código COMPE. STRING — `001` continua `001`.' }
      expose :city, documentation: { type: 'String' }
      expose :uf, documentation: { type: 'String' }
      expose :city_label, documentation: { type: 'String', desc: 'Cidade formatada com fallback `-` (BE-071)' } do |c|
        c.formatted_city
      end

      # A estrutura de FIDC.
      expose :net_worth, documentation: { type: 'BigDecimal', desc: 'Patrimônio líquido' }
      expose :senior_accounts, documentation: { type: 'Integer' }
      expose :subordinated_accounts, documentation: { type: 'Integer' }
      expose :subordinated_accounts_percent,
             documentation: { type: 'BigDecimal', desc: 'DERIVADO no servidor (DC-09) pela fórmula do legado (DEC-30): subordinadas ÷ sênior × 100; 0 quando sênior é 0.' }

      # DEC-47 — o logo volta, por ActiveStorage no próprio model (DEC-91).
      expose :logo_url, documentation: { type: 'String' } do |c|
        c.logo_url
      end

      expose :projects_count,
             documentation: { type: 'Integer', desc: 'Projetos conectados a este portador' } do |c, options|
        (options[:usage] || {})[c.id].to_i
      end

      expose :created_at
      expose :updated_at
    end
  end
end
