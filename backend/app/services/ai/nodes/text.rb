module Ai
  module Nodes
    class Text < BaseNode
      def process!
        # Text nodes generally don't process input, they just display.
        # However, if we are "waiting" on this node, any input triggers the next step.
        return unless input.present?
        @selected_option = find_option_by_input
      end

      # For text nodes with options (buttons), determine which handle to follow
      def next_handle_id
        return nil unless @selected_option || input.present?

        # If we found a selected option with an ID, use it
        if @selected_option&.dig('id')
          return @selected_option['id']
        end

        # Fallback: legacy format using index
        data = step['data'] || {}
        options = data['options'] || step['options'] || []
        return nil if options.empty? || input.blank?

        options.each_with_index do |opt, idx|
          label = opt.is_a?(Hash) ? opt['label'] : opt
          if label.to_s.strip.downcase == input.to_s.strip.downcase
            return "option-#{idx}"
          end
        end

        nil
      end

      private

      def find_option_by_input
        options = step.dig('data', 'options') || step['options'] || []
        return nil if options.empty?

        # Match by label (case insensitive) or by id
        options.find do |opt|
          next unless opt.is_a?(Hash)
          opt['label']&.downcase&.strip == input.to_s.downcase.strip ||
          opt['id'] == input
        end
      end
    end
  end
end
