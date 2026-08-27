# frozen_string_literal: true

require 'sidekiq/api'

module Sfg
  # **Existe worker do Sidekiq servindo ESTE app?**
  #
  # ## O defeito que este arquivo existe para tornar visível
  #
  # Medido em 26/08/2026, no banco de desenvolvimento: desativar um padrão de
  # disponibilidade respondia **202**, travava seis nós pelo `TemplateLock` e o
  # job ficava na fila **para sempre** — a tela travava na frente do cliente. O
  # código dos dois jobs estava certo (rodados à mão, travam, reconsolidam e
  # liberam no `ensure`). O que faltava era **processo consumindo a fila**.
  #
  # ## Por que `pgrep sidekiq` responde a pergunta ERRADA
  #
  # Vários apps dividem o mesmo Redis, e as filas são prefixadas por `APP_NAME`
  # justamente por isso (`config/sidekiq.yml`). No dia da medição havia um
  # processo `sidekiq` vivo na máquina — apontando para **outro banco e outro
  # `APP_NAME`**. `pgrep` dizia "tem worker", `Sidekiq::ProcessSet` (que é global
  # ao Redis) também, e o app de desenvolvimento continuava sem nenhum.
  #
  # A pergunta que decide é outra: **cada fila que este app ENFILEIRA está na
  # lista de alguma execução viva?** É isso que `report` responde.
  #
  # ## Por que existe uma SEGUNDA fonte, e não só o Redis
  #
  # `Sidekiq::ProcessSet` lê o *heartbeat*, uma chave com TTL de 60 s. Nesta
  # máquina o Redis é compartilhado com outros apps e outros agentes, e foi
  # **medido** que essas chaves somem: doze leituras em 36 s acharam o heartbeat
  # do worker vivo em **três**. Quem apaga é limpeza ampla de terceiro (`FLUSHDB`
  # e afins — o mesmo risco que o `platform-runbook.md` §4.2 já registra para o
  # agendamento). Com uma fonte só, este diagnóstico diria "sem worker" com o
  # worker rodando — e um diagnóstico que erra é pior do que nenhum.
  #
  # Por isso a checagem local: processos `sidekiq` **desta árvore** (mesmo
  # `Rails.root`), com `APP_NAME` igual ao nosso ou herdado do `.env`. Não é o
  # `pgrep` ingênuo — é `pgrep` mais as duas perguntas que o `pgrep` não faz.
  # Vale só na mesma máquina, que é onde o problema aparece (desenvolvimento).
  #
  # Não é autorização nem portão de suíte: é diagnóstico de operação, chamado
  # por `rails sidekiq:health` antes de apresentar.
  module WorkerHealth
    Report = Struct.new(:expected_queues, :processes, :missing_queues, :local_workers,
                        keyword_init: true) do
      # O Redis é a fonte boa quando ele responde; a máquina é a rede de baixo.
      def ok? = expected_queues.any? && (missing_queues.empty? || local_workers.any?)

      def by_redis? = expected_queues.any? && missing_queues.empty?

      # Só há worker de OUTRO app no Redis: o caso que engana o `pgrep`.
      def foreign_only? = !by_redis? && processes.any?
    end

    module_function

    # As filas vêm do **mesmo arquivo** que o processo lê, com o mesmo ERB — ler
    # daqui uma segunda lista de filas seria garantir que as duas divergissem no
    # dia em que alguém acrescentasse uma.
    def expected_queues(path = Rails.root.join('config/sidekiq.yml'))
      raw = ERB.new(File.read(path)).result
      data = YAML.safe_load(raw, permitted_classes: [Symbol], aliases: true) || {}
      queues = data[:queues] || data[':queues'] || data['queues'] || []
      Array(queues).map { |entry| Array(entry).first.to_s }
    end

    # `Sidekiq::ProcessSet` é do REDIS INTEIRO, não deste app — daí `queues` vir
    # junto: é o campo que diz de quem é cada processo.
    def processes
      Sidekiq::ProcessSet.new.map do |process|
        { identity: process['identity'].to_s, queues: Array(process['queues']).map(&:to_s) }
      end
    rescue StandardError => e
      # Redis fora do ar é uma resposta legítima para "tem worker?": é **não**.
      Rails.logger.warn("[Sfg::WorkerHealth] não foi possível ler o ProcessSet: #{e.message}")
      []
    end

    # Processos `sidekiq` DESTA árvore, na máquina. Só Linux (`/proc`), que é o
    # ambiente de desenvolvimento desta migração; noutro sistema devolve vazio e
    # o relatório fica só com o Redis.
    def local_workers
      return [] unless File.directory?('/proc')

      pids_de_sidekiq.filter_map { |pid| deste_app?(pid) }
    end

    # As duas perguntas que o `pgrep` não faz: é desta árvore? é do nosso
    # `APP_NAME`? `APP_NAME` ausente no `environ` significa que veio do `.env`
    # **depois** do `exec` — ou seja, é o mesmo `.env` que este processo leu.
    def deste_app?(pid)
      nosso_app = ENV.fetch('APP_NAME', 'ai9')
      return nil unless File.realpath("/proc/#{pid}/cwd") == Rails.root.realpath.to_s

      deles = env_de(pid)['APP_NAME']
      return nil if deles.present? && deles != nosso_app

      { pid: pid, app_name: deles || "#{nosso_app} (do .env)" }
    rescue StandardError
      nil
    end

    def report
      esperadas = expected_queues
      vivos = processes
      atendidas = vivos.flat_map { |process| process[:queues] }.uniq
      faltando = esperadas - atendidas

      Report.new(expected_queues: esperadas, processes: vivos, missing_queues: faltando,
                 local_workers: faltando.empty? ? [] : local_workers)
    end

    def pids_de_sidekiq
      Dir.glob('/proc/[0-9]*/cmdline').filter_map do |caminho|
        next unless worker_cmdline?(File.read(caminho).tr("\0", ' '))

        caminho[%r{/proc/(\d+)/}, 1].to_i
      rescue StandardError
        next
      end
    end

    # **"Menciona sidekiq" não basta** — e este método existe porque a primeira
    # versão aceitava isso e listou como worker o `bash -c` que LANÇOU um worker
    # (e que, por ter recebido o `APP_NAME` via `env` só no filho, ainda parecia
    # ser do nosso app). O `rails sidekiq:health` casaria pelo nome da tarefa.
    #
    # O Sidekiq reescreve o proctitle para `sidekiq 8.0.10 backend [0 of 5 busy]`
    # assim que sobe; antes disso o executável é `…/bin/sidekiq`. Só esses dois
    # são worker.
    def worker_cmdline?(linha)
      primeiro = linha.strip.split(/\s+/).first.to_s
      primeiro == 'sidekiq' || File.basename(primeiro) == 'sidekiq'
    end

    def env_de(pid)
      File.read("/proc/#{pid}/environ").split("\0").filter_map do |par|
        chave, valor = par.split('=', 2)
        [chave, valor] if valor
      end.to_h
    rescue StandardError
      {}
    end
  end
end
