# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefas 3.12 e 3.13 — **OPS-473: a varredura diária não volta.**
#
# O legado tinha um cron só, e ele era este
# (`../sfg/config/schedule.prod.rb` + `lib/cron_facade.rb`):
#
#     every :day, at: '00:01 am' do
#       runner "CRONFacade.update_renegotiations_counters"
#     end
#
#     Renegotiation.where.not(state: STATE__CLOSED).each { |r| r.update_values! }
#
# Quatro defeitos em três linhas: contagem até 24 h velha (D-54), renegociação
# liquidada nunca mais reprocessada, `save` sem bang engolindo falha (D-79), e
# nenhuma trava de concorrência (`whenever` instala o crontab **por host**).
#
# A substituição da S9 é o que fecha as duas partes da tarefa:
#
#  - **parte 1 (3.12)** — o que depende só da data vira **consulta**
#    (`AggregateService.live_overdue_for`, uma consulta para a página inteira);
#  - **parte 2 (3.13)** — os somatórios viram **recálculo por evento** na
#    renegociação afetada, pelo mesmo service que grava (contrato C2).
#
# Este arquivo é o portão que impede a volta. Ele não testa o cálculo — isso é
# de `spec/services/renegotiations/` — testa que **não existe varredura**.
RSpec.describe 'OPS-473 — nenhuma varredura periódica de renegociação' do
  let(:schedule) do
    YAML.safe_load(ERB.new(File.read(Rails.root.join('config/schedule.yml'))).result, aliases: true) || {}
  end

  it 'nenhum cron agendado mexe em renegociação' do
    suspeitos = schedule.select do |nome, definicao|
      next false unless definicao.is_a?(Hash)

      "#{nome} #{definicao['class']} #{definicao['description']}".match?(/renegoti/i)
    end.keys

    expect(suspeitos).to be_empty,
                         "Cron de renegociação encontrado: #{suspeitos.join(', ')}. " \
                         'A contagem é apurada na CONSULTA e o somatório é recalculado por EVENTO ' \
                         '(OPS-190/OPS-191). Recriar o cron reintroduz a janela de 24 h do D-54.'
  end

  it 'nenhum job varre a tabela inteira de renegociações' do
    jobs = Dir[Rails.root.join('app/jobs/**/*.rb')]
    infratores = jobs.select do |path|
      fonte = File.read(path)
      fonte.match?(/Renegotiation[^.\s]*\s*\.\s*(all|where)[^\n]*\.\s*(each|find_each)/)
    end.map { |p| File.basename(p) }

    expect(infratores).to be_empty,
                          "Job varrendo renegociações: #{infratores.join(', ')}."
  end

  it 'o recálculo tem UM dono, e ele é o mesmo que a prévia usa (C2)' do
    # `recalculate!` grava; `preview`/`compute` calculam sem gravar — e as duas
    # passam por `compute_from`, que é a fonte única. Nenhum outro lugar do
    # repositório escreve os agregados persistidos.
    escritores = Dir[Rails.root.join('app/**/*.rb')].select do |path|
      next false if path.end_with?('aggregate_service.rb')

      File.read(path).match?(/overdue_installments\s*=/)
    end.map { |p| p.delete_prefix("#{Rails.root}/") }

    expect(escritores).to be_empty,
                          "Escrita de agregado fora do AggregateService: #{escritores.join(', ')}"
  end

  it '`overdue` é apurado com a data de HOJE, sem depender de rodada anterior' do
    # Parcela que vence à meia-noite aparece vencida no primeiro acesso: o
    # escopo compara `due_date < hoje`, e `hoje` é o parâmetro da consulta.
    fonte = File.read(Rails.root.join('app/models/renegotiation_installment.rb'))
    expect(fonte).to match(/scope :overdue, ->\(hoje = Date\.current\)/)
  end
end
