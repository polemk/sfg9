# frozen_string_literal: true

# S6 / **DB-159**, **DB-560** — tipo de recebível (Duplicata, Cheque, ACC…).
# **Catálogo GLOBAL** (C1, regra 4).
#
# `is_active` sem efeito em filtro (Q-B12), igual a `Wallet`.
class ReceivableKind < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }

  def self.blocking_dependents
    { 'ReceivableEntry' => { foreign_key: :receivable_kind_id, label: 'borderô(s)' } }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze
end
