module Ai
  module Nodes
    class Handoff < BaseNode
      def process!
        # Logic is handled by the engine, this node just holds data
      end

      def target_flow_id
        step.dig('data', 'target_flow_id')
      end

      def transparent?
        # It's unique: it doesn't follow edges, it resets the flow.
        # We handle it explicitly in the engine.
        false 
      end

      def payload
        original_payload = super
        flow_name = nil
        
        if target_flow_id.present?
          flow = ChatFlow.find_by(id: target_flow_id)
          flow_name = flow&.name
        end

        original_payload.merge({
          target_flow_id: target_flow_id,
          target_flow_name: flow_name,
          action: 'handoff'
        })
      end
    end
  end
end
