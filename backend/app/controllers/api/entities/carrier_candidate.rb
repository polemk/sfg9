# frozen_string_literal: true

module Api
  module Entities
    # S4 / BE-104 — **candidato a conexão**: um portador do catálogo GLOBAL com
    # o estado da conexão com o projeto corrente já resolvido.
    #
    # `connected` vem da opção `connected_ids`, calculada em **uma** consulta
    # pelo serviço. O legado fazia `o.carriers.include?(t)` dentro do laço da
    # view — uma consulta por linha da lista.
    class CarrierCandidate < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID do PORTADOR' }
      expose :title
      expose :integration_key
      expose :is_active
      expose :group_title, documentation: { type: 'String' } do |c|
        c.group&.title
      end
      expose :connected,
             documentation: { type: 'Boolean', desc: 'Resolvido em UMA consulta, não por linha' } do |c, options|
        (options[:connected_ids] || Set.new).include?(c.id)
      end
    end
  end
end
