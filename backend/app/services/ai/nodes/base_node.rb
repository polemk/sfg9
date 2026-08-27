module Ai
  module Nodes
    class BaseNode
      attr_reader :step, :session, :input

      def initialize(step, session, input = nil)
        @step = step
        @session = session
        @input = input
      end

      # Validates input if necessary (e.g. email format)
      def validate!
        true
      end
  
      # Processes the node logic
      def process!
        # Default: do nothing
      end

      # If true, the engine will move to the next node without waiting for user input
      def transparent?
        false
      end

      # For branching nodes, returns the specific sourceHandle ID to follow
      def next_handle_id
        nil
      end

      # Returns the payload to be sent to the frontend
      def payload
        data = step['data'] || {}
        
        # Resolve variables in top-level content
        content = resolve_variables(data['content'] || step['content'])
        
        # Resolve variables in options
        options = (data['options'] || step['options'] || []).map do |o|
          if o.is_a?(Hash)
            o.dup.tap { |obj| obj['label'] = resolve_variables(obj['label']) if obj['label'].is_a?(String) }
          else
            resolve_variables(o)
          end
        end
        
        # Resolve variables inside blocks if they exist
        blocks = data['blocks']&.map do |block|
          if block.is_a?(Hash)
            # Recursively or specifically resolve common text fields in blocks
            new_block = block.dup
            ['content', 'text', 'body'].each do |field|
              new_block[field] = resolve_variables(new_block[field]) if new_block[field].is_a?(String)
            end
            new_block
          else
            block
          end
        end

        {
          id: step['id'],
          type: step['type'],
          content: content,
          options: options,
          blocks: blocks
        }
      end

      private

      def resolve_variables(text)
        return text unless text.is_a?(String)

        # Replace {{variable}} with context value
        # (Bloco 6 do trim: o fallback para atributo do `Lead` saiu com o AI9-006)
        text.gsub(/\{\{(\w+)\}\}/) do |match|
          key = Regexp.last_match(1)
          
          # 1. Try session context (case insensitive check)
          value = session.context&.dig(key)
          value ||= session.context&.find { |k, v| k.to_s.downcase == key.downcase }&.last
          
          if value.blank? && ['full_name', 'first_name', 'name'].include?(key.to_s.downcase)
            value = 'Visitante'
          end

          value.presence || match
        end.tap { |result| Rails.logger.debug "[Ai::BaseNode] resolve_variables: input=#{text.inspect}, output=#{result.inspect}" }
      end
    end
  end
end
