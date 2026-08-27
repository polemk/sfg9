# frozen_string_literal: true

# S2 / DB-392, DB-512 — a junção observador × contexto.
#
# A prevenção de duplicata **é o índice único** `(observer_id, context)`, não a
# validação: no legado (`observer_context.rb:9`) era um `SELECT COUNT` a cada
# save, e duas requisições concorrentes passavam as duas pela contagem antes de
# qualquer uma gravar. A validação abaixo existe só para a mensagem de erro ser
# legível no caminho de uso normal — quem realmente barra é o banco.
class ObserverContext < ApplicationRecord
  belongs_to :observer, inverse_of: :observer_contexts

  validates :context, presence: true, inclusion: { in: AdminMessage::CONTEXTS.keys }
  validates :context, uniqueness: { scope: :observer_id, message: 'já está definido para este observador' }
end
