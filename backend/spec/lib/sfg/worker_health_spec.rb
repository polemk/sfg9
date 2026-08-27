# frozen_string_literal: true

require 'rails_helper'

# **A armadilha que deixou a demonstração sem worker.**
#
# Em 26/08/2026 a tela travou na frente do cliente: desativar um padrão de
# disponibilidade respondia 202 e o job nunca saía da fila. Havia um processo
# `sidekiq` vivo na máquina — de **outro app, noutro banco**, no mesmo Redis. Um
# `pgrep sidekiq` respondia "tem worker", `Sidekiq::ProcessSet.size` também, e o
# app de desenvolvimento continuava sem nenhum.
#
# Os dois sinais fáceis são, portanto, os dois errados. O que separa os casos é
# comparar a lista de filas do processo com a lista de filas DESTE app — e é
# essa comparação que estes exemplos travam. Sem eles a checagem "existe worker"
# volta a ser `ProcessSet.any?` na primeira vez que alguém a reescrever.
#
# A segunda metade dos exemplos trava a **rede de baixo**: nesta máquina o Redis
# é compartilhado e as chaves de heartbeat somem por limpeza de terceiro (medido:
# 3 de 12 leituras em 36 s acharam o heartbeat de um worker vivo). Sem a checagem
# local, o diagnóstico diria "sem worker" com o worker rodando.
RSpec.describe Sfg::WorkerHealth do
  let(:prefixo) { ENV.fetch('APP_NAME', 'ai9') }
  let(:minhas_filas) { described_class.expected_queues }

  # Os dois sinais são sempre encenados: sem isto o exemplo lê a máquina em que
  # a suíte roda e passa (ou reprova) por acidente do ambiente.
  def com(redis: [], locais: [])
    allow(described_class).to receive(:processes).and_return(redis)
    allow(described_class).to receive(:local_workers).and_return(locais)
  end

  describe '.expected_queues' do
    it 'vem do mesmo config/sidekiq.yml que o processo lê, com o APP_NAME já resolvido' do
      expect(minhas_filas).to include("#{prefixo}_default", "#{prefixo}_low_priority")
      expect(minhas_filas).to all(start_with("#{prefixo}_"))
    end

    # `low_priority` é a fila do `DeactivateProjectTemplateJob` — o job que ficou
    # preso. Fila que o app usa e o arquivo não declara é o mesmo defeito por
    # outro caminho, e está registrado no cabeçalho do `config/sidekiq.yml`.
    it 'declara a fila dos jobs de baixa prioridade' do
      expect(minhas_filas).to include("#{prefixo}_low_priority")
    end
  end

  describe '.report' do
    it 'sem nenhum processo, em lugar nenhum: reprova e nomeia todas as filas' do
      com(redis: [], locais: [])
      report = described_class.report

      expect(report).not_to be_ok
      expect(report).not_to be_foreign_only
      expect(report.missing_queues).to match_array(minhas_filas)
    end

    # **O exemplo que dá nome a este arquivo.** Um processo vivo, no mesmo Redis,
    # servindo as filas de outro app: `pgrep` aprova, este relatório reprova.
    it 'worker de OUTRO app no mesmo Redis NÃO conta como worker deste app' do
      com(redis: [{ identity: 'vinao:630384:e63ba06ebfd9',
                    queues: %w[sfg9s13_default sfg9s13_low_priority] }])
      report = described_class.report

      expect(report).not_to be_ok
      expect(report).to be_foreign_only
      expect(report.missing_queues).to match_array(minhas_filas)
    end

    it 'worker deste app, com todas as filas: aprova, e pelo Redis' do
      com(redis: [{ identity: 'vinao:1:aaa', queues: minhas_filas }])
      report = described_class.report

      expect(report).to be_ok
      expect(report).to be_by_redis
    end

    # Meio worker é o pior caso: a maioria dos jobs anda, e só a fila esquecida
    # empilha em silêncio — foi assim que `low_priority` sumiu no brsw e no facil.
    it 'worker que serve só PARTE das filas reprova, nomeando apenas a que falta' do
      com(redis: [{ identity: 'vinao:1:aaa', queues: minhas_filas - ["#{prefixo}_low_priority"] }])
      report = described_class.report

      expect(report).not_to be_ok
      expect(report.missing_queues).to eq(["#{prefixo}_low_priority"])
    end

    it 'heartbeat sumido do Redis não vira "sem worker" quando a máquina tem o processo' do
      com(redis: [], locais: [{ pid: 1_038_352, app_name: "#{prefixo} (do .env)" }])
      report = described_class.report

      expect(report).to be_ok
      expect(report).not_to be_by_redis
      expect(report.local_workers.size).to eq(1)
    end

    it 'não consulta a máquina quando o Redis já respondeu que está tudo servido' do
      allow(described_class).to receive(:processes)
        .and_return([{ identity: 'vinao:1:aaa', queues: minhas_filas }])
      expect(described_class).not_to receive(:local_workers)

      expect(described_class.report).to be_ok
    end

    it 'Redis fora do ar responde "não há worker", em vez de estourar' do
      allow(Sidekiq::ProcessSet).to receive(:new).and_raise(RuntimeError, 'Error connecting to Redis')
      allow(described_class).to receive(:local_workers).and_return([])

      expect(described_class.processes).to eq([])
      expect(described_class.report).not_to be_ok
    end
  end

  describe '.local_workers' do
    # `Rails.root.realpath` também passa por `File.realpath`: sem o default o
    # `with` de baixo derruba a própria leitura da raiz.
    before { allow(File).to receive(:realpath).and_call_original }

    # A diferença para o `pgrep` ingênuo: o processo tem de estar NESTA árvore e
    # com o MESMO `APP_NAME`. O worker do vizinho passa no `pgrep` e reprova aqui.
    it 'descarta processo sidekiq com APP_NAME de outro app' do
      allow(described_class).to receive(:pids_de_sidekiq).and_return([4242])
      allow(File).to receive(:realpath).with('/proc/4242/cwd').and_return(Rails.root.realpath.to_s)
      allow(described_class).to receive(:env_de).with(4242).and_return({ 'APP_NAME' => 'sfg9s13' })

      expect(described_class.local_workers).to be_empty
    end

    it 'aceita processo desta árvore que herdou o APP_NAME do .env' do
      allow(described_class).to receive(:pids_de_sidekiq).and_return([4242])
      allow(File).to receive(:realpath).with('/proc/4242/cwd').and_return(Rails.root.realpath.to_s)
      allow(described_class).to receive(:env_de).with(4242).and_return({})

      expect(described_class.local_workers.map { |w| w[:pid] }).to eq([4242])
    end

    # Regressão medida: a primeira versão aceitava qualquer linha que MENCIONASSE
    # "sidekiq" e listou como worker o `bash -c` que lançou um — que, tendo
    # passado o `APP_NAME` ao filho via `env`, ainda parecia ser do nosso app.
    it 'só reconhece worker de verdade, não quem apenas MENCIONA sidekiq' do
      aceitos = ['sidekiq 8.0.10 backend [0 of 5 busy]',
                 '/home/vinao/.rvm/gems/ruby-3.4.9/bin/sidekiq -C config/sidekiq.yml']
      recusados = ['/bin/bash -c cd backend && bundle exec sidekiq -C config/sidekiq.yml',
                   '/home/vinao/.rvm/rubies/ruby-3.4.9/bin/ruby bin/rails sidekiq:health',
                   'grep -af sidekiq']

      aceitos.each { |linha| expect(described_class.worker_cmdline?(linha)).to be(true), linha }
      recusados.each { |linha| expect(described_class.worker_cmdline?(linha)).to be(false), linha }
    end

    it 'descarta processo sidekiq de OUTRA árvore' do
      allow(described_class).to receive(:pids_de_sidekiq).and_return([4242])
      allow(File).to receive(:realpath).with('/proc/4242/cwd').and_return('/home/vinao/workspace/apl9/backend')
      allow(described_class).to receive(:env_de).with(4242).and_return({})

      expect(described_class.local_workers).to be_empty
    end
  end
end
