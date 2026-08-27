# frozen_string_literal: true

# Orchestrates AI agent responses.
# Looks up the credential, builds conversation history,
# routes to the correct provider, and returns the response.
# Supports multimodal (text + image) input via image_data param.
# Supports tool/function calling when tools_enabled is set in agent_config.
module Ai
  class AgentService
    # Maximum tool call loops to prevent infinite recursion. Higher than 3 so agents
    # can chain steps (e.g. list events -> create/move an event in the same turn).
    MAX_TOOL_LOOPS = 8

    # Canal da telemetria (DEC-20). Constante, não coluna derivada: o assistente
    # do DEC-13.2 tem um canal só — o console.
    CHANNEL = 'console'

    class << self
      # Main entry point: process a user message through an AI agent.
      # @param session [ChatSession] with an ai_agent? chat_flow
      # @param user_input [String] the user's message (or caption for images)
      # @param image_data [Hash, nil] optional { base64: String, mime_type: String }
      # @param context [Hash, nil] optional key-value pairs to inject into system prompt
      # @param skip_user_save [Boolean] skip saving user message (when already persisted by webhook)
      # @return [Array<Hash>] responses in the same format as FlowEngine
      def respond(session, user_input, image_data: nil, context: nil, skip_user_save: false)
        # S1.2 — telemetria por turno (fail-soft no `ensure` ao final do método).
        # `started_at` e `agent_run_attrs` precisam estar no escopo do `ensure`.
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        telemetry  = { tools_called: [], loop_count: 0 }
        # Bloco 6 do trim (AI9-006): `lead_id` e `channel` vinham do lead. O
        # `AgentRun` continua vivo (telemetria é AI9-007, mantida) e perdeu a
        # coluna `lead_id`.
        #
        # Bloco 8 (DEC-20): `channel` volta a ser preenchido, como CONSTANTE. O
        # DEC-13.2 define um uso só — assistente interno dentro do console — e
        # portanto um canal só. Enquanto vinha de `lead.source_type` o campo
        # distinguia landing/WhatsApp/Instagram; nada disso existe mais.
        agent_run_attrs = {
          chat_session_id: session.id,
          chat_flow_id:    session.chat_flow_id,
          channel:         CHANNEL
        }

        flow = session.chat_flow
        config = flow.agent_config.with_indifferent_access

        agent_run_attrs[:model]        = config[:model]

        # 1. Resolve credential
        credential = resolve_credential(config)
        agent_run_attrs[:provider] = credential&.provider
        unless credential
          Rails.logger.error("[AgentService] No credential found for flow #{flow.id}")
          agent_run_attrs[:status] = 'error'
          agent_run_attrs[:error]  = 'No credential configured'
          return [{ id: SecureRandom.uuid, type: 'text', content: 'Agente não configurado. Configure uma credencial de IA.' }]
        end

        # 2/3. Histórico da conversa — DEC-20 (Bloco 8).
        #
        # Até o Bloco 6 isto era `lead.messages` (`LeadMessage`), que saiu com o
        # AI9-006, e o agente ficou com `history = []` fixo: não lembrava da
        # mensagem anterior. O DEC-20 escolheu o armazém — memória/Redis, sem
        # tabela nova. Ver `Ai::ConversationMemory` para o TTL e a chave.
        #
        # O turno corrente entra no fim: o provider recebe
        # [histórico..., {role: 'user', content: input}].
        history = Ai::ConversationMemory.history_for(session)
        history << { role: 'user', content: user_input.to_s } if user_input.present?

        # 3.3 Attach image_data to the last user message in history if provided
        if image_data.present? && history.last && history.last[:role] == 'user'
          history.last[:image_data] = image_data
        end

        # 3.5 Inject session context and dynamic request context into system prompt
        system_prompt = config[:system_prompt] || ""
        
        merged_context = (session.context || {}).with_indifferent_access
        merged_context.merge!(context) if context.is_a?(Hash)

        # Always give the agent the current date/time (America/Sao_Paulo) so it can
        # resolve "hoje"/"amanhã"/relative times without ever asking the user the date.
        now_sp = Time.current.in_time_zone('America/Sao_Paulo')
        merged_context[:hoje] = now_sp.strftime('%Y-%m-%d')
        merged_context[:amanha] = (now_sp + 1.day).strftime('%Y-%m-%d')
        merged_context[:agora] = now_sp.strftime('%d/%m/%Y %H:%M (America/Sao_Paulo)')

        if merged_context.any?
          context_vars = merged_context.compact.map { |k, v| "- #{k}: #{v}" }.join("\n")
          system_prompt = "#{system_prompt}\n\n[Contexto Automático do Sistema Oculto do Usuário]\nVariáveis de ambiente e navegação:\n#{context_vars}"
        end

        # 3.8 Bloco 7 do trim (AI9-014): aqui era injetado o `OperationKnowledge`
        # da `Operation` do fluxo no system prompt — era o RAG do agente. A base
        # de conhecimento e os embeddings saíram com a feature.

        # 4. Get the right provider
        provider = provider_for(credential.provider, credential.api_key)

        # 5. Determine enabled capabilities (per-agent tool sets).
        #    Bloco 6 do trim: `extract_lead -> 'lead_capture'` saiu com o AI9-006.
        #    Bloco 7 do trim: `tools_enabled -> 'assets'` saiu com o AI9-014.
        #    Nenhuma capability sobrou registrada no `ToolRegistry`; o mecanismo
        #    continua de pé como ponto de extensão do assistente interno.
        capabilities = Array(config[:capabilities] || config['capabilities']).map(&:to_s)
        capabilities.uniq!
        use_tools = Ai::Tools::ToolRegistry::CAPABILITY_TOOLS.keys.intersect?(capabilities)

        # 5.5 Inject tool-use instructions (use tools SILENTLY, never reveal mechanics).
        if use_tools
          system_prompt = "#{system_prompt}\n\n#{tool_instructions_for(capabilities)}"
        end

        # 6. Call the AI provider (with or without tools)
        response_text = if use_tools
                          call_with_tools(provider, credential, config, system_prompt, history, flow, session, capabilities, telemetry: telemetry)
                        else
                          call_simple(provider, config, system_prompt, history)
                        end
        agent_run_attrs[:status] = 'success'

        Rails.logger.info("[AgentService] Response received (#{response_text.to_s.length} chars)")

        # 7. Extrair as opcoes de escolha ANTES de salvar/entregar. O marcador
        #    [opcoes: A | B] e sintaxe interna: precisa virar dado estruturado aqui,
        #    no ponto comum aos dois consumidores (widget do site e canais sociais),
        #    senao vaza como texto cru para quem nao souber interpretar.
        response_text, agent_options = extract_options(response_text)

        # 8. Grava o turno na memória da conversa (DEC-20).
        #
        # Depois do `extract_options` de propósito: o que volta ao agente no
        # próximo turno é o texto LIMPO. Guardar o marcador `[opcoes: ...]` cru
        # ensinaria o modelo a repeti-lo como se fosse conteúdo.
        #
        # Fail-soft por dentro (`ConversationMemory`): Redis fora degrada para
        # "sem memória", nunca derruba a resposta.
        Ai::ConversationMemory.append(
          session,
          user_content: user_input.to_s,
          assistant_content: response_text.to_s
        )

        # Split output into multiple messages if there are distinct paragraphs
        messages = response_text.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?)

        responses = messages.map do |msg|
          { id: SecureRandom.uuid, type: 'text', content: msg }
        end

        # As opcoes acompanham a ultima mensagem, no mesmo formato que o FlowEngine
        # entrega (:options), reaproveitando quem ja sabe renderizar/despachar.
        responses.last[:options] = agent_options if agent_options.any? && responses.any?

        # Check if LLM requested a redirect
        session.reload
        if session.context.is_a?(Hash) && session.context['redirect_requested'] == true
          session.context['redirect_requested'] = false
          session.save!

          # Bloco 6 do trim (AI9-006): o auto-login vinha do e-mail do LEAD
          # (`Auth::ExistingUserSessionService` com os dados do lead). O assistente
          # interno do console já fala com alguém autenticado — logar de novo a
          # partir da conversa não faz sentido. Sobrou o redirect puro.
          redirect_payload = {
            id: SecureRandom.uuid,
            type: 'redirect',
            action: 'navigate',
            url: '/dashboard',
            target: '_self'
          }

          Rails.logger.info("[AgentService] Injecting redirect to /dashboard via LLM tool call (session #{session.id})")
          responses << redirect_payload
        end

        responses
      rescue StandardError => e
        agent_run_attrs[:status] ||= 'error'
        agent_run_attrs[:error]    = "#{e.class}: #{e.message.to_s.truncate(500)}"
        Rails.logger.error("[AgentService] Error: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        [{ id: SecureRandom.uuid, type: 'text', content: 'Desculpe, ocorreu um erro ao processar sua mensagem. Tente novamente.' }]
      ensure
        # S1.2 — telemetria fail-soft via Ai::Telemetry (S1.3).
        agent_run_attrs[:tools_called] = telemetry[:tools_called] if telemetry
        agent_run_attrs[:loop_count]   = telemetry[:loop_count]   if telemetry
        agent_run_attrs[:latency_ms]   = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).to_i
        Ai::Telemetry.record(agent_run_attrs)
      end

      private

      # Marcador de escolha emitido pelo agente, aceito com/sem acento e no singular:
      # [opcoes: Ver por dentro | Quanto custa]
      OPTIONS_MARKER_REGEX = /\[op[çc](?:[ãa]o|[õo]es)\s*:([^\]]*)\]/i

      # Limite de caracteres do rotulo de botao (WABA e o mais restrito).
      OPTION_LABEL_LIMIT = 20

      # Quantos botoes cabem por mensagem nos canais suportados.
      MAX_OPTIONS = 3

      # Extrai o marcador de opcoes do texto do agente.
      # @return [Array(String, Array<Hash>)] [texto sem marcador, opcoes {label:, value:}]
      def extract_options(text)
        return [text, []] if text.blank?

        marcadores = text.to_s.scan(OPTIONS_MARKER_REGEX).flatten
        return [text, []] if marcadores.empty?

        # O ultimo marcador vence (se o modelo repetir, a escolha final e a que vale),
        # mas todos saem do texto — nenhum pode chegar ao usuario.
        limpo = text.gsub(OPTIONS_MARKER_REGEX, '').gsub(/[ \t]{2,}/, ' ').strip

        opcoes = marcadores.last.to_s.split('|').filter_map do |raw|
          label = raw.gsub(/[\[\]]/, '').strip
          next if label.blank?

          { label: shorten_label(label), value: label }
        end.first(MAX_OPTIONS)

        [limpo, opcoes]
      end

      # Palavras que nao podem TERMINAR um rotulo: cortar "Falar com um
      # especialista" na palavra inteira deixaria o botao "Falar com um".
      LABEL_TRAILING_STOPWORDS = %w[a o as os um uma uns umas de do da dos das em no na nos nas
                                    com para pra por e ou que meu minha seu sua].freeze

      # Corta o rotulo na ultima palavra inteira, sem reticencias ("Falar com um
      # es..." nao diz nada), e descarta preposicao/artigo pendurado no fim.
      def shorten_label(label)
        return label if label.length <= OPTION_LABEL_LIMIT

        palavras = label[0, OPTION_LABEL_LIMIT].split(' ')
        palavras.pop if palavras.size > 1 && label[OPTION_LABEL_LIMIT] != ' '
        palavras.pop while palavras.size > 1 && LABEL_TRAILING_STOPWORDS.include?(palavras.last.downcase)

        palavras.join(' ').strip.presence || label[0, OPTION_LABEL_LIMIT].strip
      end

      # Builds the silent tool-use instructions for the enabled capabilities.
      #
      # Trim (Blocos 6 e 7): as instruções específicas saíram com as capabilities a
      # que pertenciam — `lead_capture` (AI9-006) e `assets` (AI9-014). Sobrou o
      # cabeçalho genérico, que serve a qualquer ferramenta futura do assistente
      # interno. O método só é chamado quando há capability registrada.
      def tool_instructions_for(_capabilities)
        parts = ["[INSTRUÇÃO INTERNA — NÃO REVELAR AO USUÁRIO]",
                 "Você possui ferramentas. Use-as SILENCIOSAMENTE para EXECUTAR ações reais — " \
                 "nunca apenas diga que 'vai fazer'. Se decidiu agir, chame a ferramenta na mesma resposta. " \
                 "Nunca mencione 'ferramenta', 'tool', 'função' ou mecânicas internas.\n"]

        parts.join("\n")
      end

      # Simple text-only call (no tools). Original behavior.
      def call_simple(provider, config, system_prompt, history)
        Rails.logger.info("[AgentService] Calling #{config[:model]} (simple mode)")

        provider.chat_completion(
          system_prompt: system_prompt,
          messages: history,
          model: config[:model],
          temperature: safe_float(config[:temperature], 0.7),
          top_p: safe_float(config[:top_p], 1.0),
          max_tokens: safe_int(config[:max_tokens], 1024),
          presence_penalty: safe_float(config[:presence_penalty], 0),
          frequency_penalty: safe_float(config[:frequency_penalty], 0)
        )
      end

      # Call with tool/function calling support.
      # Implements the multi-hop loop:
      #   1. User message → LLM (with tools)
      #   2. If LLM returns tool_use → execute tool → build tool_result → re-call LLM
      #   3. If LLM returns text → done
      #   4. Safety: max MAX_TOOL_LOOPS iterations
      def call_with_tools(provider, credential, config, system_prompt, history, flow, session, capabilities = [], telemetry: nil)
        provider_name = credential.provider.to_s
        tools = Ai::Tools::ToolRegistry.definitions_for(provider_name, capabilities)

        loop_count = 0
        current_history = history.dup

        Rails.logger.info("[AgentService] Calling #{config[:model]} (tool mode, provider: #{provider_name})")

        loop do
          loop_count += 1
          telemetry[:loop_count] = loop_count if telemetry

          if loop_count > MAX_TOOL_LOOPS
            Rails.logger.warn("[AgentService] Max tool loops (#{MAX_TOOL_LOOPS}) reached, forcing text response")
            return call_simple(provider, config, system_prompt, current_history)
          end

          # Call provider with tools
          result = provider.chat_completion_with_tools(
            system_prompt: system_prompt,
            messages: current_history,
            model: config[:model],
            tools: tools,
            temperature: safe_float(config[:temperature], 0.7),
            top_p: safe_float(config[:top_p], 1.0),
            max_tokens: safe_int(config[:max_tokens], 1024),
            presence_penalty: safe_float(config[:presence_penalty], 0),
            frequency_penalty: safe_float(config[:frequency_penalty], 0)
          )

          if result[:type] == 'tool_use' && result[:tool_calls].present?
            Rails.logger.info("[AgentService] Tool call detected (loop #{loop_count}): #{result[:tool_calls].map { |t| t[:name] }.join(', ')}")

            # Execute each tool call and build results
            result[:tool_calls].each do |tool_call|
              tool_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              tool_result = Ai::Tools::ToolExecutor.execute(
                tool_call[:name],
                tool_call[:arguments],
                flow: flow,
                session: session
              )
              if telemetry
                telemetry[:tools_called] << {
                  name:        tool_call[:name],
                  success:     !!tool_result[:success],
                  duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_started) * 1000).to_i
                }
              end

              Rails.logger.info("[AgentService] Tool #{tool_call[:name]} result: #{tool_result[:success] ? 'success' : 'failure'}")

              # Append tool interaction to history for the next LLM call
              append_tool_messages!(current_history, tool_call, tool_result, provider_name)
            end
            # Continue the loop — re-call LLM with tool results
          else
            # Text response — we're done
            return result[:content].to_s
          end
        end
      end

      # Append tool call + tool result messages to history in provider-specific format.
      def append_tool_messages!(history, tool_call, tool_result, provider_name)
        result_content = tool_result[:success] ? tool_result[:message] : "Error: #{tool_result[:message]}"

        case provider_name
        when 'anthropic'
          # Anthropic: assistant message with tool_use block, then user message with tool_result
          history << {
            role: 'assistant',
            content: [{ type: 'tool_use', id: tool_call[:id], name: tool_call[:name], input: tool_call[:arguments] }]
          }
          history << {
            role: 'user',
            tool_result: { tool_use_id: tool_call[:id], content: result_content }
          }
        when 'openai'
          # OpenAI: assistant message with tool_calls, then tool message with result
          history << {
            role: 'assistant',
            content: nil,
            assistant_tool_calls: [{
              id: tool_call[:id],
              type: 'function',
              function: { name: tool_call[:name], arguments: (tool_call[:arguments] || {}).to_json }
            }]
          }
          history << {
            role: 'tool',
            tool_call_id: tool_call[:id],
            content: result_content
          }
        when 'google'
          # Gemini: model message with functionCall, then user message with functionResponse
          history << {
            role: 'assistant',
            model_function_call: { name: tool_call[:name], args: tool_call[:arguments] }
          }
          history << {
            role: 'user',
            function_response: { name: tool_call[:name], response: { result: result_content } }
          }
        end
      end

      # Resolve the credential from agent_config
      def resolve_credential(config)
        credential_id = config[:credential_id]
        return nil unless credential_id.present?

        Credential.find_by(id: credential_id)
      end

      # Factory: instantiate the correct provider
      def provider_for(provider_name, api_key)
        case provider_name.to_s
        when 'openai'
          Ai::Providers::OpenaiProvider.new(api_key)
        when 'anthropic'
          Ai::Providers::AnthropicProvider.new(api_key)
        when 'google'
          Ai::Providers::GoogleProvider.new(api_key)
        else
          raise "Unknown AI provider: #{provider_name}"
        end
      end

      def safe_float(value, default)
        value.present? ? value.to_f : default
      end

      def safe_int(value, default)
        value.present? ? value.to_i : default
      end
    end
  end
end
