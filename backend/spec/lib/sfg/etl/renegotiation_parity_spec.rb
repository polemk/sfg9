# frozen_string_literal: true

require 'rails_helper'

# S9 / tarefa 5.7 — **paridade numérica da renegociação contra o legado**.
#
# O `Sfg::Etl::Parity::Renegotiations` rodou contra o dump de produção
# (`sfg-31-may-25.sql`, 169 renegociações / 5.124 parcelas / 1.230 pagamentos) em
# 26/08/2026 e mediu **47.170 comparações, 47.162 iguais, 0 regressões**.
#
# Este arquivo trava o **classificador**, que é a parte que decide o que conta
# como regressão — porque o dump não pode entrar no repositório e um verificador
# que classifica errado sai verde contra qualquer coisa. O último exemplo repete a
# medição contra o artefato real quando ele é apontado por ENV.
RSpec.describe Sfg::Etl::Parity::Renegotiations do
  # Uma origem mínima com a FORMA do legado: colunas de texto, `\N` já virado nil.
  def fonte(renegotiations:, installments: [], payments: [], attachments: nil)
    dados = {
      'renegotiations' => renegotiations,
      'renegotiation_installments' => installments,
      'renegotiation_payments' => payments
    }
    dados['renegotiation_attachments'] = attachments if attachments
    origem = instance_double(Sfg::Etl::Source::Base, describe: 'origem de teste')
    allow(origem).to receive(:table?) { |t| dados.key?(t.to_s) }
    allow(origem).to receive(:ordered_rows) { |t, **| dados.fetch(t.to_s, []) }
    origem
  end

  # Uma renegociação de uma parcela e um pagamento, com os agregados que o legado
  # gravaria. Sobrescrever uma chave é o que cada exemplo faz para criar a
  # divergência que ele mede.
  def cenario(renegotiation: {}, installment: {}, payment: {})
    parcela = { 'id' => '1', 'renegotiation_id' => '1', 'due_date' => '2025-01-10',
                'main_value' => '1000.00', 'interest_value' => '0.00',
                'monetary_correction_value' => '0.00', 'main_value_with_interest' => '1000.00',
                'main_value_with_interest_cm' => '1000.00', 'late_payment_value' => '0.00',
                'installment_total_value' => '1000.00', 'paid_value' => '400.00',
                'saldo' => '-600.00', 'pending_value' => '600.00', 'is_paid' => 'f',
                'month' => '1', 'year' => '2025' }.merge(installment)

    pagamento = { 'id' => '1', 'renegotiation_id' => '1', 'renegotiation_installment_id' => '1',
                  'date' => '2025-01-10', 'installment_paid_value_with_interest_cm' => '400.00',
                  'late_payment_value' => '0.00', 'days_late' => '0',
                  'total_paid_value' => '400.00' }.merge(payment)

    reneg = { 'id' => '1', 'total_debt' => '1000.00', 'original_value' => '1000.00',
              'operation_interest_rate' => '0.0', 'updated_at' => '2025-06-01 10:00:00',
              'installments_count' => '1', 'first_due_date' => '2025-01-10',
              'last_due_date' => '2025-01-10', 'correct_value' => '1000.00',
              'installments_main_value' => '1000.00', 'installments_interest_value' => '0.00',
              'installments_main_value_with_interest' => '1000.00',
              'installments_monetary_correction_value' => '0.00',
              'installments_main_value_with_interest_cm' => '1000.00', 'main_value' => '1000.00',
              'paid_value_with_interest_cm' => '400.00', 'pending_main_value' => '600.00',
              'paid_percent' => '40.0', 'late_payment_value' => '0.00', 'paid_value' => '400.00',
              'remaining_value' => '600.00', 'paid_installments' => '0',
              'due_installments' => '1', 'overdue_installments' => '1',
              'current_installment_value' => '0.00', 'current_value' => '600.00',
              # `STATE_OPEN` do legado é literalmente a string "Pago" — o rótulo
              # mente, e ele é replicado (DEC-30).
              'state' => ::Renegotiation::STATE_OPEN }.merge(renegotiation)

    fonte(renegotiations: [reneg], installments: [parcela], payments: [pagamento])
  end

  def rodar(origem)
    described_class.new(source: origem, io: StringIO.new).tap(&:run!)
  end

  it 'não acusa nada quando o legado e o ai9 produzem os mesmos números' do
    verificador = rodar(cenario)

    expect(verificador.divergences).to be_empty
    expect(verificador.comparisons).to be > 0
    expect(verificador.report.aborted?).to be false
  end

  # A tarefa 5.7 diz, com todas as letras: *"divergência de precisão NÃO é
  # regressão"* — DEC-02/D-104 é melhoria declinada. Um centavo de diferença é
  # exatamente o resíduo da cadeia truncamento → float → arredondamento.
  it 'classifica um centavo de diferença como PRECISÃO, e não bloqueia' do
    verificador = rodar(cenario(renegotiation: { 'main_value' => '1000.01' }))

    tipos = verificador.divergences.map(&:kind).uniq
    expect(tipos).to eq([:precision])
    expect(verificador.report.aborted?).to be false
  end

  it 'classifica mudança de FÓRMULA como regressão, e BLOQUEIA' do
    verificador = rodar(cenario(renegotiation: { 'remaining_value' => '750.00' }))

    regressao = verificador.divergences.find { |d| d.field == :remaining_value }
    expect(regressao.kind).to eq(:regression)
    expect(verificador.report.aborted?).to be true
  end

  # Sinal invertido é o modo de falha que a 5.7 nomeia junto com a fórmula: o
  # `pending_main_value` PODE ser negativo (Q-B22) e um cast que o zerasse
  # passaria despercebido numa amostra.
  it 'classifica sinal invertido como regressão' do
    verificador = rodar(cenario(renegotiation: { 'main_value' => '1000.00',
                                                 'pending_main_value' => '-600.00' }))

    expect(verificador.divergences.map(&:kind)).to include(:regression)
  end

  # A ÚNICA mudança de valor declarada da fatia (D-45 / BE-209). Ela é contada e
  # nomeada, mas não aborta — e é assim que o relatório distingue "mudamos de
  # propósito" de "quebrou".
  it 'conta "-> Inconsistente" como mudança DECLARADA (D-45), não como regressão' do
    # Parcelas que não cobrem a dívida contratada e ainda têm saldo: no legado a
    # linha seguinte sobrescrevia o estado e gravava "Em Aberto".
    verificador = rodar(cenario(renegotiation: { 'total_debt' => '5000.00',
                                                 'correct_value' => '5000.00',
                                                 'state' => ::Renegotiation::STATE_OPEN }))

    expect(verificador.divergences.select { |d| d.field == :state }).to be_empty
    expect(verificador.report.aborted?).to be false
    secao = verificador.report.sections.find { |s| s.title.include?('DECLARADA') }
    expect(secao.title).to include('1')
  end

  # `overdue_installments` é fotografia do dia em que `update_values!` rodou.
  # Compará-lo com a data de hoje mediria o calendário, não a fórmula (D-54).
  it 'compara os campos dependentes de data contra o `updated_at` da linha, fora da conta de regressão' do
    verificador = rodar(cenario(renegotiation: { 'overdue_installments' => '0' }))

    expect(verificador.divergences.map(&:field)).not_to include(:overdue_installments)
    secao = verificador.report.sections.find { |s| s.title.include?('dependem de HOJE') }
    expect(secao.title).to include('1 divergência')
  end

  # Tarefa 5.4, do lado da ORIGEM: o `attachments_count` do legado é confiável?
  # Medido contra produção: 134 dos 169 são NULO e **nenhum** está fora do real
  # (44 anexos em 35 renegociações). O NULO vira 0 no ai9, que é o número certo.
  it 'confere `attachments_count` contra a contagem real de anexos da origem' do
    origem = fonte(
      renegotiations: [{ 'id' => '1', 'attachments_count' => nil, 'total_debt' => '0',
                         'original_value' => '0', 'operation_interest_rate' => '0',
                         'updated_at' => '2025-06-01 10:00:00', 'installments_count' => '0',
                         'state' => ::Renegotiation::STATE_EMPTY, 'correct_value' => '0' },
                       { 'id' => '2', 'attachments_count' => '5', 'total_debt' => '0',
                         'original_value' => '0', 'operation_interest_rate' => '0',
                         'updated_at' => '2025-06-01 10:00:00', 'installments_count' => '0',
                         'state' => ::Renegotiation::STATE_EMPTY, 'correct_value' => '0' }],
      attachments: [{ 'id' => '1', 'renegotiation_id' => '2' }]
    )

    secao = rodar(origem).report.sections.find { |s| s.title.include?('`attachments_count`') }

    # O NULO da #1 não é divergência: ela não tem anexo nenhum, e 0 é o certo.
    expect(secao.title).to include('1 NULO(S)', '1 fora do real de 1 anexo(s)')
    expect(secao.lines.join).to include('legado 5 × ai9 1')
  end

  it 'não compara `total_value_with_desagio`: a migration nunca rodou em produção' do
    expect(described_class::COMPARABLE).not_to include(:total_value_with_desagio)
    expect(described_class::ABSENT_IN_PRODUCTION).to include(:total_value_with_desagio)
  end

  # ⚠ A MEDIÇÃO DE VERDADE. Só roda com o dump apontado por ENV — ele não está
  # (e não pode estar) no repositório. Rodada em 26/08/2026:
  #
  #   SFG_DUMP=…/sfg-31-may-25.sql bundle exec rspec \
  #     spec/lib/sfg/etl/renegotiation_parity_spec.rb -e 'dump de produção'
  #
  # Resultado medido: 47.170 comparações · 47.162 iguais · 0 de precisão ·
  # 8 mudanças declaradas (D-45) · **0 regressões**.
  it 'roda contra o dump de produção sem uma única regressão', :acervo_real do
    dump = ENV.fetch('SFG_DUMP', nil)
    skip 'defina SFG_DUMP para rodar contra o dump de produção' if dump.nil?

    verificador = rodar(Sfg::Etl::Source::SqlDump.new(dump))

    expect(verificador.divergences.select { |d| d.kind == :regression }).to be_empty
    expect(verificador.comparisons).to be >= 47_170
    expect(verificador.report.aborted?).to be false
  end
end
