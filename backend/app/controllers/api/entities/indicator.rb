# frozen_string_literal: true

module Api
  module Entities
    # S10 / BE-311, BE-314, BE-315 — o indicador.
    #
    # `entries_count` e `projects_count` vêm das opções `entry_usage`/`connection_usage`,
    # calculadas **uma vez** pelo endpoint para a página inteira
    # (`IndicatorService.entry_counts`). Calcular aqui dentro seria uma consulta
    # por linha — e são justamente os dois números que a confirmação de exclusão
    # precisa mostrar ANTES de qualquer escrita (FE-315, o D-66 na copy).
    class Indicator < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title,
             documentation: { type: 'String', desc: 'Título. CAIXA ALTA e sem acento, por decisão (DEC-89).' }
      expose :key,
             documentation: { type: 'String', desc: 'Chave de Integração. Derivada na criação e congelada (DEC-85).' }
      expose :value_type, documentation: { type: 'String', desc: 'Hoje só "Dinheiro" (Q-R32).' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :project_id,
             documentation: { type: 'String', desc: 'NULL = indicador GLOBAL; preenchido = específico do projeto.' }
      # **DB-092 (S4)** — a COLUNA, não mais a inferência de `project_id IS NULL`
      # feita aqui na serialização. O valor que o front lê agora é o mesmo que o
      # banco guarda e que o CHECK protege.
      expose :scope, documentation: { type: 'String', desc: '`global` ou `project`. Coluna explícita (DB-092).' }
      # A "Instrução" — ActionText, **sanitizada aqui, no servidor**.
      #
      # Antes ia crua, com a sanitização só no cliente. Sanitizar no cliente é
      # defesa em profundidade, nunca a defesa: quem consome a API não é só a
      # nossa tela — um relatório, uma exportação ou um `curl` recebem o que o
      # servidor mandar. A allowlist é a mesma do contrato e da nota de projeto
      # (`Sfg::RichText`); três allowlists diferentes valem pela mais fraca.
      expose :description_html, documentation: { type: 'String', desc: 'Instrução em rich text (ActionText), sanitizada.' } do |i|
        Sfg::RichText.sanitize(i.description&.body&.to_html)
      end
      expose :entries_count,
             documentation: { type: 'Integer', desc: 'Lançamentos existentes — é o número da confirmação (FE-315).' } do |i, options|
        (options[:entry_usage] || {})[i.id].to_i
      end
      expose :projects_count,
             documentation: { type: 'Integer', desc: 'Projetos conectados.' } do |i, options|
        (options[:connection_usage] || {})[i.id].to_i
      end
      expose :discarded_at, documentation: { type: 'DateTime', desc: 'Exclusão lógica (D-66). NULL = vivo.' }
      expose :created_at
      expose :updated_at
    end
  end
end
