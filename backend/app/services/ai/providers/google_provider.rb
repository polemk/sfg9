# frozen_string_literal: true

# Google Gemini API provider.
# Calls POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
# Supports multimodal content (text + images) via Vision API.
# Supports tool/function calling (ver `Ai::Tools::ToolRegistry`).
# Bloco 8 do trim (AI9-007): a linha dizia "for AI lead generation" — a
# captura de lead saiu com o AI9-006 no Bloco 6 e o DEC-13.2 define o uso do
# que ficou: assistente de ajuda ao usuário INTERNO, dentro do console.
module Ai
  module Providers
    class GoogleProvider < BaseProvider
      BASE_URL = 'https://generativelanguage.googleapis.com'

      def chat_completion(system_prompt:, messages:, model:, **params)
        response = call_api(system_prompt: system_prompt, messages: messages, model: model, **params)
        extract_text(response)
      end

      # Chat completion with tool/function calling support.
      # Returns structured response: { type: 'text', content: '...' }
      # or { type: 'tool_use', tool_calls: [{ id:, name:, arguments: }], text: '...' }
      # @param tools [Array<Hash>] Gemini-formatted tool definitions
      # @return [Hash] structured response
      def chat_completion_with_tools(system_prompt:, messages:, model:, tools:, **params)
        response = call_api(system_prompt: system_prompt, messages: messages, model: model, tools: tools, **params)
        parse_tool_response(response)
      end

      private

      # Shared API call logic.
      def call_api(system_prompt:, messages:, model:, tools: nil, **params)
        model_id = model || 'gemini-2.0-flash'
        model_id = 'gemini-2.0-flash' if ['antigravity', 'gemini-3.0', 'gemini-2.5-pro'].include?(model_id)

        conn = connection(BASE_URL, { 'Content-Type' => 'application/json' })

        body = {
          contents: build_contents(messages),
          generationConfig: {
            temperature: params[:temperature] || 0.7,
            topP: params[:top_p] || 1.0,
            maxOutputTokens: params[:max_tokens] || 1024
          }.compact
        }

        if system_prompt.present?
          body[:systemInstruction] = { parts: [{ text: system_prompt }] }
        end

        body[:tools] = tools if tools.present?

        response = conn.post(
          "/v1beta/models/#{model_id}:generateContent?key=#{api_key}",
          body
        )

        if response.success?
          response.body
        else
          Rails.logger.error("[Google] API error #{response.status}: #{response.body}")
          raise "Google API error: #{response.status} - #{response.body.dig('error', 'message') || response.body}"
        end
      end

      # Extract text content from Gemini response.
      def extract_text(body)
        candidates = body.dig('candidates') || []
        parts = candidates.dig(0, 'content', 'parts') || []
        parts.filter_map { |p| p['text'] }.join("\n")
      end

      # Parse tool_use response from Gemini.
      # Gemini signals via candidates[0].content.parts[].functionCall
      def parse_tool_response(body)
        candidates = body.dig('candidates') || []
        parts = candidates.dig(0, 'content', 'parts') || []

        function_calls = parts.select { |p| p['functionCall'] }

        if function_calls.any?
          tool_calls = function_calls.map do |fc|
            call_data = fc['functionCall']
            { id: SecureRandom.uuid, name: call_data['name'], arguments: call_data['args'] || {} }
          end
          text = parts.filter_map { |p| p['text'] }.join("\n")
          { type: 'tool_use', tool_calls: tool_calls, text: text }
        else
          { type: 'text', content: extract_text(body) }
        end
      end

      # Builds contents array for the Gemini API.
      # Supports multimodal, function responses, and plain text.
      def build_contents(messages)
        messages.map do |msg|
          role = (msg[:role] || msg['role']) == 'assistant' ? 'model' : 'user'
          content = msg[:content] || msg['content']
          image_data = msg[:image_data] || msg['image_data']
          function_response = msg[:function_response] || msg['function_response']
          model_function_call = msg[:model_function_call] || msg['model_function_call']

          parts = []

          if model_function_call
            # Re-inject the model's function call for context
            parts << { functionCall: model_function_call }
            { role: 'model', parts: parts }
          elsif function_response
            # Function response message
            parts << {
              functionResponse: {
                name: function_response[:name] || function_response['name'],
                response: function_response[:response] || function_response['response']
              }
            }
            { role: 'user', parts: parts }
          else
            if image_data.present?
              mime = image_data[:mime_type] || image_data['mime_type']
              b64 = image_data[:base64] || image_data['base64']
              parts << { inlineData: { mimeType: mime, data: b64 } }
            end
            parts << { text: content } if content.present?
            { role: role, parts: parts }
          end
        end
      end
    end
  end
end
