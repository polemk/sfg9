# frozen_string_literal: true

# Telemetria por turno do agente de IA (GOAT v2 / S1.1).
#
# Append-only — gravado a partir de Ai::AgentService.respond a cada chamada de
# provider, fail-soft (S1.2). Base de evals (rake agent:eval, S1.5), do tuning
# de retrieval no S2 e do cutover do S7.
#
# Associações são `optional: true` porque:
# Telemetria sobrevive à exclusão dos pais (FK sem foreign_key na migration).
#
# NOTA DO TRIM (Blocos 6 e 7): as colunas `lead_id` (AI9-006) e `operation_id`
# (AI9-014) saíram com as features. Sobraram `chat_session_id` e `chat_flow_id`.
#
# Bloco 8: o `belongs_to :lead` tinha SOBREVIVIDO à remoção da coluna — apontava
# para um model que não existe mais e para uma coluna que saiu do `schema.rb`.
# Não quebrava no boot (a associação só resolve a constante quando acessada) e
# por isso passou pelo `zeitwerk:check` e pelo `rspec` inteiros. Removido aqui.
class AgentRun < ApplicationRecord
  STATUSES = %w[success error partial].freeze

  belongs_to :chat_session, optional: true
  belongs_to :chat_flow,    optional: true

  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :recent,        -> { order(created_at: :desc) }
  scope :by_provider,   ->(p) { where(provider: p) }
  scope :by_channel,    ->(c) { where(channel: c) }
  scope :failed,        -> { where(status: 'error') }
  scope :succeeded,     -> { where(status: 'success') }
  scope :slower_than,   ->(ms) { where('latency_ms > ?', ms) }
end
