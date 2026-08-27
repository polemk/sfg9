# frozen_string_literal: true

module Api
  module Entities
    # S12 / BE-334, FE-330 — uma versão de contrato.
    #
    # **O número da versão é exposto** (FE-330): o legado mostrava só "Atualizado
    # em", e a pessoa não tinha como saber qual texto estava lendo nem citar a
    # versão que aceitou.
    #
    # O corpo (`description_html`) só vai no `:full`, e já **sanitizado** — a
    # allowlist é aplicada na renderização (BE-345), num lugar só
    # (`Contracts::Renderer`), para que a tela pública e a do console mostrem
    # exatamente o mesmo texto. No legado eram dois caminhos diferentes e a
    # pública era a menos fiel.
    class Contract < Grape::Entity
      expose :id
      expose :kind
      expose :slug do |c|
        c.slug_value
      end
      expose :title
      expose :version
      expose :published_at
      expose :created_at
      expose :updated_at

      expose :creator, if: ->(_c, opts) { opts[:type] == :full } do |c|
        c.creator && { id: c.creator.id, name: c.creator.name }
      end

      expose :description_html, if: ->(_c, opts) { opts[:type] == :full }

      # Só para quem administra: quantos aceitaram e quantos ficariam com hash
      # divergente se o texto mudasse (mitigação 2 da DEC-80).
      expose :accepted_count, if: ->(_c, opts) { opts[:admin] } do |c|
        c.contract_deals.count
      end
      expose :divergent_count, if: ->(_c, opts) { opts[:admin] } do |c|
        c.divergent_deals_count
      end
    end
  end
end
