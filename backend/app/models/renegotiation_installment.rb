# frozen_string_literal: true

# S9 / BE-218, DB-191 — **parcela (previsão) da renegociação**.
#
# Como no `Renegotiation`, este model **não faz conta e não dispara cascata**. No
# legado o `after_destroy` chamava `renegotiation.update_values!` e
# `update_installment_numbers!` — e o `update_values!` da própria parcela chamava
# `save` sem bang e depois a renegociação, encadeando três gravações por
# callback. Aqui a cascata é escrita, uma vez, em
# `Renegotiations::RecalculateInstallment`.
#
# `project_id` é denormalizado da renegociação e **garantido coerente pelo banco**
# (FK composta, ver a migration). O model o carimba na gravação para que ninguém
# precise lembrar.
class RenegotiationInstallment < ApplicationRecord
  include ProjectScoped

  belongs_to :renegotiation, inverse_of: :installments
  has_many :payments, class_name: 'RenegotiationPayment', dependent: :restrict_with_error,
                      inverse_of: :renegotiation_installment,
                      foreign_key: :renegotiation_installment_id

  # Tipos de criação e de intervalo, com os rótulos do legado
  # (`renegotiation_installment.rb:41-53`).
  DELAY_DAY = 'Dias'
  DELAY_WEEK = 'Semanas'
  DELAY_MONTH = 'Meses'
  DELAY_TYPES = [DELAY_DAY, DELAY_WEEK, DELAY_MONTH].freeze

  validates :due_date, presence: true
  # Principal **> 0** — é a validação do legado, e é a que o servidor precisa
  # responder com 422 de verdade: no legado ela existia, o erro era engolido pelo
  # `create` cujo retorno era ignorado, e a resposta era 200 "criada com sucesso"
  # sem ter criado nada (**D-52**).
  validates :main_value, presence: true, numericality: { greater_than: 0 }
  validates :interest_value, :monetary_correction_value, :late_payment_value,
            :installment_total_value, :main_value_with_interest, :main_value_with_interest_cm,
            presence: true, numericality: true
  validates :batch_token, presence: true
  # Continua no model (mensagem legível) **e** no banco (índice único), porque a
  # checagem em Ruby sozinha é sujeita a corrida entre duas abas (**D-12**).
  validates :due_date, uniqueness: { scope: :renegotiation_id,
                                     message: 'já tem parcela cadastrada nesta renegociação' }

  before_validation :carimbar_escopo_e_periodo

  scope :ordered, -> { order(due_date: :asc, created_at: :asc) }
  scope :paid, -> { where(is_paid: true) }
  # **A definição de "vencida", num lugar só.** É o que faz a contagem parar de
  # depender do cron diário (D-54 / D-B6 / OPS-190): o mesmo escopo alimenta o
  # agregado persistido e a apuração ao vivo da leitura. Duas definições seriam
  # duas respostas para "quantas venceram".
  scope :overdue, ->(hoje = Date.current) { where(is_paid: false).where('due_date < ?', hoje) }
  # "A vencer" no sentido de "próxima": vencimento hoje ou no futuro e em aberto.
  # **Não** é o `due_installments` do agregado, que é `total - pagas` e portanto
  # inclui as vencidas (Q-B23). Os dois nomes existem, medem coisas diferentes, e
  # essa diferença é do legado.
  scope :upcoming, ->(hoje = Date.current) { where(is_paid: false).where('due_date >= ?', hoje) }
  scope :in_month, ->(mes, ano) { where(month: mes, year: ano) }

  def payment?
    payments.exists?
  end

  # "#3 12.05.2025 - R$ 1.200,00" — rótulo do seletor de previsão no painel de
  # pagamento.
  def beauty_name
    partes = ["##{number}"]
    partes << due_date.strftime('%d.%m.%Y') if due_date.present?
    partes << ActiveSupport::NumberHelper.number_to_currency(main_value, unit: 'R$', separator: ',', delimiter: '.')
    "#{partes.first} #{partes[1..].join(' - ')}"
  end

  private

  def carimbar_escopo_e_periodo
    self.project_id ||= renegotiation&.project_id
    return if due_date.blank?

    # Mês e ano acompanham a data — inclusive quando ela muda numa edição, que é
    # o ramo que o legado só cobria dentro de um `if changed.include?`.
    self.month = due_date.month
    self.year = due_date.year
  end
end
