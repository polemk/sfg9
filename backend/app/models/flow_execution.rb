# frozen_string_literal: true

# Modelo para registrar cada passo executado em uma sessão de chat
# Usado para análise, debug e visualização do histórico de execução
class FlowExecution < ApplicationRecord
  belongs_to :chat_session
  belongs_to :chat_flow

  validates :node_id, presence: true
  validates :node_type, presence: true

  scope :ordered, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_session, ->(session_id) { where(chat_session_id: session_id) }
  scope :by_flow, ->(flow_id) { where(chat_flow_id: flow_id) }
  scope :by_type, ->(type) { where(node_type: type) }

  # Retorna um resumo do passo para exibição
  def summary
    case node_type
    when 'trigger'
      "Iniciou fluxo"
    when 'text', 'message'
      "Mensagem: #{truncate_content}"
    when 'question', 'input', 'option'
      input = input_data['user_input']
      "Pergunta respondida: #{input || '(aguardando)'}"
    when 'redirect'
      action = output_data['action']
      "Ação: #{action}"
    when 'condition'
      "Condição avaliada"
    when 'handoff'
      "Transferência de fluxo"
    else
      "Nó: #{node_type}"
    end
  end

  private

  def truncate_content
    content = output_data['content'] || ''
    content.length > 50 ? "#{content[0..47]}..." : content
  end
end
