module Ai
  class FlowEngine
    attr_reader :session, :input, :nodes, :edges

    def initialize(session, input = nil, origin_node_id: nil, visited_flows: [])
      @session = session
      @input = input
      @origin_node_id = origin_node_id
      @visited_flows = visited_flows
      @original_input = input # Keep original input for logging

      definition = session.chat_flow.definition
      @nodes = definition['nodes'] || []
      @edges = definition['edges'] || []
    end

    def process!
      responses = []

      # Loop prevention check right at start (in case engine is initialized in a loop)
      if @visited_flows.include?(session.chat_flow_id)
        return [{ type: 'end', content: 'Erro: Loop infinito de fluxos detectado.' }]
      end
      # Add current flow to visited list
      current_visited_flows = @visited_flows + [session.chat_flow_id]

      # 1. Identify Current Node
      current_node_id = @origin_node_id || session.current_step_id

      # If jumping to an origin_node_id, we force the session to that state
      if @origin_node_id.present?
        session.update!(current_step_id: @origin_node_id)
        current_node_id = @origin_node_id
      end

      # If no current step (new session), find Trigger node, Start node or first node
      if current_node_id.nil?
        start_node = nodes.find { |n| n['type'] == 'trigger' } ||
                     nodes.find { |n| n['type'] == 'start' } ||
                     nodes.first

        return [{ type: 'end', content: 'Conversação iniciada' }] unless start_node

        current_node_id = start_node['id']
        session.update!(current_step_id: current_node_id)
      end

      loop do
        current_node_data = nodes.find { |n| n['id'] == current_node_id }

        unless current_node_data
          responses << { type: 'end', content: 'Conversação finalizada' }
          break
        end

        handler = node_handler(current_node_data)

        # Handle Handoff
        if handler.is_a?(Ai::Nodes::Handoff)
          log_execution(current_node_data, handler)
          target_flow_id = handler.target_flow_id
          if target_flow_id.present?
            # Append the handoff action to the responses so the UI can update
            responses << handler.payload
            
            session.update!(chat_flow_id: target_flow_id, current_step_id: nil)
            session.reload
            
            # New flow starts fresh - return merged responses
            return responses + Ai::FlowEngine.new(session, nil, visited_flows: current_visited_flows).process!
          else
            responses << { type: 'end', content: 'Handoff target not configured' }
            break
          end
        end

        # Check if this node expects user input
        node_expects_input = %w[question input option].include?(current_node_data['type']) ||
                             (handler.payload[:options].present? && handler.payload[:options].any?)

        # Process the node
        if input.present?
          if handler.validate!
            handler.process!
            log_execution(current_node_data, handler)
            @input = nil # clear input after consumption
          else
            responses << { error: 'Invalid input', retry: true, payload: handler.payload }
            break
          end
        elsif !handler.transparent?
          # If it's a message/text node without input, we show it
          payload = handler.payload
          payload[:origin_node_id] = current_node_id # Tag for temporal jump
          responses << payload
          log_execution(current_node_data, handler)

          # If this node expects input, STOP HERE and wait. Don't advance to next node yet.
          if node_expects_input
            session.update!(current_step_id: current_node_id)
            break
          end
        end

        # Find Next Node (only after processing input or if node doesn't expect input)
        next_id = find_next_node_id(current_node_id, handler.next_handle_id)

        if next_id
          current_node_id = next_id
          session.update!(current_step_id: next_id)
        else
          responses << { type: 'end', content: 'Fim do fluxo' } unless responses.any? { |r| ['end', 'redirect', 'handoff'].include?(r[:type]) }
          break
        end
      end

      responses
    end

    def find_next_node_id(source_id, handle_id = nil)
      # Find edge starting from this node
      relevant_edges = edges.select do |e| 
        e['source'] == source_id && (handle_id.nil? || e['sourceHandle'] == handle_id)
      end

      # Verify the target node actually exists in the nodes array
      valid_edge = relevant_edges.find { |e| nodes.any? { |n| n['id'] == e['target'] } }
      
      valid_edge ? valid_edge['target'] : nil
    end

    private

    def log_execution(node_data, handler)
      return if session.test? # Don't log test sessions

      FlowExecution.create!(
        chat_session: session,
        chat_flow: session.chat_flow,
        node_id: node_data['id'],
        node_type: node_data['type'],
        input_data: {
          user_input: @original_input
        }.compact,
        output_data: {
          content: handler.payload[:content],
          options: handler.payload[:options],
          action: handler.payload[:action],
          target: handler.payload[:target]
        }.compact,
        context_snapshot: session.context || {}
      )
    rescue StandardError => e
      Rails.logger.error "[FlowEngine] Failed to log execution: #{e.message}"
    end

    def node_handler(node_data)
      case node_data['type']
      when 'input', 'question', 'option'
        Ai::Nodes::Input.new(node_data, session, input)
      when 'text', 'message'
        Ai::Nodes::Text.new(node_data, session, input)
      when 'condition'
        Ai::Nodes::Condition.new(node_data, session, input)
      when 'trigger'
        Ai::Nodes::Trigger.new(node_data, session, input)
      when 'handoff'
        Ai::Nodes::Handoff.new(node_data, session, input)
      when 'redirect'
        Ai::Nodes::Redirect.new(node_data, session, input)
      else
        Ai::Nodes::BaseNode.new(node_data, session, input)
      end
    end
  end
end
