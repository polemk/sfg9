# frozen_string_literal: true

# Dispatches tool calls from AI providers to their handlers.
#
# HISTÓRICO — o despachante ficou sem NENHUMA tool entre o trim e esta mudança:
#
# - `capture_lead` / `redirect_to_dashboard` (capability `lead_capture`) —
#   AI9-006, removidas no Bloco 6. Gravavam no `Lead` via `Leads::UpsertFromChat`.
# - `search_operation_assets` / `list_all_operation_assets` (capability `assets`) —
#   AI9-014, removidas no Bloco 7. Faziam busca semântica (`pgvector`) sobre
#   `OperationAsset`.
#
# O motor multi-provider com tool calling é o núcleo do AI9-007, que o DEC-13.2
# manda manter, e este arquivo foi deixado como ponto de extensão do assistente
# interno. As seis ferramentas abaixo são esse uso.
#
# ## O escopo é resolvido AQUI, uma vez, e não dentro de cada handler
#
# A ferramenta roda depois do controller: não existe `current_user` nem
# `current_project!` à mão. `ConsoleScope` refaz as três perguntas (dono da
# sessão, projeto revalidado contra `memberships`, papel na matriz DEC-18) e é
# ela que cada handler consulta antes de ler qualquer coisa.
#
# Um handler que esqueça o portão é um vazamento — por isso o portão é a
# PRIMEIRA linha de todos eles, e há spec cobrindo cada ferramenta com uma
# sessão sem dono e com um usuário sem participação no projeto.
module Ai
  module Tools
    class ToolExecutor
      # Execute a tool call by name with the given arguments.
      # @param tool_name [String] the tool to execute
      # @param args [Hash] arguments extracted by the LLM
      # @param flow [ChatFlow] the current chat flow
      # @param session [ChatSession] the current chat session
      # @return [Hash] { success: Boolean, message: String }
      def self.execute(tool_name, args, flow: nil, session: nil)
        _ = flow

        # Sem sessão não há dono, e sem dono não há escopo. Acontece em teste e
        # em chamada mal formada; nos dois casos a resposta é a mesma recusa
        # estruturada, nunca uma exceção subindo pelo laço de tool calling.
        return { success: false, message: ConsoleScope::SEM_DONO } if session.nil?

        # O provider entrega os argumentos já como Hash, mas a chave vem string
        # no Anthropic e no Google e símbolo em alguns caminhos da OpenAI.
        argumentos = (args || {}).to_h.with_indifferent_access
        scope = ConsoleScope.new(session)

        case tool_name.to_s
        when 'search_faq'               then Handlers::ConsoleHelp.search_faq(argumentos, scope)
        when 'read_faq_item'            then Handlers::ConsoleHelp.read_faq_item(argumentos, scope)
        when 'field_help'               then Handlers::ConsoleHelp.field_help(argumentos, scope)
        when 'project_snapshot'         then Handlers::ConsoleData.project_snapshot(argumentos, scope)
        when 'overdue_renegotiations'   then Handlers::ConsoleData.overdue_renegotiations(argumentos, scope)
        when 'volume_by_carrier'        then Handlers::ConsoleData.volume_by_carrier(argumentos, scope)
        else
          Rails.logger.warn("[ToolExecutor] Unknown tool: #{tool_name}")
          { success: false, message: "Unknown tool: #{tool_name}" }
        end
      rescue StandardError => e
        # Falha de leitura não pode derrubar o turno: o laço de tool calling
        # espera `{ success:, message: }` e continua a conversa com a recusa.
        # O detalhe fica no log — mandá-lo ao modelo colocaria nome de classe e
        # de coluna numa bolha de chat.
        Rails.logger.error("[ToolExecutor] #{tool_name} falhou: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        { success: false, message: 'Não consegui consultar esse dado agora.' }
      end
    end
  end
end
