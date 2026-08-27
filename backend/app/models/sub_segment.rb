# frozen_string_literal: true

# S3 / BE-077, DB-066 — subsegmento de atuação. **Catálogo GLOBAL** (C1, regra 4).
#
# **DC-13: não há associação com `Segment`.** Apesar do nome, o legado nunca
# ligou os dois — são duas listas planas, e `projects` aponta para cada uma por
# uma coluna própria. Criar a hierarquia agora exigiria inventar o mapeamento
# dos dados existentes.
#
# **A ordenação é resolvida pelo PRÓPRIO subsegmento** (BE-077). No legado
# `SubSegment.prepare_ordering` chamava `Segment.get_ordering_key` e
# `Segment.get_ordering_style` — copiar-e-colar que acoplava os dois catálogos
# por acidente: mudar a allowlist de segmentos mudava a de subsegmentos.
class SubSegment < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }

  def self.blocking_dependents
    { 'Project' => { foreign_key: :sub_segment_id, label: 'projeto(s)' } }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze
end
