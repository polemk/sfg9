# frozen_string_literal: true

# S3 / BE-700..BE-706, DB-084 — **tipo de garantia**. Catálogo GLOBAL (C1, regra 4).
#
# É o único catálogo desta fatia com defeito de **autorização**, não de
# usabilidade: no legado o controller declarava `requires_current_user? == false`
# e o endpoint respondia **para anônimo** (D-23). O gate og/admin/gerente
# existia só na view. No ai9 ele nasce dentro de `api/v1/base.rb`, que já exige
# sessão — 401 sem credencial é o comportamento padrão da base, não um
# mecanismo novo.
#
# **DEC-86 — o conteúdo é NOVO.** A tabela existe no legado desde 2022 e nenhum
# seed a popula: o select de garantias é alimentado por
# `ProjectGuaranteeType.all` e sobe **vazio** até alguém cadastrar à mão. Não há
# nada a migrar. Por isso `is_provisional`: os tipos semeados são suposição do
# orquestrador, a lista definitiva é do cliente, e a tela avisa.
class ProjectGuaranteeType < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }
  validates :integration_key, uniqueness: { case_sensitive: false }
  validates :sort_order, numericality: { only_integer: true }

  scope :provisional, -> { where(is_provisional: true) }

  def self.blocking_dependents
    # S4 — as garantias do projeto que usam este tipo (BE-705).
    { 'ProjectGuarantee' => { foreign_key: :guarantee_type_id, label: 'garantia(s) de projeto' } }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => :title, 'key' => :integration_key,
      'sort_order' => :sort_order, 'created_at' => :created_at
    },
    default: { sort_order: :asc, title: :asc }
  ).freeze
end
