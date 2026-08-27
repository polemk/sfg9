# frozen_string_literal: true

# S3 / BE-076 — segmentos.
#
# **Fecha o D-21.** No legado a criação de segmento falhava **100% das vezes**:
# `Segment` validava `user_id` presente e `segment_params` não o permitia. A
# feature estava quebrada em produção desde 2021 e ninguém conseguia cadastrar
# um segmento pela tela. Aqui o autor vem da SESSÃO e a criação funciona.
class SegmentService < CatalogService
  class << self
    def model = ::Segment
    def resource_label = 'Segmento'
  end
end
