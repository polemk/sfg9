# frozen_string_literal: true

# S5 / BE-278, DB-233, DB-575 — **subtipo de limite**.
#
# É o subtipo que decide o **bucket** da operação no painel de exposição:
# `is_pre = false` soma em "Liquidável" (`../sfg/app/models/risk_control.rb:129-130`)
# e `is_pre = true` soma em "Pré-Faturamento" (`:144-145`). Errar aqui muda número
# na tela principal do produto.
#
# O subtipo **não é cadastrado à mão**: nasce do `after_create` do tipo pai e
# herda dele as três flags. A única coluna que é decisão própria é
# `is_default_for_type` (DEC-67).
class RiskOperationSubtype < ApplicationRecord
  include GlobalCatalog

  belongs_to :operation_type, class_name: 'RiskOperationType',
                              foreign_key: :risk_operation_type_id, inverse_of: :subtypes
  belongs_to :pair, class_name: 'RiskOperationSubtype', foreign_key: :pair_id,
                    optional: true, inverse_of: false
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :risk_operation_type_id, presence: true
  validates :title, uniqueness: { scope: :risk_operation_type_id, case_sensitive: false }
  # `validates_uniqueness_of :is_pre, scope: [:risk_operation_type_id]` do legado:
  # um tipo tem no máximo um "pré" e um "antecipação".
  validates :is_pre, uniqueness: { scope: :risk_operation_type_id }

  scope :manual, -> { where(allow_manual_operations: true, is_active: true) }
  scope :receivable, -> { where(allow_receivable_entries: true, is_active: true) }
  scope :pre, -> { where(is_pre: true) }
  scope :liquidable, -> { where(is_pre: false) }

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { is_pre: :desc, title: :asc }
  ).freeze

  def self.blocking_dependents
    { 'RiskOperation' => { foreign_key: :operation_subtype_id, label: 'operação(ões) de risco' } }
  end
end
