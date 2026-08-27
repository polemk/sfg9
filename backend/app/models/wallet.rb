# frozen_string_literal: true

# S6 / **DB-158**, **DB-559** — carteira do borderô. **Catálogo GLOBAL** (C1,
# regra 4): não tem `project_id` no legado e não ganha um aqui. Um borderô de
# 2022 aponta para a carteira "Fomento" e ela precisa continuar visível em todo
# projeto.
#
# O `is_active` **continua sem efeito em filtro** (Q-B12): no legado a coluna
# existe, tem tela e **nenhuma consulta a lê**. Passar a filtrar faria carteira
# "desativada" sumir do select do borderô e quebraria o formulário de quem
# lança sobre ela.
class Wallet < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }

  # Exclusão BLOQUEIA, nunca cascateia (D-24). Declarado por nome porque o
  # mecanismo é o mesmo do resto da base — ver `BlockingDependents`.
  def self.blocking_dependents
    { 'ReceivableEntry' => { foreign_key: :wallet_id, label: 'borderô(s)' } }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze
end
