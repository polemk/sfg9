# frozen_string_literal: true

module Sfg
  # Progresso de job — OPS-463, OPS-125, OPS-127, DB-460.
  #
  # **Ponto único de emissão.** Job nenhum chama `ActionCable.server.broadcast`
  # direto, e nenhum monta o payload à mão: os dois viram convenção oral, e convenção
  # oral é como o emissor e o consumidor divergem sem que nada reprove.
  #
  # Isso já aconteceu nesta base, e é o motivo deste arquivo existir: o
  # `DefaultMemberJob` publicava `{ kind:, state: 'running' }` enquanto o
  # `useJobProgress.ts` lê `status`. O front recebia o evento, não reconhecia nenhum
  # dos estados e caía no ramo "running" para sempre — inclusive quando o job tinha
  # **falhado**. Nenhum portão pega: o Ruby estava certo, o TypeScript estava certo,
  # e os dois falavam línguas diferentes. É a Regra de fronteira aplicada a um
  # payload de websocket.
  #
  # **O contrato, e ele é o que `useJobProgress.ts` lê:**
  #
  #     {
  #       type:    "job_progress",   # exigido por ai9-conventions §3.8
  #       job_id:  "availability_template_activate:42",
  #       status:  "running" | "done" | "failed",
  #       percent: 0..100,           # nil quando o job ainda não reportou
  #       message: "Importando 320 de 1.204",
  #       error:   "…"               # só em `failed`
  #     }
  #
  # **Por que o estado também vai para a ENTIDADE, e não só pelo socket (D2):** o
  # legado guardava progresso na linha de `delayed_jobs` e `projects.job_id` era FK
  # para essa tabela. Sidekiq não tem registro relacional (DB-460), então quem chega
  # DEPOIS do evento — a aba que estava fechada, o F5, o outro operador — não teria
  # como saber que há job rodando. As colunas `job_state`/`job_progress` são a
  # resposta para "como está agora?"; o socket é só o aviso de que mudou.
  module JobProgress
    STATES = %w[running done failed].freeze
    PAYLOAD_TYPE = 'job_progress'

    module_function

    # Publica no canal do projeto e, quando `record` for informado, grava o estado
    # na própria entidade.
    #
    # `percent` é sempre normalizado para 0..100 — `nil` significa "ainda não sei",
    # que é diferente de zero.
    def publish(project_id:, job_id:, status:, record: nil, percent: nil, message: nil, error: nil)
      status = status.to_s
      raise ArgumentError, "status inválido: #{status.inspect}" unless STATES.include?(status)

      percent = normalize_percent(percent, status)
      persist(record, status, percent) if record.present?

      return if project_id.blank?

      ProjectProgressChannel.publish(project_id, {
                                       type: PAYLOAD_TYPE,
                                       job_id: job_id.to_s,
                                       status: status,
                                       percent: percent,
                                       message: message,
                                       error: error
                                     }.compact)
    end

    # Açúcar para o caso mais comum: item N de M.
    def step(project_id:, job_id:, current:, total:, record: nil, message: nil)
      percent = total.to_i.positive? ? ((current.to_f / total) * 100).round : nil
      publish(project_id: project_id, job_id: job_id, status: 'running',
              record: record, percent: percent, message: message)
    end

    def normalize_percent(percent, status)
      # Concluído sem número é 100. Barra parada em 87% com "concluído" escrito ao
      # lado é o tipo de detalhe que faz o usuário duvidar do sistema.
      return 100 if status == 'done'
      return nil if percent.nil?

      percent.to_i.clamp(0, 100)
    end

    def persist(record, status, percent)
      return unless record.class.respond_to?(:job_progressable?) && record.class.job_progressable?

      # `update_columns`: gravar progresso NÃO é evento de domínio. Passar por
      # validação e callback aqui geraria uma versão de `paper_trail` a cada passo
      # de barra — DEC-78 guarda o payload COMPLETO, então seriam milhares de fotos
      # do registro inteiro só para dizer "37%".
      attributes = { job_state: status }
      attributes[:job_progress] = percent unless percent.nil?
      record.update_columns(attributes)
    rescue StandardError => e
      # Progresso é acessório: perder o número não pode derrubar o job que está
      # fazendo o trabalho de verdade.
      Rails.logger.warn("[JobProgress] não foi possível gravar o estado: #{e.class}: #{e.message}")
    end
  end
end
