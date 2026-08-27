class ChatSession < ApplicationRecord
  # Bloco 6 do trim (AI9-006): a sessão perdeu o `belongs_to :lead` e o
  # `garantir_lead!`. Abrir o chat nunca foi virar lead; agora nem falar é —
  # o assistente interno do console (DEC-13.2) não captura lead nenhum.
  # A coluna `chat_sessions.lead_id` saiu do schema junto (cumpre a 8.3).
  #
  # Bloco 8 (DEC-13.2): a sessão volta a ter DONO, agora o `User` autenticado do
  # console. Entre o Bloco 6 e o Bloco 8 ela ficou sem nenhum — e `session_id` é
  # inteiro sequencial vindo do parâmetro, então qualquer um lia a conversa de
  # qualquer um. Todo lookup passa a ser `user.chat_sessions.find_by(...)`.
  #
  # `optional: true` porque as sessões criadas ANTES desta coluna existirem têm
  # `user_id` nulo. Elas ficam órfãs e inalcançáveis pelo escopo do dono, que é
  # o comportamento certo: não há como adivinhar de quem eram.
  belongs_to :chat_flow
  belongs_to :user, optional: true
  has_many :flow_executions, dependent: :destroy

  def test?
    context&.fetch('is_test', false) == true
  end
end
