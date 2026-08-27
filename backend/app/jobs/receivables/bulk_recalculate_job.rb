# frozen_string_literal: true

module Receivables
  # S6 / **OPS-151** — recálculo em lote dos borderôs de um projeto.
  #
  # ## O que o legado tinha
  #
  # Uma rake/console com `ReceivableEntry.all.each(&:save)` — de uma vez, sem
  # lote, sem progresso, com o logger silenciado para "não poluir". Em 28 mil
  # borderôs isso carrega tudo na memória, e cada `save` disparava o
  # `after_commit` que mexe na exposição ao risco: rodá-lo duas vezes criava
  # **movimento duplicado** (D-11).
  #
  # ## O que muda
  #
  # - `find_each` em lotes, com progresso e falhas **visíveis**;
  # - a sincronia de risco é **desligada** por padrão: recalcular número não é o
  #   mesmo que relançar exposição. Quem quiser o efeito colateral pede por
  #   parâmetro, e aí está escolhendo;
  # - o recálculo passa pelo **mesmo `Calculator`** da tela (C2). Não existe uma
  #   segunda fórmula "de lote";
  # - a alíquota de IOF é a **vigente na data do borderô**, não a de hoje
  #   (corrige D-15). É a diferença entre reprocessar e reescrever a história.
  #
  # ## O que ele NÃO faz, e é DEC-36
  #
  # Ele não é o caminho de correção do valor das operações de risco históricas.
  # O **DEC-36** decidiu **copiar** `operation_value` como está no legado, e não
  # recalcular: *"o painel de exposição do ai9 bate 100% com o do legado, e o
  # dado errado vai junto"*. Rodar este job sobre a base carregada com
  # `sync_risk: true` desfaria essa decisão em silêncio — por isso o padrão é
  # `false` e o motivo está escrito aqui.
  class BulkRecalculateJob < ApplicationJob
    queue_as :default

    def perform(project_id, sync_risk: false, batch_size: 500)
      project = Project.find_by(id: project_id)
      return unless project

      total = ReceivableEntry.for_project(project).count
      processados = 0
      alterados = 0
      falhas = []

      ReceivableEntry.for_project(project).includes(:taxes).find_each(batch_size: batch_size) do |entry|
        resultado = recalculate(entry, sync_risk: sync_risk)
        processados += 1
        alterados += 1 if resultado == :changed
        falhas << { id: entry.id, erro: resultado } if resultado.is_a?(String)

        Rails.logger.info("[Receivables::BulkRecalculateJob] #{processados}/#{total}") if (processados % 500).zero?
      end

      Rails.logger.info(
        "[Receivables::BulkRecalculateJob] projeto=#{project_id} processados=#{processados} " \
        "alterados=#{alterados} falhas=#{falhas.size}"
      )
      falhas.each { |f| Rails.logger.error("[Receivables::BulkRecalculateJob] #{f[:id]}: #{f[:erro]}") }

      { processed: processados, changed: alterados, failures: falhas }
    end

    private

    def recalculate(entry, sync_risk:)
      erros = InputGuard.check(entry.calculator_input)
      return erros.to_sentence if erros.any?

      resultado = Calculator.call(entry.calculator_input, iof_rate: IofRate.effective_on(entry.date))
      erros = InputGuard.result_errors(resultado)
      return erros.to_sentence if erros.any?

      antes = entry.slice(*ReceivableEntry::DERIVED_COLUMNS)
      entry.assign_attributes(resultado)
      return :unchanged unless entry.changed?

      ActiveRecord::Base.transaction do
        entry.save!
        RiskSyncService.call!(entry) if sync_risk
      end
      Rails.logger.debug { "[Receivables::BulkRecalculateJob] #{entry.id} mudou: #{antes.keys.inspect}" }
      :changed
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      e.message
    end
  end
end
