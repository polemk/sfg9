# frozen_string_literal: true

module Ai
  # GOAT v2 / S1.3 — ponto único de escrita de telemetria do agente.
  #
  # Encapsula a persistência do AgentRun (S1.1, S1.2) e o log estruturado.
  # Fail-soft: nenhum erro de telemetria pode propagar para o caller — uma
  # falha aqui nunca pode afetar a resposta ao usuário final.
  #
  # API:
  #   Ai::Telemetry.record(attrs)  # cria AgentRun + log estruturado
  #   Ai::Telemetry.log(level, msg) # log livre com prefixo [AgentRun]
  class Telemetry
    PREFIX = '[AgentRun]'

    class << self
      # Persiste 1 AgentRun e emite log estruturado.
      # Nunca propaga exceção — só registra warning se falhar.
      #
      # @param attrs [Hash] atributos do AgentRun (mesmas chaves do model)
      # @return [AgentRun, nil] o AgentRun criado, ou nil se a persistência falhou
      def record(attrs)
        run = AgentRun.create!(attrs)
        log(:info, summary_for(run))
        run
      rescue StandardError => e
        Rails.logger.warn("#{PREFIX} persistência ignorada: #{e.class}: #{e.message}")
        nil
      end

      # Log livre com prefixo padronizado, para grep simples (`grep [AgentRun]`).
      #
      # @param level [Symbol] :debug | :info | :warn | :error
      # @param message [String] texto livre
      # @param payload [Hash, nil] opcional, serializado em key=value
      def log(level, message, payload = nil)
        line = +"#{PREFIX} #{message}"
        if payload.is_a?(Hash) && payload.any?
          line << ' ' << payload.compact.map { |k, v| "#{k}=#{format_value(v)}" }.join(' ')
        end
        Rails.logger.public_send(level, line)
      rescue StandardError
        # Log nunca pode quebrar nada.
        nil
      end

      private

      # Resumo legível de 1 turno, no formato grep-friendly:
      #   [AgentRun] provider=openai model=gpt-4o channel=waba latency_ms=820 status=success tools=2 loops=1
      def summary_for(run)
        tools_count = Array(run.tools_called).size
        payload = {
          provider:   run.provider,
          model:      run.model,
          channel:    run.channel,
          flow:       run.chat_flow_id,
          latency_ms: run.latency_ms,
          status:     run.status,
          tools:      tools_count,
          loops:      run.loop_count
        }
        line_payload = payload.compact.map { |k, v| "#{k}=#{format_value(v)}" }.join(' ')
        "turn #{line_payload}"
      end

      def format_value(v)
        case v
        when nil    then '-'
        when String then v.include?(' ') ? %("#{v}") : v
        else v.to_s
        end
      end
    end
  end
end
