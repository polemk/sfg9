# frozen_string_literal: true

module Api
  module Entities
    # S12 / FE-364, FE-366 — item da central de ajuda.
    class HelpItem < Grape::Entity
      expose :id
      expose :title
      expose :help_category_id
      expose :position
      expose :created_at
      expose :updated_at

      expose :category do |i|
        i.category && { id: i.category.id, title: i.category.title, slug: i.category.slug }
      end

      expose :group do |i|
        i.category&.group && { id: i.category.group.id, title: i.category.group.title }
      end

      # AUTOR e QUEM ALTEROU são campos diferentes (FE-366). No legado o autor
      # era reescrito a cada edição, então a pergunta "quem escreveu isto" não
      # tinha resposta depois da primeira revisão.
      expose :author do |i|
        i.author && { id: i.author.id, name: i.author.name }
      end
      expose :last_updated_user do |i|
        i.last_updated_user && { id: i.last_updated_user.id, name: i.last_updated_user.name }
      end

      expose :description_html, if: ->(_i, opts) { opts[:type] == :full } do |i|
        i.description_html
      end

      # Trecho em volta do termo buscado. Determinístico.
      expose :excerpt, if: ->(_i, opts) { opts[:term].present? } do |i, opts|
        ::Help::Search.excerpt(i, term: opts[:term])
      end
    end
  end
end
