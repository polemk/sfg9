# frozen_string_literal: true

# Dispatches tool calls from AI providers to their handlers.
#
# ESTADO APÓS O TRIM (Phase 1b): **nenhuma tool registrada.** As duas famílias
# que existiam saíram com as features a que pertenciam:
#
# - `capture_lead` / `redirect_to_dashboard` (capability `lead_capture`) —
#   AI9-006, removidas no Bloco 6. Gravavam no `Lead` via `Leads::UpsertFromChat`.
# - `search_operation_assets` / `list_all_operation_assets` (capability `assets`) —
#   AI9-014, removidas no Bloco 7. Faziam busca semântica (`pgvector`) sobre
#   `OperationAsset`, dentro da `Operation` do fluxo.
#
# O DESPACHANTE FICA de propósito: o motor multi-provider com tool calling é o
# núcleo do AI9-007, que o DEC-13.2 manda manter. Este arquivo e o
# `ToolRegistry` são o ponto de extensão para as ferramentas do assistente
# interno — registrar uma nova é acrescentar o `when` aqui e a spec lá.
module Ai
  module Tools
    class ToolExecutor
      # Execute a tool call by name with the given arguments.
      # @param tool_name [String] the tool to execute
      # @param args [Hash] arguments extracted by the LLM
      # @param flow [ChatFlow] the current chat flow
      # @param session [ChatSession] the current chat session
      # @return [Hash] { success: Boolean, message: String }
      def self.execute(tool_name, _args, flow: nil, session: nil)
        _ = [flow, session]

        Rails.logger.warn("[ToolExecutor] Unknown tool: #{tool_name}")
        { success: false, message: "Unknown tool: #{tool_name}" }
      end
    end
  end
end
