# frozen_string_literal: true

# **DONA: S8** (`DB-287`, `DB-562`, `BE-308`, `BE-725`…`BE-729`, Q-R19).
#
# O model nasce na S6 pelo mesmo motivo da tabela: `ReceivableEntry` exige
# `resource_source_id` (`../sfg/app/models/receivable_entry.rb:16`) e a coluna
# está preenchida em **28.131 de 28.131** linhas de produção — sem o catálogo,
# o formulário de borderô não abre e a fatia inteira fica sem tela. Mesmo
# precedente da S5, que criou `risk_operations` (da S7) por dependência de FK.
#
# **S8: o que é seu e ainda não está aqui** — endpoints, painel lateral, a
# decisão de `is_active` (Q-R19: continua **sem** filtrar) e o conteúdo final do
# seed (`DB-293`). O seed atual reproduz as **6 linhas de produção**, medidas no
# dump; o mapa da S8 previa 7 com outros nomes (Caixa, Comissária, Defasagem,
# Fomento, Garantia, Recompra, Retenção) e produção tem Caixa, Garantia,
# Comissaria, Fomento, Recompra e **13º salário**. A divergência está no
# relatório da S6.
class ResourceSource < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }

  def self.blocking_dependents
    { 'ReceivableEntry' => { foreign_key: :resource_source_id, label: 'borderô(s)' } }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze
end
