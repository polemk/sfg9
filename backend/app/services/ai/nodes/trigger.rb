module Ai
  module Nodes
    class Trigger < BaseNode
      def transparent?
        # If content is present, treat it as a message node (not transparent)
        # So it displays the content (Welcome Message).
        return false if step['content'].present? || step.dig('data', 'content').present?
        true
      end

      def process!
        # Triggers are entry points, usually no logic here as the engine
        # already found this node based on keywords.
        # When user selects an option, we need to find the matching handle
        return unless input.present?

        @selected_option = find_option_by_input
      end

      def next_handle_id
        @selected_option&.dig('id')
      end

      private

      def find_option_by_input
        options = step.dig('data', 'options') || step['options'] || []
        return nil if options.empty?

        # Match by label (case insensitive) or by id
        options.find do |opt|
          opt['label']&.downcase&.strip == input.downcase.strip ||
          opt['id'] == input
        end
      end
    end
  end
end
