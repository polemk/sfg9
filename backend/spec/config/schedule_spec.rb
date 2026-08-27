# frozen_string_literal: true

require 'rails_helper'

# Portão do agendamento (upstream-flags.md #13).
#
# Estes exemplos existem porque o defeito que eles cobrem é SILENCIOSO: cron apontando
# para classe inexistente re-enfileira `NameError` para sempre e só aparece no log do
# Sidekiq. Um `rspec` verde não prova que o cron roda — prova que o arquivo é válido e
# que as classes existem, que é exatamente o que faltava.
RSpec.describe 'config/schedule.yml' do
  let(:schedule) { SidekiqCronSchedule.read }

  it 'existe e declara pelo menos um cron' do
    expect(File).to exist(SidekiqCronSchedule::SCHEDULE_PATH)
    expect(schedule).not_to be_empty
  end

  it 'passa no portão: toda classe agendada existe e toda expressão cron é válida' do
    expect(SidekiqCronSchedule.problems(schedule)).to eq([])
  end

  # Sem esta declaração o `load_from_hash!` REMOVERIA o único cron legítimo que a base
  # tem hoje — que até 25/08/2026 só existia como chave do Redis.
  it 'declara cleanup_login_codes, que antes só existia no Redis' do
    expect(schedule).to include('cleanup_login_codes')
    expect(schedule.dig('cleanup_login_codes', 'class')).to eq('CleanupLoginCodesJob')
  end

  it 'declara os expurgos do DEC-60 (login_attempts) e do DEC-90 (email_logs)' do
    expect(schedule.dig('purge_login_attempts', 'class')).to eq('PurgeLoginAttemptsJob')
    expect(schedule.dig('purge_email_logs', 'class')).to eq('PurgeEmailLogsJob')
  end

  # O job é da fatia S0, que deixou o agendamento para cá de propósito. Job de expurgo
  # sem linha no schedule é job que nunca roda — e ninguém percebe, porque nada falha.
  it 'declara o expurgo da trilha de auditoria (DEC-59), cujo job veio de outra fatia' do
    expect(schedule.dig('purge_audit_versions', 'class')).to eq('PurgeAuditVersionsJob')
  end

  # Portão contra o buraco de coordenação: job de expurgo criado e nunca agendado.
  it 'não deixa nenhum job de expurgo fora do schedule' do
    jobs_de_expurgo = Dir[Rails.root.join('app/jobs/purge_*_job.rb')]
                      .map { |f| File.basename(f, '.rb').camelize }
    agendados = schedule.values.map { |d| d['class'] }

    expect(jobs_de_expurgo - agendados).to be_empty
  end

  it 'reprova uma entrada cuja classe não existe' do
    bad = { 'ghost' => { 'class' => 'ClasseQueNaoExiste', 'cron' => '0 4 * * *' } }

    expect(SidekiqCronSchedule.problems(bad).first).to match(/ClasseQueNaoExiste.*não existe/)
    expect { SidekiqCronSchedule.verify!(bad) }.to raise_error(RuntimeError, /não existe/)
  end

  it 'reprova uma expressão cron inválida' do
    bad = { 'torto' => { 'class' => 'CleanupLoginCodesJob', 'cron' => 'todo dia de manhã' } }

    expect(SidekiqCronSchedule.problems(bad).first).to match(/cron inválida/)
  end

  # A retenção é decisão registrada, não número solto no código.
  it 'mantém as retenções decididas (DEC-60: 90 dias; DEC-90: 180 dias)' do
    expect(PurgeLoginAttemptsJob::DEFAULT_RETENTION_DAYS).to eq(90)
    expect(PurgeEmailLogsJob::DEFAULT_RETENTION_DAYS).to eq(180)
  end
end
