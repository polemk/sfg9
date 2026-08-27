# frozen_string_literal: true

require 'rails_helper'

# S6 / **BE-189**, tarefa **2.36** — a gravação do pacote de recibos **em lote**.
#
# ## Por que este arquivo só existe agora
#
# A tarefa ficou aberta desde o fechamento da S6 com o rótulo *"ESCRITO, SEM
# GOLDEN REAL — depende da S8"*: o serviço existia inteiro, mas `Remuneration`
# não existia e ele parava num 422 nomeando a fatia. **Nenhum exemplo chegava a
# gravar ou remover um recibo de verdade** — e foi exatamente aí que se
# escondeu o defeito que a seção "o 500 do desmarcar" trava mais abaixo.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115
#
# FONTE, não ORÁCULO.
#
# `charges`, `receipts` e `remunerations` nunca subiram em produção. O que estes
# exemplos travam é a leitura de `../sfg/app/controllers/pub/charges_controller.rb`
# e do `after_create`/`after_destroy` de `../sfg/app/models/receipt.rb:27-35`,
# não comportamento observado em uso.
#
# **Encerramento (DEC-115, 26/08/2026):** a tarefa **13.5** pedia reconferir
# estes goldens *"contra o legado, com o dump carregado"*. Ela foi **reescrita**,
# não adiada: o usuário confirmou que não existe outra base (*"nao tem, a tabela
# de excel que tinha foi perdida"*), e a conferência que vale passou a ser
# **contra a FONTE de 2022** — que é o que este arquivo faz. **Nada disso
# promove ID a `verified`**: a régua continua sendo "comparado com dado de
# produção e bateu", e para esta família isso é permanentemente impossível.

