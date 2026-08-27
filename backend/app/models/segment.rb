# frozen_string_literal: true

# S3 / BE-076, DB-064 — segmento de atuação. **Catálogo GLOBAL** (C1, regra 4).
#
# **A criação passa a funcionar** (D-21). No legado o model exigia
# `validates :user_id, presence: true` e o `SegmentsController` deixava
# `user_id` **fora do `permit`** — a criação falhava **100% das vezes**, em
# produção, desde 2021. Aqui o autor vem da SESSÃO (`SegmentService.create`) e
# é informativo: um seed ou um ETL grava sem autor, e isso não reprova o
# registro.
class Segment < ApplicationRecord
  include GlobalCatalog

  # Autor do cadastro. `optional` de propósito — ver o cabeçalho.
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }

  # Projeto vinculado bloqueia a exclusão (D-24). `projects.segment_id` nasce na
  # S0 como FK lógica e ganha a constraint real na S4 — a regra já vale aqui.
  def self.blocking_dependents
    { 'Project' => { foreign_key: :segment_id, label: 'projeto(s)' } }
  end

  # Ordenação dirigida pelo cliente (BE-075): título **e** chave. Chave
  # desconhecida é ignorada, nunca 500 — ver `Sfg::Sortable`.
  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze
end
