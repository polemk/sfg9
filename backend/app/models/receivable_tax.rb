# frozen_string_literal: true

# S6 / **BE-184**, **DB-161**, **DB-565** — a tarifa de um borderô. 58.473
# linhas em produção.
#
# ## Título e classificadores são DENORMALIZADOS na gravação (D-B13)
#
# É o que o legado faz (`../sfg/app/models/receivable_tax.rb:11-15`) e é o que
# preserva a classificação usada **no dia do lançamento**. Se a tarifa lesse os
# flags do `MovementKind` na hora do cálculo, alterar `is_desagio` de um tipo
# reescreveria a base do IOF de todos os borderôs históricos — 28 mil números
# mudando por causa de uma edição de catálogo.
#
# ## O recálculo do pai é do SERVIÇO, não de um callback
#
# No legado nada aqui recalculava o borderô: os `tarifas_*` só se corrigiam no
# próximo `save` do pai, e quem disparava esse save era o **JavaScript da tela**
# (`update_and_save()`). É o D-09 — e é por isso que quatro borderôs de produção
# têm o denormalizado defasado em relação às próprias tarifas.
#
# Aqui o recálculo acontece em `Receivables::TaxService` e nos serviços de
# criação/edição, dentro da mesma transação, chamando o `Calculator` uma vez.
# Um `after_save` aqui daria dois recálculos por save do pai.
class ReceivableTax < ApplicationRecord
  belongs_to :receivable_entry, inverse_of: :taxes
  belongs_to :movement_kind

  before_validation :denormalize_from_movement_kind

  # A presença do pai vem do próprio `belongs_to` (obrigatório por padrão no
  # Rails 5+). Validar `receivable_entry_id` em vez da ASSOCIAÇÃO quebraria a
  # criação em cascata: a tarifa é construída por `entry.taxes.build` **antes**
  # de o borderô ter id, e o `inverse_of` já aponta para o pai em memória.
  validates :movement_kind_id, presence: true
  validates :title, presence: true
  # **`value` NULO é permitido, e significa "valor DESCONHECIDO" (DEC-120).**
  #
  # Não é frouxidão: o caminho da tela continua exigindo o valor, porque o Grape
  # o declara `requires :value` (`api/v1/receivables.rb`) e um payload sem ele é
  # 400 antes de chegar aqui. Quem grava `nil` é **só** o ETL, e só na única
  # linha de produção em que o legado gravou `NaN` (D-10). Uma validação de
  # presença aqui obrigaria a carga a escolher entre falhar ou **afirmar zero** —
  # e afirmar zero é exatamente o que a decisão recusa.
  validates :value, numericality: true, allow_nil: true
  validate :value_must_be_finite

  # **Duplicidade de tipo no mesmo borderô continua PERMITIDA** (Q-B15): o
  # legado aceita duas linhas de "Outras Despesas", e em produção isso acontece.
  # Uma unicidade nova recusaria lançamento que existe.

  private

  def denormalize_from_movement_kind
    return if movement_kind_id.blank?

    kind = movement_kind
    return if kind.nil?

    self.title = kind.title
    self.is_advalorem = kind.is_advalorem
    self.is_desagio = kind.is_desagio
    self.is_iof = kind.is_iof
  end

  # D-10: `NaN` numa tarifa contamina o total, o líquido e os quatro
  # percentuais. Foi assim que o borderô 22424 de produção ficou com `NaN` em
  # nove colunas — a partir de um único deságio inválido.
  def value_must_be_finite
    return unless Receivables::InputGuard.nonfinite?(value)

    errors.add(:value, 'não é um número válido.')
  end
end
