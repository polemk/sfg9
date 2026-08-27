# frozen_string_literal: true

# S6 / **BE-160** (parte de dados) — a alíquota de IOF **com vigência**.
# Corrige o **D-15**.
#
# No legado as duas alíquotas estão cravadas dentro da fórmula
# (`../sfg/app/models/receivable_entry.rb:54`):
#
#     (vlr_bruto_final - v_advlr_iof) * (prz_med_pond_bco * 0.000041) +
#     (vlr_bruto_final - v_advlr_iof) * 0.0038
#
# Enquanto a alíquota nunca muda, isso funciona. No dia em que mudar, **todo
# recálculo de borderô histórico passa a usar a alíquota de hoje**, em silêncio
# — inclusive o recálculo em lote (`OPS-151`), que é justamente o que roda sobre
# a base inteira.
#
# Aqui a alíquota é resolvida **pela data da operação** e injetada no
# `Receivables::Calculator`, que continua puro. O golden fixa as alíquotas e não
# depende do seed.
#
# **Padrão reaproveitável**: qualquer taxa regulada que mude por decreto cabe
# nesta forma. É a única tabela nova desta fatia que não existe no legado.
class IofRate < ApplicationRecord
  validates :daily_rate, presence: true, numericality: true
  validates :fixed_rate, presence: true, numericality: true
  validates :valid_from, presence: true
  validate :period_is_coherent
  validate :period_does_not_overlap

  scope :ordered, -> { order(valid_from: :desc) }

  class << self
    # A vigente numa data. Devolve o par `[diária, fixa]` já em Float, pronto
    # para o calculador — que não conhece `ActiveRecord`.
    #
    # Sem linha vigente, devolve `nil` e o calculador cai nas alíquotas de
    # origem. É deliberado: um borderô **não pode deixar de ser calculável**
    # porque o seed não rodou.
    def effective_on(date = Date.current)
      registro = effective_record_on(date)
      return nil if registro.nil?

      [registro.daily_rate.to_f, registro.fixed_rate.to_f]
    end

    def effective_record_on(date = Date.current)
      data = date.respond_to?(:to_date) ? date.to_date : Date.parse(date.to_s)
      where(valid_from: ..data)
        .where('valid_to IS NULL OR valid_to >= ?', data)
        .order(valid_from: :desc)
        .first
    rescue Date::Error, TypeError
      nil
    end
  end

  private

  def period_is_coherent
    return if valid_to.blank? || valid_from.blank?
    return if valid_to >= valid_from

    errors.add(:valid_to, 'não pode ser anterior ao início da vigência')
  end

  # Duas alíquotas vigentes na mesma data dariam dois resultados para o mesmo
  # borderô conforme a ordem da consulta. É o tipo de ambiguidade que só
  # aparece depois, no número.
  def period_does_not_overlap
    return if valid_from.blank?

    conflito = self.class.where.not(id: id)
                   .where('valid_from <= :fim AND (valid_to IS NULL OR valid_to >= :inicio)',
                          inicio: valid_from, fim: valid_to || Date.new(9999, 12, 31))
    return unless conflito.exists?

    errors.add(:base, 'Já existe uma alíquota de IOF vigente neste período.')
  end
end
