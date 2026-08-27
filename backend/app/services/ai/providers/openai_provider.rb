# frozen_string_literal: true

# OpenAI Chat Completions provider.
# Calls POST https://api.openai.com/v1/chat/completions
# Supports multimodal content (text + images) via Vision API.
# Supports tool/function calling (ver `Ai::Tools::ToolRegistry`).
# Bloco 8 do trim (AI9-007): a linha dizia "for AI lead generation" — a
# captura de lead saiu com o AI9-006 no Bloco 6 e o DEC-13.2 define o uso do
# que ficou: assistente de ajuda ao usuário INTERNO, dentro do console.
module Ai
  module Providers
    class OpenaiProvider < BaseProvider
      BASE_URL = 'https://api.openai.com'

      def chat_completion(system_prompt:, messages:, model:, **params)
        response = call_api(system_prompt: system_prompt, messages: messages, model: model, **params)
        response.dig('choices', 0, 'message', 'content') || ''
      end

      # Chat completion with tool/function calling support.
      # Returns structured response: { type: 'text', content: '...' }
      # or { type: 'tool_use', tool_calls: [{ id:, name:, arguments: }], text: '...' }
      # @param tools [Array<Hash>] OpenAI-formatted tool definitions
      # @return [Hash] structured response
      def chat_completion_with_tools(system_prompt:, messages:, model:, tools:, **params)
        response = call_api(system_prompt: system_prompt, messages: messages, model: model, tools: tools, **params)
        parse_tool_response(response)
      end

      private

      # Shared API call logic.
      def call_api(system_prompt:, messages:, model:, tools: nil, **params)
        conn = connection(BASE_URL, {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        })

        model_id = model || 'gpt-4o'
        model_id = 'gpt-4o-mini' if ['gpt-4.1-mini'].include?(model_id)

        body = {
          model: model_id,
          messages: build_messages(system_prompt, messages),
          temperature: params[:temperature] || 0.7,
          top_p: params[:top_p] || 1.0,
          max_tokens: params[:max_tokens] || 1024,
          presence_penalty: params[:presence_penalty] || 0,
          frequency_penalty: params[:frequency_penalty] || 0
        }.compact

        body[:tools] = tools if tools.present?

        response = conn.post('/v1/chat/completions', body)

        if response.success?
          response.body
        else
          Rails.logger.error("[OpenAI] API error #{response.status}: #{response.body}")
          raise "OpenAI API error: #{response.status} - #{response.body.dig('error', 'message') || response.body}"
        end
      end

      # Parse tool_use response from OpenAI.
      # OpenAI signals via finish_reason: 'tool_calls' and message.tool_calls array.
      def parse_tool_response(body)
        choice = body.dig('choices', 0) || {}
        message = choice['message'] || {}
        finish_reason = choice['finish_reason']

        if finish_reason == 'tool_calls' && message['tool_calls'].present?
          tool_calls = message['tool_calls'].map do |tc|
            {
              id: tc['id'],
              name: tc.dig('function', 'name'),
              arguments: parse_json_safe(tc.dig('function', 'arguments'))
            }
          end
          { type: 'tool_use', tool_calls: tool_calls, text: message['content'] }
        else
          { type: 'text', content: message['content'] || '' }
        end
      end

      # Safely parse JSON string arguments from tool calls.
      def parse_json_safe(json_str)
        return {} unless json_str.present?

        JSON.parse(json_str)
      rescue JSON::ParserError => e
        Rails.logger.warn("[OpenAI] Failed to parse tool arguments: #{e.message}")
        {}
      end

      # Builds messages array for the OpenAI API.
      # Supports multimodal, tool responses, and plain text.
      def build_messages(system_prompt, messages)
        result = []
        result << { role: 'system', content: system_prompt } if system_prompt.present?
        messages.each do |msg|
          role = msg[:role] || msg['role']
          content = msg[:content] || msg['content']
          image_data = msg[:image_data] || msg['image_data']
          tool_call_id = msg[:tool_call_id] || msg['tool_call_id']
          assistant_tool_calls = msg[:assistant_tool_calls] || msg['assistant_tool_calls']

          if assistant_tool_calls
            # Re-inject the assistant message that requested tool calls
            result << { role: 'assistant', content: content, tool_calls: assistant_tool_calls }
          elsif tool_call_id
            # Tool result message
            result << { role: 'tool', tool_call_id: tool_call_id, content: content.to_s }
          elsif image_data.present?
            mime = image_data[:mime_type] || image_data['mime_type']
            b64 = image_data[:base64] || image_data['base64']
            parts = [
              { type: 'image_url', image_url: { url: "data:#{mime};base64,#{b64}" } }
            ]
            parts << { type: 'text', text: content } if content.present?
            result << { role: role, content: parts }
          else
            result << { role: role, content: content }
          end
        end
        result
      end
    end
  end
end
