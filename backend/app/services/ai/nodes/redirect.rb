module Ai
  module Nodes
    class Redirect < BaseNode
      def process!
        # If auto_auth is enabled, we try to authenticate/create the user
        if auto_auth?
          authenticate_user!
        end

        # When user selects an option, find the matching handle for branching
        return unless input.present?
        @selected_option = find_option_by_input
      end

      def next_handle_id
        @selected_option&.dig('id')
      end

      def transparent?
        # Redirect node performs an action on the client but doesn't necessarily stop the flow?
        # Usually it's a terminal action or a side-effect.
        # If it's a redirect to another page, the flow technically "ends" or pauses until they come back.
        # But if it's 'scroll_to', the chat continues.
        # Let's say it's NOT transparent, it returns a payload that the widget executes.
        # The widget might then continue or not.
        false 
      end

      def auto_auth?
        step.dig('data', 'auto_auth') == true
      end

      def action
        step.dig('data', 'action') || 'navigate'
      end

      def url
        resolve_variables(step.dig('data', 'url'))
      end

      def target
        step.dig('data', 'target')
      end

      def payload
        # Ensure we try to authenticate if we haven't yet, because FlowEngine might not call process!
        # for non-transparent nodes that don't receive input.
        if auto_auth? && @auth_token.nil?
          authenticate_user!
        end

        original_payload = super
        
        extra_data = {
          action: action,
          url: url,
          target: target
        }

        # If we authenticated, passing the token
        if @auth_token
          extra_data[:auth] = {
            token: @auth_token,
            refresh_token: @refresh_token,
            user_name: @user_name,
            user_email: @user_email
          }
        end

        original_payload.merge(extra_data)
      end

      private

      def authenticate_user!
        # Try to find variables in context (support PT-BR variations)
        email = session.context['email'] || session.context['user_email'] || session.context['e-mail']
        # (Bloco 6 do trim: o fallback para `session.lead&.email` saiu com o AI9-006)

        phone = session.context['phone'] || session.context['user_phone'] || session.context['whatsapp'] || session.context['telefone'] || session.context['celular']
        name = session.context['name'] || session.context['user_name'] || session.context['nome'] || 'Visitante'

        if email.present? || phone.present?
          # Casa o usuário do contexto com uma conta EXISTENTE (nunca cria — DEC-18.7).
          # We purposefully mock the params it expects
          auth_params = {
            email: email,
            phone: phone,
            name: name,
            company: session.context['company']
          }

          result = Auth::ExistingUserSessionService.call(auth_params)

          if result[:status] == 200
            data = result[:data] # { user: ..., token: ..., refresh_token: ... }
            @auth_token = data[:token]
            @refresh_token = data[:refresh_token]
            # data[:user] is a Grape::Entity, need to serialize it to access attributes
            user_entity = data[:user]
            @user_name = user_entity.object.name
            @user_email = user_entity.object.email
          else
            Rails.logger.error("RedirectNode Auth Failed: #{result[:error]}")
          end
        else
          Rails.logger.warn("RedirectNode Auth Skipped: No email/phone in context")
        end
      rescue StandardError => e
        Rails.logger.error("RedirectNode Crash Prevented: #{e.message}")
        # Retrieve backtrace if needed
        Rails.logger.error(e.backtrace.join("\n"))
      end

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
