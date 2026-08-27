# frozen_string_literal: true

# S3 / BE-074, OPS-058 — grupo de portadores. **Catálogo GLOBAL** (C1, regra 4).
#
# **`carriers_count` é `counter_cache`, e é ele que decide o botão.** No legado
# a coluna existia, divergia da lista, e era ela que a view consultava para
# mostrar (ou esconder) o botão de exclusão. O botão sumia e a exclusão passava
# assim mesmo, deixando `group_id` órfão. Agora o critério do botão **é** o
# critério do servidor: grupo com portador responde 422 (BE-073), e o front
# reflete a resposta real.
#
# Título **não** é único: o legado não o exige, e este catálogo herda a mesma
# política do portador (ver `Carrier`).
class CarrierGroup < ApplicationRecord
  include GlobalCatalog

  has_many :carriers, foreign_key: :group_id, inverse_of: :group, dependent: :restrict_with_error
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  def self.blocking_dependents
    { 'Carrier' => { foreign_key: :group_id, label: 'portador(es)' } }
  end

  # Ordenar por título respondia **500** no legado: `CarrierGroup` não define
  # `prepare_ordering`, e a chamada do controller levantava `NoMethodError`
  # (D-21). Aqui a allowlist é dado, e chave desconhecida é ignorada.
  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => :title, 'key' => :integration_key,
      'carriers_count' => :carriers_count, 'created_at' => :created_at
    },
    default: { title: :asc }
  ).freeze
end
