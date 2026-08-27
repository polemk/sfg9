# frozen_string_literal: true

# S5 / BE-269, DB-231, DB-573 — **posição diária de risco**.
#
# **DEC-57: tabela e model, SEM service, SEM endpoint e SEM tela.** O dado
# sobrevive; a superfície não volta. É o que o legado faz hoje — não existe
# nenhuma view de `risk_entries`, o controller aponta para templates inexistentes
# (500 em toda chamada) e a aba do console está comentada.
#
# **O agravante que impede portar a tela mesmo se quiséssemos:** os 15 campos de
# valor são hardcode dos **4 tipos originais** e não acompanham o
# `RiskOperationType` dinâmico que existe desde 2022. Remodelá-los por tipo é
# feature nova.
#
# ### Os cinco totais são DERIVADOS e sobrepõem o que vier
#
# `before_validation` recalcula os cinco a cada save
# (`../sfg/app/models/risk_entry.rb:33-37`), ignorando qualquer valor enviado. É
# o que impede a linha de guardar um total que não bate com as parcelas dele.
#
# ### O `after_initialize` do legado NÃO é portado
#
# Lá havia um `after_initialize` que fazia `self.company.project_id` em **toda**
# instanciação (`:25-27`) — inclusive em `RiskEntry.new` sem empresa, o que
# levanta `NoMethodError`, e inclusive ao carregar linhas do banco, o que dispara
# uma consulta por linha. O `before_validation` já garante o mesmo invariante no
# único momento em que ele importa. Registrado como divergência consciente.
class RiskEntry < ApplicationRecord
  include SafegoldStamped
  safegold_stamp_source :company

  include ProjectScoped

  belongs_to :company
  belongs_to :risk_control

  # **DEC-129.2 — a abertura por modalidade de 2022 tem de sobreviver à carga.**
  #
  # Medido no dump de 31/05/2025: **4.082 linhas** (161 limites, 19 projetos,
  # **R$ 4.884.851.467,94**), de 28/01/2022 a 14/04/2022, guardam um total
  # **não-zero** com as duas parcelas correspondentes **zeradas**. Palavras do
  # usuário: *"manter como é no legado"*.
  #
  # Sem esta chave o `before_validation` abaixo recalcularia zero por cima do
  # valor que o ETL copiou da origem — a contagem continuaria 4.082/4.082 e o
  # **detalhe sumiria em silêncio**, que é o modo de falha mais caro desta
  # migração. Só o ETL a liga, e a liga **por linha**.
  attr_accessor :preserve_legacy_totals

  before_validation :derive_scope_and_totals

  validates :date, presence: true
  validates :company_id, presence: true
  validates :risk_control_id, presence: true
  validates :date, uniqueness: {
    scope: %i[risk_control_id company_id],
    message: 'já tem posição lançada para este limite e esta empresa'
  }

  # As dez parcelas são obrigatórias; os cinco totais são derivados delas.
  VALUE_FIELDS = %i[
    vencidos_value a_vencer_value liquidacao_value descontos_value
    comissaria_vencidos_value comissaria_a_vencer_value
    fomento_vencidos_value fomento_a_vencer_value
    intercompany_vencidos_value intercompany_a_vencer_value
  ].freeze

  validates(*VALUE_FIELDS, presence: true, numericality: true)

  private


  def derive_scope_and_totals
    self.project_id = company.project_id if company_id.present? && company
    self.risk_control_title = risk_control.title if risk_control_id.present? && risk_control

    # DEC-129.2 — na carga, o total copiado da origem vence a derivação. Só os
    # TOTAIS: o escopo acima continua sendo derivado, porque ele é invariante de
    # integridade e não dado do cliente. Ver `attr_accessor
    # :preserve_legacy_totals` no topo.
    return if preserve_legacy_totals

    self.total_carteira_value = zero(vencidos_value) + zero(a_vencer_value)
    self.total_reducoes_value = zero(liquidacao_value) + zero(descontos_value)
    self.comissaria_total_value = zero(comissaria_vencidos_value) + zero(comissaria_a_vencer_value)
    self.fomento_total_value = zero(fomento_vencidos_value) + zero(fomento_a_vencer_value)
    self.intercompany_total_value = zero(intercompany_vencidos_value) + zero(intercompany_a_vencer_value)
  end

  def zero(value)
    value || 0
  end
end
