# frozen_string_literal: true

# S3 / BE-072, BE-073, BE-074 — grupos de portadores.
#
# **Fecha o D-21** (ordenar por título respondia 500, porque `CarrierGroup` não
# define `prepare_ordering`) e o **D-24** (grupo com portadores respondia `:ok`
# sem excluir; agora é 422 de verdade, e o `group_id` dos portadores permanece —
# nada de órfão).
class CarrierGroupService < CatalogService
  class << self
    def model = ::CarrierGroup
    def resource_label = 'Grupo de portadores'
  end
end
