# frozen_string_literal: true

# S6 / **BE-185** — carteiras. Catálogo GLOBAL, sobre o molde `CatalogService`
# da S3 (mesma paginação, mesma busca, mesmo formato de erro nos cinco+três
# catálogos do sistema).
#
# `is_active` **continua sem filtrar** (Q-B12): a coluna existe, tem tela e
# nenhuma consulta a lê — nem no legado. Passar a filtrar faria carteira
# desativada sumir do select do borderô.
class WalletService < CatalogService
  class << self
    def model = ::Wallet
    def resource_label = 'Carteira'
    def resource_genero = :feminino
  end
end
