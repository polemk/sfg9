# frozen_string_literal: true

module Api
  module Entities
    # S4 / BE-102 — **conexão projeto ↔ portador**.
    #
    # O estado "conectado" é resolvido em **uma consulta** pelo serviço e chega
    # aqui pela opção `connected_ids`. O legado fazia `o.carriers.include?(t)`
    # dentro do laço da view — uma consulta por linha da lista.
    class ProjectCarrierConnection < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID da CONEXÃO (não do portador)' }
      expose :project_id
      expose :carrier_id
      expose :carrier_title, documentation: { type: 'String' } do |c|
        c.carrier&.title
      end
      expose :carrier_group_title, documentation: { type: 'String' } do |c|
        c.carrier&.group&.title
      end
      expose :carrier_is_active, documentation: { type: 'Boolean' } do |c|
        c.carrier&.is_active
      end
      expose :created_at
    end
  end
end
