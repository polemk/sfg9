# frozen_string_literal: true

# Base class for AI provider integrations.
# All providers must implement #chat_completion and return a String response.
module Ai
  module Providers
    class BaseProvider
      attr_reader :api_key

      def initialize(api_key)
        @api_key = api_key
      end

      # @param system_prompt [String] The system instruction
      # @param messages [Array<Hash>] Conversation history [{role:, content:}]
      # @param model [String] Model identifier
      # @param params [Hash] temperature, top_p, max_tokens, etc.
      # @return [String] The AI response text
      def chat_completion(system_prompt:, messages:, model:, **params)
        raise NotImplementedError, "#{self.class}#chat_completion must be implemented"
      end

      private

      # Shared Faraday connection builder
      def connection(base_url, headers = {})
        Faraday.new(url: base_url) do |f|
          f.request :json
          f.response :json
          f.options.timeout = 60
          f.options.open_timeout = 10
          f.headers.merge!(headers)
        end
      end
    end
  end
end
