# frozen_string_literal: true

require 'rails_helper'

# S13 / OPS-472, OPS-624 — portão da FILA do agendamento.
#
# O portão que já existia (`config/initializers/sidekiq_cron.rb`) confere se a
# **classe** agendada existe. Ele não pegava — e não tinha como pegar — o defeito
# medido em 25/08/2026: o cron disparava, o job era enfileirado numa fila
# **duplamente prefixada** (`ai9_ai9_default`) e nenhum worker o consumia.
#
# Contagem na fila morta naquele dia: 441 `DriveIngestionJob`, 441
# `PublishScheduledDraftsJob`, 221 `BlogIntakeSessionExpiryJob` e **56
# `CleanupLoginCodesJob`** — a limpeza de códigos de login nunca tinha rodado, nem
# uma vez, e nada denunciava.
#
# A causa: `sidekiq-cron` 2.4.0, quando a entrada não declara `queue:`, lê a fila da
# própria classe — e `ActiveJob` devolve o nome **já prefixado**. O gem então chama
# `set(queue: "ai9_default")`, e o `queue_name_prefix` de `config/application.rb` é
# aplicado de novo.
RSpec.describe 'config/schedule.yml — fila de cada cron' do
  let(:schedule) do
    YAML.safe_load(ERB.new(File.read(Rails.root.join('config/schedule.yml'))).result, aliases: true) || {}
  end

  let(:declared_queues) do
    raw = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/sidekiq.yml'))).result,
                         aliases: true, permitted_classes: [Symbol])
    Array(raw[:queues] || raw['queues']).map(&:to_s)
  end

  let(:prefix) { "#{ActiveJob::Base.queue_name_prefix}#{ActiveJob::Base.queue_name_delimiter}" }

  it 'toda entrada declara `queue`' do
    sem_fila = schedule.reject { |_, definition| definition.is_a?(Hash) && definition['queue'].present? }.keys

    expect(sem_fila).to be_empty,
                        "Crons sem `queue:` declarada: #{sem_fila.join(', ')}. " \
                        'Sem ela o sidekiq-cron reusa o nome já prefixado da classe e a fila sai dobrada.'
  end

  it 'a fila declarada NÃO vem prefixada — o ActiveJob prefixa uma vez' do
    dobradas = schedule.select do |_, definition|
      definition.is_a?(Hash) && definition['queue'].to_s.start_with?(prefix)
    end.keys

    expect(dobradas).to be_empty,
                        "Crons com fila já prefixada: #{dobradas.join(', ')}. " \
                        "Declare `queue: default`, não `queue: #{prefix}default`."
  end

  it 'a fila resultante existe em config/sidekiq.yml — senão o job empilha para sempre' do
    faltando = schedule.filter_map do |name, definition|
      next unless definition.is_a?(Hash)

      fila = "#{prefix}#{definition['queue']}"
      "#{name} → #{fila}" unless declared_queues.include?(fila)
    end

    expect(faltando).to be_empty,
                        "Filas de cron ausentes de config/sidekiq.yml: #{faltando.join(', ')}"
  end

  it 'a fila declarada bate com o `queue_as` da própria classe do job' do
    # Divergência aqui não quebra nada hoje — as duas filas existem —, mas faz o job
    # rodar num lugar quando agendado e noutro quando chamado à mão, o que
    # transforma qualquer investigação de "onde foi parar" em caça ao tesouro.
    divergentes = schedule.filter_map do |name, definition|
      next unless definition.is_a?(Hash)

      klass = definition['class'].to_s.safe_constantize
      next if klass.nil?

      esperada = klass.queue_name.to_s.delete_prefix(prefix)
      "#{name}: schedule diz #{definition['queue']}, a classe diz #{esperada}" if esperada != definition['queue'].to_s
    end

    expect(divergentes).to be_empty, divergentes.join('; ')
  end
end
