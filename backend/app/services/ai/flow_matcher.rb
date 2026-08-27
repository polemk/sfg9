module Ai
  class FlowMatcher
    class << self
      # Main entry point.
      #
      # Bloco 7 do trim (AI9-014): as duas primeiras etapas (`match_by_operation`,
      # por embeddings via `Operations::IntentDetectorService`, e
      # `match_by_operation_keyword`, por `Operation#matches_text?`) saíram com o
      # `Operation`. Sobrou o casamento por `chat_flows.keywords`, que é do próprio
      # AI9-007 e não depende de base de conhecimento nenhuma.
      #
      # @param text [String] user input text
      # @return [ChatFlow, nil] matched flow or nil
      def match(text)
        return nil if text.blank?

        match_by_keyword(text)
      end

      # Keyword matching: text contains any flow keyword
      # @param text [String] user input text
      # @return [ChatFlow, nil] flow with matching keyword
      def match_by_keyword(text)
        return nil if text.blank?
        input_down = text.to_s.strip.downcase

        # Use Ruby filtering for maximum safety and flexibility
        # This avoids complex SQL unnesting issues with empty arrays/nulls
        ChatFlow.all.find do |flow|
          next false unless flow.keywords.is_a?(Array)
          flow.keywords.any? do |kw|
            kw.present? && input_down.include?(kw.to_s.strip.downcase)
          end
        end
      end
    end
  end
end
