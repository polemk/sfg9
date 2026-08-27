# frozen_string_literal: true

module Api
  module Entities
    # S2 / BE-528 — uma fala da thread.
    class MessageNote < Grape::Entity
      expose :id
      expose :description
      expose :author_name
      expose :author_email
      expose :unread
      # `from_admin` é o que a tela usa para decidir de que lado do diálogo a
      # bolha fica. No legado isso era `user_id.nil?` calculado na view.
      expose :from_admin do |n|
        n.from_admin?
      end
      # DEC-58 / P-088: portadas sem consumidor de UI. Ficam expostas para que a
      # ausência seja verificável, não invisível.
      expose :quoted_note_id
      expose :top_parent_quote_id
      expose :created_at
    end
  end
end
