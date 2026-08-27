# frozen_string_literal: true

require 'rails_helper'

# S9 / tarefa 4.23 — **o canal da renegociação** (FE-207, D-B5).
#
# Prova três coisas: a assinatura é escopada por participação (C1), o broadcast
# sai **uma vez** por operação e **depois do COMMIT**, e não existe polling na
# área (Princípio 10).
RSpec.describe RenegotiationChannel, type: :channel do
  let(:dono) { create(:user, :gerente) }
  let(:estranho) { create(:user, :gerente) }
  let(:project) { create_project_with_owner(dono) }
  let(:renegotiation) do
    create(:renegotiation, project: project,
                           provider: create(:provider, project: project),
                           company: create(:company, project: project))
  end

  it 'ACEITA quem participa do projeto' do
    stub_connection current_user: dono
    subscribe(renegotiation_id: renegotiation.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("renegotiation:#{renegotiation.id}")
  end

  it 'RECUSA quem não participa — assinante de outro projeto não recebe' do
    create_project_with_owner(estranho)
    stub_connection current_user: estranho
    subscribe(renegotiation_id: renegotiation.id)

    expect(subscription).to be_rejected
  end

  it 'RECUSA sem id e RECUSA id inexistente' do
    stub_connection current_user: dono

    subscribe
    expect(subscription).to be_rejected

    subscribe(renegotiation_id: SecureRandom.uuid)
    expect(subscription).to be_rejected
  end

  describe 'emissão' do
    it 'alterar parcela emite UM broadcast' do
      renegotiation

      expect do
        Renegotiations::CreateInstallmentsBatch.call(
          renegotiation: renegotiation,
          attrs: { due_date: Date.new(2025, 1, 10), main_value: 1000 }
        )
      end.to have_broadcasted_to("renegotiation:#{renegotiation.id}").exactly(:once)
    end

    it 'alterar pagamento emite UM broadcast' do
      parcela = create(:renegotiation_installment, renegotiation: renegotiation,
                                                   due_date: Date.new(2025, 1, 10))

      expect do
        RenegotiationPaymentService.create_payment(
          installment: parcela,
          attrs: { date: Date.new(2025, 1, 10), installment_paid_value_with_interest_cm: 100 },
          actor: dono
        )
      end.to have_broadcasted_to("renegotiation:#{renegotiation.id}").exactly(:once)
    end

    it 'o payload diz O QUE mudou, não CARREGA o estado' do
      # De propósito: o assinante invalida a consulta e relê pelo endpoint, que
      # é onde a autorização é conferida. Empurrar o registro pelo canal seria
      # uma segunda superfície de leitura, sem gate.
      expect do
        Renegotiations::AggregateService.recalculate!(renegotiation)
      end.to have_broadcasted_to("renegotiation:#{renegotiation.id}")
        .with(hash_including('event' => 'renegotiation.changed'))
    end
  end

  it 'não existe polling na área (Princípio 10)' do
    arquivos = Dir[Rails.root.join('../frontend/src/app/pages/renegotiations/**/*.{ts,tsx}')] +
               Dir[Rails.root.join('../frontend/src/components/renegotiations/**/*.{ts,tsx}')] +
               Dir[Rails.root.join('../frontend/src/hooks/useRenegotiation*.ts')]
    infratores = arquivos.select do |caminho|
      conteudo = File.read(caminho)
      # A chamada, não o prefixo: `setIntervalo(...)` — o estado do intervalo do
      # LOTE de parcelas — contém a substring `setInterval` e não é polling.
      # Um portão que reprova o nome de uma variável é um portão que alguém
      # desliga.
      conteudo.match?(/\bsetInterval\s*\(/) || conteudo.match?(/refetchInterval\s*:/)
    end

    expect(infratores.map { |c| File.basename(c) }).to be_empty
  end
end
