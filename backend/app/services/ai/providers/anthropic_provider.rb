# frozen_string_literal: true

# Anthropic Messages API provider.
# Calls POST https://api.anthropic.com/v1/messages
# Supports multimodal content (text + images) via Vision API.
# Supports tool/function calling (ver `Ai::Tools::ToolRegistry`).
# Bloco 8 do trim (AI9-007): a linha dizia "for AI lead generation" — a
# captura de lead saiu com o AI9-006 no Bloco 6 e o DEC-13.2 define o uso do
# que ficou: assistente de ajuda ao usuário INTERNO, dentro do console.
module Ai
  module Providers
    class AnthropicProvider < BaseProvider
      BASE_URL = 'https://api.anthropic.com'

      def chat_completion(system_prompt:, messages:, model:, **params)
        response = call_api(system_prompt: system_prompt, messages: messages, model: model, **params)
        extract_text(response)
      end

      # Chat completion with tool/function calling support.
      # Returns structured response: { type: 'text', content: '...' }
      # or { type: 'tool_use', tool_calls: [{ id:, name:, arguments: }], text: '...' }
      # @param tools [Array<Hash>] Anthropic-formatted tool definitions
      # @return [Hash] structured response
      def chat_completion_with_tools(system_prompt:, messages:, model:, tools:, **params)
        response = call_api(system_prompt: system_prompt, messages: messages, model: model, tools: tools, **params)
        parse_tool_response(response)
      end

      private

      # -----------------------------------------------------------------------
      # Bloco 8 do trim (AI9-007) — o catálogo de modelos estava MORTO.
      #
      # Conferido EXECUTANDO contra `GET /v1/models` com a chave do `.env`:
      # `claude-3-5-sonnet-20241022` (o default deste arquivo, o do seed e a
      # primeira opção do seletor do flow builder) e `claude-3-haiku-20240307`
      # **não existem mais** — a API devolve `404 - model: ...`. O assistente
      # respondia "ocorreu um erro" em 100% dos turnos por causa disto, e nenhum
      # portão pegava: o `rspec` estuba o provider com WebMock.
      #
      # Não é resíduo de feature removida; é deriva de API. Corrigido aqui porque
      # sem isto o AI9-007 não responde ponta a ponta, que é o aceite do bloco.
      # -----------------------------------------------------------------------
      DEFAULT_MODEL = 'claude-opus-5'

      # Ids que a API não conhece mais. Reapontados em vez de propagados: um
      # agente gravado no banco com um destes continuaria quebrado para sempre.
      MODELOS_APOSENTADOS = %w[
        claude-3-5-sonnet-20241022
        claude-3-5-sonnet-20240620
        claude-3-haiku-20240307
        claude-3-opus-20240229
        claude-3-sonnet-20240229
        claude-4.6-opus
        claude-3-7-sonnet
      ].freeze

      # Famílias que rejeitam `temperature`/`top_p`/`top_k` com 400.
      SEM_AMOSTRAGEM = %w[
        claude-opus-5
        claude-sonnet-5
        claude-fable-5
        claude-mythos-5
        claude-opus-4-8
        claude-opus-4-7
      ].freeze

      def resolve_model(model)
        id = model.presence || DEFAULT_MODEL
        MODELOS_APOSENTADOS.include?(id) ? DEFAULT_MODEL : id
      end

      def sem_amostragem?(model_id)
        SEM_AMOSTRAGEM.any? { |m| model_id.to_s.start_with?(m) }
      end

      # Shared API call logic for both text-only and tool-enabled completions.
      def call_api(system_prompt:, messages:, model:, tools: nil, **params)
        conn = connection(BASE_URL, {
          'x-api-key' => api_key,
          'anthropic-version' => '2023-06-01',
          'Content-Type' => 'application/json'
        })

        model_id = resolve_model(model)

        body = {
          model: model_id,
          system: system_prompt.presence,
          messages: build_messages(messages),
          max_tokens: params[:max_tokens] || 1024
        }.compact

        # Modelos Anthropic mais novos (Sonnet 4.x+) REJEITAM temperature + top_p
        # juntos, e os da família 5 / 4.7+ rejeitam os DOIS (ver
        # `SEM_AMOSTRAGEM`). Manda no máximo um, e só quando o modelo aceita.
        unless sem_amostragem?(model_id)
          if params[:temperature]
            body[:temperature] = params[:temperature]
          elsif params[:top_p]
            body[:top_p] = params[:top_p]
          else
            body[:temperature] = 0.7
          end
        end

        body[:tools] = tools if tools.present?

        response = conn.post('/v1/messages', body)

        if response.success?
          response.body
        else
          Rails.logger.error("[Anthropic] API error #{response.status}: #{response.body}")
          raise "Anthropic API error: #{response.status} - #{response.body.dig('error', 'message') || response.body}"
        end
      end

      # Extract text content from a raw Anthropic response body.
      def extract_text(body)
        blocks = body['content'] || []
        blocks.filter_map { |b| b['text'] if b['type'] == 'text' }.join("\n")
      end

      # Parse tool_use response from Anthropic.
      # Anthropic signals tool use via stop_reason: 'tool_use'
      # and content blocks of type 'tool_use'.
      def parse_tool_response(body)
        stop_reason = body['stop_reason']
        blocks = body['content'] || []

        if stop_reason == 'tool_use'
          tool_calls = blocks.select { |b| b['type'] == 'tool_use' }.map do |block|
            { id: block['id'], name: block['name'], arguments: block['input'] || {} }
          end
          text = blocks.filter_map { |b| b['text'] if b['type'] == 'text' }.join("\n")
          { type: 'tool_use', tool_calls: tool_calls, text: text }
        else
          { type: 'text', content: extract_text(body) }
        end
      end

      # Builds messages array for the Anthropic API.
      # Supports multimodal, tool_result, and plain text messages.
      def build_messages(messages)
        messages.map do |msg|
          role = msg[:role] || msg['role']
          content = msg[:content] || msg['content']
          image_data = msg[:image_data] || msg['image_data']
          tool_result = msg[:tool_result] || msg['tool_result']

          if tool_result
            # Tool result message for the multi-hop loop
            {
              role: 'user',
              content: [{
                type: 'tool_result',
                tool_use_id: tool_result[:tool_use_id] || tool_result['tool_use_id'],
                content: tool_result[:content] || tool_result['content']
              }]
            }
          elsif image_data.present?
            blocks = [
              {
                type: 'image',
                source: {
                  type: 'base64',
                  media_type: image_data[:mime_type] || image_data['mime_type'],
                  data: image_data[:base64] || image_data['base64']
                }
              }
            ]
            blocks << { type: 'text', text: content } if content.present?
            { role: role, content: blocks }
          else
            { role: role, content: content }
          end
        end
      end
    end
  end
end
