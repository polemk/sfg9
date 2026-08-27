# frozen_string_literal: true

module Api
  module Entities
    # S10 / FE-319, FE-320 — uma linha da tela "Indicadores específicos".
    #
    # O que a tela precisa saber de cada indicador alcançável pelo projeto:
    # se está **conectado** (o interruptor) e se é **global** ou **específico**
    # (só o global tem interruptor; o específico tem menu de edição/exclusão).
    class IndicatorConnection < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID do INDICADOR, não da conexão.' }
      expose :title, documentation: { type: 'String' }
      expose :key, documentation: { type: 'String' }
      expose :is_active, documentation: { type: 'Boolean' }
      # **DB-092 (S4)** — a coluna explícita. Era `project_id IS NULL` inferido
      # aqui; é ela que decide interruptor × menu na linha da tela.
      expose :scope, documentation: { type: 'String', desc: '`global` ou `project`. Coluna explícita (DB-092).' }
      expose :connected, documentation: { type: 'Boolean', desc: 'Aparece na grade mensal deste projeto?' } do |i, options|
        (options[:connected_ids] || Set.new).include?(i.id)
      end
      expose :description_html, documentation: { type: 'String', desc: 'Instrução em rich text (ActionText).' } do |i|
        i.description&.body&.to_html
      end
      expose :entries_count,
             documentation: { type: 'Integer', desc: 'Lançamentos existentes — o número da confirmação (FE-321).' } do |i, options|
        (options[:entry_usage] || {})[i.id].to_i
      end
    end
  end
end
