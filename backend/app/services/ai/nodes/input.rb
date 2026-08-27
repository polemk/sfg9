module Ai
  module Nodes
    class Input < BaseNode
      def validate!
        data = step['data'] || {}
        return false if input.blank?

        case data['inputType'] || step['inputType']
        when 'email'
          input.match?(URI::MailTo::EMAIL_REGEXP)
        when 'phone'
          # Simple check for now, can be improved
          input.gsub(/\D/, '').length >= 10
        else
          # Generic Regex Validation if provided
          if (regex = data['validationRegex']).present?
            begin
              # Case insensitive match by default unless specified otherwise?
              # Let's assume standard regex format or simple string match
              # If user provides regex "baqueta", we match /baqueta/i
              Regexp.new(regex, Regexp::IGNORECASE).match?(input)
            rescue RegexpError
              inputs_match = input.strip.downcase == regex.strip.downcase
              inputs_match
            end
          else
            true
          end
        end
      end

      def process!
        data = step['data'] || {}
        # Save input to context using the variable name defined in the step
        raw_variable = data['variable'] || step['variable'] || "step_#{step['id']}"
        variable_name = raw_variable.to_s.gsub(/[\{\}]/, '')

        current_context = session.context || {}
        current_context[variable_name] = input

        # Bloco 6 do trim (AI9-006): aqui o input também era espelhado no `Lead`
        # (`update_lead_if_matching`). O contexto da sessão continua guardando.

        session.update!(context: current_context)
      end

      # For option nodes, determine which handle to follow based on selected option
      def next_handle_id
        data = step['data'] || {}
        options = data['options'] || step['options'] || []

        return nil if options.empty?
        
        selected_option = nil
        selected_index = nil

        options.each_with_index do |opt, idx|
          label = opt.is_a?(Hash) ? opt['label'] : opt
          opt_id = opt.is_a?(Hash) ? opt['id'] : nil

          # Match by label (text response) OR by id (WhatsApp interactive button payload)
          if label.to_s.strip.downcase == input.to_s.strip.downcase ||
             (opt_id.present? && opt_id.to_s.strip.downcase == input.to_s.strip.downcase)
            selected_option = opt
            selected_index = idx
            break
          end
        end

        return nil unless selected_option

        if selected_option.is_a?(Hash)
          # React Flow edges coming from custom option nodes often use the option's ID or target as the sourceHandle
          selected_option['id'] || selected_option['target'] || "option-#{selected_index}"
        else
          "option-#{selected_index}"
        end
      end

    end
  end
end
