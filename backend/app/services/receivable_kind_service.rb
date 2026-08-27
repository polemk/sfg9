# frozen_string_literal: true

# S6 / **BE-185** — tipos de recebível. Catálogo GLOBAL.
#
# **A criação passa a responder 422 quando falha.** No legado
# `receivable_kinds_controller#create` respondia **200** com o registro não
# gravado: a tela dizia "cadastrado" e nada tinha sido cadastrado.
class ReceivableKindService < CatalogService
  class << self
    def model = ::ReceivableKind
    def resource_label = 'Tipo de recebível'
  end
end
