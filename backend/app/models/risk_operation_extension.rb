# frozen_string_literal: true

# S7 / **BE-277, DB-577** — **prorrogação de vencimento** de uma operação de risco.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220616181724_create_risk_operation_extensions` está entre as **24
# migrations que nunca subiram** (`analise-dump-producao.md` §1). A última
# migration aplicada em produção é de 25/05/2022 e o sistema rodou em uso até
# 31/05/2025 — **não existe uma única prorrogação no dump**. O golden `M4` tem
# uma **fonte** (`../sfg/app/models/risk_operation_extension.rb`), não um
# **oráculo**: ele trava a leitura do código de 2022, não um comportamento
# observado.
#
# ## O que o legado faz, em quatro linhas
#
# ```ruby
# before_validation -> { self.original_due_date = self.operation.due_date }, on: [:create]
# after_create      -> { self.operation.due_date = self.new_due_date; self.operation.save }
# ```
#
# Duas consequências são **comportamento a preservar**:
#
# 1. **O `original_due_date` que vem do formulário é ignorado.** Ele é carimbado
#    da operação, sempre. É o que faz o log ser um log e não um campo editável.
# 2. **Salvar a operação dispara o recálculo da cadeia** (`BE-265`), porque
#    esticar o vencimento muda a janela em que os movimentos são aceitos.
#
# ## A única regra nova, e ela é do banco também
#
# `new_due_date > original_due_date` passa a valer **no servidor**. No legado só
# o `minDate` do datepicker impedia (`extension_helper/_body`), e por requisição
# direta dava para **encurtar** o vencimento — `after_create` aplicava a data
# menor à operação sem reclamar, e movimentos legítimos passavam a cair fora da
# janela. A S5 já pôs o `CHECK` no banco; aqui está a validação que dá a
# mensagem em vez do 500 de constraint.
#
# ## O log é imutável
#
# Não há `update` exposto (o legado também não tem). Corrigir uma prorrogação é
# lançar outra — que é o que preserva o histórico de quantas vezes a operação
# foi esticada, número que a lista de operações mostra na coluna "Prorrogações".
class RiskOperationExtension < ApplicationRecord
  # **Sem `Auditable`, e a linha está escrita em `Sfg::AuditTrail::EXCLUDED`**:
  # este registro **já é** o log imutável da prorrogação (autor, data anterior,
  # data nova, observação, sem update exposto). Versioná-lo seria a segunda
  # trilha que o DEC-59 existe para evitar; a mudança de `due_date` que ele
  # causa aparece na trilha da `RiskOperation`, que é versionada.

  belongs_to :operation, class_name: 'RiskOperation', foreign_key: :risk_operation_id,
                         inverse_of: :extensions
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  before_validation :stamp_original_due_date, on: :create
  after_create :push_operation_due_date!

  validates :risk_operation_id, :user_id, presence: true
  validates :original_due_date, :new_due_date, presence: true
  validate :must_move_forward

  scope :chronological, -> { order(created_at: :asc) }

  private

  # `:5` — o valor do formulário **não é lido**.
  def stamp_original_due_date
    self.original_due_date = operation&.due_date
  end

  # `:9-10` — a operação recebe a data nova e é salva, o que refaz a cadeia.
  def push_operation_due_date!
    operation.due_date = new_due_date
    operation.save!
  end

  # A regra que o legado só tinha no datepicker.
  def must_move_forward
    return if original_due_date.blank? || new_due_date.blank?
    return if new_due_date > original_due_date

    errors.add(:new_due_date,
               "deve ser posterior ao vencimento atual (#{I18n.l(original_due_date, format: :default)}). " \
               'Prorrogação não encurta prazo.')
  end
end
