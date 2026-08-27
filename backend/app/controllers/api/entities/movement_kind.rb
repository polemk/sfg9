# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-186 — tipo de movimentação (tarifa). Catálogo global.
    #
    # `tax_classifier` é o classificador ATIVO num campo só — a tela mostra uma
    # coluna em vez de quatro caixas, e o servidor garante que só um está ligado
    # (BE-447). Os quatro booleanos continuam expostos porque o painel lateral
    # de edição precisa deles.
    class MovementKind < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Nome do tipo' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'Chave de integração, derivada do título na criação (BE-446)' }
      expose :is_active, documentation: { type: 'Boolean', desc: 'Ativo. Sem efeito em filtro (Q-B12)' }
      expose :kind, documentation: { type: 'String', desc: 'Sentido contábil: credit | debit' }
      expose :kind_label, documentation: { type: 'String', desc: 'Rótulo pt-BR do sentido (Crédito | Débito)' }
      expose :is_operation,
             documentation: { type: 'Boolean', desc: 'Aparece na lista de tarifas do borderô' }
      expose :is_advalorem, documentation: { type: 'Boolean' }
      expose :is_desagio, documentation: { type: 'Boolean' }
      expose :is_iof, documentation: { type: 'Boolean' }
      expose :is_liquidation,
             documentation: { type: 'Boolean', desc: 'Portado SEM consumidor (D-74, Q-B13)' }
      expose :is_title,
             documentation: { type: 'Boolean', desc: 'Portado SEM consumidor (D-74, Q-B13)' }
      expose :tax_classifier,
             documentation: { type: 'String', desc: 'O classificador ativo, ou nulo. No máximo um (BE-447)' } do |k|
        k.tax_classifier&.to_s
      end
      expose :receivable_taxes_count,
             documentation: { type: 'Integer', desc: 'Tarifas vinculadas — é o que bloqueia a exclusão (BE-448)' } do |k, options|
        (options[:usage] || {})[k.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
