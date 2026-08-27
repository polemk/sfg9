# frozen_string_literal: true

# S12 / DB-331, BE-333, BE-347, OPS-333 — **a prova de que uma pessoa aceitou um
# texto** (DEC-80).
#
# No legado esta tabela guardava `user_id`, `contract_id` e as duas datas do
# `timestamps`. Nada mais. Era o D-65: prova de que existiu um aceite, sem prova
# do que foi aceito.
#
# **Não entra no `paper_trail`** — está em `Sfg::AuditTrail::EXCLUDED` com o
# motivo: o aceite tem prova própria, no próprio registro. Versioná-lo criaria
# duas fontes para o mesmo fato, e a pergunta "qual vale no tribunal" não tem
# resposta boa.
class ContractDeal < ApplicationRecord
  SOURCE_EXPLICIT = 'explicit'
  SOURCE_IMPLICIT_LEGACY = 'implicit_legacy'
  SOURCES = [SOURCE_EXPLICIT, SOURCE_IMPLICIT_LEGACY].freeze

  belongs_to :user
  belongs_to :contract, inverse_of: :contract_deals

  validates :accepted_at, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :contract_kind, presence: true
  validates :contract_version, presence: true
  # A unicidade real é o índice `(user_id, contract_id)`; a validação existe
  # para devolver mensagem em vez de `RecordNotUnique`. No legado só havia a
  # validação, e dois cliques gravavam duas linhas.
  validates :contract_id, uniqueness: { scope: :user_id, message: 'já foi aceito por este usuário' }

  # DEC-66: o aceite carimbado pela base antiga **não conta** como consentimento.
  # É o que faz o novo aceite ser exigido na próxima entrada sem descartar o
  # histórico nem fingir que ele vale.
  scope :explicit, -> { where(source: SOURCE_EXPLICIT) }
  scope :implicit_legacy, -> { where(source: SOURCE_IMPLICIT_LEGACY) }
  scope :for_user, ->(user) { where(user_id: user.respond_to?(:id) ? user.id : user) }

  def explicit?
    source == SOURCE_EXPLICIT
  end

  def implicit_legacy?
    source == SOURCE_IMPLICIT_LEGACY
  end

  # O texto guardado ainda bate com o texto que está no ar? `false` significa
  # que o contrato foi editado depois deste aceite — e é aí que `accepted_body`
  # deixa de ser redundância e vira a única fonte do que a pessoa leu.
  def hash_matches_current?
    return false if content_hash.blank?

    content_hash == contract&.content_hash
  end
end
