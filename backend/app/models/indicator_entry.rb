# frozen_string_literal: true

# S10 / BE-329, BE-716, DB-311 — **o lançamento mensal**.
#
# A identidade de um lançamento é **(projeto, indicador, ano, mês)** e a
# periodicidade é **sempre mensal**: não há diário, semanal nem trimestral em
# lugar nenhum do legado. `year` e `month` são inteiros soltos, não uma `date`
# (BE-329 / Q-R30) — preservar isso mantém a chave de unicidade e o payload da
# API exatamente como estão.
#
# ## Não há fuso horário neste módulo. Medido, não suposto.
#
# O bucket do mês **não é derivado de nenhum timestamp**: o usuário digita o
# valor numa célula que já sabe o seu mês e o seu ano
# (`../sfg/app/views/pub/console/parts/indicator_entries/list/_widget.html.erb:21-22`,
# campos escondidos `month` e `year`), e as quatro consultas do legado
# (`project.rb:424-441`) filtram por `where(month:, year:)` — inteiros, nunca
# `created_at`. A conversão UTC-2/UTC-3 que a S14 mediu no ETL **não alcança esta
# tabela**: não há virada de mês a errar aqui. O que viaja no ETL são os próprios
# inteiros.
#
# ## Zero é válido; ausência não é zero
#
# `value` tem `presence` **e** default 0: gravar `0` é um lançamento legítimo, e
# `nil` é recusado. O que muda em relação ao legado é a LEITURA: a grade passa a
# distinguir "não lançado" (não existe linha) de "lançado como zero" (**DEC-70**).
# Hoje a view instancia um `IndicatorEntry.new` para o mês vazio e renderiza `0`,
# indistinguível de um lançamento real de zero. A distinção nasce no serviço
# (`Indicators::EntryService#grid`), nunca numa heurística do componente.
#
# **Negativos são aceitos** — replicado. A máscara do legado permite o sinal na
# primeira posição e a view pinta a célula de vermelho quando `< 0`.
class IndicatorEntry < ApplicationRecord
  include ProjectScoped
  # **Sem `Auditable`, de propósito**: `IndicatorEntry` está em
  # `Sfg::AuditTrail::EXCLUDED` por volume de escrita (DEC-78 #1) — é a tabela em
  # que o usuário grava célula a célula. Quem carrega a trilha deste módulo é o
  # `Indicator`, e é lá que está escrito o porquê.

  # Ranges com extremos imutáveis já nascem congelados no Ruby 3 — sem `.freeze`.
  MONTHS = (1..12)
  YEARS = (1900..2999)

  belongs_to :indicator
  # Quem lançou e quem alterou por último (Q-R28). No legado era **uma** coluna,
  # `user_id`, que vinha do formulário e estava no `permit` — dava para registrar
  # lançamento em nome de outro usuário forjando o campo escondido. Aqui as duas
  # vêm da sessão e são `optional`: um seed ou o ETL grava sem autor, e isso não
  # pode reprovar o registro.
  belongs_to :creator, class_name: 'User', foreign_key: :created_by, optional: true, inverse_of: false
  belongs_to :updater, class_name: 'User', foreign_key: :updated_by, optional: true, inverse_of: false

  validates :year, presence: true, inclusion: { in: YEARS, message: 'fora da faixa aceita (1900 a 2999)' }
  validates :month, presence: true, inclusion: { in: MONTHS, message: 'precisa estar entre 1 e 12' }
  # `presence` num decimal com default 0 recusa `nil` e aceita `0` — que é
  # exatamente o contrato: zero é um lançamento, ausência não é.
  validates :value, presence: true, numericality: true
  validates :title, presence: true
  validates :value_type, presence: true
  # `key` NÃO tem `presence`, como no legado (`indicator_entry.rb:8-15` valida
  # title e value_type, não key).

  validates :month, uniqueness: { scope: %i[year project_id indicator_id],
                                  message: 'já tem lançamento para este indicador neste período' }

  before_validation :copy_denormalized_fields_from_indicator

  scope :on_period, ->(year:, month: nil) { month.present? ? where(year: year, month: month) : where(year: year) }
  scope :for_indicator, ->(indicator) { where(indicator_id: indicator.respond_to?(:id) ? indicator.id : indicator) }

  # **G4** — reescreve a foto denormalizada de TODAS as entries de um indicador.
  #
  # `update_all` de propósito: pula validações e callbacks e **não** toca
  # `updated_at`, exatamente como `../sfg/app/models/indicator.rb:48-50`. Trocar
  # por `find_each(&:save)` mudaria `updated_at` de milhares de linhas e faria a
  # trilha de auditoria explodir sem nenhum fato novo.
  def self.propagate_from(indicator)
    for_indicator(indicator).update_all(
      title: indicator.title,
      key: indicator.key,
      value_type: indicator.value_type
    )
  end

  # `../sfg/app/models/indicator_entry.rb:29-39`. Entrada sem id devolve `"N/A"`
  # — o legado escreveu este método e nunca o chamou na grade, que renderizava
  # `entry.value.blank? ? 0 : entry.value` e por isso não distinguia nada.
  #
  # ⚠ **Isto NÃO é o caminho de exibição do produto.** A entity manda o decimal
  # cru e quem formata é o cliente, com a moeda de `lib/config/currency.ts`. O
  # `R$` aqui é a réplica literal do `to_currency(Currency::BRL)` do legado
  # (DEC-30), preservada porque o método é comportamento do domínio — não a
  # segunda implementação de "como o app escreve dinheiro". Se um dia a moeda do
  # produto mudar, é o cliente que muda; este método continua contando o que o
  # legado fazia.
  def beauty_value
    return 'N/A' if id.blank?
    return format_brl(value) if value_type == Indicator::VALUE_TYPE_MONEY

    value
  end

  # Data fictícia só para formatar mês/ano. Só é chamada com `month`/`year`
  # já validados — no legado ela era o ponto onde mês 13 explodia.
  def entry_pseudo_date
    Date.new(year, month)
  end

  private

  def format_brl(amount)
    ActiveSupport::NumberHelper.number_to_currency(amount, unit: 'R$', separator: ',', delimiter: '.')
  end

  # A foto do indicador no momento. Sem indicador não há o que copiar — e o
  # `belongs_to` já reprova com 422; no legado `self.indicator.title` levantava
  # `NoMethodError` **antes** da validação, e `indicator_id` nulo virava 500.
  def copy_denormalized_fields_from_indicator
    return if indicator.nil?

    self.title = indicator.title
    self.key = indicator.key
    self.value_type = indicator.value_type
  end
end
