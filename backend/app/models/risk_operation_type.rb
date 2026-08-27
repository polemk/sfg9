# frozen_string_literal: true

# S5 / BE-278, DB-232, DB-574 — **tipo de limite de risco**. Catálogo GLOBAL.
#
# As quatro modalidades do Safegold (Fomento, Comissária, Intercompany, Auto
# Liquidável) são **linhas desta tabela** desde 2022, não colunas de
# `risk_controls` (achado C-09). Isso é o que dá ao produto o cadastro aberto de
# tipos — e é o que o motor de pré-faturamento inteiro depende.
#
# ### O `after_create` é a regra mais importante da classe
#
# O tipo **gera os próprios subtipos**, e a quantidade depende de
# `has_pre_faturamento`:
#
# - **com** pré-faturamento → **dois** subtipos, "… - pré-faturamento"
#   (`is_pre = true`) e "… - antecipação" (`is_pre = false`), ligados por
#   `pair_id`. São eles que decidem em qual bucket a operação soma no painel;
# - **sem** → **um** subtipo homônimo.
#
# Sem os subtipos certos, `Risk::StaticPairService` não consegue abrir o par
# estático do limite e a criação do limite **falha antes de gravar** (BE-241).
#
# ### `has_pre_faturamento` é imutável depois do create
#
# Não é capricho: mudá-la deixaria o tipo com o número errado de subtipos e
# trocaria, em silêncio, o bucket de limite de **toda operação já gravada**. O
# serviço a mantém fora do `permit` do update (`Risk::OperationTypeService`).
#
# ### DEC-67 — o subtipo padrão passa a ser declarado
#
# No legado, a operação criada sem campo de subtipo na tela pegava
# `subtypes.where(...).pluck(:id).first` — **sem `order`**, ou seja, ordem de
# inserção. Aqui o subtipo padrão é a coluna `is_default_for_type`, e o valor que
# este `after_create` grava **reproduz o que o `.first` fazia** (o "pré" nasce
# antes, logo era ele). Nada muda para quem já opera; o que muda é que a
# classificação deixa de depender da ordem de linhas num cadastro.
class RiskOperationType < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  has_many :subtypes, -> { order(is_pre: :desc, created_at: :asc) },
           class_name: 'RiskOperationSubtype', foreign_key: :risk_operation_type_id,
           dependent: :destroy, inverse_of: :operation_type

  validates :title, uniqueness: { case_sensitive: false }
  validates :integration_key, uniqueness: { case_sensitive: false }

  # Os três scopes do legado (`risk_operation_type.rb:2-5`), com `is_active`
  # como boolean. `active` vem do `GlobalCatalog`.
  scope :manual, -> { where(allow_manual_operations: true, is_active: true) }
  scope :receivable, -> { where(allow_receivable_entries: true, is_active: true) }
  scope :with_pre, -> { where(has_pre_faturamento: true, is_active: true) }

  after_create :generate_subtypes!
  after_update :propagate_flags_to_subtypes!
  before_destroy :refuse_to_destroy_seeded_type, prepend: true

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  def self.blocking_dependents
    {
      'RiskControl' => { foreign_key: :risk_operation_type_id, label: 'limite(s) de risco' },
      'RiskOperation' => { foreign_key: :operation_type_id, label: 'operação(ões) de risco' }
    }
  end

  # O subtipo que o formulário assume quando não pergunta (DEC-67).
  def default_subtype
    subtypes.find_by(is_default_for_type: true) || subtypes.first
  end

  # Ids dos subtipos de um bucket. É o que `Risk::Calculator` usa para separar
  # "liquidável" de "pré-faturamento".
  #
  # Filtra a associação **em memória**, de propósito: um `where(...).pluck(:id)`
  # aqui é uma consulta por chamada, e o motor de exposição chama isto uma vez
  # por fórmula por limite. Com `includes(risk_operation_type: :subtypes)` no
  # agregado, sai zero consulta; sem ele, sai uma (a do carregamento da
  # associação) em vez de uma por chamada. O conjunto de ids é o mesmo — cada
  # tipo tem no máximo dois subtipos, então não há custo de memória a discutir.
  def subtype_ids_for(is_pre:)
    subtypes.select { |subtipo| subtipo.is_pre == is_pre }.map(&:id)
  end

  private

  # Réplica de `../sfg/app/models/risk_operation_type.rb:21-54`.
  def generate_subtypes!
    if has_pre_faturamento?
      pre = build_subtype(title: "#{title} - pré-faturamento", is_pre: true, default_for_type: true)
      ant = build_subtype(title: "#{title} - antecipação", is_pre: false, default_for_type: false)
      pre.save!
      ant.save!
      # O par se conhece nos dois sentidos, como no legado.
      pre.update_columns(pair_id: ant.id, updated_at: Time.current)
      ant.update_columns(pair_id: pre.id, updated_at: Time.current)
    else
      build_subtype(title: title, is_pre: false, default_for_type: true).save!
    end
  end

  def build_subtype(title:, is_pre:, default_for_type:)
    subtypes.build(
      title: title,
      user_id: user_id,
      is_default: is_default,
      is_default_for_type: default_for_type,
      is_pre: is_pre,
      allow_manual_operations: allow_manual_operations,
      allow_receivable_entries: allow_receivable_entries,
      is_active: is_active
    )
  end

  # Réplica do `after_commit … on: [:update]` (`:56-63`), promovido a
  # `after_update` **dentro da transação**: no legado a propagação rodava depois
  # do commit e, se falhasse, o tipo ficava salvo com os subtipos divergentes.
  def propagate_flags_to_subtypes!
    return unless saved_change_to_allow_manual_operations? ||
                  saved_change_to_allow_receivable_entries? ||
                  saved_change_to_is_active?

    subtypes.find_each do |subtype|
      subtype.update!(
        allow_manual_operations: allow_manual_operations,
        allow_receivable_entries: allow_receivable_entries,
        is_active: is_active
      )
    end
  end

  def refuse_to_destroy_seeded_type
    return unless is_default?

    errors.add(:is_default, 'Não pode remover tipo padrão')
    throw(:abort)
  end
end
