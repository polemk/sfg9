# frozen_string_literal: true

# S3 / BE-700..BE-706 — tipos de garantia.
#
# **DC-22 — a chave de integração é CONGELADA na criação.** Ela é derivada do
# título uma vez (no model) e só muda se o cliente mandar `integration_key`
# explicitamente. Renomear o título **não** a recalcula: é chave de
# **integração**, e recalculá-la em silêncio quebra consumidor externo sem
# nenhum erro aparecer — o pior modo de falha que existe (mesma leitura do
# DEC-85). No legado título e chave divergiam a partir da primeira edição.
#
# **DEC-86 — `is_provisional`.** O catálogo nasce semeado com tipos plausíveis
# marcados como provisórios, porque no legado o select de garantias sobe VAZIO
# (nenhum seed popula a tabela). O usuário com papel de escrita pode desmarcar,
# e a lista definitiva é do cliente.
class ProjectGuaranteeTypeService < CatalogService
  class << self
    def model = ::ProjectGuaranteeType
    def resource_label = 'Tipo de garantia'

    def writable_attributes
      %i[title integration_key is_active is_provisional sort_order description observation]
    end
  end
end
