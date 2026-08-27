# frozen_string_literal: true

require 'rails_helper'

# S9 / tarefas 5.4 e 5.5 (**OPS-197**) — os fixups pós-carga.
#
# Cada exemplo **estraga o dado de propósito** e prova que a rotina o conserta.
# Rodar o fixup contra uma base já coerente e ver "0 divergências" prova que ele
# não quebra nada; não prova que ele conserta alguma coisa.
#
# Os dois portões que a tarefa 5.5 pede estão aqui:
#  - **idempotente**: a segunda passada sai com tudo em zero;
#  - **ensaio que reconcilia antes de escrever**: o `dry_run` relata a mesma
#    divergência e o banco continua exatamente como estava.
RSpec.describe Sfg::Etl::Fixups::Renegotiations do
  def rodar(dry_run: false, only: nil)
    described_class.new(dry_run: dry_run, only: only, batch_size: 50,
                        report: Sfg::Etl::Report.new('spec-fixups', io: StringIO.new)).tap(&:run!)
  end

  def secao(fixup, trecho)
    fixup.report.sections.find { |s| s.title.include?(trecho) }
  end

  describe 'recálculo geral (OPS-197)' do
    let!(:renegotiation) { create(:renegotiation, total_debt: 1_000) }
    let!(:installment) do
      create(:renegotiation_installment, renegotiation: renegotiation,
                                         due_date: Date.new(2025, 2, 10), main_value: 1_000)
    end

    it 'reconstrói parcela e agregado a partir dos pagamentos, gravando UMA vez por renegociação' do
      # Um pagamento inserido **sem** passar pela cascata — é o estado em que a
      # carga do ETL deixa a base: linhas copiadas, derivados não recalculados.
      RenegotiationPayment.insert_all!(
        [{ id: SecureRandom.uuid, renegotiation_id: renegotiation.id, project_id: renegotiation.project_id,
           renegotiation_installment_id: installment.id, date: Date.new(2025, 2, 20),
           installment_paid_value_with_interest_cm: 400, late_payment_value: 0,
           days_late: 0, total_paid_value: 0, payment_number: 0,
           created_at: Time.current, updated_at: Time.current }]
      )

      fixup = rodar

      # O pagamento: `days_late` sai da diferença entre a data e o vencimento…
      pagamento = RenegotiationPayment.find_by(renegotiation_installment_id: installment.id)
      expect(pagamento.days_late).to eq(10)
      expect(pagamento.total_paid_value).to eq(400)
      expect(pagamento.payment_number).to eq(1)

      # …a parcela lê a soma dos pagamentos…
      expect(installment.reload.paid_value).to eq(400)
      expect(installment.pending_value).to eq(600)
      expect(installment.is_paid).to be false

      # …e o agregado lê as parcelas.
      expect(renegotiation.reload.paid_value_with_interest_cm).to eq(400)
      expect(renegotiation.remaining_value).to eq(600)
      expect(renegotiation.paid_percent).to eq(40.0)

      expect(secao(fixup, 'Recálculo geral').title).to include('1 renegociação')
    end

    it 'é idempotente: a segunda passada não encontra nada para mudar' do
      RenegotiationPayment.insert_all!(
        [{ id: SecureRandom.uuid, renegotiation_id: renegotiation.id, project_id: renegotiation.project_id,
           renegotiation_installment_id: installment.id, date: Date.new(2025, 2, 20),
           installment_paid_value_with_interest_cm: 400, late_payment_value: 0,
           days_late: 0, total_paid_value: 0, payment_number: 0,
           created_at: Time.current, updated_at: Time.current }]
      )

      rodar
      segunda = rodar

      expect(segunda.counts[:recalculated]).to eq(0)
      expect(secao(segunda, 'Recálculo geral').severity).to eq(:ok)
    end

    it 'no ENSAIO relata a mesma divergência e NÃO grava' do
      RenegotiationPayment.insert_all!(
        [{ id: SecureRandom.uuid, renegotiation_id: renegotiation.id, project_id: renegotiation.project_id,
           renegotiation_installment_id: installment.id, date: Date.new(2025, 2, 20),
           installment_paid_value_with_interest_cm: 400, late_payment_value: 0,
           days_late: 0, total_paid_value: 0, payment_number: 0,
           created_at: Time.current, updated_at: Time.current }]
      )
      antes = renegotiation.reload.paid_value_with_interest_cm

      ensaio = rodar(dry_run: true)

      expect(ensaio.counts[:recalculated]).to eq(1)
      expect(renegotiation.reload.paid_value_with_interest_cm).to eq(antes)
      expect(RenegotiationPayment.find_by(renegotiation_installment_id: installment.id).days_late).to eq(0)
    end
  end

  describe 'renumeração' do
    it 'renumera parcelas por vencimento e pagamentos por criação, sem passar por callback' do
      renegotiation = create(:renegotiation)
      tarde = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 5, 10))
      cedo = create(:renegotiation_installment, renegotiation: renegotiation, due_date: Date.new(2025, 1, 10))
      RenegotiationInstallment.where(id: [tarde.id, cedo.id]).update_all(number: 99)

      rodar(only: %w[renumber])

      expect(cedo.reload.number).to eq(1)
      expect(tarde.reload.number).to eq(2)
    end
  end

  describe '`attachments_count` — tarefa 5.4' do
    it 'reconcilia o contador contra as linhas de anexo de fato migradas (DB-195)' do
      renegotiation = create(:renegotiation)
      create(:renegotiation_attachment, renegotiation: renegotiation)
      create(:renegotiation_attachment, renegotiation: renegotiation)
      # O contador escrito errado é o estado que a carga produz: as linhas entram
      # por `insert_all`/ETL, que não passa pelo `counter_cache`.
      Renegotiation.where(id: renegotiation.id).update_all(attachments_count: 0)

      fixup = rodar(only: %w[counters])

      expect(renegotiation.reload.attachments_count).to eq(2)
      expect(fixup.counts[:counters_fixed]).to eq(1)
      expect(secao(fixup, '`attachments_count`').title).to include('2 anexo(s) no destino')
    end

    it 'no ENSAIO aponta o contador errado sem corrigi-lo' do
      renegotiation = create(:renegotiation)
      create(:renegotiation_attachment, renegotiation: renegotiation)
      Renegotiation.where(id: renegotiation.id).update_all(attachments_count: 7)

      fixup = rodar(dry_run: true, only: %w[counters])

      expect(fixup.counts[:counters_fixed]).to eq(1)
      expect(renegotiation.reload.attachments_count).to eq(7)
    end

    it 'não mexe em contador que já está certo' do
      renegotiation = create(:renegotiation)
      create(:renegotiation_attachment, renegotiation: renegotiation)

      fixup = rodar(only: %w[counters])

      expect(fixup.counts[:counters_fixed]).to eq(0)
      expect(renegotiation.reload.attachments_count).to eq(1)
    end
  end

  describe 'empresa padrão' do
    it 'cria uma empresa para o projeto que não tem nenhuma' do
      projeto = create(:project)
      Company.where(project_id: projeto.id).delete_all

      fixup = rodar(only: %w[company])

      expect(Company.where(project_id: projeto.id).pluck(:title)).to include('Empresa Padrão')
      expect(fixup.counts[:companies_created]).to be >= 1
    end

    # ⚠ O DESVIO DECLARADO. O legado terminava a rotina com
    # `p.renegotiations.update_all(company_id: c.id)` — **sem condição** —, o que
    # reescreve a empresa CERTA de toda renegociação do projeto. Aqui a que já
    # está certa não é tocada.
    it 'NÃO reescreve a empresa de quem já tem a empresa certa (o legado reescrevia)' do
      renegotiation = create(:renegotiation)
      outra = create(:company, project: renegotiation.project, title: 'Segunda Empresa')
      empresa_original = renegotiation.company_id

      rodar(only: %w[company])

      expect(renegotiation.reload.company_id).to eq(empresa_original)
      expect(renegotiation.company_id).not_to eq(outra.id)
    end

    # C1 aplicado ao dado: empresa de outro projeto numa renegociação é vazamento
    # de escopo gravado em coluna.
    it 'troca a empresa que é de OUTRO projeto pela do próprio projeto' do
      renegotiation = create(:renegotiation)
      invasora = create(:company)
      Renegotiation.where(id: renegotiation.id).update_all(company_id: invasora.id)

      fixup = rodar(only: %w[company])

      expect(renegotiation.reload.company.project_id).to eq(renegotiation.project_id)
      expect(fixup.counts[:companies_repaired]).to eq(1)
    end
  end

  # A rotina do legado era `Renegotiation.all.each`, que materializa a tabela
  # inteira antes da primeira gravação. A prova de que aqui não é assim não é ler
  # o código: é **contar as consultas**. Com lote de 1 e três renegociações, a
  # varredura tem de emitir três SELECTs limitados, e não um só.
  it 'lê em LOTES, nunca a tabela inteira (OPS-197)' do
    create_list(:renegotiation, 3)

    selects = []
    assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql].to_s
      selects << sql if sql.start_with?('SELECT') && sql.include?('"renegotiations"') && sql.include?('LIMIT')
    end

    described_class.new(dry_run: true, only: %w[counters], batch_size: 1,
                        report: Sfg::Etl::Report.new('spec-lotes', io: StringIO.new)).run!
  ensure
    ActiveSupport::Notifications.unsubscribe(assinatura) if assinatura
    expect(selects.size).to be >= 3
    expect(selects).to all(include('ORDER BY "renegotiations"."id" ASC'))
  end
end
