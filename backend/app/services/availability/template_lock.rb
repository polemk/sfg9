# frozen_string_literal: true

module Availability
  # S11 / BE-147, DB-128, DB-129 — **o serviço único de bloqueio de padrão**.
  #
  # ## O defeito que este arquivo existe para fechar (D-05)
  #
  # O legado tinha quatro operações em segundo plano — ativar, desativar,
  # remover e propagar — e **quatro implementações** do mesmo par
  # bloquear/desbloquear. Em três delas o `unlocked!` era chamado **só no
  # caminho feliz** (`project_availability_template.rb:718`, `:786`), e na
  # quarta — `background_removal` — **não era chamado nunca**. Somado a
  # `destroy_failed_jobs? false` e à exceção engolida, uma falha deixava o
  # padrão **bloqueado para sempre**, sem caminho de recuperação pela interface.
  #
  # A regra aqui é uma só e vale para os quatro jobs:
  #
  #     Availability::TemplateLock.around(template, motivo: '…', actor: usuário) do
  #       # trabalho
  #     end
  #
  # O `unlock!` roda em **`ensure`**. Com exceção, sem exceção, com `raise` do
  # Sidekiq no meio do retry: o padrão termina utilizável. `spec/jobs/` tem um
  # teste que **força a exceção** em cada um dos quatro e confere isso — é o
  # teste que fecha o "bloqueado para sempre".
  #
  # ## Estado da tarefa (DB-129)
  #
  # `job_state` é `enum` string de conjunto fechado
  # (`pending`/`running`/`done`/`failed`). O legado usava texto livre em pt-BR
  # (`"Concluido"`, sem acento), guardava array Ruby numa coluna de texto e
  # tinha `job_id` como FK para `delayed_jobs` — tabela que não existe no ai9
  # (DB-460). O relatório de falha vira `jsonb` estruturado.
  class TemplateLock
    class AlreadyLocked < StandardError; end

    class << self
      # Bloqueia, executa, **desbloqueia em `ensure`**.
      #
      # `job_id` identifica a operação para o `Sfg::JobProgress` e, por
      # consequência, para o `useJobProgress` na tela.
      def around(template, motivo:, actor: nil, job_id: nil, &)
        identificador = job_id || default_job_id(template)
        lock!(template, motivo: motivo, actor: actor)
        start!(template, job_id: identificador)

        begin
          resultado = yield
          finish!(template, job_id: identificador)
          resultado
        rescue StandardError => e
          fail!(template, job_id: identificador, error: e)
          raise
        ensure
          # **A linha que fecha o D-05.** Nunca mova para dentro do `begin`.
          unlock!(template)
        end
      end

      def lock!(template, motivo:, actor: nil)
        template.lock!(motivo, actor: actor)
      end

      # Idempotente: desbloquear o que já está desbloqueado não é erro, e
      # desbloquear o que a própria operação destruiu também não (OPS-124).
      def unlock!(template)
        template.unlock!
      rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid => e
        Rails.logger.info("[Availability::TemplateLock] nada a desbloquear: #{e.class} #{e.message}")
        true
      end

      def start!(template, job_id:)
        Sfg::JobProgress.publish(project_id: template.project_id, job_id: job_id,
                                 status: 'running', record: template, percent: 0)
      end

      def step!(template, job_id:, current:, total:, message: nil)
        Sfg::JobProgress.step(project_id: template.project_id, job_id: job_id,
                              current: current, total: total, record: template, message: message)
      end

      def finish!(template, job_id:, message: nil)
        Sfg::JobProgress.publish(project_id: template.project_id, job_id: job_id,
                                 status: 'done', record: template, message: message)
        write_report!(template, { state: 'done', finished_at: Time.current.iso8601 })
      end

      def fail!(template, job_id:, error:)
        Sfg::JobProgress.publish(project_id: template.project_id, job_id: job_id,
                                 status: 'failed', record: template, error: error.message)
        write_report!(template, { state: 'failed', error_class: error.class.name,
                                  error_message: error.message, failed_at: Time.current.iso8601 })
      end

      def default_job_id(template)
        "availability_template:#{template.id}"
      end

      private

      # `update_columns` de propósito: o relatório do job não é edição do
      # usuário e não deve disparar validação nem trilha de auditoria. E o
      # registro pode já ter sido destruído pela própria operação — o legado
      # gravava estado sobre registro destruído e levantava (OPS-124).
      def write_report!(template, payload)
        return unless AvailabilityTemplate.exists?(id: template.id)

        # **Hash, nunca `to_json`.** A coluna é `jsonb`: passar uma String faz o
        # Rails codificar de novo e guardar um escalar JSON, e a leitura volta
        # texto em vez de objeto.
        AvailabilityTemplate.where(id: template.id)
                            .update_all(job_report: payload, updated_at: Time.current)
      end
    end
  end
end
