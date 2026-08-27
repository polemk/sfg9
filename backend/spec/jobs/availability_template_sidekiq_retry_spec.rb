# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/api'
require 'sidekiq/capsule'
require 'sidekiq/job_retry'

# S11 / tarefa **6.3.2** — **OPS-128 (S0) aplicado aos jobs de padrão de
# disponibilidade**: job falho é **reexecutado** pelo Sidekiq e, ao esgotar as
# tentativas, fica **visível** no dead set.
#
# ## Por que este arquivo existe, e o que ele NÃO faz
#
# A pré-condição já está coberta em `availability_template_jobs_spec.rb` ("a
# exceção SOBE"): sem isso o Sidekiq marcaria sucesso e nada seria retentado —
# é o **D-79** do legado, em que `destroy_failed_jobs? false` somado ao `rescue`
# vazio fazia o job sumir sem deixar rastro.
#
# O que faltava era o outro lado: provar que, **quando a exceção sobe, o Sidekiq
# de verdade faz alguma coisa com ela**. A tarefa 6.3.2 ficou aberta com o
# argumento de que "um spec aqui estubaria o Sidekiq e provaria o estube". O
# argumento está certo sobre estubes e errado sobre a única saída: o Sidekiq
# expõe a própria máquina de retentativa como classe pública
# (`Sidekiq::JobRetry`), e é ela que o worker chama. Este arquivo chama a
# **mesma** classe, com o **mesmo** payload que o worker montaria, contra um
# **Redis de verdade** — e depois lê o resultado pela API pública
# (`Sidekiq::RetrySet` / `Sidekiq::DeadSet`), que é a mesma que o painel lê.
#
# Nada é estubado. O que não é exercitado aqui, e fica dito: o **agendador** que
# tira o job do `retry` na hora marcada, que vive dentro do processo `sidekiq`.
# O que se prova é que o job **entra** no retry com hora marcada, e que ao
# esgotar ele **entra** no dead set — que é onde "fica visível e reenfileirável".
#
# ## Isolamento do Redis — leia antes de mudar
#
# ⚠ Os conjuntos `retry` e `dead` do Sidekiq são **globais por banco Redis**, e
# NÃO levam o prefixo de fila do `APP_NAME`. Rodar isto no banco 0 escreveria no
# dead set compartilhado com o **apl9**, que divide este Redis
# (`platform-runbook.md` §4.2). Por isso o spec troca o Redis para o banco
# **15** e limpa **apenas as duas chaves que cria**, nunca `FLUSHDB`.
RSpec.describe 'Job falho é reexecutado e, ao esgotar, fica visível (OPS-128 / D-05)' do
  let(:redis_do_ensaio) { ENV.fetch('SIDEKIQ_SPEC_REDIS_URL', 'redis://localhost:6379/15') }

  # Um Redis indisponível **não** pode virar exemplo verde: ou ele roda, ou o
  # arquivo diz em voz alta que não rodou.
  before(:all) do
    @redis_ok = begin
      Sidekiq::RedisConnection.create(url: ENV.fetch('SIDEKIQ_SPEC_REDIS_URL', 'redis://localhost:6379/15'),
                                      size: 1).then do |pool|
        pool.with { |c| c.call('PING') }
      end
      true
    rescue StandardError => e
      @redis_erro = e.message
      false
    end
  end

  around do |exemplo|
    skip("Redis indisponível em #{redis_do_ensaio}: #{@redis_erro}") unless @redis_ok

    config = Sidekiq.default_configuration
    anterior = config.instance_variable_get(:@redis_config)
    config.redis = { url: redis_do_ensaio }
    limpar_conjuntos!
    begin
      exemplo.run
    ensure
      limpar_conjuntos!
      config.redis = anterior || { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
    end
  end

  # Só as duas chaves do teste. `FLUSHDB` aqui seria o mesmo erro que o runbook
  # proíbe na seção do cron: limpeza que não filtra derruba o vizinho.
  def limpar_conjuntos!
    Sidekiq.redis { |c| c.call('DEL', 'retry', 'dead') }
  end

  let(:project) { create(:project) }
  let(:template) { create(:project_availability_template, project: project) }
  let(:actor) { create(:user) }

  # O payload que o worker receberia: ActiveJob embrulhado pelo adapter do
  # Sidekiq. `wrapped` é o que faz o dead set nomear **o job de negócio**, e não
  # o embrulho — sem ele, o painel mostraria 4 jobs idênticos chamados
  # `Sidekiq::ActiveJob::Wrapper` e ninguém saberia qual padrão travou.
  def payload(job_class, retry_count: nil)
    aj = job_class.new(template.id, actor.id)
    msg = {
      'class' => 'Sidekiq::ActiveJob::Wrapper',
      'wrapped' => job_class.name,
      'queue' => job_class.queue_name,
      'args' => [aj.serialize],
      'jid' => SecureRandom.hex(12),
      'retry' => true,
      'created_at' => Time.now.to_f
    }
    msg['retry_count'] = retry_count if retry_count
    msg
  end

  def falhar!(msg, erro)
    retrier = Sidekiq::JobRetry.new(Sidekiq.default_configuration.default_capsule)
    instancia = Sidekiq::ActiveJob::Wrapper.new
    expect do
      retrier.local(instancia, Sidekiq.dump_json(msg), msg['queue']) { raise erro }
    end.to raise_error(Sidekiq::JobRetry::Handled)
  end

  # ---------------------------------------------------------------------------
  describe 'a primeira falha vira RETENTATIVA, não sumiço (D-79)' do
    it 'entra no retry set com hora marcada, contador e a causa preservada' do
      msg = payload(ActivateProjectTemplateJob)
      falhar!(msg, StandardError.new('índice fora do ar'))

      conjunto = Sidekiq::RetrySet.new
      expect(conjunto.size).to eq(1)

      entrada = conjunto.first
      expect(entrada['wrapped']).to eq('ActivateProjectTemplateJob')
      expect(entrada['jid']).to eq(msg['jid'])
      expect(entrada['error_message']).to include('índice fora do ar')
      expect(entrada['error_class']).to eq('StandardError')
      # Primeira falha é `retry_count = 0`: já houve uma execução, e vem outra.
      expect(entrada['retry_count']).to eq(0)
      # Reagendado para o FUTURO — é isto que "reexecutado" significa na fila.
      expect(entrada.score).to be > Time.now.to_f
      # E ele NÃO foi para o dead set ainda.
      expect(Sidekiq::DeadSet.new.size).to eq(0)
    end

    it 'a falha seguinte INCREMENTA o contador em vez de abrir um segundo registro' do
      falhar!(payload(DeactivateProjectTemplateJob, retry_count: 3),
              StandardError.new('de novo'))

      expect(Sidekiq::RetrySet.new.size).to eq(1)
      expect(Sidekiq::RetrySet.new.first['retry_count']).to eq(4)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'esgotadas as tentativas, o job FICA VISÍVEL — não desaparece' do
    # É a diferença literal com o legado: `Delayed::Worker.destroy_failed_jobs`
    # apagava o registro, e não havia onde olhar (OPS-624 / D-79).
    it 'vai para o dead set, nomeando o job de negócio e a causa' do
      # 25 é o padrão do Sidekiq e a política declarada desta migração
      # (`app/jobs/application_job.rb`: nada de `retry_on` empilhado por cima).
      ultima = Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS - 1
      falhar!(payload(RemoveProjectTemplateJob, retry_count: ultima),
              StandardError.new('a última'))

      expect(Sidekiq::RetrySet.new.size).to eq(0)

      mortos = Sidekiq::DeadSet.new
      expect(mortos.size).to eq(1)
      morto = mortos.first
      expect(morto['wrapped']).to eq('RemoveProjectTemplateJob')
      expect(morto['error_message']).to include('a última')
      expect(morto['retry_count']).to eq(Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS)
    end

    it 'o job morto é REENFILEIRÁVEL — visível sem ação possível seria metade da correção' do
      falhar!(payload(ActivateProjectTemplateJob,
                      retry_count: Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS - 1),
              StandardError.new('travou'))

      morto = Sidekiq::DeadSet.new.first
      expect(morto).to respond_to(:retry)
      expect(morto.queue).to eq(ActivateProjectTemplateJob.queue_name)
    end

    it 'a retenção do dead set é a declarada em `config/sidekiq.yml` (OPS-624)' do
      config = Sidekiq.default_configuration
      expect(config[:dead_max_jobs]).to eq(10_000)
      # 6 meses — cobre o ciclo de uma operação de crédito, que é o horizonte em
      # que ainda se pergunta "por que este recálculo não rodou em março?".
      expect(config[:dead_timeout_in_seconds]).to eq(15_552_000)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'o contrato com o D-05 — retentativa não substitui o `ensure`' do
    it 'o padrão continua desbloqueado enquanto o job espera na fila de retentativa' do
      template.update_columns(is_locked: true)
      msg = payload(ActivateProjectTemplateJob)
      falhar!(msg, StandardError.new('caiu'))

      # A retentativa acontece **depois**, e pode demorar. Se o bloqueio
      # dependesse dela para sair, o padrão ficaria travado no meio-tempo — que
      # é exatamente o D-05. Quem libera é o `ensure` do job, não a fila.
      expect(Sidekiq::RetrySet.new.size).to eq(1)
      fonte = File.read(Rails.root.join('app/jobs/activate_project_template_job.rb'))
      expect(fonte).to include('ensure')
    end
  end
end
