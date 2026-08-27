# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefa 3.8 — **timeout de bloqueio** (melhoria de OPS-469 e OPS-470).
#
# O `ensure` do `Availability::TemplateLock` já cobre exceção. O que este job
# cobre é o caso em que **nenhum `ensure` roda**: o worker morre de `SIGKILL`, o
# container é reciclado, a máquina cai. O padrão fica `is_locked` para sempre e a
# interface não oferece saída — o estado terminal do legado (D-05) chegando por
# outra porta.
RSpec.describe UnlockStaleTemplatesJob do
  let(:project) { create(:project) }

  def travado_ha(minutos, **atributos)
    template = create(:project_availability_template, project: project, **atributos)
    AvailabilityTemplate.where(id: template.id).update_all(
      is_locked: true, locked_at: minutos.minutes.ago, locked_message: 'Removendo o padrão.',
      job_state: 'running', job_progress: 37
    )
    template.reload
  end

  it 'padrão travado DENTRO do prazo continua travado — não se destrava operação em curso' do
    recente = travado_ha(5)

    described_class.perform_now

    expect(recente.reload.is_locked).to be(true)
    expect(recente.job_state).to eq('running')
  end

  it 'padrão travado ALÉM do prazo é liberado' do
    preso = travado_ha(described_class.timeout_minutes + 5)

    expect { described_class.perform_now }.to change { preso.reload.is_locked }.from(true).to(false)
    expect(preso.locked_at).to be_nil
    expect(preso.locked_message).to be_nil
  end

  it 'o MOTIVO fica escrito — destravar calado só troca um mistério por outro' do
    preso = travado_ha(described_class.timeout_minutes + 30)

    described_class.perform_now

    relatorio = preso.reload.job_report
    expect(preso.job_state).to eq('failed')
    expect(relatorio['reason']).to eq('lock_timeout')
    expect(relatorio['timeout_minutes']).to eq(described_class.timeout_minutes)
    expect(relatorio['locked_for_minutes']).to be >= described_class.timeout_minutes
    expect(relatorio['message']).to include('não terminou')
    expect(relatorio['released_at']).to be_present
  end

  it 'a tela aberta é avisada pelo CABO — sem polling (tarefa 8.4)' do
    preso = travado_ha(described_class.timeout_minutes + 1)

    expect { described_class.perform_now }
      .to have_broadcasted_to(ProjectProgressChannel.stream_name_for(project.id))
      .with(hash_including(status: 'failed', job_id: "availability_template:#{preso.id}"))
      .exactly(:once)
  end

  it '`is_locked` sem `locked_at` também sai — travado sem prazo é travado para sempre' do
    template = create(:project_availability_template, project: project)
    AvailabilityTemplate.where(id: template.id).update_all(is_locked: true, locked_at: nil)

    described_class.perform_now

    expect(template.reload.is_locked).to be(false)
    expect(template.job_report['reason']).to eq('lock_timeout')
  end

  it 'o prazo vem do ambiente' do
    preso = travado_ha(20)

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('AVAILABILITY_LOCK_TIMEOUT_MINUTES', anything).and_return('10')

    described_class.perform_now

    expect(preso.reload.is_locked).to be(false)
    expect(preso.job_report['timeout_minutes']).to eq(10)
  end

  it 'um padrão que falha não impede os outros, e a falha SOBE ao fim (D-C)' do
    presos = Array.new(3) { travado_ha(described_class.timeout_minutes + 1) }
    quebrado = presos.first

    chamadas = 0
    allow(Sfg::JobProgress).to receive(:publish).and_wrap_original do |orig, **kwargs|
      chamadas += 1
      raise StandardError, 'cabo fora do ar' if kwargs[:job_id].to_s.include?(quebrado.id)

      orig.call(**kwargs)
    end

    expect { described_class.perform_now }.to raise_error(described_class::StaleUnlockFailed, /#{quebrado.id}/)

    # Os outros dois foram destravados mesmo com o primeiro falhando.
    expect(chamadas).to eq(3)
    expect(presos.drop(1).map { |t| t.reload.is_locked }).to all(be(false))
  end

  it 'a fila do job está declarada em config/sidekiq.yml' do
    declaradas = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/sidekiq.yml'))).result,
                                aliases: true, permitted_classes: [Symbol])
    filas = Array(declaradas[:queues] || declaradas['queues']).map(&:to_s)

    expect(filas).to include(described_class.queue_name.to_s)
  end

  # O portão geral vive em `spec/config/schedule_queue_spec.rb`; aqui a asserção
  # é só que ESTE job entrou no agendamento — job de watchdog sem linha no
  # `schedule.yml` é job que nunca roda, que é o defeito do próprio watchdog.
  it 'está agendado em config/schedule.yml, com fila explícita' do
    schedule = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/schedule.yml'))).result, aliases: true)
    entrada = schedule.values.find { |d| d.is_a?(Hash) && d['class'] == described_class.name }

    expect(entrada).to be_present
    expect(entrada['queue']).to eq('low_priority')
    expect(entrada['cron']).to be_present
  end
end
