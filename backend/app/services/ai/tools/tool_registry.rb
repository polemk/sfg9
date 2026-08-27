# frozen_string_literal: true

# Central registry for AI tool/function calling definitions.
# Tools are grouped into CAPABILITIES that can be enabled per-agent via
# agent_config (e.g. ['assets']).
#
# @example
#   Ai::Tools::ToolRegistry.definitions_for('anthropic', ['assets'])
module Ai
  module Tools
    class ToolRegistry
      # ESTADO APÓS O TRIM (Phase 1b): **nenhuma capability registrada.**
      #
      # - `lead_capture` (`capture_lead` + `redirect_to_dashboard`) saiu no Bloco 6
      #   com o AI9-006: `capture_lead` gravava no `Lead`, e `redirect_to_dashboard`
      #   só existia como passo seguinte dela ("após capturar nome+email").
      # - `assets` (`search_operation_assets` + `list_all_operation_assets`) saiu no
      #   Bloco 7 com o AI9-014: as duas liam `OperationAsset` por embedding.
      #
      # O que FICA, de propósito, é a máquina de formatação por provider
      # (`format_specs`: `input_schema` do Anthropic, `type: function` da OpenAI,
      # `functionDeclarations` do Google). É o núcleo multi-provider do AI9-007 que
      # o DEC-13.2 manda manter, e o ponto de extensão do assistente interno.
      CAPABILITY_TOOLS = {}.freeze

      # Returns tool definitions formatted for the given provider, for the enabled capabilities.
      # @param provider_name [String] 'anthropic', 'openai', or 'google'
      # @param capabilities [Array<String>] enabled capability names
      # @return [Array<Hash>] tool definitions in provider-specific format
      def self.definitions_for(provider_name, capabilities = [])
        specs = Array(capabilities).map(&:to_s).uniq.flat_map { |cap| CAPABILITY_TOOLS[cap] || [] }
        return [] if specs.empty?

        format_specs(provider_name, specs)
      end

      # Formats neutral specs ({name, description, parameters}) for each provider's API.
      def self.format_specs(provider_name, specs)
        case provider_name.to_s
        when 'anthropic'
          specs.map { |s| { name: s[:name], description: s[:description], input_schema: s[:parameters] } }
        when 'openai'
          specs.map { |s| { type: 'function', function: { name: s[:name], description: s[:description], parameters: s[:parameters] } } }
        when 'google'
          [{ functionDeclarations: specs.map { |s| { name: s[:name], description: s[:description], parameters: s[:parameters] } } }]
        else
          []
        end
      end
    end
  end
end
