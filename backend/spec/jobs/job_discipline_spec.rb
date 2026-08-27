# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefa 3.14, contrato **D-C** — portão de disciplina dos jobs.
#
# Não testa comportamento: testa que ninguém reintroduziu o **D-79**. É um portão de
# leitura de código, e ele existe porque o antipadrão é fácil de reintroduzir por
# analogia: `ai9-conventions.md` §3.7 traz como exemplo canônico um job com
# `rescue StandardError => e; Rails.logger.error(...)` **sem `raise`**.
#
# Quando este exemplo reprovar, a correção é acrescentar `raise` — não acrescentar o
# arquivo à lista de exceções.
RSpec.describe 'Disciplina dos jobs' do
  JOB_FILES = Dir[Rails.root.join('app/jobs/**/*.rb')].sort

  # `rescue` LARGO: bare `rescue`, `rescue => e` ou `rescue StandardError`. É a
  # forma do D-79 — captura tudo, inclusive o que ninguém previu. `rescue` de erro
  # ESPECÍFICO e esperado (`ActiveRecord::RecordNotUnique` numa corrida de índice
  # único, por exemplo) é tratamento de caso conhecido, não é engolir, e por isso
  # não entra na varredura.
  RESCUE_LARGO = /^\s*rescue\s*(?:$|=>|StandardError\b|#)/

  # Exceções nominais, com o motivo escrito. **Corrigir um job é acrescentar `raise`,
  # nunca acrescentar o arquivo a esta lista.**
  RESCUE_SEM_RAISE_PERMITIDO = {
    # O `rescue_from DeserializationError` é o caso conhecido-e-sem-conserto:
    # registro apagado entre enfileirar e executar. Ele LOGA, que é justamente o
    # que o D-79 não fazia.
    'application_job.rb' => 'registro removido antes da execução (documentado no arquivo)',
    # Expurgo: tolerância deliberada à tabela que outra fatia ainda não criou.
    'purge_email_logs_job.rb' => 'tolerância deliberada à tabela ainda inexistente',
    # Job da BASE ai9 (WhatsApp, DEC-83), fora desta fatia. Ele não engole de todo:
    # reenfileira a si mesmo até MAX_ATTEMPTS, que é uma política de retentativa
    # própria. Fica registrado aqui para que a decisão seja visível — e para que
    # um job NOVO com o mesmo formato reprove.
    'evolution_reconnect_job.rb' => 'job da base ai9, com reenfileiramento próprio limitado'
  }.freeze

  it 'nenhum job engole exceção sem relançar (D-79)' do
    infratores = JOB_FILES.filter_map do |path|
      nome = File.basename(path)
      next if RESCUE_SEM_RAISE_PERMITIDO.key?(nome)

      fonte = File.read(path)
      next unless fonte.match?(RESCUE_LARGO)
      next if fonte.match?(/\braise\b/)

      nome
    end

    expect(infratores).to be_empty,
                          "Jobs com `rescue` sem `raise` (D-79): #{infratores.join(', ')}. " \
                          'Em job do Safegold, `rescue` enriquece o log e SEMPRE relança.'
  end

  it 'nenhum job usa uma fila que não está declarada em config/sidekiq.yml' do
    declaradas = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/sidekiq.yml'))).result,
                                aliases: true, permitted_classes: [Symbol])
    prefixo = "#{ENV.fetch('APP_NAME', 'ai9')}_"
    nomes = Array(declaradas[:queues] || declaradas['queues']).map { |q| q.to_s.delete_prefix(prefixo) }

    usadas = JOB_FILES.flat_map { |path| File.read(path).scan(/queue_as\s+:(\w+)/).flatten }.uniq

    # Fila não declarada = job enfileirado que NENHUM worker consome. Ele empilha
    # para sempre e não aparece em erro nenhum.
    expect(usadas - nomes).to be_empty,
                              "Filas usadas e não declaradas em config/sidekiq.yml: #{(usadas - nomes).join(', ')}"
  end
end
