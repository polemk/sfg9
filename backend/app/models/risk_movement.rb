# frozen_string_literal: true

# **Model criado na S5, de propriedade compartilhada — leia antes de mexer.**
#
# O esquema (`DB-236`) é da S5, porque as 7 tabelas de risco nascem juntas e as
# FKs precisam existir antes de a S7 escrever. **O comportamento é da S7**:
# recálculo da cadeia (`update_values`), movimento espelho de transferência,
# CRUD e telas.
#
# O que está aqui é o mínimo para que a S5 possa **ler** saldo por data
# (`Risk::Calculator#balance_on`, BE-266) e para que os golden tests do motor de
# exposição possam montar uma cadeia realista. **S7: acrescente, não reescreva.**
#
# Duas notas de esquema que valem regra:
#
# 1. **`sequence`, não `order`.** `order` é palavra reservada em SQL e só
#    sobrevive no legado porque o Rails a cita. O payload da API expõe
#    `sequence`.
# 2. **A ordem é (`date`, `created_at`), nunca `id`.** É a ordem em que os
#    sinais `+1`/`−1` se acumulam — reordenar por `id` **muda saldo**. O índice
#    do banco é exatamente esse trio.
class RiskMovement < ApplicationRecord
  include ProjectScoped

  belongs_to :risk_operation, inverse_of: :movements
  belongs_to :movement_type, class_name: 'RiskMovementType',
                             foreign_key: :movement_type_id, inverse_of: false
  belongs_to :company
  belongs_to :carrier
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  belongs_to :pair_movement, class_name: 'RiskMovement', foreign_key: :pair_id,
                             optional: true, inverse_of: false

  delegate :credit_type, :credit_type_value, to: :movement_type, allow_nil: true

  # Carimbos copiados da operação, como no legado (`:15-19`).
  before_validation :stamp_scope_from_operation

  validates :risk_operation_id, :movement_type_id, presence: true
  validates :company_id, :carrier_id, presence: true
  validates :date, presence: true
  validates :movement_value, presence: true
  validate :date_inside_operation_window

  # A ordem canônica da cadeia. Todo consumidor usa esta, e só esta.
  scope :chain_order, -> { order(date: :asc, created_at: :asc) }
  scope :until_date, ->(date) { where('DATE(risk_movements.date) <= DATE(?)', date.to_date) }
  scope :transfers, -> { joins(:movement_type).where(risk_movement_types: { is_transfer: true }) }

  # ---------------------------------------------------------------------
  # S7 / BE-273, BE-276 — o movimento reescreve a cadeia da operação
  # ---------------------------------------------------------------------
  # `../sfg/app/models/risk_movement.rb:30-32,67-69`: gravar ou apagar um
  # movimento salva a operação, e o `before_validation` dela recalcula tudo.
  # É a mesma implementação que a tela lê (contrato C2) — nenhum componente
  # React soma saldo.
  after_commit :recalculate_operation, on: %i[create update]
  after_commit :mirror_to_pair, on: :update
  after_destroy :recalculate_operation_after_destroy

  private

  # **BE-276 — a correção do D-97.** O legado escreve
  # `on_duplicate_key_update: [:date, movement_value]` (`:40`) — **`movement_value`
  # sem os dois-pontos**, ou seja uma variável local que não existe. Editar um
  # movimento que tenha par levanta `NameError` **em produção**: a transferência
  # pré↔antecipação está quebrada no legado desde que foi escrita.
  #
  # A intenção era clara e é o que fica: data **e** valor espelhados no par.
  # `update_columns` porque o espelho não pode reentrar nas callbacks (o par
  # espelharia de volta, em laço); a cadeia do par é refeita logo em seguida,
  # explicitamente.
  def mirror_to_pair
    par = pair_movement
    return if par.nil?
    return if par.date == date && par.movement_value == movement_value

    par.update_columns(date: date, movement_value: movement_value, updated_at: Time.current)
    par.risk_operation&.save
  end

  def recalculate_operation
    risk_operation&.save
  end

  # `after_destroy`, não `after_commit`: o `sequence` dos restantes tem de ser
  # renumerado dentro da mesma transação da exclusão, senão uma falha posterior
  # deixaria a cadeia numerada como se a linha ainda existisse.
  def recalculate_operation_after_destroy
    risk_operation&.save
  end

  def stamp_scope_from_operation
    return if risk_operation.nil?

    self.project_id = risk_operation.project_id
    self.company_id = risk_operation.company_id
    self.carrier_id = risk_operation.carrier_id
  end

  # Réplica de `date_on_interval` (`../sfg/app/models/risk_movement.rb:22-28`),
  # com a única adaptação que a B-08 obriga: a operação **estática** não tem
  # janela (as datas são nulas em vez das sentinelas de ±2000 anos), e no legado
  # a comparação passava sempre justamente porque a janela era absurda. O efeito
  # é o mesmo: movimento em operação estática aceita qualquer data.
  def date_inside_operation_window
    return if date.blank? || risk_operation.nil?
    return if risk_operation.is_static?
    return if risk_operation.issue_date.blank? || risk_operation.due_date.blank?

    return unless date < risk_operation.issue_date || date > risk_operation.due_date

    errors.add(:date, 'Deve estar entre as datas de emissão e de vencimento da operação')
  end
end