RSpec.describe Charges::BulkReceiptsService do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:tipo) { create(:structured_operation_type) }
  let(:autor) { create(:user) }
  let(:cobranca) { create(:charge, project: project, author: autor) }

  def operacao(valor: '200000.00', **extra)
    create(:structured_operation, project: project, company: company, operation_type: tipo,
                                  operation_value: BigDecimal(valor), **extra)
  end

  def temp_ids_de(*operacoes)
    lista = Charges::ReceiptGenerator.candidates(project: project, charge: cobranca)[:data]
    operacoes.map { |op| lista.find { |c| c[:operation_id] == op.id }.fetch(:temp_id) }
  end

  # ====================================================================
  # O caminho feliz — e o vínculo dos DOIS lados (DB-165)
  # ====================================================================
  describe 'gravação do lote' do
    it 'grava os dois recibos, aponta os dois lados do vínculo e recalcula a cobrança' do
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      a = operacao(valor: '200000.00')
      b = operacao(valor: '1234.56')

      resultado = described_class.call(project: project, charge_id: cobranca.id,
                                       temp_ids: temp_ids_de(a, b), actor: autor)

      expect(resultado[:status]).to eq(200)
      expect(cobranca.reload.receipts.count).to eq(2)
      # Golden E1 + E2, agora somados no pacote.
      expect(cobranca.receipts.sum(:value)).to eq(BigDecimal('5131.48'))
      # `../sfg/app/models/receipt.rb:27-30` fazia `operation.save` **sem checar
      # o retorno**: se a operação falhasse na validação sobrava recibo sem
      # operação apontando de volta. Aqui é `update!`, dentro da transação.
      expect(a.reload.receipt_id).to be_present
      expect(b.reload.receipt_id).to be_present
    end

    it 'reenviar a mesma lista NÃO duplica — o `temp_id` é a identidade' do
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      op = operacao
      ids = temp_ids_de(op)

      described_class.call(project: project, charge_id: cobranca.id, temp_ids: ids, actor: autor)
      persistido = cobranca.reload.receipts.first.temp_id
      described_class.call(project: project, charge_id: cobranca.id, temp_ids: [persistido], actor: autor)

      expect(Receipt.where(operation_id: op.id).count).to eq(1)
    end
  end

  # ====================================================================
  # 2.36 — o LOTE INTEIRO numa transação (FE-185)
  # ====================================================================
  describe 'o lote inteiro numa transação' do
    it 'falha no meio do lote reverte TUDO — nenhum recibo fica, nenhum vínculo fica' do
      # No legado cada marcação era uma requisição própria: quando a terceira
      # falhava, as duas primeiras já estavam gravadas e a tela ficava fora de
      # sincronia com o servidor. O que este exemplo trava é a **fronteira da
      # transação**; a causa da falha é indiferente, e por isso é forçada.
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      a = operacao(valor: '200000.00')
      b = operacao(valor: '1234.56')
      ids = temp_ids_de(a, b)

      chamadas = 0
      allow(Receipt).to receive(:create!).and_wrap_original do |original, *args|
        chamadas += 1
        raise ActiveRecord::RecordInvalid, Receipt.new if chamadas == 2

        original.call(*args)
      end

      resultado = described_class.call(project: project, charge_id: cobranca.id,
                                       temp_ids: ids, actor: autor)

      expect(resultado[:status]).to eq(422)
      expect(Receipt.count).to eq(0)
      expect(a.reload.receipt_id).to be_nil
      expect(b.reload.receipt_id).to be_nil
      expect(cobranca.reload.receipts).to be_empty
    end
  end

  # ====================================================================
  # 2.36 / D-18 — "Faturado" recusa no SERVIDOR, não só na tela
  # ====================================================================
  describe 'D-18 — cobrança Faturada recusa alteração no servidor' do
    it 'PUT de recibos em cobrança `done` responde 422 e não toca em nada' do
      # No legado o bloqueio existia **só na UI**: o botão sumia, e a rota
      # continuava aceitando. Aqui a recusa é do serviço.
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      op = operacao
      faturada = create(:charge, project: project, author: autor, state: Charge::STATE_DONE)

      resultado = described_class.call(project: project, charge_id: faturada.id,
                                       temp_ids: ["RCP-#{project.id}-EST-x-#{op.id}"], actor: autor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('Faturada')
      expect(Receipt.count).to eq(0)
    end

    it 'a recusa vem ANTES de qualquer validação de conteúdo — estado é a primeira porta' do
      faturada = create(:charge, project: project, author: autor, state: Charge::STATE_DONE)
      resultado = described_class.call(project: project, charge_id: faturada.id,
                                       temp_ids: [], actor: autor)
      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('Faturada')
    end

    it '`editing` e `available` aceitam' do
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      operacao
      [Charge::STATE_EDITING, Charge::STATE_AVAILABLE].each do |estado|
        pacote = create(:charge, project: project, author: autor, state: estado)
        expect(described_class.call(project: project, charge_id: pacote.id,
                                    temp_ids: [], actor: autor)[:status]).to eq(200), estado
      end
    end
  end

  # ====================================================================
  # 2.36 / C1 — recibo de operação de OUTRO projeto não entra no lote
  # ====================================================================
  describe 'C1 — a operação de outro projeto não entra no lote' do
    it 'o `temp_id` alheio é recusado com 422 e NADA é gravado' do
      # Família D-01/D-16/D-29/D-76/D-100: no legado, id por parâmetro
      # descartava o escopo. Aqui o candidato só existe se sair de
      # `ReceiptGenerator.candidates(project:)`, que já nasce escopado.
      outro = create(:project)
      outra_empresa = create(:company, project: outro)
      create(:remuneration, project: outro, operation_type: tipo, value: BigDecimal('2.55'))
      alheia = create(:structured_operation, project: outro, company: outra_empresa,
                                             operation_type: tipo,
                                             operation_value: BigDecimal('200000.00'))
      rem_alheia = Remuneration.find_by(project_id: outro.id)
      temp_id_alheio = Receipt.temp_id_for(project_id: outro.id, kind: 'EST',
                                           remuneration_id: rem_alheia.id, operation_id: alheia.id)

      resultado = described_class.call(project: project, charge_id: cobranca.id,
                                       temp_ids: [temp_id_alheio], actor: autor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:details][:temp_ids]).to eq([temp_id_alheio])
      expect(Receipt.count).to eq(0)
      expect(alheia.reload.receipt_id).to be_nil
    end

    it 'cobrança de outro projeto responde 404 — igual a id inexistente' do
      outro = create(:project)
      alheia = create(:charge, project: outro)
      expect(described_class.call(project: project, charge_id: alheia.id,
                                  temp_ids: [], actor: autor)[:status]).to eq(404)
      expect(described_class.call(project: project, charge_id: SecureRandom.uuid,
                                  temp_ids: [], actor: autor)[:status]).to eq(404)
    end

    it '`charge_id` malformado responde 404, não 500' do
      expect(described_class.call(project: project, charge_id: 'nao-e-uuid',
                                  temp_ids: [], actor: autor)[:status]).to eq(404)
    end
  end

  # ====================================================================
  # O 500 do "desmarcar" — a ORDEM da remoção (EST-S8-01)
  # ====================================================================
  describe 'remoção: soltar o vínculo ANTES de destruir o recibo' do
    it 'desmarcar apaga o recibo e devolve a operação à lista de candidatos' do
      # **Regressão real, e ela viveu escondida desde a S6.** Enquanto
      # `Remuneration` não existia, este caminho era inalcançável e nenhum teste
      # o percorria. No primeiro "desmarcar" de verdade o Postgres respondeu
      # `PG::ForeignKeyViolation` — `structured_operations.receipt_id` tem FK
      # real para `receipts`, e o serviço destruía o recibo com a operação ainda
      # apontando para ele. A FK estava certa; a ordem é que estava errada.
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      op = operacao
      described_class.call(project: project, charge_id: cobranca.id,
                           temp_ids: temp_ids_de(op), actor: autor)
      expect(op.reload.receipt_id).to be_present

      resultado = described_class.call(project: project, charge_id: cobranca.id,
                                       temp_ids: [], actor: autor)

      expect(resultado[:status]).to eq(200)
      expect(Receipt.count).to eq(0)
      expect(op.reload.receipt_id).to be_nil
      expect(cobranca.reload.value).to eq(0)
      expect(cobranca.receipts_count).to eq(0)
      # E volta a ser candidata — o ciclo fecha nos dois sentidos.
      candidatos = Charges::ReceiptGenerator.candidates(project: project, charge: cobranca)[:data]
      expect(candidatos.map { |c| c[:operation_id] }).to include(op.id)
    end

    it 'vale igual na classe LIQ — a FK de `risk_operations.receipt_id` é a mesma' do
      controle = create(:risk_control, project: project, company: company)
      op = create(:risk_operation, risk_control: controle, operation_value: BigDecimal('200000.00'))
      create(:remuneration, project: project, operation_type: controle.risk_operation_type,
                            value: BigDecimal('2.55'))

      ids = Charges::ReceiptGenerator.candidates(project: project, charge: cobranca)[:data]
                                     .select { |c| c[:kind] == 'LIQ' }.map { |c| c[:temp_id] }
      described_class.call(project: project, charge_id: cobranca.id, temp_ids: ids, actor: autor)
      expect(op.reload.receipt_id).to be_present

      resultado = described_class.call(project: project, charge_id: cobranca.id,
                                       temp_ids: [], actor: autor)

      expect(resultado[:status]).to eq(200)
      expect(op.reload.receipt_id).to be_nil
    end

    it 'o diff é parcial: manter um e soltar o outro remove SÓ o que saiu da lista' do
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      a = operacao(valor: '200000.00')
      b = operacao(valor: '1234.56')
      described_class.call(project: project, charge_id: cobranca.id,
                           temp_ids: temp_ids_de(a, b), actor: autor)

      manter = cobranca.reload.receipts.find { |r| r.operation_id == a.id }.temp_id
      described_class.call(project: project, charge_id: cobranca.id, temp_ids: [manter], actor: autor)

      expect(cobranca.reload.receipts.count).to eq(1)
      expect(a.reload.receipt_id).to be_present
      expect(b.reload.receipt_id).to be_nil
      expect(cobranca.receipts.sum(:value)).to eq(BigDecimal('5100.00'))
    end
  end
end
