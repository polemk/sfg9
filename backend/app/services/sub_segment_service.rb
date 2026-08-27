# frozen_string_literal: true

# S3 / BE-077, BE-078 — subsegmentos.
#
# Catálogo INDEPENDENTE de `segments` (DC-13) — inclusive na ordenação, que no
# legado era resolvida por `Segment.get_ordering_key` dentro do
# `SubSegment.prepare_ordering`.
class SubSegmentService < CatalogService
  class << self
    def model = ::SubSegment
    def resource_label = 'Subsegmento'
  end
end
