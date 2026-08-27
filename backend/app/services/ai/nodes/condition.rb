module Ai
  module Nodes
    class Condition < BaseNode
      def transparent?
        true
      end

      def process!
        # Condition nodes don't change context, they just branch
      end

      def next_handle_id
        data = step['data'] || {}
        variable_name = data['variable']
        operator = data['operator'] || '=='
        target_value = data['value']

        # Get current value from session context
        current_value = session.context&.dig(variable_name).to_s

        result = case operator
                 when '=='
                   current_value == target_value.to_s
                 when '!='
                   current_value != target_value.to_s
                 when '>'
                   current_value.to_f > target_value.to_f
                 when '<'
                   current_value.to_f < target_value.to_f
                 when 'contains'
                   current_value.include?(target_value.to_s)
                 else
                   false
                 end

        result ? 'true' : 'false'
      end
    end
  end
end
