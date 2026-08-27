# frozen_string_literal: true

# Bloco 8 do trim (AI9-007, DEC-13.2): a sessão do assistente ganha DONO.
#
# Até aqui `chat_sessions` tinha `chat_flow_id`, `current_step_id` e `context` —
# e mais nada. O dono era o `lead` (`chat_sessions.lead_id`), que saiu com o
# AI9-006 no Bloco 6 e não foi substituído: qualquer um que passasse um
# `session_id` inteiro em `/chat/input` continuava a conversa de outra pessoa.
#
# O DEC-13.2 define o chatbot como assistente do usuário INTERNO, dentro do
# console — e assistente interno sem dono de conversa é a feature errada. O
# `User` autenticado é o dono que o lead nunca teve.
#
# `null: true` de propósito: as sessões que já existem no banco são anteriores ao
# dono. Elas ficam órfãs e invisíveis (o escopo é sempre `user.chat_sessions`),
# que é exatamente o comportamento desejado — não há como adivinhar de quem eram.
#
# Isto NÃO contraria o DEC-20: o que o DEC-20 descartou foi a tabela de
# MENSAGENS. A dona da sessão é uma coluna numa tabela que já existe, e é o
# mínimo para o isolamento existir.
# `type: :uuid` é obrigatório: `users.id` é `uuid` (`gen_random_uuid()`), não
# bigint. Sem isto o Postgres recusa a FK com `PG::DatatypeMismatch`.
class AddUserToChatSessions < ActiveRecord::Migration[8.0]
  def change
    add_reference :chat_sessions, :user, type: :uuid, null: true, index: true, foreign_key: true
  end
end
