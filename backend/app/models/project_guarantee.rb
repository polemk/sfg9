# frozen_string_literal: true

# S4 / BE-118, BE-119, DB-083 — **garantia do projeto**.
#
# Este é o model do defeito que dá nome ao contrato **C1**. Em
# `pub/project_guarantees_controller.rb:21-22` o legado escrevia:
#
#     @project_guarantees = ProjectGuarantee.joins(:carrier).joins(:guarantee_type)
#                                           .where(project_id: current_user.default_project_id)
#     @project_guarantees = ProjectGuarantee.where(id: params[:project_guarantee_id]) unless …
#
# A segunda linha **reatribui** a relação: o filtro de projeto simplesmente
# desaparece, e qualquer sessão lia a garantia de qualquer projeto passando o id
# na query string. É a família D-01 / D-16 / D-29 / D-76 / D-100 — e é por isso
# que o filtro por id, aqui, é aplicado **dentro** de `for_project`.
#
# Duas regras de negócio que o servidor passa a garantir:
#
# 1. **Só portador CONECTADO ao projeto** (BE-119). O legado usava dois
#    critérios diferentes para "o projeto tem portador": o botão olhava
#    `active_risk_controls_carriers` e o formulário olhava `project.carriers`.
#    Um critério, e é a conexão.
# 2. **`user_id` vem da SESSÃO.** O `permit` do legado aceitava `:user_id` e
#    `:project_id` do corpo, e o `update` não sobrescrevia nenhum dos dois.
class ProjectGuarantee < ApplicationRecord
  include ProjectScoped

  belongs_to :carrier
  belongs_to :guarantee_type, class_name: 'ProjectGuaranteeType'
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, presence: true, length: { maximum: 255 }
  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validate :carrier_connected_to_project

  before_validation :normalize_title

  # `carriers.title` e `project_guarantees.title` — os dois campos que a tela
  # deixa buscar, exatamente como o legado (`OR` entre os dois).
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    joins(:carrier).where('carriers.title ILIKE :q OR project_guarantees.title ILIKE :q', q: padrao)
  }

  # **Ordenar por "Título" FUNCIONA** (D-32). No legado a chave `title` devolvia
  # `"risk_operations.title"` — tabela que o `joins` nem incluía —, então clicar
  # no cabeçalho "Título" produzia erro de SQL. Aqui a chave aponta para a
  # coluna que a tela mostra.
  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => 'project_guarantees.title',
      'guarantee_type' => 'project_guarantee_types.title',
      'carrier' => 'carriers.title',
      'value' => 'project_guarantees.value',
      'created_at' => 'project_guarantees.created_at'
    },
    default: { 'project_guarantees.created_at' => :desc }
  ).freeze

  # As duas chaves acima precisam do join para ordenar. Aplicado sempre: o custo
  # é um join sobre tabelas pequenas, e a alternativa é a listagem quebrar
  # conforme a coluna clicada — que foi o que aconteceu no legado.
  scope :with_ordering_joins, -> { joins(:carrier).joins(:guarantee_type) }

  private

  def normalize_title
    self.title = title.to_s.strip.presence
  end

  # Regra 1 do cabeçalho. Sem projeto ou sem portador não é este o erro a
  # reportar — a validação de presença já fala por si.
  def carrier_connected_to_project
    return if project_id.blank? || carrier_id.blank?
    return if ProjectToCarrierConnection.exists?(project_id: project_id, carrier_id: carrier_id)

    errors.add(:carrier_id, 'não está conectado a este projeto')
  end
end
